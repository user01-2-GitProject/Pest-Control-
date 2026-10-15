class_name Protocol
extends RefCounted
## Wire format shared by GameServer and NetClient. Pure functions, no nodes.
##
## Every packet starts with a u8 message type. Little-endian throughout.
## decode() returns {} for anything malformed (short, oversized, unknown type,
## wrong magic), so callers only ever see well-formed messages.
##
##   HELLO     c->s  magic u32, version u16
##   WELCOME   s->c  player u8, tick u32, tick_rate u8, map_half x f32, y f32
##   REJECT    s->c  reason u8
##   ORDER     c->s  seq u32, target x f32, y f32, target_id u16, count u8, ids u16 * count
##   RESULT    s->c  seq u32, ok u8, tick u32
##   SNAPSHOT  s->c  tick u32, players u8 (bitmask of connected slots), winner u8,
##                   started u8, then for player 1 and 2: honeydew u16, ants u8,
##                   queue length u8, queue front kind u8, progress u8 (1/255),
##                   then count u16 and per entity: id u16, kind u8, owner u8,
##                   x i16, y i16, facing u8, hp u8 (1/255 of max), flags u8
##   TRAIN     c->s  seq u32, kind u8
##
## Snapshot positions are fixed point (1/POS_SCALE m), facing is 1/256 turn.
## 11 bytes per entity: at the 2 x 50 ant cap plus colonies and aphids that is
## ~1.2 KB per tick, ~24 KB/s per client. Every snapshot is a full state.
## Known limitation: both players' honeydew is sent to both clients.

const MAGIC := 0x54534550  # "PEST"
## Bump on any wire change. Server rejects clients with a different version.
const VERSION := 2
const DEFAULT_PORT := 7777

const HELLO := 1
const WELCOME := 2
const REJECT := 3
const ORDER := 4
const RESULT := 5
const SNAPSHOT := 6
const TRAIN := 7

const REJECT_VERSION := 1
const REJECT_FULL := 2

const POS_SCALE := 100.0
const MAX_SNAPSHOT_UNITS := 1024
const MAX_ORDER_IDS := 255
const PLAYER_BLOCK := 6
const SNAPSHOT_HEADER := 1 + 4 + 1 + 1 + 1 + 2 * PLAYER_BLOCK + 2
const ENTITY_BYTES := 11


static func hello() -> PackedByteArray:
	var b := _buf(HELLO)
	b.put_u32(MAGIC)
	b.put_u16(VERSION)
	return b.data_array


static func welcome(player: int, tick: int, tick_rate: int, map_half: Vector2) -> PackedByteArray:
	var b := _buf(WELCOME)
	b.put_u8(player)
	b.put_u32(tick)
	b.put_u8(tick_rate)
	b.put_float(map_half.x)
	b.put_float(map_half.y)
	return b.data_array


static func reject(reason: int) -> PackedByteArray:
	var b := _buf(REJECT)
	b.put_u8(reason)
	return b.data_array


## Returns an empty array if the command can't be encoded (too many ids, or an
## id outside u16). Callers treat that as rejected locally.
static func order(seq: int, ids: Array, target: Vector2, target_id: int = 0) -> PackedByteArray:
	if ids.size() > MAX_ORDER_IDS or target_id < 0 or target_id > 0xFFFF:
		return PackedByteArray()
	var b := _buf(ORDER)
	b.put_u32(seq)
	b.put_float(target.x)
	b.put_float(target.y)
	b.put_u16(target_id)
	b.put_u8(ids.size())
	for id in ids:
		if int(id) < 0 or int(id) > 0xFFFF:
			return PackedByteArray()
		b.put_u16(int(id))
	return b.data_array


static func train(seq: int, kind: int) -> PackedByteArray:
	var b := _buf(TRAIN)
	b.put_u32(seq)
	b.put_u8(kind & 0xFF)
	return b.data_array


static func result(seq: int, ok: bool, tick: int) -> PackedByteArray:
	var b := _buf(RESULT)
	b.put_u32(seq)
	b.put_u8(1 if ok else 0)
	b.put_u32(tick)
	return b.data_array


