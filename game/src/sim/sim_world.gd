class_name SimWorld
extends RefCounted
## Authoritative game state and rules.
##
## No nodes, rendering or input live here, so the server runs this class
## unchanged. Players queue commands (queue_order, queue_train); step()
## applies them at the start of the next tick, and views read snapshot() and
## player_state() only. Positions are 2D on the ground plane: x maps to world X,
## y maps to world Z.
##
## Match loop (Milestone 3, Ants only): workers milk aphids for honeydew and
## carry it home; the colony spends honeydew to train workers and soldiers up
## to MAX_UNITS_PER_PLAYER; ants fight in melee; destroying the enemy colony
## wins. At MATCH_TICKS the colony with more health left wins.
##
## Movement (Milestone 2 navigation): logs and rocks are static obstacles.
## A move whose straight line is blocked follows an A* path on a 1 m grid,
## string-pulled to a few waypoints. Units steer around friends they would
## bump (keeping right when head-on), are pushed out of each other and out
## of obstacles every tick, and wait in line behind moving friends instead
## of giving up.

const TICK_RATE := 20
const DT := 1.0 / TICK_RATE

const MAX_UNITS_PER_PLAYER := 50
const UNIT_RADIUS := 0.5
const FORMATION_GAP := 0.25
## Overlap passes per tick over every unit, then up to the max over only the
## units a pass still pushed more than SETTLED_PUSH (a jammed crowd).
const OVERLAP_PASSES := 3
const MAX_OVERLAP_PASSES := 8
const SETTLED_PUSH := 0.05
## A moving unit that gains less than this per tick for STALL_TICKS gives up
## and accepts where it is, so crowds settle instead of pushing forever.
const STALL_EPSILON := 0.02
const STALL_TICKS := 20
## An idle unit shoved further than this from its slot walks back to it.
const RETURN_DISTANCE := 0.6
## A unit pressed against moving friends (a queue at a chokepoint) waits this
## long without progress before it gives up.
const WAIT_TICKS := 100
## Blocked units re-plan their path this many times before giving up.
const MAX_REPATHS := 2
const NAV_CELL := 1.0
## Obstacles are grown by this when marking the nav grid and testing
## line of sight, so the largest ant fits through every path.
const NAV_CLEARANCE := 0.65
const WAYPOINT_REACH := 0.5
## Steering: friends within this much of touching, ahead of a mover, push
## its heading sideways.
const AVOID_MARGIN := 0.7
const AVOID_GAIN := 1.5
## Speed fraction for a unit that has made no progress for a few ticks.
## Pushing at full speed into a jam squeezes the ants in front together.
const JAM_PACE := 0.25

## Entity kinds. These values go on the wire.
const WORKER := 1
const SOLDIER := 2
const COLONY := 3
const APHID := 4

## Placeholder balance. Tune from playtests.
const STATS := {
	WORKER: {"hp": 40, "damage": 4, "speed": 4.0, "radius": 0.5, "cost": 50, "train_ticks": 100},
	SOLDIER: {"hp": 100, "damage": 12, "speed": 3.5, "radius": 0.6, "cost": 100, "train_ticks": 160},
}
const COLONY_HP := 1500
const COLONY_RADIUS := 2.5
const APHID_RADIUS := 0.6
const START_HONEYDEW := 100
const START_WORKERS := 6
const START_SOLDIERS := 4
const MAX_QUEUE := 5
## A worker milks for this long, then carries LOAD honeydew home.
const MILK_TICKS := 40
const LOAD := 10
const GATHER_REACH := 0.6
const MELEE_REACH := 0.35
const ATTACK_TICKS := 20
## Idle soldiers attack enemies that come this close.
const AGGRO_RANGE := 6.0
## Auto-acquired targets are dropped beyond this, so soldiers don't chase forever.
const LEASH_RANGE := 9.0
const MATCH_TICKS := 10 * 60 * TICK_RATE
## winner value when both colonies fall on the same tick, or equal health at time.
const DRAW := 3

## Spatial grid cell. About one ant-pair's reach, so overlap queries stay
## small even when a crowd packs into a chokepoint.
const GRID_CELL := 1.25
## Widest two ants can be and still touch (two soldiers).
const MAX_PAIR_REACH := 1.2

enum Task { NONE, GATHER, ATTACK }

## Order modes. These values go on the wire.
const MODE_NORMAL := 0  ## move / attack / milk, by target
const MODE_ATTACK_MOVE := 1  ## walk to the point, fighting anything met on the way
const MODE_STOP := 2  ## drop everything and stand still
const MODE_HOLD := 3  ## stay here; hit only what comes into reach
const MODE_COUNT := 4


class Unit:
	var id: int
	var owner: int
	var kind: int = WORKER
	var pos: Vector2
	var prev_pos: Vector2
	var facing: float = 0.0
	var radius: float = 0.5
	var speed: float = 4.0
	var target: Vector2
	var moving: bool = false
	var best_dist: float = 0.0
	var stall: int = 0
	## Set when the unit stalled out; it stops returning to its slot until the
	## next command, so two blocked units can't swap pushes forever.
	var gave_up: bool = false
	var hp: int = 40
	var max_hp: int = 40
	var damage: int = 4
	var cooldown: int = 0
	var task: int = Task.NONE
	## Aphid (GATHER) or enemy (ATTACK) the player ordered.
	var task_target: int = 0
	## Enemy this soldier picked on its own (auto-acquire).
	var engage: int = 0
	## Honeydew carried home.
	var carrying: int = 0
	var milk: int = 0
	## On an explicit move: don't auto-acquire until it arrives.
	var hold: bool = false
	var attacking: bool = false
	## Attack-move: fights whatever it meets, then carries on to `dest`.
	var amove: bool = false
	var dest: Vector2
	## Hold position: never chases; only hits enemies already in reach.
	var hold_ground: bool = false
	## Waypoints around obstacles; the last one is `target`. Empty = straight.
	var path: PackedVector2Array = PackedVector2Array()
	var path_i: int = 0
	## Movement over the last tick, for steering.
	var vel: Vector2 = Vector2.ZERO
	## Touched a moving friend this tick (it's queueing, not blocked).
	var bumped: bool = false
	var wait: int = 0
	var repaths: int = 0
	## After giving up, task code waits until this tick to try again.
	var retry_tick: int = 0
	## Scratch for _resolve_overlaps.
	var shoving: bool = false
	var hot: bool = false


