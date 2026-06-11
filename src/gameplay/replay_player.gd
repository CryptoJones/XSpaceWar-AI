class_name ReplayPlayer
extends RefCounted
## Plays a Replay back bit-exact. The world is rebuilt the SAME way the
## original match built it — ships created through world.add_ship() in roster
## order so the gameplay RNG consumes identically (spawns, respawns, and
## hyperspace rolls all depend on it). Inputs are then re-applied per tick.
##
## Owns a shell GameSession so WorldView/Hud render it unchanged; drive from
## the renderer via update(dt). No bots run — their decisions are in the tape.

var session := GameSession.new()
var replay: Replay
var finished := false
var paused := false
var speed := 1.0

var _inputs := {}          ## ship_id -> [turn, flags], latest known
var _cursor := 0
var _accum := 0.0

func load_replay(r: Replay) -> bool:
	replay = r
	var h := r.header
	var cfg := SimConfig.from_seed(int(h.get("seed", 0)))
	var world := SimWorld.new(cfg)
	ArenaGen.populate(world, h.get("prm", {}))
	for entry in h.get("ros", []):
		var s := world.add_ship(int(entry[1]))  # consumes RNG exactly like the original
		if s.id != int(entry[0]):
			return false  # roster out of sync with the build path
		var pname := String(entry[3])
		if pname != "":
			session.ship_names[s.id] = pname
	session.world = world
	session.mode = int(h.get("mode", GameSession.Mode.FFA))
	session.movie_mode = false
	session.human_ship_id = -1     # nobody is "you" — the action camera directs
	session.generation = 1
	return true

func update(dt: float) -> void:
	if finished or session.world == null:
		return
	if paused:
		session.world.events.clear()
		return
	var world := session.world
	_accum += dt * speed
	while _accum >= world.config.fixed_dt - 1e-9:
		_accum -= world.config.fixed_dt
		_advance_frames(world)
		for sid in _inputs:
			var s := world.ship_by_id(int(sid))
			if s == null or not s.alive:
				continue
			var rec: Array = _inputs[sid]
			s.in_turn = float(rec[0])
			var flags := int(rec[1])
			s.in_thrust = (flags & Replay.FLAG_THRUST) != 0
			s.in_fire = (flags & Replay.FLAG_FIRE) != 0
			s.in_hyper = (flags & Replay.FLAG_HYPER) != 0
			s.in_mine = (flags & Replay.FLAG_MINE) != 0
		world.step()
		if world.tick > replay.final_tick:
			finished = true
			return

func _advance_frames(world: SimWorld) -> void:
	while _cursor < replay.frames.size() and int(replay.frames[_cursor][0]) <= world.tick:
		var f: Array = replay.frames[_cursor]
		if int(f[0]) == world.tick:
			_inputs[int(f[1])] = [float(f[2]), int(f[3])]
		_cursor += 1
