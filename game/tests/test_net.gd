extends SceneTree
## Network tests. Run from the game/ folder after importing:
##   godot --headless -s res://tests/test_net.gd
## Part 1: wire format and jitter buffer, no sockets.
## Part 2: a GameServer and real NetClients in this process, talking ENet over
## loopback UDP. (tests/net_bot.gd covers separate processes.)

const Proto = preload("res://src/net/protocol.gd")
const Buffer = preload("res://src/net/snapshot_buffer.gd")
const Server = preload("res://src/net/game_server.gd")
const Client = preload("res://src/net/net_client.gd")

const PORT := 47801
## setup_match(): 8 aphid clusters + 2 colonies + 2 x 10 ants.
const ENTITIES := 30

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_roundtrip()
	_test_malformed_rejected()
	_test_snapshot_quantization()
	_test_buffer_interpolates()
	_test_buffer_out_of_order_and_duplicates()
	_test_buffer_holds_when_starved()
	_test_buffer_smooth_under_jitter_and_loss()
	await _test_live_match()
	print("test_net: %s" % ("FAILED (%d)" % _failures if _failures else "all passed"))
	quit(1 if _failures else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


# --- Part 1: protocol --------------------------------------------------------

func _test_roundtrip() -> void:
	var m := Proto.decode(Proto.hello(0x1234567890ABCDEF))
	_check(m.get("type") == Proto.HELLO and m.version == Proto.VERSION and m.token == 0x1234567890ABCDEF,
		"hello roundtrip")
	m = Proto.decode(Proto.notice(Proto.NOTICE_HOST_PAUSED))
	_check(m.get("type") == Proto.NOTICE and m.code == Proto.NOTICE_HOST_PAUSED, "notice roundtrip")
	m = Proto.decode(Proto.welcome(2, 1234, 20, Vector2(30, 25)))
	_check(m.get("player") == 2 and m.tick == 1234 and m.tick_rate == 20 and m.map_half == Vector2(30, 25),
		"welcome roundtrip")
	m = Proto.decode(Proto.reject(Proto.REJECT_FULL))
	_check(m.get("reason") == Proto.REJECT_FULL, "reject roundtrip")
	m = Proto.decode(Proto.order(77, [1, 2, 65535], Vector2(-3.5, 9.25), 300))
	_check(m.get("seq") == 77 and m.ids == [1, 2, 65535] and m.target == Vector2(-3.5, 9.25)
		and m.target_id == 300, "order roundtrip")
	m = Proto.decode(Proto.train(78, SimWorld.SOLDIER))
	_check(m.get("type") == Proto.TRAIN and m.seq == 78 and m.kind == SimWorld.SOLDIER, "train roundtrip")
	m = Proto.decode(Proto.result(77, false, 999))
	_check(m.get("seq") == 77 and m.ok == false and m.tick == 999, "result roundtrip")


func _test_malformed_rejected() -> void:
	_check(Proto.decode(PackedByteArray()).is_empty(), "empty packet")
	_check(Proto.decode(PackedByteArray([99, 1, 2])).is_empty(), "unknown type")
	var hello := Proto.hello(5)
	_check(Proto.decode(hello.slice(0, 14)).is_empty(), "truncated hello")
	hello[1] ^= 0xFF
	_check(Proto.decode(hello).is_empty(), "bad magic")
	_check(Proto.decode(Proto.hello(9, 2)).get("version") == 2 and Proto.VERSION != 2,
		"M2 wire version is recognized as incompatible")
	var notice := Proto.decode(Proto.notice(Proto.NOTICE_HOST_PAUSED))
	_check(notice.get("type") == Proto.NOTICE and Proto.NOTICE != Proto.TRAIN,
		"pause notices cannot be confused with training commands")
	var old := Proto.decode(Proto.hello(0, 1).slice(0, 7))
	_check(old.get("version") == 1, "v1 hello (no token) still decodes, so it can be told to update")
	var mv := Proto.order(1, [1, 2, 3], Vector2.ZERO)
	_check(Proto.decode(mv.slice(0, mv.size() - 1)).is_empty(), "truncated order")
	mv.append(0)
	_check(Proto.decode(mv).is_empty(), "order with trailing bytes")
	var tr := Proto.train(1, 1)
	tr.append(0)
	_check(Proto.decode(tr).is_empty(), "train with trailing bytes")
	var snap := Proto.snapshot(5, 3, [{"id": 1, "owner": 1, "pos": Vector2.ZERO, "facing": 0.0}])
	snap[Proto.SNAPSHOT_HEADER - 2] = 0xFF  # claims 65535+ entities
	snap[Proto.SNAPSHOT_HEADER - 1] = 0xFF
	_check(Proto.decode(snap).is_empty(), "snapshot count larger than packet")
	_check(Proto.order(1, range(300), Vector2.ZERO).is_empty(), "too many ids not encoded")
	_check(Proto.order(1, [70000], Vector2.ZERO).is_empty(), "id outside u16 not encoded")
	_check(Proto.order(1, [1], Vector2.ZERO, 70000).is_empty(), "target id outside u16 not encoded")
	# Random garbage never crashes and never decodes into a MOVE with bad length.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2000:
		var junk := PackedByteArray()
		junk.resize(rng.randi_range(1, 40))
		for j in junk.size():
			junk[j] = rng.randi_range(0, 255)
		var d := Proto.decode(junk)
		if d.get("type") == Proto.ORDER and junk.size() != 16 + d.ids.size() * 2:
			_check(false, "garbage decoded as inconsistent ORDER")


func _test_snapshot_quantization() -> void:
	var units := [
		{"id": 3, "kind": SimWorld.SOLDIER, "owner": 2, "pos": Vector2(12.3456, -29.999), "facing": -1.0,
			"hp": 0.5, "flags": 3},
		{"id": 4, "kind": SimWorld.COLONY, "owner": 1, "pos": Vector2(-400, 400), "facing": 7.0,
			"hp": 1.0, "flags": 0},
	]
	var states := {1: {"honeydew": 70000, "units": 12, "queue": [SimWorld.SOLDIER, SimWorld.WORKER],
		"progress": 0.5}}
	var m := Proto.decode(Proto.snapshot(42, 3, units, 2, true, states))
	_check(m.get("tick") == 42 and m.players == 3 and m.units.size() == 2, "snapshot header")
	_check(m.winner == 2 and m.started, "winner and started")
	var p1: Dictionary = m.states[1]
	_check(p1.honeydew == 0xFFFF and p1.units == 12 and p1.queue_len == 2 and p1.front == SimWorld.SOLDIER
		and absf(p1.progress - 0.5) < 0.01, "player 1 economy (honeydew clamps), got %s" % p1)
	_check(m.states[2].honeydew == 0 and m.states[2].queue_len == 0, "missing player encodes as zeros")
	var a: Dictionary = m.units[0]
	_check(a.id == 3 and a.owner == 2 and a.kind == SimWorld.SOLDIER, "snapshot ids and kind")
	_check(absf(a.hp - 0.5) < 0.01 and a.flags == 3, "hp and flags")
	_check(Proto.snapshot(1, 0, units).size() == Proto.SNAPSHOT_HEADER + 2 * Proto.ENTITY_BYTES, "documented size")
	_check(a.pos.distance_to(units[0].pos) < 0.01, "pos within 1 cm, got %s" % a.pos)
	_check(absf(angle_difference(a.facing, -1.0)) < TAU / 256.0, "facing within 1/256 turn")
	_check(absf(m.units[1].pos.x) < 330.0, "out-of-range pos clamps instead of wrapping")


# --- Part 1: jitter buffer ---------------------------------------------------

func _snap_units(x: float) -> Array:
	return [{"id": 1, "owner": 1, "pos": Vector2(x, 0), "facing": 0.0}]


func _test_buffer_interpolates() -> void:
	var b := Buffer.new()
	b.push(10, _snap_units(0.0))
	b.push(11, _snap_units(1.0))
	b.push(12, _snap_units(2.0))
	b.advance(0.0)
	_check(is_equal_approx(b.render_tick, 10.0), "render starts delay_ticks behind newest")
	b.render_tick = 10.5
	var s := b.sample()
	_check(s.size() == 1 and is_equal_approx(s[0].pos.x, 0.5), "halfway between ticks")


func _test_buffer_out_of_order_and_duplicates() -> void:
	var b := Buffer.new()
	_check(b.push(10, _snap_units(0.0)), "first push")
	_check(b.push(12, _snap_units(2.0)), "gap push")
	_check(b.push(11, _snap_units(1.0)), "late packet fills the gap")
	_check(not b.push(11, _snap_units(9.0)), "duplicate dropped")
	b.render_tick = 11.0
	_check(is_equal_approx(b.sample()[0].pos.x, 1.0), "late packet used in order")
	for t in range(13, 13 + Buffer.MAX_SNAPSHOTS):
		b.push(t, _snap_units(t))
	_check(not b.push(10, _snap_units(0.0)), "packet older than buffer dropped")


func _test_buffer_holds_when_starved() -> void:
	var b := Buffer.new()
	b.push(1, _snap_units(0.0))
	b.push(2, _snap_units(1.0))
	b.advance(0.0)
	for i in 40:
		b.advance(0.05)
	_check(b.render_tick <= 2.0, "never renders past newest snapshot")
	_check(is_equal_approx(b.sample()[0].pos.x, 1.0), "holds last position, no extrapolation")


## A unit moves at constant speed; packets arrive with up to 60 ms jitter and
## 10% loss while the client renders at 60 FPS. The drawn motion should stay
## smooth: no backwards steps and no frame jumping much more than normal.
func _test_buffer_smooth_under_jitter_and_loss() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var speed := 4.0  # m/s, same as an ant
	var arrivals: Array = []  # [arrive_time, tick]
	for tick in range(1, 200):
		if rng.randf() < 0.1:
			continue
		arrivals.append([tick * 0.05 + rng.randf_range(0.0, 0.06), tick])
	arrivals.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])

	var b := Buffer.new()
	var frame := 1.0 / 60.0
	var t := 0.0
	var next := 0
	var last_x := -INF
	var worst_step := 0.0
	var backwards := 0
	while t < 9.5:
		t += frame
		while next < arrivals.size() and arrivals[next][0] <= t:
			var tick: int = arrivals[next][1]
			b.push(tick, _snap_units(tick * 0.05 * speed))
			next += 1
		b.advance(frame)
		var s := b.sample()
		if s.is_empty() or t < 1.0:
			continue
		var x: float = s[0].pos.x
		if last_x > -INF:
			if x < last_x - 0.0001:
				backwards += 1
			worst_step = maxf(worst_step, x - last_x)
		last_x = x
	var ideal := speed * frame
	_check(backwards == 0, "no backwards steps under jitter (%d)" % backwards)
	_check(worst_step < ideal * 2.5, "largest frame step %.3f m vs ideal %.3f m" % [worst_step, ideal])