class Colony:
	var id: int
	var owner: int
	var pos: Vector2
	var radius: float = COLONY_RADIUS
	var hp: int = COLONY_HP
	var max_hp: int = COLONY_HP
	var queue: Array[int] = []
	var progress: int = 0
	## Where newly trained ants go. has_rally false = workers auto-milk the
	## nearest aphids and soldiers stay by the mound.
	var has_rally := false
	var rally := Vector2.ZERO
	var rally_id := 0  # aphid or enemy to milk / attack, else 0


class Aphid:
	var id: int
	var pos: Vector2
	var radius: float = APHID_RADIUS


## Static terrain that blocks movement: a rock (circle, `radius`) or a log
## (axis-aligned box, `size`).
class Obstacle:
	var pos: Vector2
	var radius: float = 0.0
	var size: Vector2 = Vector2.ZERO
	## Bounding radius, for cheap rejection.
	var bound: float = 0.0

	func is_box() -> bool:
		return size != Vector2.ZERO

	## Distance from `p` to the surface; negative inside.
	func distance(p: Vector2) -> float:
		if not is_box():
			return p.distance_to(pos) - radius
		var q := (p - pos).abs() - size * 0.5
		return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0)

	## Outward direction from the surface nearest `p`.
	func normal(p: Vector2) -> Vector2:
		if not is_box():
			var d := p - pos
			return d.normalized() if d.length_squared() > 0.000001 else Vector2.RIGHT
		var rel := p - pos
		var q := rel.abs() - size * 0.5
		if q.x > 0.0 or q.y > 0.0:
			var out := Vector2(signf(rel.x) * maxf(q.x, 0.0), signf(rel.y) * maxf(q.y, 0.0))
			return out.normalized()
		# Inside: leave through the nearest face.
		if q.x > q.y:
			return Vector2(1.0 if rel.x >= 0.0 else -1.0, 0.0)
		return Vector2(0.0, 1.0 if rel.y >= 0.0 else -1.0)

	## True if the segment a-b passes within `grow` of the obstacle.
	func blocks(a: Vector2, b: Vector2, grow: float) -> bool:
		if not is_box():
			return Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos) < radius + grow
		var r := Rect2(pos - size * 0.5, size).grow(grow)
		if r.has_point(a) or r.has_point(b):
			return true
		var tl := r.position
		var br := r.end
		var corners := [tl, Vector2(br.x, tl.y), br, Vector2(tl.x, br.y)]
		for i in 4:
			if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
				return true
		return false


var tick: int = 0
var map_half_size: Vector2
var units: Array[Unit] = []
var aphids: Array[Aphid] = []
var obstacles: Array[Obstacle] = []
## player -> Colony, while it stands
var colonies: Dictionary = {}
## player -> honeydew
var honeydew: Dictionary = {}
## 0 while playing, else the winning player, or DRAW.
var winner: int = 0
## Results of commands applied during the last step():
## [{ "player", "seq", "tick", "ok", "what" }]. The server sends these back.
var last_results: Array[Dictionary] = []

var _entities: Dictionary = {}  # id -> Unit / Colony / Aphid
var _next_id: int = 1
var _pending: Array[Dictionary] = []
var _has_match := false
var _damage: Array = []  # [[entity, amount]] applied together at end of tick
var _nav: AStarGrid2D  # built lazily once obstacles exist


func _init(half_size: Vector2 = Vector2(30, 30)) -> void:
	map_half_size = half_size


## Standard 1v1 layout: colonies on the left (player 1) and right (player 2),
## three aphid clusters near each, two in the middle. Starting workers are
## already sent to milk.
func setup_match() -> void:
	for o in standard_obstacles(map_half_size):
		if o.has("size"):
			add_box(o.pos, o.size)
		else:
			add_rock(o.pos, o.radius)
	var cx := map_half_size.x - 8.0
	for p in [1, 2]:
		var side := -1.0 if p == 1 else 1.0
		add_colony(p, Vector2(side * cx, 0))
		honeydew[p] = START_HONEYDEW
		for a in [Vector2(7, -6), Vector2(7, 6), Vector2(-2, 9)]:
			add_aphid(Vector2(side * (cx - a.x), a.y))
	add_aphid(Vector2(0, -map_half_size.y * 0.45))
	add_aphid(Vector2(0, map_half_size.y * 0.45))
	for p in [1, 2]:
		var col: Colony = colonies[p]
		var side := -1.0 if p == 1 else 1.0
		for i in START_WORKERS + START_SOLDIERS:
			var kind := WORKER if i < START_WORKERS else SOLDIER
			var spot := col.pos + Vector2(-side * (col.radius + 1.5), 0).rotated((i - 4.5) * 0.3)
			var u := spawn_unit(p, spot, kind)
			if kind == WORKER:
				_start_gather(u, nearest_aphid(u.pos))


