class_name UnitView
extends Node3D
## Placeholder low-poly ant (worker or soldier). Reads sim state; never writes it.

const TURN_SPEED := 14.0
## Body colour per player slot. Player 1 rust red, player 2 dark slate.
const OWNER_COLORS := {1: Color(0.36, 0.12, 0.07), 2: Color(0.14, 0.17, 0.24)}

static var _meshes: Dictionary = {}

var unit_id: int
var player := 1
var kind := SimWorld.WORKER
var _ring: MeshInstance3D
var _body: MeshInstance3D
var _drop: MeshInstance3D
var _bar: HealthBar
var _lunge := 0.0
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
	var flags: int = s.get("flags", 0)
	if _drop:
		_drop.visible = flags & 1 != 0
	if _bar:
		_bar.set_value(s.get("hp", 1.0))
	# Attacking ants bob forward: cosmetic only.
	_lunge = _lunge + delta * 9.0 if flags & 2 else 0.0
	if _body:
		_body.position.x = absf(sin(_lunge)) * 0.15


func _build() -> void:
	_init_shared()
	_body = MeshInstance3D.new()
	_body.mesh = _ant_mesh(player, kind)
	add_child(_body)
	_drop = MeshInstance3D.new()
	_drop.mesh = _meshes["drop"]
	_drop.position = Vector3(-0.3, 0.45, 0)
	_drop.visible = false
	add_child(_drop)
	_bar = HealthBar.new()
	_bar.width = 1.0
	_bar.position.y = 1.0
	add_child(_bar)
	_ring = MeshInstance3D.new()
	_ring.mesh = _meshes["ring"]
	_ring.position.y = 0.03
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = _selected
	add_child(_ring)
	if kind == SimWorld.SOLDIER:
		_body.scale = Vector3.ONE * 1.2
		_ring.scale = Vector3.ONE * 1.2


static func _init_shared() -> void:
	if _meshes.has("ring"):
		return
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
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(1.0, 0.7, 0.15)
	drop_mat.emission_enabled = true
	drop_mat.emission = Color(0.6, 0.35, 0.0)
	var drop := _sphere(0.14)
	drop.material = drop_mat
	_meshes["drop"] = drop


## One merged mesh per ant (one draw, one shadow draw), shared per owner and
## kind. Body runs along +X. Soldiers are bigger with a large head and jaws.
static func _ant_mesh(owner_id: int, ant_kind: int) -> Mesh:
	var key := "ant%d_%d" % [owner_id, ant_kind]
	if _meshes.has(key):
		return _meshes[key]
	var body := StandardMaterial3D.new()
	body.albedo_color = OWNER_COLORS.get(owner_id, Color(0.5, 0.5, 0.5))
	body.roughness = 0.6

	var leg := BoxMesh.new()
	leg.size = Vector3(0.04, 0.04, 0.7)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_sphere(0.2), 0, Transform3D(Basis.from_scale(Vector3(1.35, 1, 1)), Vector3(-0.28, 0.22, 0)))
	st.append_from(_sphere(0.12), 0, Transform3D(Basis(), Vector3(0.02, 0.2, 0)))
	st.append_from(_sphere(0.14), 0, Transform3D(Basis(), Vector3(0.28, 0.22, 0)))
	for x in [-0.08, 0.04, 0.16]:
		st.append_from(leg, 0, Transform3D(Basis(), Vector3(x, 0.12, 0)))
	if ant_kind == SimWorld.SOLDIER:
		st.append_from(_sphere(0.2), 0, Transform3D(Basis(), Vector3(0.36, 0.24, 0)))
		var jaw := BoxMesh.new()
		jaw.size = Vector3(0.3, 0.05, 0.06)
		for z in [-0.1, 0.1]:
			st.append_from(jaw, 0, Transform3D(Basis(Vector3.UP, -z * 3.0), Vector3(0.6, 0.2, z)))
	st.set_material(body)
	_meshes[key] = st.commit()
	return _meshes[key]


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 7
	s.rings = 4
	return s
