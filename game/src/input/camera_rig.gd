class_name CameraRig
extends Node3D
## High-angle RTS camera. The rig sits on the ground; the camera orbits above it.

@export var pitch_deg := 55.0
@export var min_distance := 8.0
@export var max_distance := 40.0
@export var distance := 20.0
## Keyboard / edge scroll speed, in camera distances per second.
@export var scroll_speed := 1.1

var bounds := Vector2(30, 30)
var camera: Camera3D

var _ground := Plane(Vector3.UP, 0.0)


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	_apply()


## Ground point under a screen position, or null if the ray misses.
func screen_to_ground(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var normal := camera.project_ray_normal(screen_pos)
	return _ground.intersects_ray(origin, normal)


func world_to_screen(world_pos: Vector3) -> Variant:
	if camera.is_position_behind(world_pos):
		return null
	return camera.unproject_position(world_pos)


## Keeps the ground point under `from` under the finger at `to`.
func pan_screen(from: Vector2, to: Vector2) -> void:
	var a: Variant = screen_to_ground(from)
	var b: Variant = screen_to_ground(to)
	if a == null or b == null:
		return
	position += a - b
	_clamp()


## Slides the view along screen axes (dir.x right, dir.y down), faster when
## zoomed out. The camera never yaws, so screen right is world +X.
func scroll(dir: Vector2, delta: float) -> void:
	position += Vector3(dir.x, 0.0, dir.y) * distance * scroll_speed * delta
	_clamp()


## factor > 1 zooms in, anchored on the screen point `at`.
func zoom_at(factor: float, at: Vector2) -> void:
	if factor <= 0.0:
		return
	var before: Variant = screen_to_ground(at)
	distance = clampf(distance / factor, min_distance, max_distance)
	_apply()
	var after: Variant = screen_to_ground(at)
	if before != null and after != null:
		position += before - after
		_clamp()


func _apply() -> void:
	var p := deg_to_rad(pitch_deg)
	camera.position = Vector3(0.0, sin(p) * distance, cos(p) * distance)
	camera.rotation = Vector3(-p, 0.0, 0.0)


func _clamp() -> void:
	position.x = clampf(position.x, -bounds.x, bounds.x)
	position.z = clampf(position.z, -bounds.y, bounds.y)
	position.y = 0.0
