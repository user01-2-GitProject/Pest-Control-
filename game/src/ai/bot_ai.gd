class_name BotAI
extends RefCounted
## Local bot opponent for offline play. Not networked and not smart: it reads
## the sim directly and issues commands through the same queue_* calls a
## player's input uses, so it obeys every rule a player does.
##
## Plan: keep idle workers milking, train workers up to WORKER_TARGET then
## soldiers, and send idle soldiers at the enemy colony in waves of WAVE_SIZE.

const THINK_TICKS := 10
const WORKER_TARGET := 8
const WAVE_SIZE := 6

var player: int
var _next_think := 0


func _init(player_id: int) -> void:
	player = player_id


func think(sim: SimWorld) -> void:
	if sim.tick < _next_think or sim.winner != 0:
		return
	_next_think = sim.tick + THINK_TICKS
	var col: SimWorld.Colony = sim.colonies.get(player)
	if col == null:
		return

	var workers := 0
	var idle_soldiers: Array = []
	for u in sim.units:
		if u.owner != player:
			continue
		if u.kind == SimWorld.WORKER:
			workers += 1
			if u.task == SimWorld.Task.NONE and not u.moving:
				var a := sim.nearest_aphid(u.pos)
				if a:
					sim.queue_order(player, [u.id], a.pos, a.id)
		elif u.task == SimWorld.Task.NONE and u.engage == 0 and not u.moving:
			idle_soldiers.append(u.id)

	if col.queue.size() < 2:
		var kind := SimWorld.WORKER if workers + col.queue.count(SimWorld.WORKER) < WORKER_TARGET \
			else SimWorld.SOLDIER
		if sim.honeydew.get(player, 0) >= SimWorld.STATS[kind].cost:
			sim.queue_train(player, kind)

	if idle_soldiers.size() >= WAVE_SIZE:
		for p in sim.colonies:
			if p != player:
				var enemy: SimWorld.Colony = sim.colonies[p]
				sim.queue_order(player, idle_soldiers, enemy.pos, enemy.id)
