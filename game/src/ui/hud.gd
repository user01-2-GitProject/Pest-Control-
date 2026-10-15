class_name Hud
extends CanvasLayer
## Overlay: stats, selection buttons, drag box, hold indicator, toast messages.

signal select_all_pressed
signal clear_pressed

const MARGIN := 16.0

var _root: Control
var _stats: Label
var _toast: Label
var _buttons: HBoxContainer
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
	_add_button("All", select_all_pressed)
	_add_button("Clear", clear_pressed)

	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func set_stats(text: String) -> void:
	_stats.text = text


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
	return _buttons.get_global_rect().grow(12.0).has_point(pos)


func _add_button(text: String, sig: Signal) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 72)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: sig.emit())
	_buttons.add_child(b)


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var inset := _safe_insets(view)
	_stats.position = Vector2(inset.position.x + MARGIN, inset.position.y + MARGIN)
	_toast.size = Vector2(view.x, 40)
	_toast.position = Vector2(0, inset.position.y + MARGIN + 40)
	var bs := _buttons.get_combined_minimum_size()
	_buttons.size = bs
	_buttons.position = Vector2(view.x - inset.size.x - MARGIN - bs.x, view.y - inset.size.y - MARGIN - bs.y)


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