## The standard map's terrain, mirrored left/right. Views call this too, so
## clients draw the same logs and rocks the server simulates.
## Logs: two across the middle leave a 4 m chokepoint at the centre and lanes
## past each end. Rocks: one big rock in each outer lane and one in front of
## each colony, so the straight march to the centre needs a path.
static func standard_obstacles(half: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in [-1.0, 1.0]:
		out.append({"pos": Vector2(0, s * 7.0), "size": Vector2(2.0, 10.0)})
		out.append({"pos": Vector2(0, s * half.y * 0.73), "radius": 3.0})
		out.append({"pos": Vector2(s * (half.x - 19.0), 0), "radius": 1.5})
	return out


func add_rock(pos: Vector2, radius: float) -> Obstacle:
	var o := Obstacle.new()
	o.pos = pos
	o.radius = radius
	o.bound = radius
	obstacles.append(o)
	_nav = null
	return o


func add_box(pos: Vector2, size: Vector2) -> Obstacle:
	var o := Obstacle.new()
	o.pos = pos
	o.size = size
	o.bound = size.length() * 0.5
	obstacles.append(o)
	_nav = null
	return o


func add_colony(owner: int, pos: Vector2) -> Colony:
	var c := Colony.new()
	c.id = _take_id()
	c.owner = owner
	c.pos = pos
	colonies[owner] = c
	_entities[c.id] = c
	honeydew[owner] = honeydew.get(owner, 0)
	# Victory rules start once both sides have a colony.
	_has_match = _has_match or (colonies.has(1) and colonies.has(2))
	return c


func add_aphid(pos: Vector2) -> Aphid:
	var a := Aphid.new()
	a.id = _take_id()
	a.pos = clamp_to_map(pos)
	aphids.append(a)
	_entities[a.id] = a
	return a


func spawn_unit(owner: int, pos: Vector2, kind: int = WORKER) -> Unit:
	var st: Dictionary = STATS[kind]
	var u := Unit.new()
	u.id = _take_id()
	u.owner = owner
	u.kind = kind
	u.radius = st.radius
	u.speed = st.speed
	u.hp = st.hp
	u.max_hp = st.hp
	u.damage = st.damage
	u.pos = clamp_to_map(pos)
	u.prev_pos = u.pos
	u.target = u.pos
	units.append(u)
	_entities[u.id] = u
	return u


func get_unit(id: int) -> Unit:
	var e: Variant = _entities.get(id)
	return e if e is Unit else null


func get_entity(id: int) -> Object:
	return _entities.get(id)


func unit_count(player: int) -> int:
	var n := 0
	for u in units:
		if u.owner == player:
			n += 1
	return n


func nearest_aphid(from: Vector2) -> Aphid:
	var best: Aphid = null
	for a in aphids:
		if best == null or from.distance_squared_to(a.pos) < from.distance_squared_to(best.pos):
			best = a
	return best


## Queues an order to apply at the start of the next tick. This and
## queue_train are the only entry points for player input, local or from the
## network. `seq` is echoed back in last_results so a client can match the
## reply to its command.
func queue_order(player: int, unit_ids: Array, target: Vector2, target_id: int = 0, seq: int = 0,
		mode: int = MODE_NORMAL) -> void:
	_pending.append({"what": "order", "player": player, "ids": unit_ids.duplicate(),
		"target": target, "target_id": target_id, "seq": seq, "mode": mode})


func queue_move(player: int, unit_ids: Array, target: Vector2, seq: int = 0) -> void:
	queue_order(player, unit_ids, target, 0, seq)


func queue_train(player: int, kind: int, seq: int = 0) -> void:
	_pending.append({"what": "train", "player": player, "kind": kind, "seq": seq})


func queue_rally(player: int, target: Vector2, target_id: int = 0, seq: int = 0) -> void:
	_pending.append({"what": "rally", "player": player, "target": target,
		"target_id": target_id, "seq": seq})


## Plain per-entity state for views: they never touch Unit directly, so the
## same view code draws server snapshots. hp is a 0..1 fraction; flags bit 0 =
## carrying honeydew, bit 1 = attacking this tick.
func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in aphids:
		out.append({"id": a.id, "kind": APHID, "owner": 0, "pos": a.pos, "prev_pos": a.pos,
			"facing": 0.0, "hp": 1.0, "flags": 0})
	for p in colonies:
		var c: Colony = colonies[p]
		out.append({"id": c.id, "kind": COLONY, "owner": c.owner, "pos": c.pos, "prev_pos": c.pos,
			"facing": 0.0, "hp": float(c.hp) / c.max_hp, "flags": 0})
	for u in units:
		var flags := (1 if u.carrying > 0 else 0) | (2 if u.attacking else 0)
		out.append({"id": u.id, "kind": u.kind, "owner": u.owner, "pos": u.pos,
			"prev_pos": u.prev_pos, "facing": u.facing, "hp": float(u.hp) / u.max_hp, "flags": flags})
	return out


## Economy and production for one player, for the HUD.
func player_state(player: int) -> Dictionary:
	var col: Colony = colonies.get(player)
	var progress := 0.0
	var queue: Array[int] = []
	if col:
		queue = col.queue.duplicate()
		if not queue.is_empty():
			progress = float(col.progress) / STATS[queue[0]].train_ticks
	return {"honeydew": honeydew.get(player, 0), "units": unit_count(player),
		"queue": queue, "queue_len": queue.size(), "front": 0 if queue.is_empty() else queue[0],
		"progress": progress, "has_rally": col != null and col.has_rally,
		"rally": col.rally if col else Vector2.ZERO}


## Validates and applies an order. Returns false (and changes nothing) if the
## match is over, the target is not finite, the list is empty or too long, or
## any unit is unknown or not owned by `player`.
##   target_id = enemy ant or colony: attack it (soldiers fight ants on the
##               way to a colony).
##   target_id = aphid: workers milk it; others move there.
##   otherwise: move in formation to `target`.
## `mode` overrides that: attack-move to `target` (target_id ignored), stop,
## or hold position (target ignored). Unknown modes fail.
func issue_order(player: int, unit_ids: Array, target: Vector2, target_id: int = 0,
		mode: int = MODE_NORMAL) -> bool:
	if winner != 0 or not target.is_finite() or mode < 0 or mode >= MODE_COUNT:
		return false
	if unit_ids.is_empty() or unit_ids.size() > MAX_UNITS_PER_PLAYER:
		return false
	var seen := {}
	var group: Array[Unit] = []
	for id in unit_ids:
		var u := get_unit(int(id))
		if u == null or u.owner != player:
			return false
		if not seen.has(u.id):
			seen[u.id] = true
			group.append(u)

	match mode:
		MODE_ATTACK_MOVE:
			_formation_move(group, target, true)
			return true
		MODE_STOP:
			for u in group:
				_clear_task(u)
				_halt(u)
			return true
		MODE_HOLD:
			for u in group:
				_clear_task(u)
				u.moving = false
				u.target = u.pos  # Walks back here if shoved.
				u.hold_ground = true
			return true

	var t: Object = _entities.get(target_id) if target_id != 0 else null
	if (t is Unit or t is Colony) and t.owner != player:
		for u in group:
			_clear_task(u)
			u.task = Task.ATTACK
			u.task_target = t.id
		return true
	if t is Aphid:
		var others: Array[Unit] = []
		for u in group:
			if u.kind == WORKER:
				_start_gather(u, t)
			else:
				others.append(u)
		if not others.is_empty():
			_formation_move(others, t.pos)
		return true
	_formation_move(group, target)
	return true


## Sets where `player`'s newly trained ants go. A target_id that is an aphid
## or an enemy is remembered so new ants milk / attack it; anything else is a
## ground point; the colony itself clears the rally. Fails if the match is over, the colony is gone or the point
## is not finite.
func issue_rally(player: int, target: Vector2, target_id: int = 0) -> bool:
	var col: Colony = colonies.get(player)
	if winner != 0 or col == null or not target.is_finite():
		return false
	var t: Object = _entities.get(target_id) if target_id != 0 else null
	if t == col:
		col.has_rally = false  # Rallying onto the mound itself clears it.
		col.rally_id = 0
		return true
	var keep_id: bool = t is Aphid or ((t is Unit or t is Colony) and t.owner != player)
	col.rally_id = target_id if keep_id else 0
	col.rally = t.pos if keep_id else clamp_to_map(target)
	col.has_rally = true
	return true


func issue_move(player: int, unit_ids: Array, target: Vector2) -> bool:
	return issue_order(player, unit_ids, target, 0)


## Queues a worker or soldier at `player`'s colony and takes the honeydew now.
## Fails if the match is over, the kind is unknown, the colony is gone, its
## queue is full, honeydew is short, or ants + queued would pass the cap.
func issue_train(player: int, kind: int) -> bool:
	if winner != 0 or not STATS.has(kind):
		return false
	var col: Colony = colonies.get(player)
	if col == null or col.queue.size() >= MAX_QUEUE:
		return false
	if unit_count(player) + col.queue.size() >= MAX_UNITS_PER_PLAYER:
		return false
	var cost: int = STATS[kind].cost
	if honeydew.get(player, 0) < cost:
		return false
	honeydew[player] -= cost
	col.queue.append(kind)
	return true


## Square-ish grid of slots centred on `center`. The whole grid is shifted to
## fit inside the map, so slots near an edge never pile onto each other.
func formation_slots(center: Vector2, count: int) -> Array[Vector2]:
	var spacing := UNIT_RADIUS * 2.0 + FORMATION_GAP
	var cols := int(ceil(sqrt(count)))
	var rows := int(ceil(float(count) / cols))
	var half_extent := Vector2(cols - 1, rows - 1) * spacing * 0.5
	var room := (map_half_size - Vector2(UNIT_RADIUS, UNIT_RADIUS) - half_extent).max(Vector2.ZERO)
	center = Vector2(clampf(center.x, -room.x, room.x), clampf(center.y, -room.y, room.y))
	var slots: Array[Vector2] = []
	for i in count:
		var c := i % cols
		var r := i / cols
		var offset := Vector2((c - (cols - 1) * 0.5) * spacing, (r - (rows - 1) * 0.5) * spacing)
		slots.append(clamp_to_map(center + offset))
	return _free_slots(slots, spacing)


## Moves slots that fall in or against an obstacle to the nearest open grid
## cell that no other slot is using, so a formation ordered onto a log
## wraps around it instead of stacking on its edge.
func _free_slots(slots: Array[Vector2], spacing: float) -> Array[Vector2]:
	if obstacles.is_empty():
		return slots
	var taken: Array[Vector2] = []
	var bad: Array[int] = []
	for i in slots.size():
		if _blocked(slots[i], UNIT_RADIUS + FORMATION_GAP * 0.5):
			bad.append(i)
		else:
			taken.append(slots[i])
	for i in bad:
		var best := _walkable(slots[i], UNIT_RADIUS)
		var found := false
		for ring in range(0, 12):
			var cands: Array[Vector2] = []
			for x in range(-ring, ring + 1):
				for y in range(-ring, ring + 1):
					if maxi(absi(x), absi(y)) != ring:
						continue
					var p := clamp_to_map(slots[i] + Vector2(x, y) * NAV_CELL)
					if _blocked(p, UNIT_RADIUS + FORMATION_GAP * 0.5):
						continue
					var free := true
					for t in taken:
						if t.distance_to(p) < spacing * 0.9:
							free = false
							break
					if free:
						cands.append(p)
			if not cands.is_empty():
				best = cands[0]
				for c in cands:
					if c.distance_squared_to(slots[i]) < best.distance_squared_to(slots[i]):
						best = c
				found = true
				break
		if not found:
			best = _walkable(slots[i], UNIT_RADIUS)
		slots[i] = best
		taken.append(best)
	return slots


func step() -> void:
	tick += 1
	_apply_pending()
	if winner != 0:
		return

	_produce()
	var grid := _build_grid()
	for u in units:
		u.prev_pos = u.pos
		if u.cooldown > 0:
			u.cooldown -= 1
		u.attacking = false
		if u.kind == SOLDIER or u.amove or u.hold_ground:
			_acquire(u, grid)
		var foe := _fight_target(u)
		if foe:
			_fight(u, foe)
		elif u.task == Task.GATHER:
			_gather(u)
		elif u.amove and not u.moving:
			if u.pos.distance_to(u.dest) > RETURN_DISTANCE:
				_go(u, u.dest)  # Fight over; carry on.
			else:
				u.amove = false
		elif not u.moving and not u.gave_up and u.pos.distance_to(u.target) > RETURN_DISTANCE:
			_start_moving(u, false)

	for u in units:
		u.bumped = false
		if not u.moving:
			u.hold = false
			continue
		var t2 := Time.get_ticks_usec()
		var aim := _aim(u)
		var to := aim - u.pos
		var d := to.length()
		var max_step := u.speed * DT
		if u.stall > 2 or u.wait > 2:
			max_step *= JAM_PACE  # Not getting anywhere: stop shoving the crowd.
		var last := u.path_i >= u.path.size() - 1
		if last and d <= max_step:
			u.pos = aim
			u.moving = false
		elif d > 0.0001:
			var dir := _avoid(u, to / d, d, grid)
			u.pos += dir * minf(max_step, d)
			if dir.length_squared() > 0.0001:
				u.facing = dir.angle()
		prof["mv"] = prof.get("mv", 0) + Time.get_ticks_usec() - t2

	var t1 := Time.get_ticks_usec()
	_resolve_overlaps()
	prof["ov"] = prof.get("ov", 0) + Time.get_ticks_usec() - t1

	for u in units:
		u.vel = u.pos - u.prev_pos

	for u in units:
		if u.moving:
			_update_stall(u)

	_apply_damage()
	_check_victory()


func _apply_pending() -> void:
	last_results.clear()
	var cmds := _pending
	_pending = []
	for c in cmds:
		var ok := false
		if c.what == "train":
			ok = issue_train(c.player, c.kind)
		elif c.what == "rally":
			ok = issue_rally(c.player, c.target, c.target_id)
		else:
			ok = issue_order(c.player, c.ids, c.target, c.target_id, c.get("mode", MODE_NORMAL))
		last_results.append({"player": c.player, "seq": c.seq, "tick": tick, "ok": ok, "what": c.what})


func _produce() -> void:
	for p in colonies:
		var col: Colony = colonies[p]
		if col.queue.is_empty():
			continue
		col.progress += 1
		if col.progress < STATS[col.queue[0]].train_ticks:
			continue
		var kind: int = col.queue.pop_front()
		col.progress = 0
		# Out of the side facing the map centre, fanned so ants don't stack.
		var out := (-col.pos).normalized() if col.pos.length() > 0.01 else Vector2.RIGHT
		out = out.rotated(((_next_id % 7) - 3) * 0.35)
		var u := spawn_unit(p, col.pos + out * (col.radius + 1.0), kind)
		if col.has_rally:
			# A rally target that has since died falls back to its last point.
			var tid := col.rally_id if _entities.has(col.rally_id) else 0
			issue_order(p, [u.id], col.rally, tid)
		elif kind == WORKER:
			_start_gather(u, nearest_aphid(col.pos))


func _clear_task(u: Unit) -> void:
	u.task = Task.NONE
	u.task_target = 0
	u.engage = 0
	u.milk = 0
	u.hold = false
	u.gave_up = false
	u.amove = false
	u.hold_ground = false


func _start_gather(u: Unit, a: Aphid) -> void:
	_clear_task(u)
	if a == null:
		return
	u.task = Task.GATHER
	u.task_target = a.id


func _formation_move(group: Array[Unit], target: Vector2, attack_move := false) -> void:
	target = _walkable(clamp_to_map(target), UNIT_RADIUS)
	var slots := formation_slots(target, group.size())
	# Closest units claim their nearest free slot first.
	group.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.pos.distance_squared_to(target) < b.pos.distance_squared_to(target))
	for u in group:
		var best := 0
		for i in range(1, slots.size()):
			if u.pos.distance_squared_to(slots[i]) < u.pos.distance_squared_to(slots[best]):
				best = i
		_clear_task(u)
		u.hold = not attack_move
		u.amove = attack_move
		u.dest = slots[best]
		u.target = slots[best]
		slots.remove_at(best)
		_start_moving(u)


