class_name SimWorld
extends RefCounted
## Authoritative game state and rules.
##
## No nodes, rendering or input live here, so a dedicated server can run this
## class unchanged later. Clients queue commands (queue_move); step() applies
## them at the start of the next tick, and views read snapshot() only.
## Positions are 2D on the ground plane: x maps to world X, y maps to world Z.

const TICK_RATE := 20
const DT := 1.0 / TICK_RATE

const MAX_UNITS_PER_PLAYER := 50
const UNIT_RADIUS := 0.5
const UNIT_SPEED := 4.0
const FORMATION_GAP := 0.25
const OVERLAP_PASSES := 3
## A moving unit that gains less than this per tick for STALL_TICKS gives up
## and accepts where it is, so crowds settle instead of pushing forever.
const STALL_EPSILON := 0.02
const STALL_TICKS := 20
## An idle unit shoved further than this from its slot walks back to it.
const RETURN_DISTANCE := 0.6


class Unit:
	var id: int
	var owner: int
	var pos: Vector2
	var prev_pos: Vector2
	var facing: float = 0.0
	var radius: float = 0.5
	var speed: float = 4.0
	var target: Vector2
	var moving: bool = false
	var best_dist: float = 0.0
	var stall: int = 0


var tick: int = 0
var map_half_size: Vector2
var units: Array[Unit] = []
## Results of commands applied during the last step():
## [{ "player", "tick", "ok" }]. Online this becomes the accept/reject reply.
var last_results: Array[Dictionary] = []

var _by_id: Dictionary = {}
var _next_id: int = 1
var _pending: Array[Dictionary] = []


func _init(half_size: Vector2 = Vector2(30, 30)) -> void:
	map_half_size = half_size


func spawn_unit(owner: int, pos: Vector2) -> Unit:
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.owner = owner
	u.radius = UNIT_RADIUS
	u.speed = UNIT_SPEED
	u.pos = clamp_to_map(pos)
	u.prev_pos = u.pos
	u.target = u.pos
	units.append(u)
	_by_id[u.id] = u
	return u


func get_unit(id: int) -> Unit:
	return _by_id.get(id)


## Queues a move to apply at the start of the next tick. This is the only
## entry point for player input, local or (later) from the network.
func queue_move(player: int, unit_ids: Array, target: Vector2) -> void:
	_pending.append({"player": player, "ids": unit_ids.duplicate(), "target": target})


## Plain per-unit state for views: they never touch Unit directly, so the
## same view code can later draw server snapshots.
func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in units:
		out.append({"id": u.id, "owner": u.owner, "pos": u.pos,
			"prev_pos": u.prev_pos, "facing": u.facing})
	return out


## Validates and applies a move command. Returns false (and changes nothing)
## if the target is not finite, the list is empty or too long, or any unit is
## unknown or not owned by `player`.
func issue_move(player: int, unit_ids: Array, target: Vector2) -> bool:
	if not target.is_finite():
		return false
	if unit_ids.is_empty() or unit_ids.size() > MAX_UNITS_PER_PLAYER:
		return false
	var seen := {}
	var group: Array[Unit] = []
	for id in unit_ids:
		var u: Unit = _by_id.get(id)
		if u == null or u.owner != player:
			return false
		if not seen.has(u.id):
			seen[u.id] = true
			group.append(u)

	target = clamp_to_map(target)
	var slots := formation_slots(target, group.size())
	# Closest units claim their nearest free slot first.
	group.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.pos.distance_squared_to(target) < b.pos.distance_squared_to(target))
	for u in group:
		var best := 0
		for i in range(1, slots.size()):
			if u.pos.distance_squared_to(slots[i]) < u.pos.distance_squared_to(slots[best]):
				best = i
		u.target = slots[best]
		slots.remove_at(best)
		_start_moving(u)
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
	return slots


func step() -> void:
	tick += 1
	_apply_pending()

	for u in units:
		u.prev_pos = u.pos
		if not u.moving and u.pos.distance_to(u.target) > RETURN_DISTANCE:
			_start_moving(u)
		if not u.moving:
			continue
		var to := u.target - u.pos
		var d := to.length()
		var max_step := u.speed * DT
		if d <= max_step:
			u.pos = u.target
			u.moving = false
		else:
			u.pos += to / d * max_step
			u.facing = to.angle()

	_resolve_overlaps()

	for u in units:
		u.pos = clamp_to_map(u.pos)
		if u.moving:
			_update_stall(u)


func _apply_pending() -> void:
	last_results.clear()
	var cmds := _pending
	_pending = []
	for c in cmds:
		var ok := issue_move(c.player, c.ids, c.target)
		last_results.append({"player": c.player, "tick": tick, "ok": ok})


func _start_moving(u: Unit) -> void:
	u.moving = true
	u.best_dist = u.pos.distance_to(u.target)
	u.stall = 0


func _update_stall(u: Unit) -> void:
	var d := u.pos.distance_to(u.target)
	if d < u.best_dist - STALL_EPSILON:
		u.best_dist = d
		u.stall = 0
	else:
		u.stall += 1
		if u.stall >= STALL_TICKS:
			u.moving = false
			u.target = u.pos  # Accept this spot so it doesn't retry forever.


## Pushes overlapping units apart. O(n^2) is fine for the prototype's 20 units;
## swap in a spatial hash before scaling to 2 x 50.
func _resolve_overlaps() -> void:
	var n := units.size()
	for _pass in OVERLAP_PASSES:
		for i in n:
			var a := units[i]
			for j in range(i + 1, n):
				var b := units[j]
				var min_d := a.radius + b.radius
				var delta := b.pos - a.pos
				var d2 := delta.length_squared()
				if d2 >= min_d * min_d:
					continue
				var d := sqrt(d2)
				var dir := delta / d if d > 0.0001 else Vector2.RIGHT.rotated(float(a.id * 7 + b.id))
				var push := (min_d - d)
				# Idle units yield to moving ones so groups can pass through.
				var wa := 0.5
				if a.moving != b.moving:
					wa = 0.2 if a.moving else 0.8
				a.pos -= dir * push * wa
				b.pos += dir * push * (1.0 - wa)


func clamp_to_map(p: Vector2) -> Vector2:
	var m := map_half_size - Vector2(UNIT_RADIUS, UNIT_RADIUS)
	return Vector2(clampf(p.x, -m.x, m.x), clampf(p.y, -m.y, m.y))
