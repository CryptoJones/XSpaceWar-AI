class_name AudioDirector
extends Node2D
## Positional game audio, all procedurally synthesized at startup by
## SoundForge. One-shots (fire/explosion/hyperspace) play from a small pool of
## AudioStreamPlayer2Ds at the event position; thrust is a per-ship looping
## rumble held alive while thrust events keep arriving.

const POOL_SIZE := 16
const THRUST_HOLD := 0.12          ## seconds a thrust event keeps the loop alive

var _fire_s: AudioStreamWAV
var _boom_s: AudioStreamWAV
var _hyper_s: AudioStreamWAV
var _thrust_s: AudioStreamWAV

var _pool: Array[AudioStreamPlayer2D] = []
var _pool_next := 0
var _thrusters := {}               ## ship_id -> {"p": player, "hold": float}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_fire_s = SoundForge.fire()
	_boom_s = SoundForge.explosion()
	_hyper_s = SoundForge.hyperspace()
	_thrust_s = SoundForge.thrust_loop()
	_rng.randomize()
	for _i in range(POOL_SIZE):
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 2600.0
		p.attenuation = 1.2
		add_child(p)
		_pool.append(p)

## Feed every sim event through; non-audio events are ignored.
func play_event(ev: Dictionary) -> void:
	var pos: Vector2 = ev.get("pos", Vector2.ZERO)
	match String(ev.get("type", "")):
		"fire":
			_play_at(_fire_s, pos, -10.0, _rng.randf_range(0.92, 1.12))
		"explosion":
			_play_at(_boom_s, pos, -1.0, _rng.randf_range(0.85, 1.10))
		"hyperspace":
			_play_at(_hyper_s, pos, -5.0, _rng.randf_range(0.95, 1.05))
		"thrust":
			_hold_thrust(int(ev.get("ship", -1)), pos)

## Call once per physics step after the frame's events are fed in: ages the
## thrust holds and keeps loop players glued to their ships.
func update(dt: float, world: SimWorld) -> void:
	for sid in _thrusters:
		var e: Dictionary = _thrusters[sid]
		e["hold"] = float(e["hold"]) - dt
		var p: AudioStreamPlayer2D = e["p"]
		if float(e["hold"]) <= 0.0:
			if p.playing:
				p.stop()
		else:
			var s := world.ship_by_id(int(sid))
			if s != null:
				p.position = s.pos + s.render_pos_offset

## Stop everything and drop per-ship players (arena regenerated / left match).
func reset() -> void:
	for sid in _thrusters:
		(_thrusters[sid]["p"] as AudioStreamPlayer2D).queue_free()
	_thrusters.clear()
	for p in _pool:
		if p.playing:
			p.stop()

func _play_at(stream: AudioStreamWAV, pos: Vector2, db: float, pitch: float) -> void:
	var p := _pool[_pool_next]
	for cand in _pool:
		if not cand.playing:
			p = cand
			break
	_pool_next = (_pool_next + 1) % POOL_SIZE
	p.stream = stream
	p.position = pos
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()

func _hold_thrust(sid: int, pos: Vector2) -> void:
	if sid < 0:
		return
	if not _thrusters.has(sid):
		var p := AudioStreamPlayer2D.new()
		p.stream = _thrust_s
		p.max_distance = 2200.0
		p.attenuation = 1.4
		p.volume_db = -14.0
		add_child(p)
		_thrusters[sid] = {"p": p, "hold": 0.0}
	var e: Dictionary = _thrusters[sid]
	e["hold"] = THRUST_HOLD
	var p2: AudioStreamPlayer2D = e["p"]
	p2.position = pos
	if not p2.playing:
		p2.play()