## Walks toward `p`, restarting after a stall. Task code calls this every tick.
func _go(u: Unit, p: Vector2) -> void:
	p = _walkable(clamp_to_map(p), u.radius)
	if u.moving and u.target.distance_to(p) < 0.3:
		return
	# Gave up in a jam: wait a moment before pushing in again.
	if u.gave_up and tick < u.retry_tick and u.target.distance_to(p) < 1.0:
		return
	# Chasing along a path: nudge its end rather than re-plan every tick.
	if u.moving and u.path.size() > 1 and u.target.distance_to(p) < 1.5 \
			and line_clear(u.path[u.path.size() - 2], p, u.radius):
		u.path[u.path.size() - 1] = p
		u.target = p
		u.gave_up = false
		return
	u.target = p
	u.gave_up = false
	_start_moving(u)


## Stops here and stays (no walking back to an old slot).
func _halt(u: Unit) -> void:
	u.moving = false
	u.target = u.pos
	u.gave_up = true


func _gather(u: Unit) -> void:
	if u.carrying > 0:
		var col: Colony = colonies.get(u.owner)
		if col == null:
			_clear_task(u)
			return
		if u.pos.distance_to(col.pos) <= col.radius + u.radius + GATHER_REACH:
			honeydew[u.owner] = honeydew.get(u.owner, 0) + u.carrying
			u.carrying = 0
		else:
			_go(u, col.pos + (u.pos - col.pos).normalized() * (col.radius + u.radius))
		return
	var a: Aphid = _entities.get(u.task_target)
	if a == null:
		_clear_task(u)
		return
	if u.pos.distance_to(a.pos) <= a.radius + u.radius + GATHER_REACH:
		_halt(u)
		u.facing = (a.pos - u.pos).angle()
		u.milk += 1
		if u.milk >= MILK_TICKS:
			u.milk = 0
			u.carrying = LOAD
	else:
		var dir := (u.pos - a.pos).normalized() if u.pos != a.pos else Vector2.RIGHT
		_go(u, a.pos + dir * (a.radius + u.radius))


