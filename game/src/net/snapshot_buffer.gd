class_name SnapshotBuffer
extends RefCounted
## Client-side jitter buffer. Holds recent server snapshots and draws the world
## a little in the past (delay_ticks), blending between the two snapshots either
## side of the render time. Late, duplicate or out-of-order packets are absorbed;
## a lost packet just widens one blend. Never extrapolates: if snapshots stop
## arriving, units hold at the newest known position.
##
## The render clock follows the newest snapshot with a gentle speed correction
## (+-10%) so jitter doesn't cause visible stutter, and snaps if it falls more
## than RESYNC_TICKS behind or ahead (app resume, long stall).

const MAX_SNAPSHOTS := 32
const RESYNC_TICKS := 6.0
const MAX_RATE_CORRECTION := 0.1

## 2 ticks = 100 ms at 20 Hz. Covers ~50 ms jitter plus one lost packet.
var delay_ticks := 2.0
var tick_rate := 20
var render_tick := -1.0

## Ascending by tick: [{ "tick": int, "units": { id: entry } }]
var _snaps: Array[Dictionary] = []


func clear() -> void:
	_snaps.clear()
	render_tick = -1.0


func is_empty() -> bool:
	return _snaps.is_empty()


func newest_tick() -> int:
	return -1 if _snaps.is_empty() else _snaps[-1].tick


## Adds a decoded snapshot. Returns false for duplicates and packets older than
## everything still buffered.
func push(tick: int, units: Array) -> bool:
	if not _snaps.is_empty() and tick < _snaps[0].tick:
		return false
	var by_id := {}
	for u in units:
		by_id[u.id] = u
	var i := _snaps.size()
	while i > 0 and _snaps[i - 1].tick > tick:
		i -= 1
	if i > 0 and _snaps[i - 1].tick == tick:
		return false
	_snaps.insert(i, {"tick": tick, "units": by_id})
	while _snaps.size() > MAX_SNAPSHOTS:
		_snaps.pop_front()
	return true


func advance(delta: float) -> void:
	if _snaps.is_empty():
		return
	var newest := float(newest_tick())
	var target := newest - delay_ticks
	if render_tick < 0.0 or absf(target - render_tick) > RESYNC_TICKS:
		render_tick = target
	else:
		var rate := 1.0 + clampf((target - render_tick) * 0.1, -MAX_RATE_CORRECTION, MAX_RATE_CORRECTION)
		render_tick += delta * tick_rate * rate
	render_tick = minf(render_tick, newest)


## Interpolated entities at render_tick, in the same shape as SimWorld.snapshot()
## (prev_pos == pos, so views draw them with alpha 1). Other fields (hp, flags)
## come from the older snapshot. An entity missing from it has died or not yet
## appeared at render time.
func sample() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _snaps.is_empty():
		return out
	var a: Dictionary = _snaps[0]
	var b: Dictionary = {}
	for s in _snaps:
		if s.tick <= render_tick:
			a = s
		else:
			b = s
			break
	var t := 0.0
	if not b.is_empty() and b.tick > a.tick:
		t = clampf((render_tick - a.tick) / float(b.tick - a.tick), 0.0, 1.0)
	for id in a.units:
		var ua: Dictionary = a.units[id]
		var e := ua.duplicate()
		if not b.is_empty() and b.units.has(id):
			var ub: Dictionary = b.units[id]
			e.pos = (ua.pos as Vector2).lerp(ub.pos, t)
			e.facing = lerp_angle(ua.facing, ub.facing, t)
		e.prev_pos = e.pos
		out.append(e)
	return out
