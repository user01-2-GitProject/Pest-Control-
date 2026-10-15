class_name WorldView
extends Node3D
## Flat forest-floor map: ground, light, environment and cosmetic clutter.
## Clutter is visual only; it does not exist in the simulation.

var half_size := Vector2(30, 30)


func _ready() -> void:
	_build_environment()
	_build_ground()
	_scatter(_pebble_mesh(), 70, Vector2(0.3, 0.9), 1)
	_scatter(_leaf_mesh(), 45, Vector2(0.8, 1.8), 2)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.2, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_ground() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.27, 0.17)
	mat.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = half_size * 2.0
	plane.material = mat
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## One MultiMesh per clutter type keeps it to a single draw call each.
func _scatter(mesh: Mesh, count: int, scale_range: Vector2, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var xf_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		var pos := Vector3(
			rng.randf_range(-half_size.x, half_size.x), 0.0,
			rng.randf_range(-half_size.y, half_size.y))
		mm.set_instance_transform(i, Transform3D(xf_basis, pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _pebble_mesh() -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.44)
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 0.5
	s.radial_segments = 6
	s.rings = 3
	s.material = mat
	return s


func _leaf_mesh() -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.5, 0.18)
	var b := BoxMesh.new()
	b.size = Vector3(1.0, 0.03, 0.5)
	b.material = mat
	return b
