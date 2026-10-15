extends SceneTree
## Headless sim tests. Run from the game/ folder:
##   godot --headless --import
##   godot --headless -s res://tests/test_sim.gd

const Sim = preload("res://src/sim/sim_world.gd")

var _failures := 0


func _initialize() -> void:
	_test_single_unit_reaches_target()
	_test_group_move_ends_without_overlap()
	_test_rejects_unowned_units()
	_test_rejects_unknown_units()
	_test_rejects_non_finite_target()
	_test_rejects_oversized_command()
	_test_queued_command_applies_next_tick()
	_test_target_clamped_to_map()
	_test_crowd_into_corner_settles()
	print("test_sim: %s" % ("FAILED (%d)" % _failures if _failures else "all passed"))
	quit(1 if _failures else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


func _run(sim: Sim, ticks: int) -> void:
	for i in ticks:
		sim.step()


func _grid(sim: Sim, owner: int, count: int, origin: Vector2) -> Array:
	var ids: Array = []
	for i in count:
		ids.append(sim.spawn_unit(owner, origin + Vector2(i % 5, i / 5) * 1.2).id)
	return ids


func _min_gap(sim: Sim) -> float:
	var worst := INF
	for i in sim.units.size():
		for j in range(i + 1, sim.units.size()):
			var a = sim.units[i]
			var b = sim.units[j]
			worst = minf(worst, a.pos.distance_to(b.pos) - a.radius - b.radius)
	return worst


func _test_single_unit_reaches_target() -> void:
	var sim := Sim.new()
	var u = sim.spawn_unit(1, Vector2.ZERO)
	_check(sim.issue_move(1, [u.id], Vector2(10, 5)), "move accepted")
	_run(sim, Sim.TICK_RATE * 5)
	_check(u.pos.distance_to(Vector2(10, 5)) < 0.01, "single unit reaches target, at %s" % u.pos)
	_check(not u.moving, "single unit stops")


func _test_group_move_ends_without_overlap() -> void:
	var sim := Sim.new()
	var ids := _grid(sim, 1, 20, Vector2(-15, -2))
	_check(sim.issue_move(1, ids, Vector2(12, 4)), "group move accepted")
	_run(sim, Sim.TICK_RATE * 15)
	var moving := 0
	var far := 0
	for u in sim.units:
		if u.moving:
			moving += 1
		if u.pos.distance_to(Vector2(12, 4)) > 4.0:
			far += 1
	_check(moving == 0, "all 20 stopped (still moving: %d)" % moving)
	_check(far == 0, "all 20 arrived near target (far: %d)" % far)
	_check(_min_gap(sim) > -0.05, "no persistent overlap (min gap %.3f)" % _min_gap(sim))


func _test_rejects_unowned_units() -> void:
	var sim := Sim.new()
	var mine = sim.spawn_unit(1, Vector2.ZERO)
	var theirs = sim.spawn_unit(2, Vector2(5, 0))
	_check(not sim.issue_move(1, [mine.id, theirs.id], Vector2(10, 10)), "mixed-owner move rejected")
	_check(not mine.moving and not theirs.moving, "rejected command changes nothing")


func _test_rejects_unknown_units() -> void:
	var sim := Sim.new()
	_check(not sim.issue_move(1, [999], Vector2.ZERO), "unknown id rejected")
	_check(not sim.issue_move(1, [], Vector2.ZERO), "empty selection rejected")


func _test_rejects_non_finite_target() -> void:
	var sim := Sim.new()
	var u = sim.spawn_unit(1, Vector2.ZERO)
	_check(not sim.issue_move(1, [u.id], Vector2(NAN, 0)), "NaN target rejected")
	_check(not sim.issue_move(1, [u.id], Vector2(0, INF)), "INF target rejected")
	_run(sim, 5)
	_check(u.pos.is_finite() and not u.moving, "unit unaffected by bad target")


func _test_rejects_oversized_command() -> void:
	var sim := Sim.new()
	var u = sim.spawn_unit(1, Vector2.ZERO)
	var ids: Array = []
	for i in Sim.MAX_UNITS_PER_PLAYER + 1:
		ids.append(u.id)
	_check(not sim.issue_move(1, ids, Vector2(5, 5)), "over-long id list rejected")


func _test_queued_command_applies_next_tick() -> void:
	var sim := Sim.new()
	var mine = sim.spawn_unit(1, Vector2.ZERO)
	var theirs = sim.spawn_unit(2, Vector2(5, 0))
	sim.queue_move(1, [mine.id], Vector2(10, 0))
	sim.queue_move(1, [theirs.id], Vector2(10, 0))
	_check(not mine.moving, "queued command not applied before step")
	sim.step()
	_check(sim.last_results.size() == 2, "two results reported")
	_check(sim.last_results[0].ok and not sim.last_results[1].ok, "accept + reject reported")
	_check(sim.last_results[0].tick == sim.tick, "result stamped with tick")
	_check(mine.moving and not theirs.moving, "only the valid command applied")
	sim.step()
	_check(sim.last_results.is_empty(), "results cleared next tick")


func _test_target_clamped_to_map() -> void:
	var sim := Sim.new(Vector2(10, 10))
	var u = sim.spawn_unit(1, Vector2.ZERO)
	sim.issue_move(1, [u.id], Vector2(100, -100))
	_run(sim, Sim.TICK_RATE * 10)
	_check(absf(u.pos.x) <= 10.0 and absf(u.pos.y) <= 10.0, "unit stays inside map, at %s" % u.pos)


func _test_crowd_into_corner_settles() -> void:
	# The formation must shift inside the map instead of piling into the corner.
	var sim := Sim.new(Vector2(10, 10))
	var ids := _grid(sim, 1, 20, Vector2(-4, -4))
	sim.issue_move(1, ids, Vector2(10, 10))
	_run(sim, Sim.TICK_RATE * 20)
	var moving := 0
	for u in sim.units:
		if u.moving:
			moving += 1
	_check(moving == 0, "corner crowd settles (still moving: %d)" % moving)
	_check(_min_gap(sim) > -0.05, "corner crowd has no overlap (min gap %.3f)" % _min_gap(sim))
