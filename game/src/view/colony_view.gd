class_name ColonyView
extends Node3D
## Placeholder low-poly ant mound with an owner-coloured ring and health bar.

const RADIUS := SimWorld.COLONY_RADIUS

var unit_id: int
var player := 1
var _bar: HealthBar
var _sel_ring: MeshInstance3D
var _selected := false


func _ready() -> void:
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.45, 0.32, 0.2)
	soil.roughness = 1.0
	var mound := CylinderMesh.new()
	mound.top_radius = RADIUS * 0.3
	mound.bottom_radius = RADIUS
	mound.height = 1.6
	mound.radial_segments = 9
	mound.rings = 1
	mound.material = soil
	var mi := MeshInstance3D.new()
	mi.mesh = mound
	mi.position.y = 0.8
	add_child(mi)

	var hole_mat := StandardMaterial3D.new()
	hole_mat.albedo_color = Color(0.08, 0.05, 0.03)
	var hole := CylinderMesh.new()
	hole.top_radius = RADIUS * 0.22
	hole.bottom_radius = RADIUS * 0.22
	hole.height = 0.05
	hole.radial_segments = 8
	hole.material = hole_mat
	var hi := MeshInstance3D.new()
	hi.mesh = hole
	hi.position.y = 1.61
	add_child(hi)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = UnitView.OWNER_COLORS.get(player, Color.GRAY).lightened(0.35)
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS + 0.05
	ring.outer_radius = RADIUS + 0.3
	ring.rings = 18
	ring.ring_segments = 3
	ring.material = ring_mat
	var ri := MeshInstance3D.new()
	ri.mesh = ring
	ri.position.y = 0.03
	ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ri)

	# Green selection ring, same look as a selected ant's.
	var sel_mat := StandardMaterial3D.new()
	sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sel_mat.albedo_color = Color(0.4, 1.0, 0.35)
	var sel := TorusMesh.new()
	sel.inner_radius = RADIUS + 0.4
	sel.outer_radius = RADIUS + 0.6
	sel.rings = 24
	sel.ring_segments = 3
	sel.material = sel_mat
	_sel_ring = MeshInstance3D.new()
	_sel_ring.mesh = sel
	_sel_ring.position.y = 0.05
	_sel_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sel_ring.visible = _selected
	add_child(_sel_ring)

	_bar = HealthBar.new()
	_bar.width = 3.0
	_bar.position.y = 2.6
	add_child(_bar)


func set_selected(value: bool) -> void:
	_selected = value
	if _sel_ring:
		_sel_ring.visible = value


func sync(s: Dictionary, _alpha: float, _delta: float) -> void:
	position = Vector3(s.pos.x, 0.0, s.pos.y)
	if _bar:
		_bar.set_value(s.hp)
