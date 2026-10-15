class_name HealthBar
extends Node3D
## Billboard health bar. Hidden at full health so a calm map stays clean.

var width := 0.9
var _fill: MeshInstance3D
var _back: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	_back = _quad(Color(0, 0, 0, 0.6), 0.0)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.no_depth_test = true
	_mat.render_priority = 1
	_fill = _quad(Color.GREEN, 0.001)
	_fill.material_override = _mat
	visible = false


## frac is 0..1 of max health.
func set_value(frac: float) -> void:
	if _fill == null:
		return
	visible = frac < 0.999
	if not visible:
		return
	frac = clampf(frac, 0.0, 1.0)
	_fill.scale.x = maxf(frac, 0.01)
	_mat.albedo_color = Color(1.0, 0.25, 0.2).lerp(Color(0.35, 1.0, 0.3), frac)


func _quad(color: Color, z: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(width, width * 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.z = z
	add_child(mi)
	return mi
