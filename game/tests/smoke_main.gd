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
	failures += await _check_pc_controls(main)

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
		var queued: int = main.sim.colonies[1].queue.size()
		main.command_train(SimWorld.WORKER)
		if not await _wait(func() -> bool: return main.sim.colonies[1].queue.size() == queued + 1, 3.0):
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


## Mouse and keyboard, fed as input events into PcControls.
func _check_pc_controls(main: Node) -> int:
	var fails := 0
	var pc: PcControls = main.pc
	pc._unhandled_input(_key(KEY_A, true, true))
	if main.selection.size() != 10:
		printerr("FAIL: Ctrl+A should select our 10 ants, got %d" % main.selection.size())
		fails += 1
	pc._unhandled_input(_key(KEY_A, false, true))
	if main.selection.size() > 0:
		var markers := _count_markers(main)
		var center: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
		pc._unhandled_input(_click(MOUSE_BUTTON_RIGHT, center, true))
		pc._unhandled_input(_click(MOUSE_BUTTON_RIGHT, center, false))
		if _count_markers(main) != markers + 1:
			printerr("FAIL: right click should order the selection")
			fails += 1
	# A drag cut off by focus loss must not leave the box stuck, select
	# anything, or block orders. Sent through the viewport like real input.
	var vp: Viewport = main.get_viewport()
	var center2: Vector2 = vp.get_visible_rect().size * 0.5
	main._set_selection([])
	vp.push_input(_click(MOUSE_BUTTON_LEFT, center2 + Vector2(-200, -150), true))
	vp.push_input(_drag(center2 + Vector2(-100, -50), MOUSE_BUTTON_MASK_LEFT))
	if not pc._boxing:
		printerr("FAIL: viewport drag should start a box")
		fails += 1
	pc.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	vp.push_input(_drag(center2, 0))
	if pc._boxing or pc._left_down:
		printerr("FAIL: focus loss should cancel the box drag")
		fails += 1
	if not main.selection.is_empty():
		printerr("FAIL: an interrupted drag must not select anything")
		fails += 1
	main._select_all()
	var before := _count_markers(main)
	vp.push_input(_click(MOUSE_BUTTON_RIGHT, center2, true))
	vp.push_input(_click(MOUSE_BUTTON_RIGHT, center2, false))
	if _count_markers(main) != before + 1:
		printerr("FAIL: right click should order after an interrupted drag")
		fails += 1
	# Same, when the release is simply missed (no focus event).
	vp.push_input(_click(MOUSE_BUTTON_LEFT, center2 + Vector2(-200, -150), true))
	vp.push_input(_drag(center2 + Vector2(-100, -50), MOUSE_BUTTON_MASK_LEFT))
	vp.push_input(_drag(center2, 0))
	if pc._boxing or pc._left_down:
		printerr("FAIL: motion without the left button should cancel the drag")
		fails += 1
	if main.selection.size() != 10:
		printerr("FAIL: a missed release must not change the selection")
		fails += 1
	pc._unhandled_input(_key(KEY_ESCAPE, true))
	if not main.selection.is_empty():
		printerr("FAIL: Esc should clear the selection")
		fails += 1
	var x: float = main.rig.position.x
	pc._unhandled_input(_key(KEY_RIGHT, true))
	for i in 5:
		await process_frame
	pc._unhandled_input(_key(KEY_RIGHT, false))
	if main.rig.position.x <= x:
		printerr("FAIL: holding Right should pan the camera right")
		fails += 1
	# Control groups: Ctrl+1 stores, Esc clears, 1 recalls.
	main._select_all()
	var group_size: int = main.selection.size()
	pc._unhandled_input(_key(KEY_1, true, true))
	pc._unhandled_input(_key(KEY_ESCAPE, true))
	pc._unhandled_input(_key(KEY_1, true))
	if main.selection.size() != group_size or group_size == 0:
		printerr("FAIL: 1 should recall group 1 (%d of %d)" % [main.selection.size(), group_size])
		fails += 1
	# Second tap centers the camera on the group.
	main.rig.position = Vector3(25, 0, 25)
	pc._unhandled_input(_key(KEY_1, true))
	if main.rig.position.distance_to(Vector3(25, 0, 25)) < 1.0:
		printerr("FAIL: double-tapping 1 should center the camera on the group")
		fails += 1
	# Holding Space and moving the mouse drags the camera; release stops it.
	main.rig.position = Vector3(0, 0, 0)
	var mid: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	pc._unhandled_input(_key(KEY_SPACE, true))
	pc._unhandled_input(_move(mid + Vector2(-120, 0), Vector2(-120, 0)))
	var panned_x: float = main.rig.position.x
	if panned_x <= 0.5:
		printerr("FAIL: Space + mouse left should pan the camera right (x=%f)" % panned_x)
		fails += 1
	pc._unhandled_input(_key(KEY_SPACE, false))
	pc._unhandled_input(_move(mid, Vector2(120, 0)))
	if absf(main.rig.position.x - panned_x) > 0.01:
		printerr("FAIL: mouse motion after releasing Space should not pan")
		fails += 1
	# Backspace centers on our colony.
	main.rig.position = Vector3(25, 0, 25)
	pc._unhandled_input(_key(KEY_BACKSPACE, true))
	var col: Vector2 = main.sim.colonies[main.local_player].pos
	if Vector2(main.rig.position.x, main.rig.position.z).distance_to(col) > 0.5:
		printerr("FAIL: Backspace should center the camera on our colony")
		fails += 1
	# Q trains a worker.
	var queued: int = main.sim.colonies[main.local_player].queue.size()
	pc._unhandled_input(_key(KEY_Q, true))
	if not await _wait(func() -> bool:
			return main.sim.colonies[main.local_player].queue.size() == queued + 1, 3.0):
		printerr("FAIL: Q should train a worker")
		fails += 1
	fails += await _check_rally(main)
	fails += await _check_unit_orders(main)
	main._set_selection([])
	return fails