## Soldiers (and any ant on attack-move or hold) pick the nearest enemy ant
## in AGGRO_RANGE when idle, arrived, or marching on a colony; failing that,
## an enemy colony in range. Holding ants only look as far as they can hit.
func _acquire(u: Unit, grid: Dictionary) -> void:
	if u.engage != 0 or u.hold:
		return
	if u.task == Task.ATTACK and _entities.get(u.task_target) is Unit:
		return
	if u.task == Task.GATHER:
		return
	var best: Unit = null
	var best_d := AGGRO_RANGE * AGGRO_RANGE
	for o in _grid_query(grid, u.pos, AGGRO_RANGE):
		if o.owner == u.owner:
			continue
		var d := u.pos.distance_squared_to(o.pos)
		if u.hold_ground and d > pow(u.radius + o.radius + MELEE_REACH, 2):
			continue
		if d < best_d:
			best_d = d
			best = o
	if best:
		u.engage = best.id
		return
	if u.task == Task.NONE:
		for p in colonies:
			var c: Colony = colonies[p]
			var reach := u.radius + MELEE_REACH if u.hold_ground else AGGRO_RANGE
			if p != u.owner and u.pos.distance_to(c.pos) - c.radius < reach:
				u.engage = c.id


func _fight_target(u: Unit) -> Object:
	if u.engage != 0:
		var e: Object = _entities.get(u.engage)
		if e != null and u.pos.distance_to(e.pos) - e.radius <= LEASH_RANGE:
			return e
		u.engage = 0
		if u.amove:
			_go(u, u.dest)  # Chase over (dead or out of leash): back on course.
	if u.task == Task.ATTACK:
		var t: Object = _entities.get(u.task_target)
		if t != null:
			return t
		_clear_task(u)
		_halt(u)
	return null


