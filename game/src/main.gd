extends Node3D
## Wires the layers together. Two ways to play, same views and controls:
##   Offline: SimWorld runs here at its fixed 20 Hz tick against a local bot
##            (BotAI, player 2); views blend between ticks.
##   Online:  NetClient sends moves to a GameServer and draws its snapshots
##            through a jitter buffer. "Host" also runs the server in this app.
## Selection is client-side only; neither sim nor server knows what is selected.

enum Mode { MENU, OFFLINE, ONLINE }

const MAP_HALF := Vector2(30, 30)
const PICK_RADIUS_PX := 40.0
const MAX_TICKS_PER_FRAME := 5
## Second tap of a group key within this many ms centers the camera on it.
const GROUP_DOUBLE_TAP_MS := 350

var mode := Mode.MENU
var local_player := 1
var sim: SimWorld  # offline only
var bot: BotAI  # offline only
var client: NetClient  # online only
var server: GameServer  # only when hosting on this device
var rig: CameraRig
var controls: TouchControls
var pc: PcControls
var hud: Hud
var menu: Menu
var selection: Dictionary = {}  # unit id -> true
var groups: Dictionary = {}  # 1-9 -> Array of unit ids (client-side only)

var _views: Dictionary = {}  # entity id -> UnitView / ColonyView / AphidView
var _units_root: Node3D
var _acc := 0.0
var _snapshot: Array[Dictionary] = []
var _stats_timer := 0.0
## Online: seq -> "order" / "train", to word rejections.
var _sent: Dictionary = {}
var _last_group := 0
var _last_group_ms := 0


func _ready() -> void:
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
	hud.train_pressed.connect(command_train)
	hud.menu_pressed.connect(func() -> void: _back_to_menu(""))
	hud.visible = false

	controls = TouchControls.new()
	controls.ui_hit_test = hud.is_over_ui
	add_child(controls)
	controls.tapped.connect(_on_tapped)
	controls.box_changed.connect(hud.set_box)
	controls.box_finished.connect(_on_box_finished)
	controls.hold_armed.connect(hud.show_hold)
	controls.pan.connect(rig.pan_screen)
	controls.pinch.connect(func(f: float, c: Vector2) -> void: rig.zoom_at(f, c))
	controls.set_process_unhandled_input(false)

	pc = PcControls.new()
	pc.ui_hit_test = hud.is_over_ui
	add_child(pc)
	pc.clicked.connect(_on_clicked)
	pc.box_changed.connect(hud.set_box)
	pc.box_finished.connect(_on_box_finished)
	pc.command.connect(_on_command)
	pc.pan.connect(rig.pan_screen)
	pc.scroll.connect(rig.scroll)
	pc.zoom.connect(func(f: float, c: Vector2) -> void: rig.zoom_at(f, c))
	pc.select_all.connect(_select_all)
	pc.clear_selection.connect(func() -> void: _set_selection([]))
	pc.group_key.connect(_on_group_key)
	pc.train.connect(command_train)
	pc.home.connect(_center_on_colony)
	pc.set_enabled(false)

	menu = Menu.new()
	add_child(menu)
	menu.offline_pressed.connect(start_offline)
	menu.host_pressed.connect(start_host)
	menu.join_pressed.connect(start_join)


func start_offline() -> void:
	_reset()
	mode = Mode.OFFLINE
	local_player = 1
	sim = SimWorld.new(MAP_HALF)
	sim.setup_match()
	bot = BotAI.new(2)
	_snapshot = sim.snapshot()
	_enter_game()


## Runs a GameServer inside this app and joins it, so two phones on the same
## Wi-Fi can play without a PC.
func start_host() -> void:
	_reset()
	server = GameServer.new()
	add_child(server)
	var err := server.start(Protocol.DEFAULT_PORT)
	if err != OK:
		menu.set_status("Can't host: port %d busy (%s)" % [Protocol.DEFAULT_PORT, error_string(err)])
		_reset()
		return
	start_join("127.0.0.1", false)


func start_join(address: String, reset := true) -> void:
	if reset:
		_reset()
	if address.is_empty():
		menu.set_status("Enter the host's address")
		return
	client = NetClient.new()
	add_child(client)
	client.joined.connect(_on_joined)
	client.rejected.connect(_on_rejected)
	client.connection_failed.connect(_on_connection_failed)
	client.command_result.connect(func(seq: int, ok: bool) -> void:
		var what: String = _sent.get(seq, "order")
		_sent.erase(seq)
		if not ok:
			_toast_rejected(what))
	var err := client.connect_to(address, Protocol.DEFAULT_PORT)
	if err != OK:
		menu.set_status("Bad address (%s)" % error_string(err))
		_reset()
		return
	mode = Mode.ONLINE
	menu.set_status("Connecting to %s..." % address)