## A then left click attack-moves; Esc / right click cancel targeting; S stops;
## H holds.
func _check_unit_orders(main: Node) -> int:
	var fails := 0
	var pc: PcControls = main.pc
	main._select_all()
	var count: int = main.selection.size()
	pc._unhandled_input(_key(KEY_A, true))
	if not pc.targeting:
		printerr("FAIL: A with ants selected should start targeting")
		return fails + 1
	pc._unhandled_input(_key(KEY_ESCAPE, true))
	if pc.targeting or main.selection.size() != count:
		printerr("FAIL: Esc should cancel targeting and keep the selection")
		fails += 1
	pc._unhandled_input(_key(KEY_A, true))
	pc._unhandled_input(_click(MOUSE_BUTTON_RIGHT, Vector2(10, 10), true))
	if pc.targeting:
		printerr("FAIL: right click should cancel targeting")
		fails += 1
	pc._unhandled_input(_key(KEY_A, true))
	pc._unhandled_input(_key(KEY_S, true))
	if pc.targeting:
		printerr("FAIL: S after A should end targeting")
		fails += 1
	var col: Vector2 = main.sim.colonies[main.local_player].pos
	var spot := col + Vector2(8, 0)
	var sp: Vector2 = main.rig.world_to_screen(Vector3(spot.x, 0.0, spot.y))
	var markers := _count_markers(main)
	pc._unhandled_input(_key(KEY_A, true))
	pc._unhandled_input(_click(MOUSE_BUTTON_LEFT, sp, true))
	pc._unhandled_input(_click(MOUSE_BUTTON_LEFT, sp, false))
	if pc.targeting or _count_markers(main) != markers + 1 or main.selection.size() != count:
		printerr("FAIL: A + left click should place one attack-move and keep the selection")
		fails += 1
	var ids: Array = main.selection.keys()
	if not await _wait(func() -> bool: return _any_unit(main, ids, func(u: SimWorld.Unit) -> bool: return u.amove), 3.0):
		printerr("FAIL: A + left click should attack-move the selection")
		fails += 1
	pc._unhandled_input(_key(KEY_S, true))
	if not await _wait(func() -> bool:
			return not _any_unit(main, ids, func(u: SimWorld.Unit) -> bool: return u.amove or u.moving), 3.0):
		printerr("FAIL: S should stop the selection")
		fails += 1
	pc._unhandled_input(_key(KEY_H, true))
	if not await _wait(func() -> bool:
			return not _any_unit(main, ids, func(u: SimWorld.Unit) -> bool: return not u.hold_ground), 3.0):
		printerr("FAIL: H should put the selection on hold")
		fails += 1
	return fails