func _fight(u: Unit, foe: Object) -> void:
	var reach: float = u.radius + foe.radius + MELEE_REACH
	var to: Vector2 = foe.pos - u.pos
	if u.hold_ground and to.length() > reach:
		u.engage = 0  # Out of reach: let it go rather than step off the spot.
		return
	if to.length() <= reach:
		if u.hold_ground:
			u.moving = false  # Keep its spot as the place to return to.
		else:
			_halt(u)
		u.facing = to.angle()
		u.attacking = true
		if u.cooldown == 0:
			_damage.append([foe, u.damage])
			u.cooldown = ATTACK_TICKS
	else:
		_go(u, foe.pos)


## All hits of a tick land together, so two ants can kill each other.
func _apply_damage() -> void:
	if _damage.is_empty():
		return
	for d in _damage:
		d[0].hp -= d[1]
	_damage.clear()
	var alive: Array[Unit] = []
	for u in units:
		if u.hp > 0:
			alive.append(u)
		else:
			_entities.erase(u.id)
	units = alive


func _check_victory() -> void:
	if not _has_match:
		return
	for p in colonies.keys():
		if colonies[p].hp <= 0:
			_entities.erase(colonies[p].id)
			colonies.erase(p)
	var a := colonies.has(1)
	var b := colonies.has(2)
	if not a and not b:
		winner = DRAW
	elif not a:
		winner = 2
	elif not b:
		winner = 1
	elif tick >= MATCH_TICKS:
		var ha: float = float(colonies[1].hp) / colonies[1].max_hp
		var hb: float = float(colonies[2].hp) / colonies[2].max_hp
		winner = 1 if ha > hb else (2 if hb > ha else DRAW)


## `fresh` = a new destination (resets the re-plan budget); false = walking
## back to the same slot.
func _start_moving(u: Unit, fresh := true) -> void:
	u.moving = true
	u.stall = 0
	u.wait = 0
	if fresh:
		u.repaths = 0
	_plan(u)
	u.best_dist = _remaining(u)


## Plans waypoints from here to u.target: straight when nothing is in the way.
func _plan(u: Unit) -> void:
	u.path = find_path(u.pos, u.target, u.radius)
	u.path_i = 0
	if not u.path.is_empty():
		u.target = u.path[u.path.size() - 1]  # Walled off: settle for the closest point.