## `units` are SimWorld.snapshot() entries; `states` maps player 1 and 2 to
## SimWorld.player_state() (a missing player encodes as zeros).
static func snapshot(tick: int, players: int, units: Array, winner: int = 0,
		started: bool = true, states: Dictionary = {}) -> PackedByteArray:
	var b := _buf(SNAPSHOT)
	var count := mini(units.size(), MAX_SNAPSHOT_UNITS)
	b.put_u32(tick)
	b.put_u8(players)
	b.put_u8(winner)
	b.put_u8(1 if started else 0)
	for p in [1, 2]:
		var st: Dictionary = states.get(p, {})
		var queue: Array = st.get("queue", [])
		b.put_u16(clampi(st.get("honeydew", 0), 0, 0xFFFF))
		b.put_u8(clampi(st.get("units", 0), 0, 255))
		b.put_u8(clampi(queue.size(), 0, 255))
		b.put_u8(0 if queue.is_empty() else int(queue[0]) & 0xFF)
		b.put_u8(clampi(roundi(float(st.get("progress", 0.0)) * 255.0), 0, 255))
	b.put_u16(count)
	for i in count:
		var u: Dictionary = units[i]
		var p: Vector2 = u.pos
		b.put_u16(u.id)
		b.put_u8(u.get("kind", 1))
		b.put_u8(u.owner)
		b.put_16(clampi(roundi(p.x * POS_SCALE), -32768, 32767))
		b.put_16(clampi(roundi(p.y * POS_SCALE), -32768, 32767))
		b.put_u8(roundi(fposmod(float(u.facing), TAU) / TAU * 256.0) & 0xFF)
		b.put_u8(clampi(roundi(float(u.get("hp", 1.0)) * 255.0), 0, 255))
		b.put_u8(int(u.get("flags", 0)) & 0xFF)
	return b.data_array


static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var type := b.get_u8()
	var n := data.size()
	match type:
		HELLO:
			if n != 7:
				return {}
			var magic := b.get_u32()
			var version := b.get_u16()
			if magic != MAGIC:
				return {}
			return {"type": HELLO, "version": version}
		WELCOME:
			if n != 15:
				return {}
			var player := b.get_u8()
			var tick := b.get_u32()
			var rate := b.get_u8()
			var half := Vector2(b.get_float(), b.get_float())
			if rate == 0 or not half.is_finite():
				return {}
			return {"type": WELCOME, "player": player, "tick": tick, "tick_rate": rate, "map_half": half}
		REJECT:
			if n != 2:
				return {}
			return {"type": REJECT, "reason": b.get_u8()}
		ORDER:
			if n < 16:
				return {}
			var seq := b.get_u32()
			var target := Vector2(b.get_float(), b.get_float())
			var target_id := b.get_u16()
			var count := b.get_u8()
			if n != 16 + count * 2:
				return {}
			var ids: Array = []
			for i in count:
				ids.append(b.get_u16())
			return {"type": ORDER, "seq": seq, "target": target, "target_id": target_id, "ids": ids}
		TRAIN:
			if n != 6:
				return {}
			return {"type": TRAIN, "seq": b.get_u32(), "kind": b.get_u8()}
		RESULT:
			if n != 10:
				return {}
			var seq := b.get_u32()
			var ok := b.get_u8() != 0
			return {"type": RESULT, "seq": seq, "ok": ok, "tick": b.get_u32()}
		SNAPSHOT:
			if n < SNAPSHOT_HEADER:
				return {}
			var tick := b.get_u32()
			var players := b.get_u8()
			var winner := b.get_u8()
			var started := b.get_u8() != 0
			var states := {}
			for p in [1, 2]:
				var honey := b.get_u16()
				var ants := b.get_u8()
				var qlen := b.get_u8()
				var front := b.get_u8()
				var progress := b.get_u8() / 255.0
				states[p] = {"honeydew": honey, "units": ants, "queue_len": qlen,
					"front": front, "progress": progress}
			var count := b.get_u16()
			if count > MAX_SNAPSHOT_UNITS or n != SNAPSHOT_HEADER + count * ENTITY_BYTES:
				return {}
			var units: Array[Dictionary] = []
			for i in count:
				var id := b.get_u16()
				var kind := b.get_u8()
				var owner := b.get_u8()
				var pos := Vector2(b.get_16(), b.get_16()) / POS_SCALE
				var facing := b.get_u8() / 256.0 * TAU
				var hp := b.get_u8() / 255.0
				var flags := b.get_u8()
				units.append({"id": id, "kind": kind, "owner": owner, "pos": pos, "facing": facing,
					"hp": hp, "flags": flags})
			return {"type": SNAPSHOT, "tick": tick, "players": players, "winner": winner,
				"started": started, "states": states, "units": units}
	return {}


static func _buf(type: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.put_u8(type)
	return b