## True if any live unit in `ids` matches `pred`.
func _any_unit(main: Node, ids: Array, pred: Callable) -> bool:
	for id in ids:
		var u: SimWorld.Unit = main.sim.get_unit(id)
		if u != null and pred.call(u):
			return true
	return false


## Click the mound, right-click the ground: the rally point is set and its
## line shows. Right-clicking the mound clears it.
func _check_rally(main: Node) -> int:
	var fails := 0
	var pc: PcControls = main.pc
	var col: SimWorld.Colony = main.sim.colonies[main.local_player]
	var col_sp: Vector2 = main.rig.world_to_screen(Vector3(col.pos.x, 0.2, col.pos.y))
	# An ant standing by the mound (within the fuzzy pick radius) must not
	# steal the click from the mound.
	var ant: SimWorld.Unit = null
	for u in main.sim.units:
		if u.owner == main.local_player:
			ant = u
			break
	ant.pos = col.pos + Vector2(SimWorld.COLONY_RADIUS + 0.3, 0)
	ant.prev_pos = ant.pos
	await process_frame
	pc._unhandled_input(_click(MOUSE_BUTTON_LEFT, col_sp, true))
	pc._unhandled_input(_click(MOUSE_BUTTON_LEFT, col_sp, false))
	if not main.colony_selected or not main.selection.is_empty():
		printerr("FAIL: clicking our mound should select it")
		return fails + 1
	var target := col.pos + Vector2(6, 0)
	var sp: Vector2 = main.rig.world_to_screen(Vector3(target.x, 0.0, target.y))
	var markers := _count_markers(main)
	pc._unhandled_input(_click(MOUSE_BUTTON_RIGHT, sp, true))
	pc._unhandled_input(_click(MOUSE_BUTTON_RIGHT, sp, false))
	if _count_markers(main) != markers + 1:
		printerr("FAIL: right click with the mound selected should show a marker")
		fails += 1
	if not await _wait(func() -> bool: return col.has_rally, 3.0):
		printerr("FAIL: right click with the mound selected should set the rally")
		return fails + 1
	if col.rally.distance_to(target) > 0.5:
		printerr("FAIL: rally at %s, expected near %s" % [col.rally, target])
		fails += 1
	await process_frame
	if main.rally_view.dash_count() == 0:
		printerr("FAIL: the rally line should show while the mound is selected")
		fails += 1
	# Selecting ants deselects the mound; the line fades after a moment.
	main._select_all()
	if main.colony_selected:
		printerr("FAIL: selecting ants should deselect the mound")
		fails += 1
	if not await _wait(func() -> bool: return not main.rally_view.visible, 3.0):
		printerr("FAIL: the rally line should hide once the mound is deselected")
		fails += 1
	main._select_colony()
	pc._unhandled_input(_click(MOUSE_BUTTON_RIGHT, col_sp, true))
	pc._unhandled_input(_click(MOUSE_BUTTON_RIGHT, col_sp, false))
	if not await _wait(func() -> bool: return not col.has_rally, 3.0):
		printerr("FAIL: right-clicking our own mound should clear the rally")
		fails += 1
	return fails


func _key(code: Key, pressed: bool, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	e.ctrl_pressed = ctrl
	return e


func _click(button: MouseButton, pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.position = pos
	e.pressed = pressed
	return e


func _drag(pos: Vector2, mask: int) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = mask
	return e


func _move(pos: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = relative
	return e


func _count_markers(main: Node) -> int:
	var n := 0
	for c in main.get_children():
		if c is MoveMarker:
			n += 1
	return n


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
