class_name TouchControls
extends Node
## Turns raw touch (and desktop mouse) input into RTS gestures.
##
## Touch:
##   tap                       select unit / move selection
##   one-finger drag           pan camera
##   hold, then drag           box select
##   two fingers               pan + pinch zoom
## Mouse and keyboard live in PcControls.

signal tapped(screen_pos: Vector2)
signal box_changed(rect: Rect2)  ## Empty rect means hide the box.
signal box_finished(rect: Rect2)
signal hold_armed(screen_pos: Vector2)
signal pan(from: Vector2, to: Vector2)
signal pinch(factor: float, center: Vector2)

enum Mode { NONE, PENDING, PAN, BOX, MULTI, BLOCKED }

const TAP_SLOP := 16.0
const HOLD_TIME := 0.35

## Returns true if a screen point is over UI, so the world ignores that touch.
var ui_hit_test: Callable

var _touches: Dictionary = {}
var _mode := Mode.NONE
var _start := Vector2.ZERO
var _start_time := 0.0
var _armed := false
var _last_centroid := Vector2.ZERO
var _last_spread := 0.0


func _process(_delta: float) -> void:
	if _mode == Mode.PENDING and not _armed and _now() - _start_time >= HOLD_TIME:
		_armed = true
		hold_armed.emit(_start)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _touches.is_empty() and ui_hit_test.is_valid() and ui_hit_test.call(e.position):
			_mode = Mode.BLOCKED
		_touches[e.index] = e.position
		if _mode == Mode.BLOCKED:
			return
		if _touches.size() == 1:
			_mode = Mode.PENDING
			_start = e.position
			_start_time = _now()
			_armed = false
		else:
			if _mode == Mode.BOX:
				box_changed.emit(Rect2())
			_mode = Mode.MULTI
			_reset_multi()
		return

	_touches.erase(e.index)
	match _mode:
		Mode.PENDING:
			# Releasing after the hold ring appeared cancels: no accidental move.
			if _touches.is_empty() and not e.canceled and not _armed:
				tapped.emit(e.position)
		Mode.BOX:
			box_changed.emit(Rect2())
			if not e.canceled:
				box_finished.emit(_rect(_start, e.position))
		Mode.MULTI:
			if _touches.size() >= 2:
				_reset_multi()
	if _touches.is_empty():
		_mode = Mode.NONE
	elif _mode != Mode.MULTI and _mode != Mode.BLOCKED:
		# Lifting a finger out of a gesture never starts a new one mid-touch.
		_mode = Mode.BLOCKED


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	var prev: Vector2 = _touches[e.index]
	_touches[e.index] = e.position
	match _mode:
		Mode.PENDING:
			if e.position.distance_to(_start) > TAP_SLOP:
				if _armed:
					_mode = Mode.BOX
					box_changed.emit(_rect(_start, e.position))
				else:
					_mode = Mode.PAN
					pan.emit(_start, e.position)
		Mode.PAN:
			pan.emit(prev, e.position)
		Mode.BOX:
			box_changed.emit(_rect(_start, e.position))
		Mode.MULTI:
			if _touches.size() >= 2:
				var c := _centroid()
				var s := _spread()
				pan.emit(_last_centroid, c)
				if _last_spread > 1.0 and s > 1.0:
					pinch.emit(s / _last_spread, c)
				_last_centroid = c
				_last_spread = s


func _reset_multi() -> void:
	_last_centroid = _centroid()
	_last_spread = _spread()


func _first_two() -> Array:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _centroid() -> Vector2:
	if _touches.size() < 2:
		return _start
	var p := _first_two()
	return (p[0] + p[1]) * 0.5


func _spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var p := _first_two()
	return (p[0] as Vector2).distance_to(p[1])


static func _rect(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(a, b - a).abs()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
