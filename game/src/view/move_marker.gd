class_name MoveMarker
extends MeshInstance3D
## Short-lived ring that shows where a move command was sent.

const LIFETIME := 0.6


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 1.0, 0.35, 0.9)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.7
	ring.outer_radius = 0.85
	ring.rings = 24
	ring.ring_segments = 4
	ring.material = mat
	mesh = ring
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = 0.05
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "scale", Vector3(0.3, 1, 0.3), LIFETIME).from(Vector3(1.4, 1, 1.4))
	tw.tween_property(mat, "albedo_color:a", 0.0, LIFETIME)
	tw.chain().tween_callback(queue_free)