# --- Part 2: live match over loopback UDP ------------------------------------

func _test_live_match() -> void:
	var server: GameServer = Server.new()
	root.add_child(server)
	_check(server.start(PORT, "127.0.0.1") == OK, "server listens")

	var c1: NetClient = Client.new()
	var c2: NetClient = Client.new()
	root.add_child(c1)
	root.add_child(c2)
	var results := {}
	c1.command_result.connect(func(seq: int, ok: bool) -> void: results[seq] = ok)

	# Alone on the server: the match waits and commands are refused.
	c1.connect_to("127.0.0.1", PORT)
	_check(await _wait(func() -> bool: return c1.state == NetClient.State.JOINED and _ids(c1, c1.player_id).size() == 10, 5.0),
		"first client joins and sees its 10 starting ants")
	var early := c1.send_move(_ids(c1, c1.player_id), Vector2.ZERO)
	_check(await _wait(func() -> bool: return results.has(early), 3.0) and results[early] == false,
		"commands refused before the opponent joins")
	_check(not c1.match_started and server.sim.tick == 0, "match clock waits for two players")

	c2.connect_to("127.0.0.1", PORT)
	var both_joined := func() -> bool:
		return c1.state == NetClient.State.JOINED and c2.state == NetClient.State.JOINED \
			and c1.opponent_present() and c2.opponent_present() and c1.match_started \
			and c1.buffer.sample().size() == ENTITIES and c2.buffer.sample().size() == ENTITIES
	_check(await _wait(both_joined, 5.0), "two clients join and each sees all %d entities" % ENTITIES)
	_check([c1.player_id, c2.player_id].has(1) and [c1.player_id, c2.player_id].has(2),
		"distinct player slots (%d, %d)" % [c1.player_id, c2.player_id])

	# Third client is told the server is full.
	var c3: NetClient = Client.new()
	root.add_child(c3)
	var rejected := [-1]
	c3.rejected.connect(func(r: int) -> void: rejected[0] = r)
	c3.connect_to("127.0.0.1", PORT)
	_check(await _wait(func() -> bool: return rejected[0] != -1, 5.0) and rejected[0] == Proto.REJECT_FULL,
		"third client rejected as full")

	# Wrong protocol version is refused.
	var raw := ENetMultiplayerPeer.new()
	raw.create_client("127.0.0.1", PORT)
	var got: Array = [{}]
	var bad_version := func() -> bool:
		raw.poll()
		if raw.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and got[0].is_empty():
			got[0] = {"sent": true}
			raw.set_target_peer(1)
			raw.put_packet(Proto.hello(99, Proto.VERSION + 1))
		while raw.get_available_packet_count() > 0:
			got[0] = Proto.decode(raw.get_packet())
		return got[0].get("type") == Proto.REJECT
	_check(await _wait(bad_version, 5.0) and got[0].reason == Proto.REJECT_VERSION, "old client version rejected")
	raw.close()

	# Each player moves only its own ants; moving the enemy's is rejected.
	var mine := _ids(c1, c1.player_id)
	var theirs := _ids(c1, c2.player_id)
	results.clear()
	var target := Vector2(0, 12)
	var ok_seq := c1.send_move(mine, target)
	var bad_seq := c1.send_move(theirs, Vector2(-20, -20))
	var mixed_seq := c1.send_move([mine[0], theirs[0]], Vector2(-20, -20))
	_check(await _wait(func() -> bool: return results.size() >= 3, 3.0), "results come back")
	_check(results.get(ok_seq) == true, "own move accepted")
	_check(results.get(bad_seq) == false, "enemy move rejected")
	_check(results.get(mixed_seq) == false, "mixed own+enemy move rejected")

	# An enemy soldier: idle, so any movement would come from the refused order.
	var enemy_soldier := -1
	for e in c2.buffer.sample():
		if e.id in theirs and e.kind == SimWorld.SOLDIER:
			enemy_soldier = e.id
	var enemy_start := _pos(c2, enemy_soldier)
	var arrived := func() -> bool:
		for id in mine:
			if _pos(c2, id).distance_to(target) > 4.0:
				return false
		return true
	_check(await _wait(arrived, 12.0), "player %d's ants arrive, seen by the other client" % c1.player_id)
	_check(_pos(c2, enemy_soldier).distance_to(enemy_start) < 0.5, "enemy ants were not moved")
	var s1 := c1.buffer.sample()
	var s2 := c2.buffer.sample()
	_check(s1.size() == ENTITIES and s2.size() == ENTITIES, "both clients still see everything")

	# Economy and production through the server: workers earn, train spends.
	var me := c1.player_id
	var honey: int = c1.player_states[me].honeydew
	var t_ok := c1.send_train(SimWorld.WORKER)
	var t_bad := c1.send_train(77)
	_check(await _wait(func() -> bool: return results.has(t_ok) and results.has(t_bad), 3.0)
		and results[t_ok] == true and results[t_bad] == false, "train accepted, unknown kind refused")
	_check(await _wait(func() -> bool: return c2.player_states.get(me, {}).get("queue_len", 0) == 1, 3.0),
		"queued worker visible to both clients")
	_check(await _wait(func() -> bool: return _ids(c1, me).size() == 11, 8.0), "trained worker appears")
	_check(await _wait(func() -> bool: return c1.player_states[me].honeydew > honey - SimWorld.STATS[SimWorld.WORKER].cost, 15.0),
		"workers deliver honeydew (started %d, now %d)" % [honey, c1.player_states[me].honeydew])

	# Command flood: 8 per tick reach the sim, one reject reply, rest dropped.
	results.clear()
	for i in 30:
		c1.send_move(mine, target)
	await _wait(func() -> bool: return false, 0.5)
	var accepted := 0
	var refused := 0
	for ok in results.values():
		if ok:
			accepted += 1
		else:
			refused += 1
	_check(accepted >= 8 and accepted <= 16 and refused >= 1 and refused <= 2,
		"flood of 30: %d accepted, %d refused replies (want 8-16, 1-2)" % [accepted, refused])

	# The host pausing reaches the other player.
	server.notify_paused(true)
	_check(await _wait(func() -> bool: return c1.host_paused, 2.0), "client told host paused")
	server.notify_paused(false)
	_check(await _wait(func() -> bool: return not c1.host_paused, 2.0), "client told host resumed")

	# A phone that vanishes without disconnecting (Wi-Fi drop, app killed)
	# and rejoins with the same install token gets its slot back at once.
	var lost_slot := c2.player_id
	var lost_token := c2.token
	c2.process_mode = Node.PROCESS_MODE_DISABLED  # stops polling: no clean disconnect
	var stranger: NetClient = Client.new()
	root.add_child(stranger)
	var stranger_rej := [-1]
	stranger.rejected.connect(func(r: int) -> void: stranger_rej[0] = r)
	stranger.connect_to("127.0.0.1", PORT)
	_check(await _wait(func() -> bool: return stranger_rej[0] != -1, 5.0) and stranger_rej[0] == Proto.REJECT_FULL,
		"another device can't take a player's slot")
	var c4: NetClient = Client.new()
	c4.token = lost_token
	root.add_child(c4)
	var t0 := Time.get_ticks_msec()
	c4.connect_to("127.0.0.1", PORT)
	_check(await _wait(func() -> bool: return c4.state == NetClient.State.JOINED, 3.0)
		and c4.player_id == lost_slot, "same install rejoins its slot")
	_check(Time.get_ticks_msec() - t0 < 2000, "rejoin doesn't wait for the old connection to time out")
	_check(await _wait(func() -> bool: return _ids(c4, lost_slot).size() == theirs.size(), 2.0),
		"rejoined player retains their army")
	c2.process_mode = Node.PROCESS_MODE_INHERIT
	_check(await _wait(func() -> bool: return c2.state == NetClient.State.CLOSED, 3.0),
		"stale connection is closed by the server")

	# A client spamming packets is kicked.
	var failed := [""]
	c1.connection_failed.connect(func(m: String) -> void: failed[0] = m)
	for i in 300:
		c1.send_move(mine, target)
	_check(await _wait(func() -> bool: return failed[0] != "", 3.0), "packet flooder gets disconnected")

	for n in [c1, c3, c4, stranger]:
		n.close()
	server.stop()


## Ids of `player`'s ants (not its colony).
func _ids(c: NetClient, player: int) -> Array:
	var out: Array = []
	for s in c.buffer.sample():
		if s.owner == player and (s.kind == SimWorld.WORKER or s.kind == SimWorld.SOLDIER):
			out.append(s.id)
	return out


func _pos(c: NetClient, id: int) -> Vector2:
	for s in c.buffer.sample():
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
