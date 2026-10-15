class_name Menu
extends CanvasLayer
## Start screen: play offline, host a game on this device, or join one by address.

signal offline_pressed
signal host_pressed
signal join_pressed(address: String)

var _panel: PanelContainer
var _address: LineEdit
var _status: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel = PanelContainer.new()
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Pest Control"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	box.add_child(_button("Play offline", func() -> void: offline_pressed.emit()))
	box.add_child(_button("Host game", func() -> void: host_pressed.emit()))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host address"
	_address.custom_minimum_size = Vector2(300, 72)
	_address.add_theme_font_size_override("font_size", 26)
	row.add_child(_address)
	row.add_child(_button("Join", func() -> void: join_pressed.emit(_address.text.strip_edges())))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	box.add_child(_status)


func set_status(text: String) -> void:
	_status.text = text


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 72)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(on_press)
	return b