## Where the unit heads now: its next waypoint, else its target.
func _aim(u: Unit) -> Vector2:
	while u.path_i < u.path.size() - 1 and u.pos.distance_to(u.path[u.path_i]) < WAYPOINT_REACH:
		u.path_i += 1
	return u.path[u.path_i] if u.path_i < u.path.size() else u.target


## Distance left along the path, for stall checks.
func _remaining(u: Unit) -> float:
	if u.path_i >= u.path.size():
		return u.pos.distance_to(u.target)
	var d := u.pos.distance_to(u.path[u.path_i])
	for i in range(u.path_i + 1, u.path.size()):
		d += u.path[i - 1].distance_to(u.path[i])
	return d


## Bends `dir` sideways away from friends just ahead that aren't walking the
## same way. A friend dead ahead is passed on the right, so two ants meeting
## head-on always pick opposite sides.
func _avoid(u: Unit, dir: Vector2, dist_left: float, grid: Dictionary) -> Vector2:
	var left := Vector2(dir.y, -dir.x)  # +x right, +y down the screen: this is the unit's left.
	var side := Vector2.ZERO
	for o in _grid_query(grid, u.pos, MAX_PAIR_REACH + AVOID_MARGIN):
		if o == u or o.owner != u.owner:
			continue
		var rel: Vector2 = o.pos - u.pos
		var dist := rel.length()
		var reach: float = u.radius + o.radius + AVOID_MARGIN
		if dist > reach or dist < 0.0001 or dist > dist_left + o.radius:
			continue
		var ahead := rel.dot(dir) / dist
		if ahead < 0.3:
			continue
		if o.moving and o.vel.dot(dir) > 0.5 * o.speed * DT:
			continue  # Same way, in line: just follow.
		var lateral := rel.dot(left)
		var away := -left if lateral > 0.05 * dist else left if lateral < -0.05 * dist else -left
		side += away * (1.0 - dist / reach) * ahead
	if side == Vector2.ZERO:
		return dir
	return (dir + side * AVOID_GAIN).normalized()


## Moving and still getting somewhere.
func _shoves(u: Unit) -> bool:
	return u.moving and u.stall <= 2 and u.wait <= 2


func _update_stall(u: Unit) -> void:
	var d := _remaining(u)
	if d < u.best_dist - STALL_EPSILON:
		u.best_dist = d
		u.stall = 0
		u.wait = 0
		return
	if u.bumped:
		u.wait += 1  # In a queue that's still flowing: be patient.
		if u.wait < WAIT_TICKS:
			return
	else:
		u.stall += 1
		if u.stall < STALL_TICKS:
			return
	if u.repaths < MAX_REPATHS and u.pos.distance_to(u.target) > RETURN_DISTANCE:
		u.repaths += 1
		u.stall = 0
		u.wait = 0
		_plan(u)
		u.best_dist = _remaining(u)
		return
	u.moving = false
	u.gave_up = true
	u.retry_tick = tick + STALL_TICKS
	u.amove = false  # Blocked: stop retrying the attack-move.


## Waypoints from `from` to `to` for an ant of `radius`, ending at `to`.
## Empty when the straight line is clear (the common case, and free). Goes
## to the nearest reachable point when `to` is walled off.
static var prof := {}
func find_path(from: Vector2, to: Vector2, radius: float) -> PackedVector2Array:
	var t0 := Time.get_ticks_usec()
	var r := _find_path(from, to, radius)
	prof["fp"] = prof.get("fp", 0) + Time.get_ticks_usec() - t0
	prof["fpn"] = prof.get("fpn", 0) + 1
	if not r.is_empty(): prof["fpa"] = prof.get("fpa", 0) + 1
	return r
func _find_path(from: Vector2, to: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if obstacles.is_empty() or line_clear(from, to, radius):
		return out
	var nav := _nav_grid()
	var a := _nav_free_cell(nav, _to_cell(from))
	var b := _nav_free_cell(nav, _to_cell(to))
	if a == Vector2i(-99999, -99999) or b == Vector2i(-99999, -99999):
		return out
	var cells := nav.get_id_path(a, b, true)
	if cells.is_empty():
		return out
	var pts: Array[Vector2] = [from]
	for c in cells:
		pts.append(_cell_center(c))
	if line_clear(pts[pts.size() - 1], to, radius):
		pts.append(to)
	# String-pull: from each kept point, walk on while the next is in sight.
	var i := 0
	while i < pts.size() - 1:
		var j := i + 1
		while j + 1 < pts.size() and line_clear(pts[i], pts[j + 1], radius):
			j += 1
		out.append(pts[j])
		i = j
	return out


## True if an ant of `radius` can walk straight from a to b.
func line_clear(a: Vector2, b: Vector2, radius: float) -> bool:
	for o in obstacles:
		if o.blocks(a, b, radius + 0.05):
			return false
	return true


func _blocked(p: Vector2, radius: float) -> bool:
	for o in obstacles:
		if o.distance(p) < radius:
			return true
	return false


## `p`, or the nearest point beside the obstacle it falls in.
func _walkable(p: Vector2, radius: float) -> Vector2:
	for _i in 4:
		var moved := false
		for o in obstacles:
			var d := o.distance(p)
			if d < radius + 0.05:
				p = clamp_to_map(p + o.normal(p) * (radius + 0.2 - d))
				moved = true
		if not moved:
			break
	return p


func _nav_grid() -> AStarGrid2D:
	if _nav != null:
		return _nav
	_nav = AStarGrid2D.new()
	var lo := Vector2i(int(floor(-map_half_size.x / NAV_CELL)), int(floor(-map_half_size.y / NAV_CELL)))
	var size := Vector2i(int(ceil(map_half_size.x * 2.0 / NAV_CELL)), int(ceil(map_half_size.y * 2.0 / NAV_CELL)))
	_nav.region = Rect2i(lo, size)
	_nav.cell_size = Vector2(NAV_CELL, NAV_CELL)
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_nav.update()
	for x in range(lo.x, lo.x + size.x):
		for y in range(lo.y, lo.y + size.y):
			if _blocked(_cell_center(Vector2i(x, y)), NAV_CLEARANCE):
				_nav.set_point_solid(Vector2i(x, y))
	return _nav


func _to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / NAV_CELL)), int(floor(p.y / NAV_CELL)))


