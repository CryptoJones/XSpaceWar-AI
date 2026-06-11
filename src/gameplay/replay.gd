class_name Replay
extends RefCounted
## Match recording: the arena recipe (seed + params + roster) plus a
## change-encoded stream of every ship's control inputs per tick. Because the
## simulation is deterministic, replaying the inputs into a freshly built
## world reproduces the match bit-for-bit — ~kilobytes per minute, not video.

const VERSION := 1
const FLAG_THRUST := 1
const FLAG_FIRE := 2
const FLAG_HYPER := 4
const FLAG_MINE := 8

var header := {}
var frames: Array = []     ## [tick, ship_id, turn: float, flags: int], changes only
var final_tick := 0

var _last := {}            ## recording state: ship_id -> [turn, flags]

## Start recording the session's CURRENT match (call right after a build).
static func begin(session: GameSession) -> Replay:
	var r := Replay.new()
	var roster := []
	for s in session.world.ships:
		roster.append([s.id, s.team, s.hull_seed, String(session.ship_names.get(s.id, ""))])
	r.header = {
		"v": VERSION,
		"seed": session.world.config.seed,
		"rs": session.world.config.respawn_time,
		"prm": session.arena_params,
		"mode": session.mode,
		"ros": roster,
		"limit": session.score_limit,
	}
	return r

## Capture all ships' pending inputs for the step about to run. Called by
## GameSession.update() immediately before world.step().
func capture(world: SimWorld) -> void:
	for s in world.ships:
		var flags := 0
		if s.in_thrust:
			flags |= FLAG_THRUST
		if s.in_fire:
			flags |= FLAG_FIRE
		if s.in_hyper:
			flags |= FLAG_HYPER
		if s.in_mine:
			flags |= FLAG_MINE
		var cur := [s.in_turn, flags]
		if _last.get(s.id) != cur:
			_last[s.id] = cur
			frames.append([world.tick, s.id, s.in_turn, flags])
	final_tick = world.tick

func duration_sec(fixed_dt: float) -> float:
	return float(final_tick) * fixed_dt

func to_bytes() -> PackedByteArray:
	return var_to_bytes({"h": header, "f": frames, "end": final_tick})

## Returns null on garbage or version mismatch.
static func from_bytes(bytes: PackedByteArray) -> Replay:
	var v: Variant = bytes_to_var(bytes)
	if typeof(v) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = v
	var r := Replay.new()
	r.header = d.get("h", {})
	r.frames = d.get("f", [])
	r.final_tick = int(d.get("end", 0))
	if int(r.header.get("v", -1)) != VERSION or typeof(r.header.get("ros")) != TYPE_ARRAY:
		return null
	return r
