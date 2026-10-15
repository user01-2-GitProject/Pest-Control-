extends SceneTree
## Headless match-loop tests: economy, production, combat, victory, and a
## full bot match. Run from the game/ folder after importing:
##   godot --headless -s res://tests/test_match.gd

const Sim = preload("res://src/sim/sim_world.gd")
const Bot = preload("res://src/ai/bot_ai.gd")

var _failures := 0


func _initialize() -> void:
	_test_setup()
	_test_worker_gathers_honeydew()
	_test_train_spends_and_spawns()
	_test_train_rejections()
	_test_unit_cap()
	_test_soldier_kills_worker()
	_test_simultaneous_kill()
	_test_idle_soldier_defends()
	_test_move_order_holds_fire()
	_test_attack_order_rules()
	_test_destroying_colony_wins()
	_test_time_limit()
	_test_bot_beats_idle_player()
	_test_bot_vs_bot()
	_test_max_scale_battle()
	print("test_match: %s" % ("FAILED (%d)" % _failures if _failures else "all passed"))
	quit(1 if _failures else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


func _run(sim: Sim, ticks: int) -> void:
	for i in ticks:
		sim.step()


func _count(sim: Sim, owner: int, kind: int) -> int:
	var n := 0
	for u in sim.units:
		if u.owner == owner and u.kind == kind:
			n += 1
	return n


func _test_setup() -> void:
	var sim := Sim.new()
	sim.setup_match()
	_check(sim.colonies.size() == 2, "two colonies")
	_check(sim.aphids.size() == 8, "eight aphid clusters")
	_check(_count(sim, 1, Sim.WORKER) == Sim.START_WORKERS and _count(sim, 2, Sim.SOLDIER) == Sim.START_SOLDIERS,
		"starting ants")
	_check(sim.honeydew[1] == Sim.START_HONEYDEW, "starting honeydew")
	var snap := sim.snapshot()
	_check(snap.size() == 8 + 2 + 2 * (Sim.START_WORKERS + Sim.START_SOLDIERS), "snapshot has every entity")
	_check(sim.colonies[1].pos == -sim.colonies[2].pos, "mirrored colonies")


func _test_worker_gathers_honeydew() -> void:
	var sim := Sim.new()
	var col := sim.add_colony(1, Vector2(-10, 0))
	var a := sim.add_aphid(Vector2(-3, 0))
	var u := sim.spawn_unit(1, Vector2(-6, 0))
	_check(sim.issue_order(1, [u.id], a.pos, a.id), "gather order accepted")
	var start: int = sim.honeydew[1]
	var carried := false
	for i in Sim.TICK_RATE * 8:
		sim.step()
		carried = carried or u.carrying > 0
	_check(carried, "worker picked up honeydew")
	_check(sim.honeydew[1] >= start + Sim.LOAD, "honeydew delivered (%d -> %d)" % [start, sim.honeydew[1]])
	_check(u.task == Sim.Task.GATHER, "worker keeps gathering")
	_check(u.pos.distance_to(col.pos) >= col.radius + u.radius - 0.01, "worker never inside colony")


func _test_train_spends_and_spawns() -> void:
	var sim := Sim.new()
	sim.add_colony(1, Vector2(-10, 0))
	sim.honeydew[1] = 150
	sim.queue_train(1, Sim.SOLDIER, 5)
	sim.step()
	_check(sim.last_results[0].ok and sim.last_results[0].what == "train" and sim.last_results[0].seq == 5,
		"train result reported")
	_check(sim.honeydew[1] == 50, "cost taken at queue time")
	_check(sim.player_state(1).queue == [Sim.SOLDIER], "queued")
	_run(sim, Sim.STATS[Sim.SOLDIER].train_ticks)
	_check(_count(sim, 1, Sim.SOLDIER) == 1, "soldier spawned after train time")
	_check(sim.player_state(1).queue.is_empty(), "queue empty")
	sim.honeydew[1] = 50
	_check(sim.issue_train(1, Sim.WORKER), "worker queued")
	_run(sim, Sim.STATS[Sim.WORKER].train_ticks + 2)
	var w: Sim.Unit = null
	for u in sim.units:
		if u.kind == Sim.WORKER:
			w = u
	_check(w != null and w.task == Sim.Task.NONE, "new worker idle when no aphids exist")


func _test_train_rejections() -> void:
	var sim := Sim.new()
	sim.add_colony(1, Vector2(-10, 0))
	sim.honeydew[1] = 40
	_check(not sim.issue_train(1, Sim.WORKER), "can't afford")
	_check(sim.honeydew[1] == 40, "rejected train costs nothing")
	sim.honeydew[1] = 10000
	_check(not sim.issue_train(1, 99), "unknown kind")
	_check(not sim.issue_train(1, Sim.COLONY), "can't train a colony")
	_check(not sim.issue_train(2, Sim.WORKER), "no colony, no training")
	for i in Sim.MAX_QUEUE:
		sim.issue_train(1, Sim.WORKER)
	_check(not sim.issue_train(1, Sim.WORKER), "queue full")


func _test_unit_cap() -> void:
	var sim := Sim.new(Vector2(40, 40))
	sim.add_colony(1, Vector2(-30, 0))
	for i in Sim.MAX_UNITS_PER_PLAYER - 2:
		sim.spawn_unit(1, Vector2(-20 + i % 10, -10 + i / 10))
	sim.honeydew[1] = 10000
	_check(sim.issue_train(1, Sim.WORKER) and sim.issue_train(1, Sim.WORKER), "two more fit")
	_check(not sim.issue_train(1, Sim.WORKER), "queued ants count toward the cap")
	_run(sim, 400)
	_check(sim.unit_count(1) == Sim.MAX_UNITS_PER_PLAYER, "exactly at cap (%d)" % sim.unit_count(1))
	_check(not sim.issue_train(1, Sim.SOLDIER), "cap holds")


func _test_soldier_kills_worker() -> void:
	var sim := Sim.new()
	var s := sim.spawn_unit(1, Vector2(0, 0), Sim.SOLDIER)
	var w := sim.spawn_unit(2, Vector2(8, 0), Sim.WORKER)
	_check(sim.issue_order(1, [s.id], w.pos, w.id), "attack accepted")
	var hits := int(ceil(float(Sim.STATS[Sim.WORKER].hp) / Sim.STATS[Sim.SOLDIER].damage))
	_run(sim, Sim.TICK_RATE * 3 + hits * Sim.ATTACK_TICKS)
	_check(sim.get_unit(w.id) == null and sim.units.size() == 1, "worker died and was removed")
	_check(s.task == Sim.Task.NONE and not s.moving, "soldier idles after the kill")
	_check(s.hp == s.max_hp, "worker that never attacked dealt no damage")


func _test_simultaneous_kill() -> void:
	var sim := Sim.new()
	var a := sim.spawn_unit(1, Vector2(0, 0), Sim.WORKER)
	var b := sim.spawn_unit(2, Vector2(1.2, 0), Sim.WORKER)
	a.hp = 3
	b.hp = 3
	sim.issue_order(1, [a.id], b.pos, b.id)
	sim.issue_order(2, [b.id], a.pos, a.id)
	sim.step()
	_check(sim.units.is_empty(), "both die on the same tick (left %d)" % sim.units.size())


func _test_idle_soldier_defends() -> void:
	var sim := Sim.new()
	var s := sim.spawn_unit(1, Vector2(0, 0), Sim.SOLDIER)
	var w := sim.spawn_unit(2, Vector2(Sim.AGGRO_RANGE - 1.0, 0), Sim.WORKER)
	var far := sim.spawn_unit(2, Vector2(-20, 0), Sim.WORKER)
	_run(sim, Sim.TICK_RATE * 8)
	_check(sim.get_unit(w.id) == null, "idle soldier killed an enemy in range")
	_check(sim.get_unit(far.id) != null, "enemy out of range left alone")
	# Idle enemy workers don't auto-attack.
	var sim2 := Sim.new()
	var w1 := sim2.spawn_unit(1, Vector2(0, 0), Sim.WORKER)
	var w2 := sim2.spawn_unit(2, Vector2(1.2, 0), Sim.WORKER)
	_run(sim2, Sim.TICK_RATE * 3)
	_check(w1.hp == w1.max_hp and w2.hp == w2.max_hp, "workers don't start fights")


func _test_move_order_holds_fire() -> void:
	var sim := Sim.new()
	var s := sim.spawn_unit(1, Vector2(-10, 0), Sim.SOLDIER)
	var e := sim.spawn_unit(2, Vector2(0, 3), Sim.WORKER)
	sim.issue_move(1, [s.id], Vector2(10, 0))
	_run(sim, Sim.TICK_RATE * 3)
	_check(e.hp == e.max_hp, "moving soldier walks past (retreat works)")
	_check(s.pos.x > 0.0, "and keeps going")


func _test_attack_order_rules() -> void:
	var sim := Sim.new()
	var mine := sim.spawn_unit(1, Vector2(0, 0), Sim.SOLDIER)
	var friend := sim.spawn_unit(1, Vector2(5, 0), Sim.WORKER)
	_check(sim.issue_order(1, [mine.id], friend.pos, friend.id), "targeting a friend is a plain move")
	_check(mine.task == Sim.Task.NONE and mine.moving, "no attack on own ant")
	_check(sim.issue_order(1, [mine.id], Vector2(3, 3), 9999), "unknown target id is a plain move")
	var col := sim.add_colony(2, Vector2(15, 0))
	_check(not sim.issue_order(2, [mine.id], col.pos, mine.id), "can't order the enemy's ant")
	_check(sim.issue_order(1, [mine.id], col.pos, col.id) and mine.task == Sim.Task.ATTACK, "attack colony")


func _test_destroying_colony_wins() -> void:
	var sim := Sim.new()
	sim.setup_match()
	var col: Sim.Colony = sim.colonies[2]
	var ids: Array = []
	for i in 12:
		ids.append(sim.spawn_unit(1, col.pos + Vector2(-5, -3 + i * 0.6), Sim.SOLDIER).id)
	sim.issue_order(1, ids, col.pos, col.id)
	var ticks := 0
	while sim.winner == 0 and ticks < Sim.TICK_RATE * 120:
		sim.step()
		ticks += 1
	_check(sim.winner == 1, "player 1 wins by destroying the colony (winner %d)" % sim.winner)
	_check(not sim.colonies.has(2), "destroyed colony removed")
	var u: Sim.Unit = sim.get_unit(ids[0])
	if u == null:
		u = sim.units[0]
	sim.queue_move(u.owner, [u.id], Vector2.ZERO)
	sim.queue_train(1, Sim.WORKER)
	var t := sim.tick
	sim.step()
	_check(sim.tick == t + 1 and sim.last_results.size() == 2, "commands still answered after the end")
	_check(not sim.last_results[0].ok and not sim.last_results[1].ok, "but rejected")


func _test_time_limit() -> void:
	var sim := Sim.new()
	sim.setup_match()
	sim.colonies[2].hp -= 1
	sim.tick = Sim.MATCH_TICKS - 1
	sim.step()
	_check(sim.winner == 1, "time limit: more colony health wins")
	var sim2 := Sim.new()
	sim2.setup_match()
	sim2.tick = Sim.MATCH_TICKS - 1
	sim2.step()
	_check(sim2.winner == Sim.DRAW, "time limit with equal health is a draw")


## The full loop through the same commands a player sends: gather, train,
## attack, win. Player 1 issues no commands (its starting soldiers still defend).
func _test_bot_beats_idle_player() -> void:
	var sim := Sim.new()
	sim.setup_match()
	var bot := Bot.new(2)
	var peak := 0
	var t0 := Time.get_ticks_usec()
	while sim.winner == 0 and sim.tick < Sim.MATCH_TICKS:
		bot.think(sim)
		sim.step()
		peak = maxi(peak, sim.unit_count(2))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  bot vs idle: winner %d at %.1f min, bot peak %d ants, %.3f ms/tick (CI machine)" %
		[sim.winner, sim.tick / float(Sim.TICK_RATE * 60), peak, ms / maxi(sim.tick, 1)])
	_check(sim.winner == 2, "bot destroys an idle player's colony inside 10 minutes (winner %d)" % sim.winner)
	_check(peak > Sim.START_WORKERS + Sim.START_SOLDIERS, "bot trained ants")