func _cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * NAV_CELL


## `c`, or the nearest open cell to it (a unit squeezed against a log, or a
## click on one). Returns (-99999, -99999) if nothing is open nearby.
func _nav_free_cell(nav: AStarGrid2D, c: Vector2i) -> Vector2i:
	for ring in range(0, 8):
		var best := Vector2i(-99999, -99999)
		for x in range(-ring, ring + 1):
			for y in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring:
					continue
				var k := c + Vector2i(x, y)
				if nav.is_in_boundsv(k) and not nav.is_point_solid(k):
					if best.x == -99999 or Vector2(k - c).length_squared() < Vector2(best - c).length_squared():
						best = k
		if best.x != -99999:
			return best
	return Vector2i(-99999, -99999)


## Uniform grid of units, rebuilt each use. Keeps overlap and target queries
## near O(n) at 2 x 50 ants.
func _build_grid() -> Dictionary:
	var grid := {}
	for u in units:
		var k := _cell_key(u.pos)
		if grid.has(k):
			grid[k].append(u)
		else:
			grid[k] = [u]
	return grid


func _cell_key(p: Vector2) -> int:
	return (int(floor(p.x / GRID_CELL)) + 1000) * 4096 + int(floor(p.y / GRID_CELL)) + 1000


func _grid_query(grid: Dictionary, p: Vector2, r: float) -> Array:
	var out: Array = []
	var cx := int(floor(p.x / GRID_CELL))
	var cy := int(floor(p.y / GRID_CELL))
	var n := int(ceil(r / GRID_CELL))
	for x in range(cx - n, cx + n + 1):
		for y in range(cy - n, cy + n + 1):
			var cell: Variant = grid.get((x + 1000) * 4096 + y + 1000)
			if cell != null:
				out.append_array(cell)
	return out


## Pushes overlapping units apart, and out of colonies, logs and rocks.
## The first passes cover every unit; later ones only the units still being
## pushed hard (a jam), so a packed chokepoint settles without paying for
## extra passes over the whole map.
func _resolve_overlaps() -> void:
	for u in units:
		u.shoving = _shoves(u)
	var active: Array = units
	for pass_i in MAX_OVERLAP_PASSES:
		var full := pass_i < OVERLAP_PASSES
		var grid := _build_grid()
		var hot := {}
		var touched := {}
		for a in active:
			# Each pair once (lower id first, unless only one side is in this
			# pass); cells are scanned in a fixed order, so the same state
			# always resolves the same way.
			for b in _grid_query(grid, a.pos, MAX_PAIR_REACH):
				if b == a or (b.id < a.id and (full or hot.has(b) or b.hot)):
					continue
				var min_d: float = a.radius + b.radius
				var delta: Vector2 = b.pos - a.pos
				var d2 := delta.length_squared()
				if d2 >= min_d * min_d:
					continue
				var d := sqrt(d2)
				var dir := delta / d if d > 0.0001 else Vector2.RIGHT.rotated(float(a.id * 7 + b.id))
				var push := (min_d - d)
				if push > SETTLED_PUSH:
					hot[a] = true
					hot[b] = true
				if a.owner == b.owner:
					a.bumped = a.bumped or b.moving
					b.bumped = b.bumped or a.moving
				# Idle units yield to moving ones so groups can pass through,
				# but not to one that's jammed: that would crush the crowd.
				var wa := 0.5
				if a.shoving != b.shoving:
					wa = 0.2 if a.shoving else 0.8
				a.pos -= dir * push * wa
				b.pos += dir * push * (1.0 - wa)
				touched[a] = true
				touched[b] = true
		for u in active:
			u.hot = hot.has(u)
		for u in (units if full else touched.keys()):
			_push_out_of_terrain(u)
		if not full or pass_i == OVERLAP_PASSES - 1:
			if hot.is_empty():
				break
			active = hot.keys()
			active.sort_custom(func(x: Unit, y: Unit) -> bool: return x.id < y.id)
	for u in units:
		u.hot = false


func _push_out_of_terrain(u: Unit) -> void:
	for p in colonies:
		var c: Colony = colonies[p]
		var delta := u.pos - c.pos
		var min_d := c.radius + u.radius
		if delta.length_squared() < min_d * min_d:
			var dir := delta.normalized() if delta.length_squared() > 0.0001 else Vector2.RIGHT
			u.pos = c.pos + dir * min_d
	for o in obstacles:
		if absf(u.pos.x - o.pos.x) > o.bound + u.radius or absf(u.pos.y - o.pos.y) > o.bound + u.radius:
			continue
		var od := o.distance(u.pos)
		if od < u.radius:
			u.pos += o.normal(u.pos) * (u.radius - od)
	# Clamp every pass so a push into a wall moves the other unit instead.
	u.pos = clamp_to_map(u.pos)


func clamp_to_map(p: Vector2) -> Vector2:
	var m := map_half_size - Vector2(UNIT_RADIUS, UNIT_RADIUS)
	return Vector2(clampf(p.x, -m.x, m.x), clampf(p.y, -m.y, m.y))


func _take_id() -> int:
	var id := _next_id
	_next_id += 1
	return id