func _on_joined(player_id: int) -> void:
	local_player = player_id
	_enter_game()


func _on_rejected(reason: int) -> void:
	var why := "server is full" if reason == Protocol.REJECT_FULL else "game version mismatch"
	_back_to_menu("Can't join: " + why)


func _on_connection_failed(message: String) -> void:
	_back_to_menu(message)


func _enter_game() -> void:
	var side := -1.0 if local_player == 1 else 1.0
	rig.position = Vector3(side * (MAP_HALF.x - 14.0), 0, 0)
	hud.show_result("")
	menu.visible = false
	hud.visible = true
	controls.set_process_unhandled_input(true)
	pc.set_enabled(true)


func _back_to_menu(status: String) -> void:
	_reset()
	menu.set_status(status)


## Drops whatever session is running and shows the menu.
func _reset() -> void:
	_set_selection([])
	groups.clear()
	_last_group = 0
	for v in _views.values():
		v.queue_free()
	_views.clear()
	_snapshot.clear()
	_sent.clear()
	_acc = 0.0
	sim = null
	bot = null
	if client:
		client.close()
		client.queue_free()
		client = null
	if server:
		server.stop()
		server.queue_free()
		server = null
	mode = Mode.MENU
	menu.visible = true
	hud.visible = false
	controls.set_process_unhandled_input(false)
	pc.set_enabled(false)


func _process(delta: float) -> void:
	var alpha := 1.0
	match mode:
		Mode.OFFLINE:
			alpha = _step_offline(delta)
		Mode.ONLINE:
			if client.state != NetClient.State.JOINED:
				return
			_snapshot = client.buffer.sample()
		_:
			return

	_sync_views(alpha, delta)

	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		hud.set_stats(_stats_text())
		hud.set_economy(_economy_text())
		_update_result()


## Advances the local sim by whole ticks; returns the blend factor into the next.
func _step_offline(delta: float) -> float:
	_acc += delta
	var ticks := 0
	while _acc >= SimWorld.DT and ticks < MAX_TICKS_PER_FRAME:
		bot.think(sim)
		sim.step()
		for r in sim.last_results:
			if r.player == local_player and not r.ok:
				_toast_rejected(r.what)
		_acc -= SimWorld.DT
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_acc = 0.0  # Don't spiral after a long stall (app resume, debugger).
	if ticks > 0:
		_snapshot = sim.snapshot()
	return _acc / SimWorld.DT


func _sync_views(alpha: float, delta: float) -> void:
	var seen := {}
	for s in _snapshot:
		seen[s.id] = true
		var v: Node3D = _views.get(s.id)
		if v == null:
			v = _make_view(s)
			_units_root.add_child(v)
			_views[s.id] = v
			v.sync(s, 1.0, 1.0)
		else:
			v.sync(s, alpha, delta)
	# Gone from the state: died (or the colony fell).
	for id in _views.keys():
		if not seen.has(id):
			_views[id].queue_free()
			_views.erase(id)
			selection.erase(id)


func _make_view(s: Dictionary) -> Node3D:
	match int(s.get("kind", SimWorld.WORKER)):
		SimWorld.COLONY:
			var c := ColonyView.new()
			c.unit_id = s.id
			c.player = s.owner
			return c
		SimWorld.APHID:
			var a := AphidView.new()
			a.unit_id = s.id
			return a
	var u := UnitView.new()
	u.unit_id = s.id
	u.player = s.owner
	u.kind = s.get("kind", SimWorld.WORKER)
	return u


func _is_ant(s: Dictionary) -> bool:
	var k: int = s.get("kind", SimWorld.WORKER)
	return k == SimWorld.WORKER or k == SimWorld.SOLDIER


## Economy for a player, same shape offline and online:
## {honeydew, units, queue_len, front, progress}
func _player_state(p: int) -> Dictionary:
	if mode == Mode.OFFLINE:
		return sim.player_state(p)
	if mode == Mode.ONLINE and client:
		return client.player_states.get(p, {})
	return {}


func _winner() -> int:
	if mode == Mode.OFFLINE:
		return sim.winner
	if mode == Mode.ONLINE and client:
		return client.winner
	return 0


func _match_tick() -> int:
	if mode == Mode.OFFLINE:
		return sim.tick
	if mode == Mode.ONLINE and client:
		return maxi(0, client.buffer.newest_tick())
	return 0


