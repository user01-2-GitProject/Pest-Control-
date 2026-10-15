extends Node3D
## Wires the layers together:
##   SimWorld (rules, fixed 20 Hz tick) <- commands from input
##   views read SimWorld every frame and interpolate between ticks.
## Selection is client-side only; the sim never knows what is selected.

const MAP_HALF := Vector2(30, 30)
const LOCAL_PLAYER := 1
const START_UNITS := 20
const PICK_RADIUS_PX := 40.0
const MAX_TICKS_PER_FRAME := 5

var sim: SimWorld
var rig: CameraRig
var controls: TouchControls
var hud: Hud
var selection: Dictionary = {}  # unit id -> true

var _views: Dictionary = {}  # unit id -> UnitView
var _units_root: Node3D
var _acc := 0.0
var _snapshot: Array[Dictionary] = []
var _stats_timer := 0.0


func _ready() -> void:
	sim = SimWorld.new(MAP_HALF)

	var world := WorldView.new()
	world.half_size = MAP_HALF
	add_child(world)

	_units_root = Node3D.new()
	_units_root.name = "Units"
	add_child(_units_root)

	rig = CameraRig.new()
	rig.bounds = MAP_HALF
	rig.position = Vector3(-8, 0, 0)
	add_child(rig)

	hud = Hud.new()
	add_child(hud)
	hud.select_all_pressed.connect(_select_all)
	hud.clear_pressed.connect(func() -> void: _set_selection([]))

	controls = TouchControls.new()
	controls.ui_hit_test = hud.is_over_ui
	add_child(controls)
	controls.tapped.connect(_on_tapped)
	controls.box_changed.connect(hud.set_box)
	controls.box_finished.connect(_on_box_finished)
	controls.hold_armed.connect(hud.show_hold)
	controls.pan.connect(rig.pan_screen)
	controls.pinch.connect(func(f: float, c: Vector2) -> void: rig.zoom_at(f, c))

	_spawn_start_units()


func _process(delta: float) -> void:
	_acc += delta
	var ticks := 0
	while _acc >= SimWorld.DT and ticks < MAX_TICKS_PER_FRAME:
		sim.step()
		_on_step_results()
		_acc -= SimWorld.DT
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_acc = 0.0  # Don't spiral after a long stall (app resume, debugger).
	if ticks > 0:
		_snapshot = sim.snapshot()

	var alpha := _acc / SimWorld.DT
	for s in _snapshot:
		_views[s.id].sync(s, alpha, delta)

	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		hud.set_stats("FPS %d   Ants %d   Selected %d" % [
			Engine.get_frames_per_second(), _snapshot.size(), selection.size()])


func _on_step_results() -> void:
	for r in sim.last_results:
		if r.player == LOCAL_PLAYER and not r.ok:
			hud.toast("Can't move those units")


func _spawn_start_units() -> void:
	var cols := 5
	for i in START_UNITS:
		var p := Vector2(-12.0 + (i % cols) * 1.4, -3.0 + (i / cols) * 1.4)
		var u := sim.spawn_unit(LOCAL_PLAYER, p)
		var v := UnitView.new()
		v.unit_id = u.id
		_units_root.add_child(v)
		_views[u.id] = v
	_snapshot = sim.snapshot()
	for s in _snapshot:
		_views[s.id].sync(s, 1.0, 1.0)


func _on_tapped(screen_pos: Vector2) -> void:
	var hit := pick_unit(screen_pos)
	if hit != -1:
		_set_selection([hit])
		return
	if selection.is_empty():
		return
	var g: Variant = rig.screen_to_ground(screen_pos)
	if g == null:
		return
	command_move(Vector2(g.x, g.z))


func _on_box_finished(rect: Rect2) -> void:
	var ids: Array = []
	for s in _snapshot:
		if s.owner != LOCAL_PLAYER:
			continue
		var sp: Variant = rig.world_to_screen(Vector3(s.pos.x, 0.2, s.pos.y))
		if sp != null and rect.has_point(sp):
			ids.append(s.id)
	_set_selection(ids)


## Sends the move to the sim, which applies it on the next tick. The marker is
## shown immediately; a rejection comes back via _on_step_results.
func command_move(target: Vector2) -> void:
	sim.queue_move(LOCAL_PLAYER, selection.keys(), target)
	var marker := MoveMarker.new()
	add_child(marker)
	marker.position = Vector3(target.x, 0.05, target.y)


## Nearest own unit within PICK_RADIUS_PX of a screen point, or -1.
func pick_unit(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS_PX
	for s in _snapshot:
		if s.owner != LOCAL_PLAYER:
			continue
		var sp: Variant = rig.world_to_screen(Vector3(s.pos.x, 0.2, s.pos.y))
		if sp == null:
			continue
		var d: float = screen_pos.distance_to(sp)
		if d < best_d:
			best_d = d
			best = s.id
	return best


func _select_all() -> void:
	var ids: Array = []
	for s in _snapshot:
		if s.owner == LOCAL_PLAYER:
			ids.append(s.id)
	_set_selection(ids)


func _set_selection(ids: Array) -> void:
	for id in selection:
		_views[id].set_selected(false)
	selection.clear()
	for id in ids:
		selection[id] = true
		_views[id].set_selected(true)
