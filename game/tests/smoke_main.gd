extends SceneTree
## Loads the real main scene headless, runs frames, and drives a select + move
## through the same functions touch input uses. Catches script errors and wiring
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

	print("smoke_main: %s" % ("FAILED (%d)" % failures if failures else "passed"))
	quit(1 if failures else 0)