func _test_bot_vs_bot() -> void:
	var sim := Sim.new()
	sim.setup_match()
	var bots := [Bot.new(1), Bot.new(2)]
	var t0 := Time.get_ticks_usec()
	var worst := 0
	while sim.winner == 0:
		for b in bots:
			b.think(sim)
		var s := Time.get_ticks_usec()
		sim.step()
		worst = maxi(worst, Time.get_ticks_usec() - s)
		_check(sim.unit_count(1) <= Sim.MAX_UNITS_PER_PLAYER and sim.unit_count(2) <= Sim.MAX_UNITS_PER_PLAYER,
			"cap respected")
		if sim.tick > Sim.MATCH_TICKS + 5:
			break
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  bot vs bot: winner %d at %.1f min, %.3f ms/tick avg, %.2f ms worst (CI machine)" %
		[sim.winner, sim.tick / float(Sim.TICK_RATE * 60), ms / sim.tick, worst / 1000.0])
	_check(sim.winner != 0, "match always ends by the time limit")


## 50 v 50 soldiers meet in the middle. Must resolve with no ant stuck inside
## another and stay inside the tick budget (50 ms at 20 Hz) on the CI machine.
func _test_max_scale_battle() -> void:
	var sim := Sim.new()
	sim.add_colony(1, Vector2(-22, 0))
	sim.add_colony(2, Vector2(22, 0))
	var sides := {1: [], 2: []}
	for p in [1, 2]:
		var x := -12.0 if p == 1 else 12.0
		for i in Sim.MAX_UNITS_PER_PLAYER:
			sides[p].append(sim.spawn_unit(p, Vector2(x + (i % 5) * 1.3 * (-1 if p == 1 else 1),
				-12 + (i / 5) * 2.6), Sim.SOLDIER).id)
	sim.issue_order(1, sides[1], sim.colonies[2].pos, sim.colonies[2].id)
	sim.issue_order(2, sides[2], sim.colonies[1].pos, sim.colonies[1].id)
	var worst := 0
	var total := 0
	var ticks := 0
	while ticks < Sim.TICK_RATE * 60 and sim.winner == 0 and sim.unit_count(1) > 0 and sim.unit_count(2) > 0:
		var s := Time.get_ticks_usec()
		sim.step()
		var e := Time.get_ticks_usec() - s
		worst = maxi(worst, e)
		total += e
		ticks += 1
	var overlap := 0.0
	for i in sim.units.size():
		for j in range(i + 1, sim.units.size()):
			var a: Sim.Unit = sim.units[i]
			var b: Sim.Unit = sim.units[j]
			overlap = maxf(overlap, a.radius + b.radius - a.pos.distance_to(b.pos))
	print("  50v50 battle: %d ticks, %.3f ms/tick avg, %.2f ms worst, left %d v %d, winner %d (CI machine)" %
		[ticks, total / 1000.0 / ticks, worst / 1000.0, sim.unit_count(1), sim.unit_count(2), sim.winner])
	_check(sim.unit_count(1) == 0 or sim.unit_count(2) == 0 or sim.winner != 0, "battle resolves within 60 s")
	_check(overlap < 0.15, "no deep overlap after battle (%.3f m)" % overlap)
	_check(total / 1000.0 / ticks < 10.0, "average tick under 10 ms on CI")
