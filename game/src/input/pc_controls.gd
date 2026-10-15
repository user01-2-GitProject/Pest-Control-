class_name PcControls
extends Node
## Standard PC RTS mouse and keyboard controls.
##
##   left click             select ant (Shift: add/remove); empty ground clears
##   double click           select all your ants of that type on screen
##   left drag              box select (Shift: add to selection)
##   right click            order selection: move, attack, or milk
##   arrows                 pan camera; also mouse at the screen edge
##                          (W A S D too while PAN_WITH_WASD is on)
##   middle drag, or hold Space and move the mouse
##                          pan camera (grab the ground)
##   wheel / trackpad pinch zoom at the cursor
##   Ctrl+A / Esc           select all / clear selection
##   Ctrl+1-9 / Shift+1-9   set / add to control group
##   1-9, twice             select group; second tap centers the camera on it
##   Q / E                  train worker / soldier
##   Backspace              center the camera on your colony
##
## Touch input stays in TouchControls; this node only reads mouse and keys.
## It reports gestures as signals and never touches game state itself.

signal clicked(screen_pos: Vector2, additive: bool, double: bool)
signal box_changed(rect: Rect2)  ## Empty rect means hide the box.
signal box_finished(rect: Rect2, additive: bool)
signal command(screen_pos: Vector2)
signal pan(from: Vector2, to: Vector2)
signal scroll(dir: Vector2, delta: float)  ## dir in screen axes, length <= 1.
signal zoom(factor: float, at: Vector2)
signal select_all
signal clear_selection
signal group_key(n: int, set_group: bool, add: bool)
signal train(kind: int)
signal home

const DRAG_SLOP := 6.0
const WHEEL_STEP := 1.12
const EDGE_PX := 8.0
## W A S D also pan. Off by default so letters are free for unit hotkeys
## (attack-move, stop, hold); see game/README.md.
const PAN_WITH_WASD := false

## Returns true if a screen point is over UI, so the world ignores that click.
var ui_hit_test: Callable
## Screen-edge scrolling; off in headless runs and when the window is unfocused.
var edge_scroll := true

var _held := {}  # keycode -> true
var _left_down := false
var _boxing := false
var _start := Vector2.ZERO
var _double := false
var _space_pan := false  # Space held: mouse motion grabs and drags the ground


func _ready() -> void:
	edge_scroll = edge_scroll and DisplayServer.get_name() != "headless"


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# The button release may happen outside the window and never arrive.
		_reset_input()


## Disabling (menu open) drops held keys and any drag in progress.
func set_enabled(on: bool) -> void:
	set_process_unhandled_input(on)
	set_process(on)
	_reset_input()


func _reset_input() -> void:
	_held.clear()
	_space_pan = false
	_reset_pointer()


func _reset_pointer() -> void:
	if _boxing:
		box_changed.emit(Rect2())
	_left_down = false
	_boxing = false


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if _held.has(KEY_LEFT):
		dir.x -= 1.0
	if _held.has(KEY_RIGHT):
		dir.x += 1.0
	if _held.has(KEY_UP):
		dir.y -= 1.0
	if _held.has(KEY_DOWN):
		dir.y += 1.0
	if dir == Vector2.ZERO and edge_scroll and not _boxing and not _space_pan \
			and DisplayServer.window_is_focused():
		dir = _edge_dir()
	if dir != Vector2.ZERO:
		scroll.emit(dir.limit_length(1.0), delta)


func _edge_dir() -> Vector2:
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	var size := vp.get_visible_rect().size
	if not Rect2(Vector2.ZERO, size).has_point(m):
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if m.x <= EDGE_PX:
		dir.x = -1.0
	elif m.x >= size.x - EDGE_PX:
		dir.x = 1.0
	if m.y <= EDGE_PX:
		dir.y = -1.0
	elif m.y >= size.y - EDGE_PX:
		dir.y = 1.0
	return dir


func _unhandled_input(event: InputEvent) -> void:
	# Mouse events the OS made up from touch belong to TouchControls.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventKey:
		_on_key(event)
	elif event is InputEventMouseButton:
		_on_button(event)
	elif event is InputEventMouseMotion:
		_on_motion(event)
	elif event is InputEventMagnifyGesture:
		zoom.emit(event.factor, event.position)
	elif event is InputEventPanGesture:
		var p: Vector2 = event.position
		pan.emit(p, p - event.delta * 8.0)


func _on_key(e: InputEventKey) -> void:
	if e.keycode == KEY_SPACE:
		_space_pan = e.pressed
		return
	if e.echo:
		return
	var k: int = e.keycode
	if PAN_WITH_WASD:
		k = {KEY_W: KEY_UP, KEY_A: KEY_LEFT, KEY_S: KEY_DOWN, KEY_D: KEY_RIGHT}.get(k, k)
	if k in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		# Ctrl+A is select all, not a pan.
		if e.pressed and not (e.ctrl_pressed or e.meta_pressed):
			_held[k] = true
		else:
			_held.erase(k)
	if not e.pressed:
		return
	var ctrl := e.ctrl_pressed or e.meta_pressed
	if e.keycode == KEY_A and ctrl:
		select_all.emit()
	elif k == KEY_ESCAPE:
		clear_selection.emit()
	elif k >= KEY_1 and k <= KEY_9:
		group_key.emit(k - KEY_0, ctrl, e.shift_pressed and not ctrl)
	elif ctrl:
		return
	elif k == KEY_Q:
		train.emit(SimWorld.WORKER)
	elif k == KEY_E:
		train.emit(SimWorld.SOLDIER)
	elif k == KEY_BACKSPACE:
		home.emit()


func _on_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				if ui_hit_test.is_valid() and ui_hit_test.call(e.position):
					return
				_left_down = true
				_boxing = false
				_double = e.double_click
				_start = e.position
			elif _left_down:
				_left_down = false
				if _boxing:
					_boxing = false
					box_changed.emit(Rect2())
					box_finished.emit(_rect(_start, e.position), e.shift_pressed)
				else:
					clicked.emit(e.position, e.shift_pressed, _double)
		MOUSE_BUTTON_RIGHT:
			if e.pressed and not _boxing:
				if ui_hit_test.is_valid() and ui_hit_test.call(e.position):
					return
				command.emit(e.position)
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				zoom.emit(WHEEL_STEP, e.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				zoom.emit(1.0 / WHEEL_STEP, e.position)


func _on_motion(e: InputEventMouseMotion) -> void:
	if _space_pan or e.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		pan.emit(e.position - e.relative, e.position)
	if not _left_down:
		return
	if not (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_reset_pointer()  # Missed the release; drop the drag.
		return
	if not _boxing and e.position.distance_to(_start) > DRAG_SLOP:
		_boxing = true
	if _boxing:
		box_changed.emit(_rect(_start, e.position))


static func _rect(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(a, b - a).abs()