func _economy_text() -> String:
	var st := _player_state(local_player)
	if st.is_empty():
		return ""
	var left := maxi(0, SimWorld.MATCH_TICKS - _match_tick()) / SimWorld.TICK_RATE
	var text := "Honeydew %d   Ants %d/%d   %d:%02d" % [st.honeydew, st.units,
		SimWorld.MAX_UNITS_PER_PLAYER, left / 60, left % 60]
	if st.queue_len > 0:
		var label := "Soldier" if st.front == SimWorld.SOLDIER else "Worker"
		text += "\nTraining %s %d%%" % [label, roundi(st.progress * 100.0)]
		if st.queue_len > 1:
			text += " (+%d)" % (st.queue_len - 1)
	return text


func _update_result() -> void:
	var w := _winner()
	if w == 0 or hud.is_result_shown():
		return
	_set_selection([])
	if w == SimWorld.DRAW:
		hud.show_result("Draw")
	else:
		hud.show_result("Victory" if w == local_player else "Defeat")


func _toast_rejected(what: String) -> void:
	hud.toast("Can't train that now" if what == "train" else "Can't order those ants")


func _stats_text() -> String:
	var text := "FPS %d   Selected %d" % [Engine.get_frames_per_second(), selection.size()]
	if mode == Mode.OFFLINE:
		text += "   vs local bot"
	if mode == Mode.ONLINE:
		text += "   P%d   RTT %d ms" % [local_player, client.rtt_ms()]
		if client.host_paused:
			text += "\nHost paused the game"
		elif client.is_stalled():
			text += "\nConnection unstable..."
		elif not client.opponent_present():
			text += "\nWaiting for opponent" if not client.match_started else "\nOpponent left"
			if server:
				text += " - join at " + ", ".join(_lan_addresses())
	return text


## This device's private IPv4 addresses, to show the other player.
func _lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10."):
			out.append(a)
		elif a.begins_with("172."):
			var second := a.get_slice(".", 1).to_int()
			if second >= 16 and second <= 31:
				out.append(a)
	return out


