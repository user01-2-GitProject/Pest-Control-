extends SceneTree
## Headless navigation and crowd tests on the standard map's logs and rocks:
## pathing round obstacles, blocked destinations, a crowd through the centre
## chokepoint, two crowds meeting head-on in it, and a 50v50 battle. Run from
## the game/ folder after importing:
##   godot --headless -s res://tests/test_nav.gd

const Sim = preload("res://src/sim/sim_world.gd")

var _failures := 0


func _initialize() -> void:
	_test_path_round_log()
	_test_order_onto_log()
	_test_formation_onto_log()
	_test_crowd_through_choke()
	_test_head_on_in_choke()
	_test_battle_at_choke()
	print("test_nav: %s" % ("FAILED (%d)" % _failures if _failures else "all passed"))
	quit(1 if _failures else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


func _map() -> Sim:
	var sim := Sim.new(Vector2(30, 30))
	for o in Sim.standard_obstacles(sim.map_half_size):
		if o.has("size"):
			sim.add_box(o.pos, o.size)
		else:
			sim.add_rock(o.pos, o.radius)
	return sim


## Deepest any ant sits inside a log or rock, in metres.
func _wall_depth(sim: Sim) -> float:
	var worst := 0.0
	for u in sim.units:
		for o in sim.obstacles:
			worst = maxf(worst, u.radius - o.distance(u.pos))
	return worst


func _overlap(sim: Sim) -> float:
	var worst := 0.0
	for i in sim.units.size():
		for j in range(i + 1, sim.units.size()):
			var a: Sim.Unit = sim.units[i]
			var b: Sim.Unit = sim.units[j]
			worst = maxf(worst, a.radius + b.radius - a.pos.distance_to(b.pos))
	return worst


## Runs `ticks`, returning the deepest wall penetration seen on any tick.
func _run(sim: Sim, ticks: int) -> float:
	var worst := 0.0
	for i in ticks:
		sim.step()
		worst = maxf(worst, _wall_depth(sim))
	return worst


func _block(sim: Sim, owner: int, count: int, origin: Vector2, kind := Sim.WORKER) -> Array:
	var ids: Array = []
	for i in count:
		ids.append(sim.spawn_unit(owner, origin + Vector2(i % 5, i / 5) * 1.3, kind).id)
	return ids


func _test_path_round_log() -> void:
	var sim := _map()
	var u = sim.spawn_unit(1, Vector2(-4, 7))
	var goal := Vector2(4, 7)  # Straight through the log.
	_check(not sim.line_clear(u.pos, goal, u.radius), "log blocks the straight line")
	sim.issue_move(1, [u.id], goal)
	_check(not u.path.is_empty(), "path planned round the log")
	var depth := _run(sim, Sim.TICK_RATE * 10)
	_check(u.pos.distance_to(goal) < 0.05, "reaches the far side of the log, at %s" % u.pos)
	_check(depth < 0.05, "never enters the log (%.3f m)" % depth)


func _test_order_onto_log() -> void:
	var sim := _map()
	var u = sim.spawn_unit(1, Vector2(-6, 0))
	sim.issue_move(1, [u.id], Vector2(0, 7))  # Middle of a log.
	var depth := _run(sim, Sim.TICK_RATE * 8)
	_check(not u.moving, "stops at a blocked destination")
	_check(u.pos.distance_to(Vector2(0, 7)) < 2.0, "ends beside the log, at %s" % u.pos)
	_check(depth < 0.05, "never enters the log (%.3f m)" % depth)


func _test_formation_onto_log() -> void:
	var sim := _map()
	var ids := _block(sim, 1, 16, Vector2(-12, 3))
	sim.issue_move(1, ids, Vector2(0, 7))
	var depth := _run(sim, Sim.TICK_RATE * 15)
	var moving := 0
	for u in sim.units:
		moving += 1 if u.moving else 0
	_check(moving == 0, "formation on a log settles (%d still moving)" % moving)
	_check(depth < 0.05, "no ant inside the log (%.3f m)" % depth)
	_check(_overlap(sim) < 0.1, "no overlap after settling (%.3f m)" % _overlap(sim))


func _test_crowd_through_choke() -> void:
	var sim := _map()
	var ids := _block(sim, 1, 30, Vector2(-12, -4))
	var goal := Vector2(10, 0)
	sim.issue_move(1, ids, goal)
	var depth := _run(sim, Sim.TICK_RATE * 25)
	var across := 0
	var moving := 0
	for u in sim.units:
		across += 1 if u.pos.x > 3.0 else 0
		moving += 1 if u.moving else 0
	print("  choke crowd: %d/30 across, %d still moving, wall %.3f m, overlap %.3f m" %
		[across, moving, depth, _overlap(sim)])
	_check(across == 30, "all 30 ants get through the chokepoint (%d)" % across)
	_check(moving == 0, "crowd settles (%d still moving)" % moving)
	_check(depth < 0.05, "no ant pushed into a log (%.3f m)" % depth)
	_check(_overlap(sim) < 0.1, "no overlap after settling (%.3f m)" % _overlap(sim))


func _test_head_on_in_choke() -> void:
	var sim := _map()
	var a := _block(sim, 1, 15, Vector2(-10, -2))
	var b := _block(sim, 1, 15, Vector2(5, -2))
	sim.issue_move(1, a, Vector2(9, 0))
	sim.issue_move(1, b, Vector2(-9, 0))
	var depth := _run(sim, Sim.TICK_RATE * 30)
	var swapped := 0
	for id in a:
		swapped += 1 if sim.get_unit(id).pos.x > 3.0 else 0
	for id in b:
		swapped += 1 if sim.get_unit(id).pos.x < -3.0 else 0
	var moving := 0
	for u in sim.units:
		moving += 1 if u.moving else 0
	print("  head-on in choke: %d/30 swapped sides, %d still moving, wall %.3f m" % [swapped, moving, depth])
	_check(swapped >= 27, "two crowds pass each other in the choke (%d/30)" % swapped)
	_check(moving == 0, "no deadlock: everyone settles (%d still moving)" % moving)
	_check(depth < 0.05, "no ant pushed into a log (%.3f m)" % depth)


func _test_battle_at_choke() -> void:
	var sim := _map()
	sim.add_colony(1, Vector2(-22, 0))
	sim.add_colony(2, Vector2(22, 0))
	var sides := {1: [], 2: []}
	for p in [1, 2]:
		var side := -1.0 if p == 1 else 1.0
		for i in Sim.MAX_UNITS_PER_PLAYER:
			sides[p].append(sim.spawn_unit(p, Vector2(side * (12 + (i % 5) * 1.3), -12 + (i / 5) * 2.6),
				Sim.SOLDIER).id)
	sim.issue_order(1, sides[1], sim.colonies[2].pos, 0, Sim.MODE_ATTACK_MOVE)
	sim.issue_order(2, sides[2], sim.colonies[1].pos, 0, Sim.MODE_ATTACK_MOVE)
	var worst := 0
	var total := 0
	var ticks := 0
	var depth := 0.0
	while ticks < Sim.TICK_RATE * 90 and sim.winner == 0 and sim.unit_count(1) > 0 and sim.unit_count(2) > 0:
		var s := Time.get_ticks_usec()
		sim.step()
		var e := Time.get_ticks_usec() - s
		worst = maxi(worst, e)
		total += e
		ticks += 1
		depth = maxf(depth, _wall_depth(sim))
	print("  50v50 on logs: %d ticks, %.3f ms/tick avg, %.2f ms worst, left %d v %d, wall %.3f m (CI machine)" %
		[ticks, total / 1000.0 / ticks, worst / 1000.0, sim.unit_count(1), sim.unit_count(2), depth])
	_check(sim.unit_count(1) == 0 or sim.unit_count(2) == 0 or sim.winner != 0, "battle resolves within 90 s")
	_check(depth < 0.05, "no ant inside a log or rock during battle (%.3f m)" % depth)
	_check(_overlap(sim) < 0.15, "no deep overlap after battle (%.3f m)" % _overlap(sim))
	_check(total / 1000.0 / ticks < 10.0, "average tick under 10 ms on CI")
