class_name NetClient
extends Node
## Connects to a GameServer, sends order and train intent, and buffers snapshots for
## smooth drawing. Holds no game rules: what the player sees is the server's
## state, ~delay_ticks in the past (see SnapshotBuffer).

signal joined(player_id: int)
signal rejected(reason: int)
## Lost the connection, or never got one (timeout / refused).
signal connection_failed(message: String)
signal command_result(seq: int, ok: bool)

enum State { IDLE, CONNECTING, HANDSHAKE, JOINED, CLOSED }

const CONNECT_TIMEOUT_MS := 6000

var state := State.IDLE
var player_id := 0
var players_mask := 0
## From the newest snapshot (not delayed like the drawn units).
var winner := 0
var match_started := false
## player -> {honeydew, units, queue_len, front, progress}
var player_states: Dictionary = {}
var map_half := Vector2.ZERO
var buffer := SnapshotBuffer.new()

var _peer: ENetMultiplayerPeer
var _seq := 0
var _started_ms := 0
var _newest_tick := -1


func connect_to(address: String, port: int = Protocol.DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	buffer.clear()
	state = State.CONNECTING
	_started_ms = Time.get_ticks_msec()
	return OK


func close() -> void:
	if _peer:
		_peer.close()
		_peer = null
	state = State.CLOSED if state != State.IDLE else State.IDLE
	player_id = 0
	winner = 0
	match_started = false
	player_states.clear()
	_newest_tick = -1


## True once both player slots are filled on the server.
func opponent_present() -> bool:
	return players_mask & 0b11 == 0b11


## Round-trip time to the server in ms, or -1 if unknown.
func rtt_ms() -> int:
	if _peer == null or state != State.JOINED:
		return -1
	var p := _peer.get_peer(1)
	return -1 if p == null else int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## Sends an order (see SimWorld.issue_order) and returns its seq, to match
## the command_result, or -1 if it couldn't be sent.
func send_order(unit_ids: Array, target: Vector2, target_id: int = 0) -> int:
	if state != State.JOINED:
		return -1
	var data := Protocol.order(_seq + 1, unit_ids, target, target_id)
	if data.is_empty():
		return -1
	_seq += 1
	_send(data)
	return _seq


func send_move(unit_ids: Array, target: Vector2) -> int:
	return send_order(unit_ids, target, 0)


## Asks the server to train an ant of `kind` at our colony. Returns seq or -1.
func send_train(kind: int) -> int:
	if state != State.JOINED:
		return -1
	_seq += 1
	_send(Protocol.train(_seq, kind))
	return _seq


func _process(delta: float) -> void:
	poll(delta)


func poll(delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	var status := _peer.get_connection_status()
	if state == State.CONNECTING:
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			state = State.HANDSHAKE
			_send(Protocol.hello())
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED or _timed_out():
			_fail("Couldn't reach server")
			return
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_fail("Disconnected from server")
		return
	if state == State.HANDSHAKE and _timed_out():
		_fail("Server didn't answer")
		return

	while _peer and _peer.get_available_packet_count() > 0:
		var msg := Protocol.decode(_peer.get_packet())
		if not msg.is_empty():
			_handle(msg)
	buffer.advance(delta)


func _handle(msg: Dictionary) -> void:
	match msg.type:
		Protocol.WELCOME:
			if state != State.HANDSHAKE:
				return
			state = State.JOINED
			player_id = msg.player
			map_half = msg.map_half
			buffer.tick_rate = msg.tick_rate
			joined.emit(player_id)
		Protocol.REJECT:
			var reason: int = msg.reason
			close()
			rejected.emit(reason)
		Protocol.SNAPSHOT:
			if state == State.JOINED:
				players_mask = msg.players
				if msg.tick >= _newest_tick:
					_newest_tick = msg.tick
					winner = msg.winner
					match_started = msg.started
					player_states = msg.states
				buffer.push(msg.tick, msg.units)
		Protocol.RESULT:
			if state == State.JOINED:
				command_result.emit(msg.seq, msg.ok)


func _timed_out() -> bool:
	return Time.get_ticks_msec() - _started_ms > CONNECT_TIMEOUT_MS


func _fail(message: String) -> void:
	close()
	connection_failed.emit(message)


func _send(data: PackedByteArray) -> void:
	_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	_peer.put_packet(data)