## When hosting, tell the other player before this phone goes to the
## background (the server stops with the app).
func _notification(what: int) -> void:
	if server == null:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		server.notify_paused(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		server.notify_paused(false)


## Touch: a tap on an own ant selects it; with a selection, a tap elsewhere
## orders (see _on_command).
func _on_tapped(screen_pos: Vector2) -> void:
	var hit := pick_unit(screen_pos)
	if hit != -1:
		_set_selection([hit])
		return
	_on_command(screen_pos)


## Mouse left click: select the ant under the cursor (Shift toggles it in the
## selection). Empty ground clears the selection unless Shift is held.
## A double click selects every own ant of that type on screen.
func _on_clicked(screen_pos: Vector2, additive: bool, double := false) -> void:
	var hit := pick_unit(screen_pos)
	if double and hit != -1:
		_select_same_kind_on_screen(hit, additive)
		return
	if not additive:
		_set_selection([] if hit == -1 else [hit])
	elif hit != -1:
		var ids := selection.keys()
		if selection.has(hit):
			ids.erase(hit)
		else:
			ids.append(hit)
		_set_selection(ids)


## Orders the selection at a screen point: an enemy ant or colony there is
## attacked, aphids are milked, anywhere else is a move.
func _on_command(screen_pos: Vector2) -> void:
	if selection.is_empty():
		return
	var g: Variant = rig.screen_to_ground(screen_pos)
	if g == null:
		return
	var ground := Vector2(g.x, g.z)
	command_order(ground, pick_target(screen_pos, ground))


func _on_box_finished(rect: Rect2, additive := false) -> void:
	var ids: Array = selection.keys() if additive else []
	for s in _snapshot:
		if s.owner != local_player or not _is_ant(s):
			continue
		var sp: Variant = rig.world_to_screen(Vector3(s.pos.x, 0.2, s.pos.y))
		if sp != null and rect.has_point(sp) and not ids.has(s.id):
			ids.append(s.id)
	_set_selection(ids)


## Sends the order to the sim (offline) or the server (online). Either applies
## it on its next tick. The marker shows at once; a rejection comes back as a
## result and shows a toast.
func command_order(target: Vector2, target_id: int = 0) -> void:
	var ids := selection.keys()
	match mode:
		Mode.OFFLINE:
			sim.queue_order(local_player, ids, target, target_id)
		Mode.ONLINE:
			var seq := client.send_order(ids, target, target_id)
			if seq == -1:
				hud.toast("Not connected")
				return
			_sent[seq] = "order"
		_:
			return
	var marker := MoveMarker.new()
	marker.attack = _is_enemy(target_id)
	add_child(marker)
	marker.position = Vector3(target.x, 0.05, target.y)


func command_move(target: Vector2) -> void:
	command_order(target, 0)


## Checks what the client can see first (cost, cap) for a clearer message;
## the sim or server still decides.
func command_train(kind: int) -> void:
	var st := _player_state(local_player)
	if st.is_empty() or _winner() != 0:
		return
	var cost: int = SimWorld.STATS[kind].cost
	if st.honeydew < cost:
		hud.toast("Need %d honeydew" % cost)
		return
	if st.units + st.queue_len >= SimWorld.MAX_UNITS_PER_PLAYER:
		hud.toast("Ant limit %d" % SimWorld.MAX_UNITS_PER_PLAYER)
		return
	if st.queue_len >= SimWorld.MAX_QUEUE:
		hud.toast("Queue full")
		return
	match mode:
		Mode.OFFLINE:
			sim.queue_train(local_player, kind)
		Mode.ONLINE:
			var seq := client.send_train(kind)
			if seq == -1:
				hud.toast("Not connected")
			else:
				_sent[seq] = "train"


## Enemy ant near the tap on screen, else an enemy colony or aphid cluster
## under it on the ground. 0 if none.
func pick_target(screen_pos: Vector2, ground: Vector2) -> int:
	var best := 0
	var best_d := PICK_RADIUS_PX
	for s in _snapshot:
		if s.owner == local_player or not _is_ant(s):
			continue
		var sp: Variant = rig.world_to_screen(Vector3(s.pos.x, 0.2, s.pos.y))
		if sp == null:
			continue
		var d: float = screen_pos.distance_to(sp)
		if d < best_d:
			best_d = d
			best = s.id
	if best != 0:
		return best
	for s in _snapshot:
		var k: int = s.get("kind", 0)
		if k == SimWorld.COLONY and s.owner != local_player \
				and ground.distance_to(s.pos) < SimWorld.COLONY_RADIUS + 0.5:
			return s.id
		if k == SimWorld.APHID and ground.distance_to(s.pos) < SimWorld.APHID_RADIUS + 1.0:
			return s.id
	return 0


func _is_enemy(id: int) -> bool:
	if id == 0:
		return false
	for s in _snapshot:
		if s.id == id:
			return s.owner != local_player and s.owner != 0
	return false


## Nearest own unit within PICK_RADIUS_PX of a screen point, or -1.
func pick_unit(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS_PX
	for s in _snapshot:
		if s.owner != local_player or not _is_ant(s):
			continue
		var sp: Variant = rig.world_to_screen(Vector3(s.pos.x, 0.2, s.pos.y))
		if sp == null:
			continue
		var d: float = screen_pos.distance_to(sp)
		if d < best_d:
			best_d = d
			best = s.id
	return best


func _select_same_kind_on_screen(id: int, additive: bool) -> void:
	var kind := -1
	for s in _snapshot:
		if s.id == id:
			kind = s.get("kind", SimWorld.WORKER)
	var view := get_viewport().get_visible_rect()
	var ids: Array = selection.keys() if additive else []
	for s in _snapshot:
		if s.owner != local_player or s.get("kind", SimWorld.WORKER) != kind or ids.has(s.id):
			continue
		var sp: Variant = rig.world_to_screen(Vector3(s.pos.x, 0.2, s.pos.y))
		if sp != null and view.has_point(sp):
			ids.append(s.id)
	_set_selection(ids)


## Ctrl+n stores the selection as group n, Shift+n adds to it, n selects it.
## Pressing n again quickly centers the camera on the group.
func _on_group_key(n: int, set_group: bool, add: bool) -> void:
	if set_group:
		groups[n] = selection.keys()
		return
	if add:
		var ids: Array = groups.get(n, [])
		for id in selection:
			if not ids.has(id):
				ids.append(id)
		groups[n] = ids
		return
	var alive: Array = []
	for id in groups.get(n, []):
		if _views.has(id):
			alive.append(id)
	groups[n] = alive
	var now := Time.get_ticks_msec()
	var again := n == _last_group and now - _last_group_ms <= GROUP_DOUBLE_TAP_MS
	_last_group = n
	_last_group_ms = now
	if alive.is_empty():
		return
	_set_selection(alive)
	if again:
		var sum := Vector2.ZERO
		var count := 0
		for s in _snapshot:
			if selection.has(s.id):
				sum += s.pos
				count += 1
		if count > 0:
			rig.center_on(sum / count)


func _center_on_colony() -> void:
	for s in _snapshot:
		if s.owner == local_player and int(s.get("kind", 0)) == SimWorld.COLONY:
			rig.center_on(s.pos)
			return


func _select_all() -> void:
	var ids: Array = []
	for s in _snapshot:
		if s.owner == local_player and _is_ant(s):
			ids.append(s.id)
	_set_selection(ids)


func _set_selection(ids: Array) -> void:
	for id in selection:
		if _views.has(id):
			_views[id].set_selected(false)
	selection.clear()
	for id in ids:
		selection[id] = true
		if _views.has(id):
			_views[id].set_selected(true)
