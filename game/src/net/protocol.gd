class_name Protocol
extends RefCounted
## Wire format shared by GameServer and NetClient. Pure functions, no nodes.
##
## Every packet starts with a u8 message type. Little-endian throughout.
## decode() returns {} for anything malformed (short, oversized, unknown type,
## wrong magic), so callers only ever see well-formed messages.
##
##   HELLO     c->s  magic u32, version u16, token u64 (random per install)
##   WELCOME   s->c  player u8, tick u32, tick_rate u8, map_half x f32, y f32
##   REJECT    s->c  reason u8
##   MOVE      c->s  seq u32, target x f32, y f32, count u8, ids u16 * count
##   RESULT    s->c  seq u32, ok u8, tick u32
##   SNAPSHOT  s->c  tick u32, players u8 (bitmask of connected slots), count u16,
##                   then per unit: id u16, owner u8, x i16, y i16, facing u8
##   NOTICE    s->c  code u8 (e.g. the hosting phone went to the background)
##
## Snapshot positions are fixed point (1/POS_SCALE m), facing is 1/256 turn.
## 8 bytes per unit: 2 x 20 ants is ~330 bytes per tick, ~6.6 KB/s per client.

const MAGIC := 0x54534550  # "PEST"
## Bump on any wire change. Server rejects clients with a different version.
const VERSION := 2
const DEFAULT_PORT := 7777

const HELLO := 1
const WELCOME := 2
const REJECT := 3
const MOVE := 4
const RESULT := 5
const SNAPSHOT := 6
const NOTICE := 7

const REJECT_VERSION := 1
const REJECT_FULL := 2

const NOTICE_HOST_PAUSED := 1
const NOTICE_HOST_RESUMED := 2

const POS_SCALE := 100.0
const MAX_SNAPSHOT_UNITS := 1024
const MAX_MOVE_IDS := 255


static func hello(token: int, version: int = VERSION) -> PackedByteArray:
	var b := _buf(HELLO)
	b.put_u32(MAGIC)
	b.put_u16(version)
	b.put_u64(token)
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
static func move(seq: int, ids: Array, target: Vector2) -> PackedByteArray:
	if ids.size() > MAX_MOVE_IDS:
		return PackedByteArray()
	var b := _buf(MOVE)
	b.put_u32(seq)
	b.put_float(target.x)
	b.put_float(target.y)
	b.put_u8(ids.size())
	for id in ids:
		if int(id) < 0 or int(id) > 0xFFFF:
			return PackedByteArray()
		b.put_u16(int(id))
	return b.data_array


static func notice(code: int) -> PackedByteArray:
	var b := _buf(NOTICE)
	b.put_u8(code)
	return b.data_array


static func result(seq: int, ok: bool, tick: int) -> PackedByteArray:
	var b := _buf(RESULT)
	b.put_u32(seq)
	b.put_u8(1 if ok else 0)
	b.put_u32(tick)
	return b.data_array


## `units` are SimWorld.snapshot() entries.
static func snapshot(tick: int, players: int, units: Array) -> PackedByteArray:
	var b := _buf(SNAPSHOT)
	var count := mini(units.size(), MAX_SNAPSHOT_UNITS)
	b.put_u32(tick)
	b.put_u8(players)
	b.put_u16(count)
	for i in count:
		var u: Dictionary = units[i]
		var p: Vector2 = u.pos
		b.put_u16(u.id)
		b.put_u8(u.owner)
		b.put_16(clampi(roundi(p.x * POS_SCALE), -32768, 32767))
		b.put_16(clampi(roundi(p.y * POS_SCALE), -32768, 32767))
		b.put_u8(roundi(fposmod(float(u.facing), TAU) / TAU * 256.0) & 0xFF)
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
			# Size is only checked after the version, so an old client still
			# gets a clean version reject instead of being ignored.
			if n < 7:
				return {}
			var magic := b.get_u32()
			var version := b.get_u16()
			if magic != MAGIC:
				return {}
			if version != VERSION:
				return {"type": HELLO, "version": version, "token": 0}
			if n != 15:
				return {}
			return {"type": HELLO, "version": version, "token": b.get_u64()}
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
		NOTICE:
			if n != 2:
				return {}
			return {"type": NOTICE, "code": b.get_u8()}
		MOVE:
			if n < 14:
				return {}
			var seq := b.get_u32()
			var target := Vector2(b.get_float(), b.get_float())
			var count := b.get_u8()
			if n != 14 + count * 2:
				return {}
			var ids: Array = []
			for i in count:
				ids.append(b.get_u16())
			return {"type": MOVE, "seq": seq, "target": target, "ids": ids}
		RESULT:
			if n != 10:
				return {}
			var seq := b.get_u32()
			var ok := b.get_u8() != 0
			return {"type": RESULT, "seq": seq, "ok": ok, "tick": b.get_u32()}
		SNAPSHOT:
			if n < 8:
				return {}
			var tick := b.get_u32()
			var players := b.get_u8()
			var count := b.get_u16()
			if count > MAX_SNAPSHOT_UNITS or n != 8 + count * 8:
				return {}
			var units: Array[Dictionary] = []
			for i in count:
				var id := b.get_u16()
				var owner := b.get_u8()
				var pos := Vector2(b.get_16(), b.get_16()) / POS_SCALE
				var facing := b.get_u8() / 256.0 * TAU
				units.append({"id": id, "owner": owner, "pos": pos, "facing": facing})
			return {"type": SNAPSHOT, "tick": tick, "players": players, "units": units}
	return {}


static func _buf(type: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.put_u8(type)
	return b
