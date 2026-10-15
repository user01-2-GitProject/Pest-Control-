extends SceneTree
## Loads the real main scene headless, runs frames, and drives a select + move
## through the same functions touch input uses, first offline, then hosting
## (in-app server + client over loopback UDP). Catches script errors and wiring
## breaks; it does not check rendering or real touch hardware.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		printerr("FAIL: main scene did not load")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	main.start_offline()
	for i in 10:
		await process_frame

	if main.sim == null or main.sim.units.size() != 20:
		printerr("FAIL: expected 20 ants")
		failures += 1
	else:
		main._select_all()
		if main.selection.size() != 20:
			printerr("FAIL: select all")
			failures += 1
		var start_pos: Vector2 = main.sim.units[0].pos
		var start_tick: int = main.sim.tick
		main.command_move(Vector2(10, 10))
		for i in 30:
			await process_frame
		if main.sim.tick <= start_tick:
			printerr("FAIL: sim did not tick")
			failures += 1
		elif main.sim.units[0].pos.distance_to(start_pos) < 0.1:
			printerr("FAIL: queued move did not move units")
			failures += 1

	failures += await _check_host(main)

	print("smoke_main: %s" % ("FAILED (%d)" % failures if failures else "passed"))
	quit(1 if failures else 0)


## Host mode: the menu's "Host game" path. Waits in real time for the join
## and for the server to move the units.
func _check_host(main: Node) -> int:
	main.start_host()
	if not await _wait(func() -> bool: return main._snapshot.size() == 20, 5.0):
		printerr("FAIL: host mode did not show 20 own ants (got %d)" % main._snapshot.size())
		return 1
	if main.local_player != 1 or main.server == null:
		printerr("FAIL: host should be player 1 with a local server")
		return 1
	main._select_all()
	var id: int = main.selection.keys()[0]
	var start := _pos_of(main, id)
	main.command_move(Vector2(0, 10))
	if not await _wait(func() -> bool: return _pos_of(main, id).distance_to(start) > 1.0, 5.0):
		printerr("FAIL: hosted move did not move units")
		return 1
	main._reset()
	return 0


func _pos_of(main: Node, id: int) -> Vector2:
	for s in main._snapshot:
		if s.id == id:
			return s.pos
	return Vector2.INF


func _wait(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()
