extends SceneTree
## Loads the real main scene headless, runs frames, and drives select, move,
## train and the end screen through the same functions touch and buttons use,
## first offline against the local bot, then hosting (in-app server + client
## over loopback UDP, with a second in-test client as the opponent). Catches script errors and wiring
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

	if main.sim == null or main.sim.units.size() != 20 or main.sim.colonies.size() != 2:
		printerr("FAIL: expected 2 colonies and 20 ants")
		failures += 1
	else:
		main._select_all()
		if main.selection.size() != 10:
			printerr("FAIL: select all should pick our 10 ants, got %d" % main.selection.size())
			failures += 1
		if main._views.size() != main.sim.snapshot().size():
			printerr("FAIL: a view per entity")
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
		main.command_train(SimWorld.WORKER)
		if not await _wait(func() -> bool: return main.sim.colonies[1].queue.size() == 1, 3.0):
			printerr("FAIL: train button path did not queue a worker")
			failures += 1
		main.sim.colonies[2].hp = 0
		await _wait(func() -> bool: return main.hud.is_result_shown(), 3.0)
		if main.sim.winner != 1 or not main.hud.is_result_shown() or main.hud._result_label.text != "Victory":
			printerr("FAIL: destroying the bot's colony should show Victory")
			failures += 1
		main.hud.menu_pressed.emit()
		if not main.menu.visible or main.sim != null:
			printerr("FAIL: Menu button returns to the menu")
			failures += 1

	failures += await _check_host(main)

	print("smoke_main: %s" % ("FAILED (%d)" % failures if failures else "passed"))
	quit(1 if failures else 0)


## Host mode: the menu's "Host game" path, plus a second client in this
## process as the opponent so the match starts. Waits in real time.
func _check_host(main: Node) -> int:
	main.start_host()
	if not await _wait(func() -> bool: return _own_ants(main) == 10, 5.0):
		printerr("FAIL: host mode did not show 10 own ants (got %d)" % _own_ants(main))
		return 1
	if main.local_player != 1 or main.server == null:
		printerr("FAIL: host should be player 1 with a local server")
		return 1
	var opponent := NetClient.new()
	root.add_child(opponent)
	opponent.connect_to("127.0.0.1", Protocol.DEFAULT_PORT)
	if not await _wait(func() -> bool: return main.client.match_started, 5.0):
		printerr("FAIL: match did not start when the opponent joined")
		return 1
	main._select_all()
	var id: int = main.selection.keys()[0]
	var start := _pos_of(main, id)
	main.command_move(Vector2(0, 10))
	if not await _wait(func() -> bool: return _pos_of(main, id).distance_to(start) > 1.0, 5.0):
		printerr("FAIL: hosted move did not move units")
		return 1
	if main.hud._economy.text.find("Honeydew") == -1:
		printerr("FAIL: economy not shown online")
		return 1
	opponent.close()
	opponent.queue_free()
	main._reset()
	return 0


func _own_ants(main: Node) -> int:
	var n := 0
	for s in main._snapshot:
		if s.owner == main.local_player and main._is_ant(s):
			n += 1
	return n


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
