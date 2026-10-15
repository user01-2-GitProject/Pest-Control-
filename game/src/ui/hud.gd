class_name Hud
extends CanvasLayer
## Overlay: stats, economy, train and selection buttons, drag box, hold
## indicator, toast messages, and the end-of-match panel.

signal select_all_pressed
signal clear_pressed
signal train_pressed(kind: int)
signal menu_pressed

const MARGIN := 16.0

var _root: Control
var _stats: Label
var _toast: Label
var _buttons: HBoxContainer
var _train: HBoxContainer
var _economy: Label
var _result: PanelContainer
var _result_label: Label
var _overlay: _Overlay


class _Overlay extends Control:
	var box := Rect2()
	var hold_pos := Vector2.ZERO
	var hold_t := 0.0

	func _process(delta: float) -> void:
		if hold_t > 0.0:
			hold_t = maxf(0.0, hold_t - delta)
			queue_redraw()

	func _draw() -> void:
		if box.has_area():
			draw_rect(box, Color(0.4, 1.0, 0.35, 0.15), true)
			draw_rect(box, Color(0.4, 1.0, 0.35, 0.9), false, 2.0)
		if hold_t > 0.0:
			draw_arc(hold_pos, 30.0 + (1.0 - hold_t / 0.4) * 10.0, 0.0, TAU, 32,
				Color(0.4, 1.0, 0.35, hold_t / 0.4), 3.0)


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_overlay = _Overlay.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)

	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 22)
	_stats.add_theme_color_override("font_outline_color", Color.BLACK)
	_stats.add_theme_constant_override("outline_size", 6)
	_root.add_child(_stats)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_root.add_child(_toast)

	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_root.add_child(_buttons)
	_add_button(_buttons, "All", select_all_pressed)
	_add_button(_buttons, "Clear", clear_pressed)

	_economy = Label.new()
	_economy.add_theme_font_size_override("font_size", 26)
	_economy.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_economy.add_theme_color_override("font_outline_color", Color.BLACK)
	_economy.add_theme_constant_override("outline_size", 6)
	_root.add_child(_economy)

	_train = HBoxContainer.new()
	_train.add_theme_constant_override("separation", 12)
	_root.add_child(_train)
	_add_button(_train, "Worker %d" % SimWorld.STATS[SimWorld.WORKER].cost,
		Callable(func() -> void: train_pressed.emit(SimWorld.WORKER)))
	_add_button(_train, "Soldier %d" % SimWorld.STATS[SimWorld.SOLDIER].cost,
		Callable(func() -> void: train_pressed.emit(SimWorld.SOLDIER)))

	_result = PanelContainer.new()
	_root.add_child(_result)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_result.add_child(box)
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 56)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_label)
	_add_button(box, "Menu", menu_pressed)
	_result.visible = false

	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func set_stats(text: String) -> void:
	_stats.text = text


## Honeydew, ant count and production line, top centre.
func set_economy(text: String) -> void:
	_economy.text = text


## Shows the end-of-match panel, or hides it with an empty string.
func show_result(text: String) -> void:
	_result.visible = not text.is_empty()
	_result_label.text = text
	_layout()


func is_result_shown() -> bool:
	return _result.visible


func set_box(rect: Rect2) -> void:
	_overlay.box = rect
	_overlay.queue_redraw()


func show_hold(pos: Vector2) -> void:
	_overlay.hold_pos = pos
	_overlay.hold_t = 0.4


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


## True if a screen point is over a button (with some finger slack).
func is_over_ui(pos: Vector2) -> bool:
	if _result.visible and _result.get_global_rect().grow(12.0).has_point(pos):
		return true
	return _buttons.get_global_rect().grow(12.0).has_point(pos) \
		or _train.get_global_rect().grow(12.0).has_point(pos)


## `action` is a Signal or Callable to fire on press.
func _add_button(parent: Container, text: String, action: Variant) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 72)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_NONE
	if action is Signal:
		b.pressed.connect(func() -> void: (action as Signal).emit())
	else:
		b.pressed.connect(action)
	parent.add_child(b)


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var inset := _safe_insets(view)
	_stats.position = Vector2(inset.position.x + MARGIN, inset.position.y + MARGIN)
	_toast.size = Vector2(view.x, 40)
	var bs := _buttons.get_combined_minimum_size()
	_buttons.size = bs
	_buttons.position = Vector2(view.x - inset.size.x - MARGIN - bs.x, view.y - inset.size.y - MARGIN - bs.y)
	var ts := _train.get_combined_minimum_size()
	_train.size = ts
	_train.position = Vector2(inset.position.x + MARGIN, view.y - inset.size.y - MARGIN - ts.y)
	_economy.size = Vector2(view.x, 36)
	_economy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_economy.position = Vector2(0, inset.position.y + MARGIN)
	_toast.position = Vector2(0, inset.position.y + MARGIN + 80)
	var rs := _result.get_combined_minimum_size()
	_result.size = rs
	_result.position = (view - rs) * 0.5


## Notch / gesture-bar insets in viewport units. position = left/top, size = right/bottom.
func _safe_insets(view: Vector2) -> Rect2:
	if not OS.has_feature("mobile"):
		return Rect2()
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.x <= 0.0 or screen.y <= 0.0:
		return Rect2()
	var k := view / screen
	var tl := safe.position * k
	var br := (screen - safe.end) * k
	return Rect2(tl, br)
