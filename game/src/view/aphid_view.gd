class_name AphidView
extends Node3D
## Placeholder aphid cluster on a leaf: neutral honeydew source.

static var _mesh: Mesh

var unit_id: int


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _cluster_mesh()
	add_child(mi)


func sync(s: Dictionary, _alpha: float, _delta: float) -> void:
	position = Vector3(s.pos.x, 0.0, s.pos.y)


static func _cluster_mesh() -> Mesh:
	if _mesh:
		return _mesh
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.3, 0.55, 0.15)
	var bug_mat := StandardMaterial3D.new()
	bug_mat.albedo_color = Color(0.65, 0.95, 0.35)
	bug_mat.roughness = 0.4
	var leaf := CylinderMesh.new()
	leaf.top_radius = 1.0
	leaf.bottom_radius = 1.0
	leaf.height = 0.04
	leaf.radial_segments = 7
	var bug := SphereMesh.new()
	bug.radius = 0.16
	bug.height = 0.26
	bug.radial_segments = 6
	bug.rings = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(leaf, 0, Transform3D(Basis.from_scale(Vector3(1.0, 1, 0.6)), Vector3(0, 0.02, 0)))
	st.set_material(leaf_mat)
	var m := st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(0, 0.12, 0), Vector3(0.35, 0.12, 0.15), Vector3(-0.3, 0.12, 0.2),
			Vector3(0.1, 0.12, -0.3), Vector3(-0.25, 0.12, -0.2)]:
		st.append_from(bug, 0, Transform3D(Basis(), p))
	st.set_material(bug_mat)
	_mesh = st.commit(m)
	return _mesh
