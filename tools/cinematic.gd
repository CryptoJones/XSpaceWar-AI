extends Node
## Live cinematic-beat workshop for the Steam trailer (issue #1).
##
## HOW TO USE (in the Godot editor on a real GPU):
##   1. Open tools/cinematic.tscn and press F6 (Run Current Scene).
##   2. Pick a beat with `preview_beat` in the Inspector — it loops every
##      `beat_seconds` so you can watch it repeat.
##   3. Tweak that beat's exported values (offsets / velocities / zoom),
##      press F6 again. Instant feedback, full HDR glow.
##   4. When a beat looks right, tell me the values — I bake them into
##      tools/render_trailer.gd and capture the final cut with Movie Maker.
##
## Combat ships are kept invincible and torpedoes are aimed to MISS, so a beat
## never empties out mid-loop.

@export_enum("All", "Chase", "Slingshot", "Gang-up", "Joust") var preview_beat: int = 1
@export var beat_seconds := 4.0

@export_group("Look")
@export var nebula := 1.0
@export var stars := 0.08
@export var nebula_seed := 2.0
@export var tint_a := Color(0.32, 0.58, 1.7)
@export var tint_b := Color(1.6, 0.42, 1.05)
@export var star_scale := 1.2
@export var combat_distance := 6000.0   ## how far combat beats sit from the star

@export_group("Chase")
@export var chase_zoom := 1.55
@export var chase_target_off := Vector2(-300, -700)
@export var chase_target_vel := Vector2(90, 640)
@export var chase_chaser_off := Vector2(-380, -1000)
@export var chase_chaser_vel := Vector2(80, 560)

@export_group("Slingshot")
@export var sling_zoom := 0.6
@export var sling_radius := 1400.0       ## start distance from the star
@export var sling_speed_mult := 1.0      ## 1.0 ≈ circular; >1 swings wider
@export var sling_angle_deg := 165.0     ## where on the ring the ship starts

@export_group("Gang-up")
@export var gang_zoom := 1.6
@export var gang_ring := 560.0
@export var gang_converge := 110.0

@export_group("Joust")
@export var joust_zoom := 1.45
@export var joust_off := Vector2(820, 360)
@export var joust_vel := Vector2(700, -300)

var _main
var _s
var _view
var _c := Vector2.ZERO
var _base := Vector2.ZERO
var _t := 0.0
var _beat := 0
var _tid := 7000

