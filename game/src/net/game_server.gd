class_name GameServer
extends Node
## Authoritative match server. Runs SimWorld at its fixed 20 Hz tick over ENet
## (UDP). Clients only send intent (ORDER, TRAIN); every command goes through
## SimWorld.issue_order / issue_train, which check ownership, honeydew, the
## unit cap and the match state. After each tick the
## server sends every joined client a full snapshot (unreliable, ordered:
## a late snapshot is dropped rather than delaying newer ones) and the
## accept/reject result of each of that client's commands (reliable).
##
## The match is set up at start() but the clock only runs once both slots
## have filled; until then commands are refused. Two player slots. A client
## that disconnects frees its slot and its ants keep following their last
## orders; the next client to join takes the slot and its colony. That is a
## stand-in for real reconnect until there are player identities.
##
## Runs headless (src/net/server_main.gd) or inside a phone's game ("Host").

signal log_line(text: String)

const MAX_PLAYERS := 2
const MAP_HALF := Vector2(30, 30)
## Extra commands in one tick are rejected, so a client can't flood the sim.
const MAX_COMMANDS_PER_TICK := 8
## Peers that haven't sent a valid HELLO by then are dropped.
const HELLO_TIMEOUT_MS := 5000
## Rejected peers get this long for the REJECT to arrive before the kick.
const KICK_DELAY_MS := 500
const MAX_TICKS_PER_FRAME := 5

var sim: SimWorld
var port := 0
## peer id -> player slot (1..MAX_PLAYERS)
var players: Dictionary = {}

var _peer: ENetMultiplayerPeer
var _acc := 0.0
## peer id -> Time.get_ticks_msec() when it connected, until it says HELLO
var _awaiting_hello: Dictionary = {}
## peer id -> msec at which to disconnect it
var _kick_at: Dictionary = {}
## peer id -> commands queued this tick
var _commands_this_tick: Dictionary = {}
## True once both players have joined; the sim only steps after that.
var started := false
var _announced_winner := false


## Opens the UDP port. Returns OK or the ENet error.
func start(listen_port: int = Protocol.DEFAULT_PORT, bind_address: String = "*") -> Error:
	sim = SimWorld.new(MAP_HALF)
	sim.setup_match()
	started = false
	_announced_winner = false
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(bind_address)
	# Room for the 2 players plus a few that will be told the server is full.
	var err := _peer.create_server(listen_port, MAX_PLAYERS + 4)
	if err != OK:
		_peer = null
		return err
	port = listen_port
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	_log("listening on UDP %d (protocol v%d)" % [port, Protocol.VERSION])
	return OK


func stop() -> void:
	if _peer:
		_peer.close()
		_peer = null
	players.clear()


func is_running() -> bool:
	return _peer != null


## Bitmask of filled slots: bit 0 = player 1, bit 1 = player 2.
func players_mask() -> int:
	var mask := 0
	for slot in players.values():
		mask |= 1 << (slot - 1)
	return mask


func _process(delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	_read_packets()
	_kick_due_peers()

	_acc += delta
	var ticks := 0
	while _acc >= SimWorld.DT and ticks < MAX_TICKS_PER_FRAME:
		_acc -= SimWorld.DT
		ticks += 1
		_tick()
	if ticks == MAX_TICKS_PER_FRAME:
		_acc = 0.0


func _tick() -> void:
	if not started and players.size() == MAX_PLAYERS:
		started = true
		_log("match started")
	if started:
		sim.step()
	if sim.winner != 0 and not _announced_winner:
		_announced_winner = true
		_log("match over: %s" % ("draw" if sim.winner == SimWorld.DRAW else "player %d wins" % sim.winner))
	_commands_this_tick.clear()
	for r in sim.last_results:
		var peer_id := _peer_for_slot(r.player)
		if peer_id != 0:
			_send(peer_id, Protocol.result(r.seq, r.ok, r.tick), true)
	var states := {1: sim.player_state(1), 2: sim.player_state(2)}
	var snap := Protocol.snapshot(sim.tick, players_mask(), sim.snapshot(), sim.winner, started, states)
	for peer_id in players:
		_send(peer_id, snap, false)


func _read_packets() -> void:
	while _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var msg := Protocol.decode(_peer.get_packet())
		if msg.is_empty() or _kick_at.has(from):
			continue
		match msg.type:
			Protocol.HELLO:
				_on_hello(from, msg)
			Protocol.ORDER, Protocol.TRAIN:
				_on_command(from, msg)


func _on_hello(from: int, msg: Dictionary) -> void:
	if players.has(from):
		return
	_awaiting_hello.erase(from)
	if msg.version != Protocol.VERSION:
		_reject(from, Protocol.REJECT_VERSION)
		return
	var slot := _free_slot()
	if slot == 0:
		_reject(from, Protocol.REJECT_FULL)
		return
	players[from] = slot
	_send(from, Protocol.welcome(slot, sim.tick, SimWorld.TICK_RATE, sim.map_half_size), true)
	_log("peer %d joined as player %d" % [from, slot])


func _on_command(from: int, msg: Dictionary) -> void:
	var slot: int = players.get(from, 0)
	if slot == 0:
		return
	var n: int = _commands_this_tick.get(from, 0)
	if n >= MAX_COMMANDS_PER_TICK or not started:
		_send(from, Protocol.result(msg.seq, false, sim.tick), true)
		return
	_commands_this_tick[from] = n + 1
	# Ownership, costs, limits and target validity are all checked by the sim.
	if msg.type == Protocol.TRAIN:
		sim.queue_train(slot, msg.kind, msg.seq)
	else:
		sim.queue_order(slot, msg.ids, msg.target, msg.target_id, msg.seq)


func _free_slot() -> int:
	var used := players.values()
	for slot in range(1, MAX_PLAYERS + 1):
		if not used.has(slot):
			return slot
	return 0


func _peer_for_slot(slot: int) -> int:
	for peer_id in players:
		if players[peer_id] == slot:
			return peer_id
	return 0


func _reject(peer_id: int, reason: int) -> void:
	_send(peer_id, Protocol.reject(reason), true)
	_kick_at[peer_id] = Time.get_ticks_msec() + KICK_DELAY_MS
	_log("peer %d rejected (reason %d)" % [peer_id, reason])


func _kick_due_peers() -> void:
	var now := Time.get_ticks_msec()
	for peer_id in _awaiting_hello.keys():
		if now - _awaiting_hello[peer_id] > HELLO_TIMEOUT_MS:
			_awaiting_hello.erase(peer_id)
			_kick_at[peer_id] = now
	for peer_id in _kick_at.keys():
		if now >= _kick_at[peer_id]:
			_kick_at.erase(peer_id)
			_peer.disconnect_peer(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	_awaiting_hello[peer_id] = Time.get_ticks_msec()


func _on_peer_disconnected(peer_id: int) -> void:
	_awaiting_hello.erase(peer_id)
	_kick_at.erase(peer_id)
	_commands_this_tick.erase(peer_id)
	if players.has(peer_id):
		_log("player %d left (peer %d)" % [players[peer_id], peer_id])
		players.erase(peer_id)


func _send(peer_id: int, data: PackedByteArray, reliable: bool) -> void:
	_peer.set_target_peer(peer_id)
	_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	_peer.put_packet(data)


func _log(text: String) -> void:
	print("[server] " + text)
	log_line.emit(text)
