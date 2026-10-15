class_name RallyView
extends Node3D
## StarCraft-style rally line: a dashed line from your mound to its rally
## point, with a small flag there. main.gd shows it while the colony is
## selected and briefly after a rally is set.

const DASH := 0.6
const GAP := 0.4
const COLOR := Color(0.4, 1.0, 0.35, 0.85)

var _mat: StandardMaterial3D
var _dashes: MultiMeshInstance3D
var _flag: Node3D
var _from := Vector2.INF
var _to := Vector2.INF


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = COLOR

	var dash := BoxMesh.new()
	dash.size = Vector3(DASH, 0.04, 0.14)
	dash.material = _mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dash
	_dashes = MultiMeshInstance3D.new()
	_dashes.multimesh = mm
	_dashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dashes)

	_flag = Node3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.04
	pole.height = 1.4
	pole.radial_segments = 6
	pole.material = _mat
	var pi := MeshInstance3D.new()
	pi.mesh = pole
	pi.position.y = 0.7
	_flag.add_child(pi)
	var cloth := BoxMesh.new()
	cloth.size = Vector3(0.6, 0.38, 0.03)
	cloth.material = _mat
	var ci := MeshInstance3D.new()
	ci.mesh = cloth
	ci.position = Vector3(0.32, 1.2, 0)
	_flag.add_child(ci)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.45
	ring.outer_radius = 0.55
	ring.rings = 16
	ring.ring_segments = 3
	ring.material = _mat
	var ri := MeshInstance3D.new()
	ri.mesh = ring
	ri.position.y = 0.03
	_flag.add_child(ri)
	add_child(_flag)
	visible = false


## Draws the line from `from` (mound) to `to` (rally point), ground coords.
func show_line(from: Vector2, to: Vector2) -> void:
	visible = true
	if from == _from and to == _to:
		return
	_from = from
	_to = to
	_flag.position = Vector3(to.x, 0.0, to.y)
	var d := to - from
	var length := d.length()
	var dir := d / length if length > 0.001 else Vector2.RIGHT
	# Start the line at the mound's edge, end it at the flag's ring.
	var start := SimWorld.COLONY_RADIUS
	var stop := length - 0.5
	var count := maxi(0, int((stop - start) / (DASH + GAP)))
	var basis := Basis(Vector3.UP, -dir.angle())
	_dashes.multimesh.instance_count = count
	for i in count:
		var p := from + dir * (start + DASH * 0.5 + i * (DASH + GAP))
		_dashes.multimesh.set_instance_transform(i, Transform3D(basis, Vector3(p.x, 0.06, p.y)))


func hide_line() -> void:
	visible = false


## Number of dashes drawn; for tests.
func dash_count() -> int:
	return _dashes.multimesh.instance_count if visible else 0
