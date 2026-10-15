class_name UnitView
extends Node3D
## Placeholder low-poly ant. Reads sim state; never writes it.

const TURN_SPEED := 14.0

static var _meshes: Dictionary = {}

var unit_id: int
var _ring: MeshInstance3D
var _selected := false


func _ready() -> void:
	_build()


func set_selected(value: bool) -> void:
	_selected = value
	if _ring:
		_ring.visible = value


## `s` is one entry of SimWorld.snapshot(). alpha blends between the last two
## sim ticks so motion is smooth at any FPS.
func sync(s: Dictionary, alpha: float, delta: float) -> void:
	var prev: Vector2 = s.prev_pos
	var p := prev.lerp(s.pos, alpha)
	position = Vector3(p.x, 0.0, p.y)
	rotation.y = lerp_angle(rotation.y, -float(s.facing), 1.0 - exp(-TURN_SPEED * delta))


func _build() -> void:
	_init_shared()
	var body := MeshInstance3D.new()
	body.mesh = _meshes["ant"]
	add_child(body)
	_ring = MeshInstance3D.new()
	_ring.mesh = _meshes["ring"]
	_ring.position.y = 0.03
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = _selected
	add_child(_ring)


static func _init_shared() -> void:
	if not _meshes.is_empty():
		return
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.36, 0.12, 0.07)
	body.roughness = 0.6

	# One merged mesh per ant (one draw, one shadow draw). Body runs along +X.
	var leg := BoxMesh.new()
	leg.size = Vector3(0.04, 0.04, 0.7)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_sphere(0.2), 0, Transform3D(Basis.from_scale(Vector3(1.35, 1, 1)), Vector3(-0.28, 0.22, 0)))
	st.append_from(_sphere(0.12), 0, Transform3D(Basis(), Vector3(0.02, 0.2, 0)))
	st.append_from(_sphere(0.14), 0, Transform3D(Basis(), Vector3(0.28, 0.22, 0)))
	for x in [-0.08, 0.04, 0.16]:
		st.append_from(leg, 0, Transform3D(Basis(), Vector3(x, 0.12, 0)))
	st.set_material(body)
	_meshes["ant"] = st.commit()

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.4, 1.0, 0.35)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.6
	ring.rings = 24
	ring.ring_segments = 4
	ring.material = ring_mat
	_meshes["ring"] = ring


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 7
	s.rings = 4
	return s