func _ready() -> void:
	process_priority = 500   # run after WorldView so our camera lock wins
	_main = load("res://src/ui/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._end_credits(); _main._dismiss_splash(); _main.set_menu_visible(false)
	_main.hud.visible = false
	_s = _main.session
	_view = _main.view
	_s.score_limit = 0; _s.time_limit = 0.0; _s.lives = 0; _s.respawn_seconds = 999.0
	_s.hazard = 0.0; _s.star_scale = star_scale; _s.planet_count = 0; _s.map_size = 26000.0
	_view.set_background_prefs(nebula, stars, true)
	_view._bg_mat.set_shader_parameter("seed", nebula_seed)
	_view._bg_mat.set_shader_parameter("tint_a", Vector3(tint_a.r, tint_a.g, tint_a.b))
	_view._bg_mat.set_shader_parameter("tint_b", Vector3(tint_b.r, tint_b.g, tint_b.b))
	_s.start_skirmish(5, GameSession.Mode.FFA, BotController.Difficulty.ACE)
	_s.human_ship_id = -1
	_c = _s.world.primary_body().pos
	_base = _c + Vector2(combat_distance, 0)
	_beat = (preview_beat - 1) if preview_beat > 0 else 0
	_begin(_beat)

func _process(dt: float) -> void:
	if _s == null:
		return
	_t += dt
	if _t >= beat_seconds:
		_t = 0.0
		_beat = (_beat + 1) % 4 if preview_beat == 0 else (preview_beat - 1)
		_begin(_beat)
	_drive(_beat, _t)

func _keep(idxs: Array) -> void:
	for i in idxs:
		_s.world.ships[i].alive = true
		_s.world.ships[i].spawn_grace = 0.0

func _torp(shooter, tgt: Vector2) -> void:
	var cfg = _s.world.config
	var t = SimTorpedo.new()
	t.id = _tid; _tid += 1; t.owner_id = shooter.id; t.team = shooter.team
	var dir = (tgt - shooter.pos).normalized()
	t.pos = shooter.pos + dir * (cfg.ship_radius * 2.0)
	t.vel = shooter.vel + dir * 1050.0
	t.age = 0.0; t.life = cfg.torpedo_life; t.radius = cfg.torpedo_radius
	_s.world.torpedoes.append(t)

func _park(idxs: Array) -> void:
	for i in range(_s.world.ships.size()):
		var sh = _s.world.ships[i]
		sh.alive = i in idxs
		if sh.alive:
			sh.spawn_grace = 0.0
			sh.fuel = _s.world.config.max_fuel

func _cam(p: Vector2, z: float) -> void:
	_view._cam_pos = p; _view._cam_pos_prev = p
	_view._cam_zoom = z; _view._cam_zoom_prev = z
	_view._camera.position = p; _view._camera.zoom = Vector2(z, z)
	_view._bg_mat.set_shader_parameter("cam", _c)

func _begin(beat: int) -> void:
	var sh = _s.world.ships
	_s.world.torpedoes.clear()
	match beat:
		0:  # chase
			_park([0, 1])
			sh[0].pos = _base + chase_target_off; sh[0].vel = chase_target_vel
			sh[1].pos = _base + chase_chaser_off; sh[1].vel = chase_chaser_vel
		1:  # slingshot
			_park([0])
			var p = _c + Vector2(sling_radius, 0).rotated(deg_to_rad(sling_angle_deg))
			sh[0].pos = p
			var r = p.distance_to(_c)
			var g = _s.world.gravity_accel(p).length()
			sh[0].vel = (p - _c).orthogonal().normalized() * sqrt(g * r) * sling_speed_mult
			sh[0].angle = sh[0].vel.angle()
		2:  # gang-up
			_park([0, 1, 2, 3, 4])
			sh[0].pos = _base; sh[0].vel = Vector2.ZERO
			for k in range(4):
				var ang = deg_to_rad(45 + 90 * k)
				sh[k + 1].pos = _base + Vector2(gang_ring, 0).rotated(ang)
				sh[k + 1].vel = (_base - sh[k + 1].pos).normalized() * gang_converge
		3:  # joust
			_park([0, 1])
			sh[0].pos = _base + Vector2(-joust_off.x, joust_off.y); sh[0].vel = joust_vel
			sh[1].pos = _base + Vector2(joust_off.x, -joust_off.y); sh[1].vel = -joust_vel

func _drive(beat: int, t: float) -> void:
	var sh = _s.world.ships
	var sframe := int(t * 60.0)
	match beat:
		0:
			_keep([0, 1])
			sh[0].angle = sh[0].vel.angle()
			sh[1].angle = (sh[0].pos - sh[1].pos).angle(); sh[1].in_thrust = true
			_cam((sh[0].pos + sh[1].pos) * 0.5, chase_zoom)
			if sframe % 22 == 0:
				_torp(sh[1], sh[0].pos - sh[0].vel.normalized() * 360.0)
		1:
			if sframe < 16: sh[0].in_thrust = true
			sh[0].angle = sh[0].vel.angle()
			_cam(_c, sling_zoom)
		2:
			_keep([0, 1, 2, 3, 4])
			for k in range(4):
				sh[k + 1].angle = (sh[0].pos - sh[k + 1].pos).angle(); sh[k + 1].in_thrust = true
			_cam(sh[0].pos, gang_zoom)
			if sframe >= 30 and sframe % 18 == 0:
				for k in range(4):
					var off = (sh[0].pos - sh[k + 1].pos).orthogonal().normalized() * (220.0 if k % 2 == 0 else -220.0)
					_torp(sh[k + 1], sh[0].pos + off)
		3:
			_keep([0, 1])
			sh[0].angle = (sh[1].pos - sh[0].pos).angle(); sh[0].in_thrust = true
			sh[1].angle = (sh[0].pos - sh[1].pos).angle(); sh[1].in_thrust = true
			_cam((sh[0].pos + sh[1].pos) * 0.5, joust_zoom)
			if sframe % 18 == 0:
				var d = (sh[1].pos - sh[0].pos).orthogonal().normalized() * 170.0
				_torp(sh[0], sh[1].pos + d)
				_torp(sh[1], sh[0].pos - d)
	if _main.hud.visible:
		_main.hud.visible = false
