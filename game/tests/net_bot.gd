extends SceneTree
## Headless test client for the multi-process check: one dedicated server and
## two of these, each its own OS process, over real UDP. Each bot joins, waits
## for its opponent, moves its own ants to its own target, tries to move the
## opponent's (must be rejected), queues a worker (must be accepted and paid
## for), and passes once the server shows its ants at the target. Run from game/:
##   godot --headless -s res://tests/net_bot.gd -- [--address 127.0.0.1] [--port 7777]

const Client = preload("res://src/net/net_client.gd")

const TIMEOUT_S := 30.0
const RETRY_MS := 500


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var address := _arg(args, "--address", "127.0.0.1")
	var port := int(_arg(args, "--port", str(Protocol.DEFAULT_PORT)))
	var deadline := Time.get_ticks_msec() + int(TIMEOUT_S * 1000)

	var c: NetClient = Client.new()
	root.add_child(c)
	# The server may still be starting: retry until joined or out of time.
	while c.state != NetClient.State.JOINED:
		if Time.get_ticks_msec() > deadline:
			return _fail("never joined %s:%d" % [address, port])
		if c.state != NetClient.State.CONNECTING and c.state != NetClient.State.HANDSHAKE:
			c.connect_to(address, port)
			await create_timer(RETRY_MS / 1000.0).timeout
		await process_frame
	var me := c.player_id
	print("net_bot: joined as player %d" % me)

	if not await _until(func() -> bool: return c.opponent_present() and c.match_started \
			and c.buffer.sample().size() == 30, deadline):
		return _fail("player %d: opponent never appeared" % me)

	var mine: Array = []
	var theirs: Array = []
	for s in c.buffer.sample():
		if s.kind == SimWorld.WORKER or s.kind == SimWorld.SOLDIER:
			(mine if s.owner == me else theirs).append(s.id)
	var results := {}
	c.command_result.connect(func(seq: int, ok: bool) -> void: results[seq] = ok)
	var target := Vector2(-8.0 if me == 1 else 8.0, 10.0)
	var ok_seq := c.send_move(mine, target)
	var bad_seq := c.send_move(theirs, Vector2.ZERO)
	var train_seq := c.send_train(SimWorld.WORKER)

	if not await _until(func() -> bool: return results.has(ok_seq) and results.has(bad_seq) \
			and results.has(train_seq), deadline):
		return _fail("player %d: no command results" % me)
	if results[ok_seq] != true or results[bad_seq] != false or results[train_seq] != true:
		return _fail("player %d: own move ok=%s, enemy move ok=%s, train ok=%s" % [me, results[ok_seq],
			results[bad_seq], results[train_seq]])

	var arrived := func() -> bool:
		for s in c.buffer.sample():
			if s.id in mine and s.pos.distance_to(target) > 4.0:
				return false
		return true
	if not await _until(arrived, deadline):
		return _fail("player %d: ants never reached %s" % [me, target])

	print("net_bot: passed player %d (rtt %d ms)" % [me, c.rtt_ms()])
	# Stay a moment so the other bot keeps seeing an opponent until it passes.
	await create_timer(3.0).timeout
	c.close()
	quit(0)


func _until(cond: Callable, deadline: int) -> bool:
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _fail(msg: String) -> void:
	printerr("FAIL: net_bot " + msg)
	quit(1)


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i != -1 and i + 1 < args.size() else fallback
