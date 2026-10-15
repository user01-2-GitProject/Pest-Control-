class_name GameServer
extends Node
## Authoritative match server. Runs SimWorld at its fixed 20 Hz tick over ENet
## (UDP). Clients only send intent (MOVE); every command goes through
## SimWorld.issue_move, which checks ownership and limits. After each tick the
## server sends every joined client a full snapshot (unreliable, ordered:
## a late snapshot is dropped rather than delaying newer ones) and the
## accept/reject result of each of that client's commands (reliable).
##
## Two player slots, each bound to the install token of the first client that
## took it. Only that token gets the slot back after a disconnect (ants stay
## put meanwhile). If the token rejoins while its old connection is still
## timing out, the new connection replaces the old one at once. The token is
## a stand-in for real player identity.
##
## Runs headless (src/net/server_main.gd) or inside a phone's game ("Host").

signal log_line(text: String)

const MAX_PLAYERS := 2
const START_UNITS := 20
const MAP_HALF := Vector2(30, 30)
## Extra commands in one tick are dropped (the first gets a reject reply), so
## a client can't flood the sim or the reliable send queue.
const MAX_COMMANDS_PER_TICK := 8
## A peer sending more than this is kicked. Honest clients send a few per second.
const MAX_PACKETS_PER_SECOND := 100
## Bounds the work one frame spends reading packets.
const MAX_PACKETS_PER_FRAME := 256
## ENet peer timeout (ms): a dead or suspended phone is dropped within ~5 s
## instead of ENet's default 30 s.
const PEER_TIMEOUT_MIN_MS := 2000
const PEER_TIMEOUT_MAX_MS := 5000
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
## peer id -> [window start msec, packets in window]
var _packet_rate: Dictionary = {}
var _spawned_slots: Dictionary = {}
## slot -> install token that owns it
var _slot_tokens: Dictionary = {}
var _dropped_ticks := 0


## Opens the UDP port. Returns OK or the ENet error.
func start(listen_port: int = Protocol.DEFAULT_PORT, bind_address: String = "*") -> Error:
	sim = SimWorld.new(MAP_HALF)
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
	_awaiting_hello.clear()
	_kick_at.clear()
	_commands_this_tick.clear()
	_packet_rate.clear()
	_spawned_slots.clear()
	_slot_tokens.clear()
	_acc = 0.0


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
	if ticks == MAX_TICKS_PER_FRAME and _acc >= SimWorld.DT:
		# Running here on a phone, a long render hitch or app pause would
		# otherwise replay seconds of sim in a burst. Drop it, but say so.
		var lost := int(_acc / SimWorld.DT)
		_dropped_ticks += lost
		_log("dropped %d ticks (%d ms) after a stall; %d total" % [lost, int(_acc * 1000), _dropped_ticks])
		_acc = 0.0


## Tells clients the hosting phone is going to the background (or back), so
## the other player sees why the game stopped.
func notify_paused(paused: bool) -> void:
	if _peer == null:
		return
	var data := Protocol.notice(Protocol.NOTICE_HOST_PAUSED if paused else Protocol.NOTICE_HOST_RESUMED)
	for peer_id in players:
		_send(peer_id, data, true)
	_peer.poll()  # Flush now; the app may be suspended right after this.


func _tick() -> void:
	sim.step()
	_commands_this_tick.clear()
	for r in sim.last_results:
		var peer_id := _peer_for_slot(r.player)
		if peer_id != 0:
			_send(peer_id, Protocol.result(r.seq, r.ok, r.tick), true)
	var snap := Protocol.snapshot(sim.tick, players_mask(), sim.snapshot())
	for peer_id in players:
		_send(peer_id, snap, false)


func _read_packets() -> void:
	var budget := MAX_PACKETS_PER_FRAME
	while budget > 0 and _peer and _peer.get_available_packet_count() > 0:
		budget -= 1
		var from := _peer.get_packet_peer()
		var data := _peer.get_packet()
		if _kick_at.has(from) or _over_rate(from):
			continue
		var msg := Protocol.decode(data)
		if msg.is_empty():
			continue
		match msg.type:
			Protocol.HELLO:
				_on_hello(from, msg)
			Protocol.MOVE:
				_on_move(from, msg)


func _on_hello(from: int, msg: Dictionary) -> void:
	if players.has(from):
		return
	_awaiting_hello.erase(from)
	if msg.version != Protocol.VERSION:
		_reject(from, Protocol.REJECT_VERSION)
		return
	var slot := _slot_for_token(msg.token)
	if slot == 0:
		_reject(from, Protocol.REJECT_FULL)
		return
	var old_peer := _peer_for_slot(slot)
	if old_peer != 0:
		# Same install rejoining before its old connection timed out.
		players.erase(old_peer)
		_kick_at[old_peer] = 0
		_log("peer %d replaces stale peer %d as player %d" % [from, old_peer, slot])
	_slot_tokens[slot] = msg.token
	players[from] = slot
	if not _spawned_slots.has(slot):
		_spawn_army(slot)
	_send(from, Protocol.welcome(slot, sim.tick, SimWorld.TICK_RATE, sim.map_half_size), true)
	_log("peer %d joined as player %d" % [from, slot])


func _on_move(from: int, msg: Dictionary) -> void:
	var slot: int = players.get(from, 0)
	if slot == 0:
		return
	var n: int = _commands_this_tick.get(from, 0)
	if n >= MAX_COMMANDS_PER_TICK:
		# Reply to the first excess command only; drop the rest silently.
		if n == MAX_COMMANDS_PER_TICK:
			_send(from, Protocol.result(msg.seq, false, sim.tick), true)
			_commands_this_tick[from] = n + 1
		return
	_commands_this_tick[from] = n + 1
	# Ownership, limits and target validity are all checked by the sim.
	sim.queue_move(slot, msg.ids, msg.target, msg.seq)


func _spawn_army(slot: int) -> void:
	_spawned_slots[slot] = true
	# Player 1 starts on the left, player 2 mirrored on the right.
	var side := -1.0 if slot == 1 else 1.0
	var cols := 5
	for i in START_UNITS:
		var p := Vector2(side * (12.0 + (i % cols) * 1.4), -3.0 + (i / cols) * 1.4)
		sim.spawn_unit(slot, p)


## The slot this token owns, else a slot nobody owns yet, else 0.
func _slot_for_token(token: int) -> int:
	for slot in _slot_tokens:
		if _slot_tokens[slot] == token:
			return slot
	for slot in range(1, MAX_PLAYERS + 1):
		if not _slot_tokens.has(slot):
			return slot
	return 0


func _over_rate(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var r: Array = _packet_rate.get(peer_id, [now, 0])
	if now - r[0] >= 1000:
		r = [now, 0]
	r[1] += 1
	_packet_rate[peer_id] = r
	if r[1] > MAX_PACKETS_PER_SECOND:
		_log("peer %d kicked: over %d packets/s" % [peer_id, MAX_PACKETS_PER_SECOND])
		players.erase(peer_id)
		_kick_at[peer_id] = 0
		return true
	return false


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
	var p := _peer.get_peer(peer_id)
	if p:
		p.set_timeout(0, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


func _on_peer_disconnected(peer_id: int) -> void:
	_awaiting_hello.erase(peer_id)
	_kick_at.erase(peer_id)
	_commands_this_tick.erase(peer_id)
	_packet_rate.erase(peer_id)
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
