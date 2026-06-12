class_name WorldView
extends Node2D
## The main procedural renderer. Draws a GameSession's SimWorld in immediate
## mode (_draw) — star, planets, moons, asteroids, ships, torpedoes — over a
## shader nebula backdrop, with HDR glow and one-shot particle explosions.
##
## Owns the Camera2D: Movie Mode auto-frames the centroid of alive ships;
## skirmish follows the human ship. Also reads human input (when enabled) and
## drives the simulation from _physics_process.

const TEAM_COLORS: Array[Color] = [
	Color(0.35, 0.90, 1.00),   # cyan
	Color(1.00, 0.45, 0.35),   # red-orange
	Color(0.55, 1.00, 0.50),   # green
	Color(1.00, 0.85, 0.40),   # gold
]

## Sixteen hand-picked distinct colors for FFA rosters — one per ship by
## roster position, identical on every peer. (Team mode keeps TEAM_COLORS:
## there, matching colors ARE the information.)
const PALETTE16: Array[Color] = [
	Color(0.30, 0.90, 1.00),   # cyan
	Color(1.00, 0.55, 0.20),   # orange
	Color(0.40, 1.00, 0.45),   # green
	Color(1.00, 0.40, 0.90),   # magenta
	Color(1.00, 0.95, 0.30),   # yellow
	Color(0.35, 0.50, 1.00),   # blue
	Color(1.00, 0.30, 0.30),   # red
	Color(0.20, 0.90, 0.75),   # teal
	Color(0.65, 0.40, 1.00),   # purple
	Color(0.75, 1.00, 0.30),   # lime
	Color(1.00, 0.60, 0.65),   # pink
	Color(0.55, 0.80, 1.00),   # sky
	Color(1.00, 0.75, 0.45),   # amber
	Color(0.60, 1.00, 0.80),   # mint
	Color(0.80, 0.70, 1.00),   # lavender
	Color(0.92, 0.92, 0.95),   # silver
]

## Local hull space: +X = facing, roughly ±19 units, scaled by radius/12.

var session: GameSession
var input_enabled := false

## Freeze the local sim (solo skirmish behind an open menu). Networked and
## replay sessions never set this — their drivers own time.
var sim_paused := false

## Rebindable primary keys (physical keycodes; arrows/Enter stay as fixed
## alternates). main.gd persists and edits these via the KEYS panel.
var key_binds := {
	"turn_left": KEY_A,
	"turn_right": KEY_D,
	"thrust": KEY_W,
	"fire": KEY_SPACE,
	"mine": KEY_S,
	"hyper": KEY_SHIFT,
	"toggle_map": KEY_M,   # UI action (minimap), lives here so binds have one home
}

## When valid, replaces the built-in input+update drive each physics step —
## set by main.gd to a net host/client pump. Signature: f(dt: float).
var external_driver: Callable = Callable()

var _camera: Camera2D
var _bg_mat: ShaderMaterial
var _audio: AudioDirector
var _thrusting := {}                ## ship_id -> true (fired thrust this step)
var _asteroid_polys := {}           ## body_id -> PackedVector2Array
var _hull_cache := {}               ## ship_id -> {"poly": ..., "tail": float}
var _seen_generation := -1
var _cam_zoom := 0.6
var _ship_vis_scale := 1.6          ## visual-only hull scale (grows when zoomed out)
var _follow_id := -1                ## camera wrap-follow tracking
var _follow_pos := Vector2.ZERO
var _focus_a := -1                  ## movie-mode action camera: current duel
var _focus_b := -1
var _focus_timer := 0.0
var _killcam_id := -1               ## while dead: ride along with your killer

# Render interpolation: the sim steps at a fixed 60Hz; drawing raw sim
# positions makes motion visibly hop on >60Hz displays. We keep last tick's
# state and draw blended by the physics interpolation fraction.
var _prev_pos := {}                 ## "s3"/"t9"/"m2"/"p7" -> last-tick position
var _prev_angle := {}               ## ship id -> last-tick angle
var _cam_pos := Vector2.ZERO        ## camera current (per-tick) state
var _cam_pos_prev := Vector2.ZERO
var _cam_zoom_prev := 0.6
var _match_over_seen := false
var _shake := 0.0                   ## camera shake energy (decays)
var _popups: Array[Dictionary] = [] ## floating kill texts: pos/vel/text/ttl/color

const DUEL_SHOT_TIME := 7.0         ## seconds before the movie camera recuts

func _ready() -> void:
	# Parallax nebula backdrop: screen-fixed full-rect shader, below the world.
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = load("res://src/render/shaders/nebula.gdshader")
	rect.material = _bg_mat
	bg_layer.add_child(rect)
	add_child(bg_layer)

	# HDR glow so colors > 1.0 bloom (needs rendering/viewport/hdr_2d=true).
	# Only on Forward+: on the compatibility/mobile renderers (e.g. launched
	# with --rendering-method gl_compatibility on boxes without Vulkan) the
	# game runs fine without bloom, so skip the environment entirely.
	# Weak iGPUs (bottom-tier Intel UHD, software rasterizers) stall under
	# HDR glow — the driver parks the game in GPU fence waits and the window
	# freezes — so skip it there too.
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var weak_gpu := adapter.contains("uhd graphics") or adapter.contains("llvmpipe") \
		or adapter.contains("gt1")
	if weak_gpu:
		push_warning("weak GPU detected (%s) — HDR glow disabled; consider --rendering-method gl_compatibility"
			% RenderingServer.get_video_adapter_name())
	if RenderingServer.get_current_rendering_method() == "forward_plus" and not weak_gpu:
		var env := Environment.new()
		env.background_mode = Environment.BG_CANVAS
		env.glow_enabled = true
		env.glow_intensity = 0.9
		env.glow_bloom = 0.05
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)

	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()

	_audio = AudioDirector.new()
	add_child(_audio)

## Render-rate: redraw every display frame at interpolated positions, and
## move the actual camera between its per-tick states the same way.
func _process(_dt: float) -> void:
	if session == null or session.world == null:
		return
	var f := Engine.get_physics_interpolation_fraction()
	_camera.position = _cam_pos_prev.lerp(_cam_pos, f)
	var z := lerpf(_cam_zoom_prev, _cam_zoom, f)
	_camera.zoom = Vector2(z, z)
	if _shake > 0.2:
		var tt := session.world.time * 70.0
		_camera.offset = Vector2(sin(tt * 1.13), cos(tt * 0.97)) * _shake
	else:
		_camera.offset = Vector2.ZERO
	queue_redraw()

## Interpolated draw position for an entity ("s3"/"t9"/"m2"/"p7"). Teleports
## (wrap, hyperspace, respawn) snap instead of smearing across the map.
func _ipos(key: String, curr: Vector2) -> Vector2:
	var prev: Variant = _prev_pos.get(key)
	if prev == null:
		return curr
	var pv := prev as Vector2
	if pv.distance_to(curr) > session.world.config.arena_size * 0.25:
		return curr
	return pv.lerp(curr, Engine.get_physics_interpolation_fraction())

func _iangle(id: int, curr: float) -> float:
	var prev: Variant = _prev_angle.get(id)
	if prev == null:
		return curr
	return lerp_angle(float(prev), curr, Engine.get_physics_interpolation_fraction())

func _capture_prev_state() -> void:
	_prev_pos.clear()
	_prev_angle.clear()
	var w := session.world
	if w == null:
		return
	for s in w.ships:
		_prev_pos["s%d" % s.id] = s.pos
		_prev_angle[s.id] = s.angle
	for t in w.torpedoes:
		_prev_pos["t%d" % t.id] = t.pos
	for m in w.mines:
		_prev_pos["m%d" % m.id] = m.pos
	for p in w.pickups:
		_prev_pos["p%d" % p.id] = p.pos

func _physics_process(dt: float) -> void:
	if session == null:
		return
	_capture_prev_state()
	_thrusting.clear()
	if external_driver.is_valid():
		external_driver.call(dt)
	elif session.world != null:
		if sim_paused:
			session.world.events.clear()  # don't re-fire last step's fx/audio
		else:
			_read_human_input()
			session.update(dt)
	if session.world == null:
		return
	if session.generation != _seen_generation:
		_on_new_generation()

	if session.match_over and not _match_over_seen:
		_match_over_seen = true
		_audio.play_fanfare()
	elif not session.match_over:
		_match_over_seen = false

	for ev in session.world.events:
		_audio.play_event(ev)
		match ev.get("type", ""):
			"thrust":
				_thrusting[ev["ship"]] = true
			"explosion":
				_spawn_burst(ev["pos"], Color(2.4, 1.5, 0.5), 56, 420.0)
				_add_shake(ev["pos"], 1.0)
			"mine_explode":
				_spawn_burst(ev["pos"], Color(2.6, 1.1, 0.25), 72, 520.0)
				_add_shake(ev["pos"], 1.4)
			"hyperspace":
				_spawn_burst(ev["pos"], Color(0.7, 1.2, 2.4), 28, 240.0)
			"wrap":
				_spawn_burst(ev["pos"], Color(0.4, 1.6, 2.0), 20, 360.0)
			"rock_break":
				_spawn_burst(ev["pos"], Color(0.9, 0.85, 0.75), 30, 260.0)
			"pickup":
				if int(ev["ship"]) == session.human_ship_id:
					_add_text_popup(ev["pos"],
						"+" + ["FUEL", "AMMO", "MINES"][int(ev["kind"])],
						Color(0.5, 1.6, 0.7))
			"kill":
				_add_kill_popup(int(ev["killer"]), int(ev["victim"]))
				if int(ev["victim"]) == session.human_ship_id:
					_killcam_id = int(ev["killer"])
	_audio.update(dt, session.world)
	_step_popups(dt)

	_update_camera(dt)
	if _bg_mat != null:
		_bg_mat.set_shader_parameter("cam", _camera.position)
	queue_redraw()

func _on_new_generation() -> void:
	_seen_generation = session.generation
	_asteroid_polys.clear()
	_hull_cache.clear()
	_thrusting.clear()
	_follow_id = -1
	_focus_a = -1
	_focus_b = -1
	_focus_timer = 0.0
	_killcam_id = -1
	if _audio != null:
		_audio.reset()
	# Re-seed the starfield per-arena so every match's sky is distinct, and
	# pick per-arena nebula tints (only visible if the player enables nebula).
	var s := session.world.config.seed
	_bg_mat.set_shader_parameter("seed", float(absi(s) % 100000) * 0.001)
	var h1 := float(absi(s) % 997) / 997.0
	var h2 := wrapf(h1 + 0.35, 0.0, 1.0)
	_bg_mat.set_shader_parameter("tint_a", Color.from_hsv(h1, 0.65, 0.35))
	_bg_mat.set_shader_parameter("tint_b", Color.from_hsv(h2, 0.55, 0.30))

func set_music_enabled(on: bool) -> void:
	if _audio != null:
		_audio.set_music_enabled(on)

## One-line diagnostic snapshot for the F3 overlay.
func debug_summary() -> String:
	return "cam (%.0f, %.0f)  zoom %.2f  shake %.1f  vis x%.1f" \
		% [_camera.position.x, _camera.position.y, _cam_zoom, _shake, _ship_vis_scale]

## Player display preferences (Settings menu): nebula 0..1, stars 0..1.5,
## far star layer on/off. Defaults match the shader's (black + near stars).
func set_background_prefs(nebula: float, stars: float, far: bool) -> void:
	_bg_mat.set_shader_parameter("nebula_intensity", clampf(nebula, 0.0, 1.0))
	_bg_mat.set_shader_parameter("star_brightness", clampf(stars, 0.0, 1.5))
	_bg_mat.set_shader_parameter("far_stars", far)

# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

## Read the local keyboard + first gamepad into a NetProtocol input payload
## ({u, t, f, h}). Used directly for solo play and forwarded for net play.
## Pad mapping: left stick = turn (analog), A or right trigger = thrust,
## X or RB = fire, Y or LB = hyperspace.
func gather_local_input() -> Dictionary:
	var turn := 0.0
	if _bind_down("turn_left") or Input.is_physical_key_pressed(KEY_LEFT):
		turn -= 1.0
	if _bind_down("turn_right") or Input.is_physical_key_pressed(KEY_RIGHT):
		turn += 1.0
	var thrust := _bind_down("thrust") or Input.is_physical_key_pressed(KEY_UP)
	var fire := _bind_down("fire")
	var hyper := _bind_down("hyper") or Input.is_physical_key_pressed(KEY_ENTER)
	var mine := _bind_down("mine") or Input.is_physical_key_pressed(KEY_DOWN)

	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var pad: int = pads[0]
		var ax := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		if absf(ax) > 0.25:
			turn = clampf(turn + ax, -1.0, 1.0)
		thrust = thrust or Input.is_joy_button_pressed(pad, JOY_BUTTON_A) \
			or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > 0.4
		fire = fire or Input.is_joy_button_pressed(pad, JOY_BUTTON_X) \
			or Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER)
		hyper = hyper or Input.is_joy_button_pressed(pad, JOY_BUTTON_Y) \
			or Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER)
		mine = mine or Input.is_joy_button_pressed(pad, JOY_BUTTON_B) \
			or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) > 0.4

	return {"u": turn, "t": thrust, "f": fire, "h": hyper, "m": mine}

func _bind_down(action: String) -> bool:
	return Input.is_physical_key_pressed(int(key_binds[action]))

func _read_human_input() -> void:
	if not input_enabled:
		return
	var ship := session.human_ship()
	if ship == null or not ship.alive:
		return
	NetProtocol.apply_input(ship, gather_local_input())

# --------------------------------------------------------------------------
# Camera
# --------------------------------------------------------------------------

func _update_camera(dt: float) -> void:
	# Per-tick camera state: _cam_pos/_cam_zoom are the simulation-rate truth;
	# _process() blends prev->curr each display frame (render interpolation).
	_cam_pos_prev = _cam_pos
	_cam_zoom_prev = _cam_zoom
	var target_pos := _cam_pos
	var target_zoom := _cam_zoom
	var human := session.human_ship()
	if human != null and session.is_eliminated(human) and _killcam_id < 0:
		human = null  # eliminated: the spectator director takes over
	var killcam_active := false

	if human != null and not human.alive and _killcam_id >= 0:
		# Killcam: ride with whoever got you until you respawn.
		var killer := session.world.ship_by_id(_killcam_id)
		if killer != null and killer.alive:
			target_pos = killer.pos + killer.render_pos_offset
			target_zoom = 1.0
			killcam_active = true
	if killcam_active:
		pass
	elif human != null:
		if human.alive:
			_killcam_id = -1
		# When the followed ship wraps the toroidal edge (or hyperspaces), jump
		# the camera by the same leap instead of lerping across the whole map.
		if _follow_id == human.id:
			var jump := human.pos - _follow_pos
			var half := session.world.config.arena_size * 0.5
			if absf(jump.x) > half:
				_cam_pos.x += signf(jump.x) * session.world.config.arena_size
				_cam_pos_prev.x = _cam_pos.x
			if absf(jump.y) > half:
				_cam_pos.y += signf(jump.y) * session.world.config.arena_size
				_cam_pos_prev.y = _cam_pos.y
		_follow_id = human.id
		_follow_pos = human.pos
		target_pos = human.pos + human.render_pos_offset
		target_zoom = 1.15
		# Failsafe: whatever else happens, never let the player lose their own
		# ship — if the camera is absurdly far from it, snap instead of pan
		# (and leave a breadcrumb so the root cause can be reported).
		if _cam_pos.distance_to(target_pos) > 6000.0:
			push_warning("camera failsafe: snapped %s -> ship %s (gen %d tick %d)"
				% [_cam_pos, target_pos, session.generation, session.world.tick])
			_cam_pos = target_pos
			_cam_pos_prev = target_pos
	elif session.watch_ship_id >= 0 \
			and session.world.ship_by_id(session.watch_ship_id) != null \
			and session.world.ship_by_id(session.watch_ship_id).alive:
		# Spectator/replay follow-cam: locked onto a chosen pilot (TAB cycles).
		var watched := session.world.ship_by_id(session.watch_ship_id)
		target_pos = watched.pos + watched.render_pos_offset
		target_zoom = 1.0
	else:
		# Movie Mode action camera: frame the closest hostile pair (a duel)
		# and recut to a fresh fight every few seconds or when one dies.
		var world := session.world
		_focus_timer -= dt
		var fa := world.ship_by_id(_focus_a)
		var fb := world.ship_by_id(_focus_b)
		if _focus_timer <= 0.0 or fa == null or not fa.alive \
				or (_focus_b >= 0 and (fb == null or not fb.alive)):
			var duel := pick_duel(world)
			_focus_a = duel[0] if duel.size() > 0 else -1
			_focus_b = duel[1] if duel.size() > 1 else -1
			_focus_timer = DUEL_SHOT_TIME
			fa = world.ship_by_id(_focus_a)
			fb = world.ship_by_id(_focus_b)
		var vp := get_viewport_rect().size
		if fa != null and fb != null:
			target_pos = (fa.pos + fb.pos) * 0.5
			var span := (fa.pos - fb.pos).abs() + Vector2(750, 750)
			target_zoom = clampf(minf(vp.x / span.x, vp.y / span.y), 0.5, 1.15)
		elif fa != null:
			target_pos = fa.pos
			target_zoom = 0.9
		else:
			var primary := world.primary_body()
			target_pos = primary.pos if primary != null else Vector2.ZERO
			target_zoom = 0.5

	var k := 1.0 - exp(-2.5 * dt)
	_cam_pos = _cam_pos.lerp(target_pos, k)
	_cam_zoom = lerpf(_cam_zoom, target_zoom, k)

	# The bleed-zone rule (Aaron's): the player's ship may NEVER leave the
	# screen. The lerp above lags proportionally to speed, so on a long
	# straight burn the ship can outrun it — when the ship reaches the outer
	# buffer of the view, the map moves instead. Hard per-axis clamp keeping
	# the ship inside the inner 72% of the screen.
	if human != null and human.alive and not killcam_active:
		var half_view := get_viewport_rect().size * 0.5 / _cam_zoom
		var limit := half_view * 0.72
		var sp := human.pos + human.render_pos_offset
		_cam_pos = _cam_pos.clamp(sp - limit, sp + limit)

	# Shake energy decays at sim rate (the offset itself is applied per
	# display frame in _process).
	if _shake > 0.2:
		_shake *= exp(-6.0 * dt)
	else:
		_shake = 0.0
	# Keep ships readable when the camera pulls back: hulls draw bigger than
	# their (unchanged) physical radius, more so the further out we are.
	_ship_vis_scale = clampf(1.6 * maxf(1.0, 0.55 / _cam_zoom), 1.6, 3.2)

# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------

func _draw() -> void:
	if session == null or session.world == null:
		return
	var world := session.world
	_draw_arena_bounds(world)
	for b in world.bodies:
		match b.kind:
			SimBody.Kind.STAR:
				_draw_star(b, world.time)
			SimBody.Kind.PLANET:
				_draw_planet(b, world)
			SimBody.Kind.MOON, SimBody.Kind.SATELLITE:
				_draw_minor(b)
			SimBody.Kind.ASTEROID:
				_draw_asteroid(b, world.time)
	var wrap := world.config.wrap_edges
	var half := world.config.arena_size * 0.5
	for p in world.pickups:
		_draw_pickup(p, world.time)
	for m in world.mines:
		for off in _ghost_offsets(_ipos("m%d" % m.id, m.pos), wrap, half, 100.0):
			_draw_mine(m, world.time, off)
	for t in world.torpedoes:
		for off in _ghost_offsets(_ipos("t%d" % t.id, t.pos), wrap, half, 80.0):
			_draw_torpedo(t, off)
	for s in world.ships:
		if s.alive:
			for off in _ghost_offsets(_ipos("s%d" % s.id, s.pos) + s.render_pos_offset, wrap, half, 240.0):
				_draw_ship(s, world.time, off)
	_draw_popups()

## Offsets at which to additionally draw an entity so it appears on both sides
## of a toroidal wrap seam (corners produce three ghosts).
func _ghost_offsets(p: Vector2, wrap: bool, half: float, margin: float) -> Array[Vector2]:
	var offs: Array[Vector2] = [Vector2.ZERO]
	if not wrap:
		return offs
	var dx := 0.0
	if p.x > half - margin:
		dx = -2.0 * half
	elif p.x < -half + margin:
		dx = 2.0 * half
	var dy := 0.0
	if p.y > half - margin:
		dy = -2.0 * half
	elif p.y < -half + margin:
		dy = 2.0 * half
	if dx != 0.0:
		offs.append(Vector2(dx, 0))
	if dy != 0.0:
		offs.append(Vector2(0, dy))
	if dx != 0.0 and dy != 0.0:
		offs.append(Vector2(dx, dy))
	return offs

func _draw_arena_bounds(world: SimWorld) -> void:
	var half := world.config.arena_size * 0.5
	if world.config.lethal_edges:
		# The wall of death announces itself: thick, red, pulsing.
		var pulse := 0.35 + 0.25 * sin(world.time * 4.0)
		draw_rect(Rect2(-half, -half, world.config.arena_size, world.config.arena_size),
			Color(1.6, 0.2, 0.15, pulse), false, 16.0)
	else:
		draw_rect(Rect2(-half, -half, world.config.arena_size, world.config.arena_size),
			Color(0.4, 0.6, 1.0, 0.08), false, 3.0)

func _draw_star(b: SimBody, t: float) -> void:
	var pulse := 1.0 + 0.04 * sin(t * 3.1 + float(b.seed % 7))
	draw_circle(b.pos, b.radius * 2.1 * pulse, Color(1.0, 0.65, 0.25, 0.07))
	draw_circle(b.pos, b.radius * 1.5 * pulse, Color(1.2, 0.8, 0.35, 0.18))
	draw_circle(b.pos, b.radius * 1.08, Color(1.8, 1.1, 0.45, 0.7))
	draw_circle(b.pos, b.radius * 0.92, Color(2.6, 1.8, 0.9))
	draw_circle(b.pos, b.radius * 0.62, Color(3.4, 3.0, 2.2))

func _draw_planet(b: SimBody, world: SimWorld) -> void:
	var hue := float(b.seed % 997) / 997.0
	var base := Color.from_hsv(hue, 0.55, 0.75)
	# Light the day side toward the star.
	var primary := world.primary_body()
	var light := Vector2.RIGHT
	if primary != null and primary.pos.distance_to(b.pos) > 1.0:
		light = (primary.pos - b.pos).normalized()
	draw_circle(b.pos, b.radius * 1.06, Color(base.r, base.g, base.b, 0.25))  # atmosphere rim
	draw_circle(b.pos, b.radius, base.darkened(0.55))
	draw_circle(b.pos + light * b.radius * 0.28, b.radius * 0.78, base)
	draw_circle(b.pos + light * b.radius * 0.45, b.radius * 0.45, base.lightened(0.25))

func _draw_minor(b: SimBody) -> void:
	if b.kind == SimBody.Kind.SATELLITE:
		draw_circle(b.pos, b.radius, Color(1.4, 1.4, 1.6))
		draw_circle(b.pos, b.radius * 2.2, Color(1.0, 0.3, 0.3, 0.18))  # hazard halo
	else:
		var hue := float(b.seed % 997) / 997.0
		var c := Color.from_hsv(hue, 0.15, 0.65)
		draw_circle(b.pos, b.radius, c)
		draw_circle(b.pos + Vector2(-b.radius * 0.25, -b.radius * 0.25), b.radius * 0.6, c.lightened(0.2))

func _draw_asteroid(b: SimBody, t: float) -> void:
	var poly: PackedVector2Array = _asteroid_polys.get(b.id, PackedVector2Array())
	if poly.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = b.seed
		var n := rng.randi_range(6, 9)
		for i in range(n):
			var a := TAU * float(i) / float(n)
			poly.append(Vector2(cos(a), sin(a)) * b.radius * rng.randf_range(0.7, 1.25))
		_asteroid_polys[b.id] = poly
	var spin := float(b.seed % 100) / 100.0 - 0.5
	draw_set_transform(b.pos, t * spin)
	var shade := 0.38 + 0.18 * (float(b.seed % 13) / 13.0)
	draw_colored_polygon(poly, Color(shade, shade * 0.95, shade * 0.88))
	draw_set_transform(Vector2.ZERO)

const PICKUP_COLORS: Array[Color] = [
	Color(0.4, 1.8, 0.7),   # fuel — green
	Color(1.8, 1.5, 0.4),   # ammo — gold
	Color(1.8, 0.8, 0.3),   # mines — orange
]
const PICKUP_LETTERS := ["F", "A", "M"]

func _draw_pickup(p: SimPickup, t: float) -> void:
	var vis := clampf(_ship_vis_scale * 0.8, 1.0, 2.2)
	var r := p.radius * vis * (1.0 + 0.12 * sin(t * 5.0 + float(p.id)))
	var c: Color = PICKUP_COLORS[p.kind % PICKUP_COLORS.size()]
	var pp := _ipos("p%d" % p.id, p.pos)
	draw_set_transform(pp, t * 1.2)
	draw_colored_polygon(PackedVector2Array([
		Vector2(r, 0), Vector2(0, r), Vector2(-r, 0), Vector2(0, -r)]),
		Color(c.r, c.g, c.b, 0.35))
	draw_set_transform(Vector2.ZERO)
	draw_string(ThemeDB.fallback_font, pp + Vector2(-6, 6),
		PICKUP_LETTERS[p.kind % PICKUP_LETTERS.size()],
		HORIZONTAL_ALIGNMENT_CENTER, 12, int(13 * vis), c)

func _draw_mine(m: SimMine, t: float, ghost: Vector2 = Vector2.ZERO) -> void:
	var p := _ipos("m%d" % m.id, m.pos) + ghost
	var vis := clampf(_ship_vis_scale * 0.8, 1.0, 2.4)
	var body_col := Color(0.55, 0.6, 0.65)
	draw_circle(p, m.radius * vis, body_col)
	for i in range(4):  # slowly rotating contact spikes
		var a := TAU * float(i) / 4.0 + t * 0.8
		var dir := Vector2(cos(a), sin(a))
		draw_line(p + dir * m.radius * vis * 0.6, p + dir * m.radius * vis * 1.5,
			body_col, 1.5)
	if m.age >= session.world.config.mine_arm_time:
		var blink := 0.4 + 0.6 * maxf(0.0, sin(t * 7.0 + float(m.id)))
		draw_circle(p, m.radius * vis * 0.45, Color(2.0 * blink, 0.2, 0.15))

func _draw_torpedo(t: SimTorpedo, ghost: Vector2 = Vector2.ZERO) -> void:
	var p := _ipos("t%d" % t.id, t.pos) + ghost
	var m := clampf(_ship_vis_scale * 0.7, 1.0, 2.2)
	var dir := t.vel.normalized() if t.vel.length() > 1.0 else Vector2.RIGHT
	draw_line(p - dir * 16.0 * m, p, Color(1.6, 1.2, 0.4, 0.35), 2.0 * m)
	draw_circle(p, t.radius * 0.8 * m, Color(2.6, 2.2, 1.4))

func _draw_ship(s: SimShip, t: float, ghost: Vector2 = Vector2.ZERO) -> void:
	var col := ship_color(s)
	var k := s.radius / 12.0 * _ship_vis_scale
	draw_set_transform(_ipos("s%d" % s.id, s.pos) + s.render_pos_offset + ghost,
		_iangle(s.id, s.angle), Vector2(k, k))

	var hull: Dictionary = _hull_cache.get(s.id, {})
	if hull.is_empty():
		hull = hull_polygon(s.hull_seed)
		_hull_cache[s.id] = hull
	var pts: PackedVector2Array = hull["poly"]
	var tail_x: float = hull["tail"]

	# Exhaust flame while thrusting (flickers), anchored to this hull's stern.
	if _thrusting.has(s.id):
		var len := 14.0 + 6.0 * sin(t * 40.0 + float(s.id))
		var flame := PackedVector2Array([Vector2(tail_x + 1.0, 4.5),
			Vector2(tail_x + 1.0, -4.5), Vector2(tail_x - len, 0)])
		draw_colored_polygon(flame, Color(2.2, 1.3, 0.35, 0.9))

	draw_colored_polygon(pts, col)
	if s.id == session.human_ship_id:
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(2.0, 2.0, 2.0), 1.5)

	# Spawn-grace shield ring.
	if s.spawn_grace > 0.0:
		var a := 0.25 + 0.35 * absf(sin(t * 8.0))
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(0.6, 1.4, 2.0, a), 2.0)

	draw_set_transform(Vector2.ZERO)

## The most watchable fight right now: the closest pair of mutually hostile
## alive ships ([id_a, id_b]), a lone survivor ([id]), or [] when empty.
static func pick_duel(world: SimWorld) -> Array:
	var alive: Array[SimShip] = []
	for s in world.ships:
		if s.alive:
			alive.append(s)
	var best_a := -1
	var best_b := -1
	var best_d := INF
	for i in range(alive.size()):
		for j in range(i + 1, alive.size()):
			var a := alive[i]
			var b := alive[j]
			if a.team != -1 and a.team == b.team:
				continue
			var d := a.pos.distance_squared_to(b.pos)
			if d < best_d:
				best_d = d
				best_a = a.id
				best_b = b.id
	if best_a >= 0:
		return [best_a, best_b]
	if not alive.is_empty():
		return [alive[0].id]
	return []

static func ship_color(s: SimShip) -> Color:
	if s.team >= 0:
		return TEAM_COLORS[s.team % TEAM_COLORS.size()]
	return PALETTE16[s.palette_idx % PALETTE16.size()]

## Build a ship silhouette from its hull seed: a symmetric polygon — nose,
## optional shoulder, swept wingtip, inner tail, pointed-or-flat stern — in
## the same local space as the classic wedge. Deterministic per seed, so
## every peer renders the identical ship. Returns {"poly": PackedVector2Array,
## "tail": float} (tail = stern x, used to anchor the exhaust flame).
static func hull_polygon(hull_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hull_seed
	var nose := rng.randf_range(13.0, 19.0)
	var tail := rng.randf_range(-12.0, -7.0)
	var span := rng.randf_range(6.5, 11.0)
	var sweep := rng.randf_range(-10.0, -3.0)
	var has_shoulder := rng.randf() < 0.55
	var shoulder := Vector2(rng.randf_range(2.0, 7.0), span * rng.randf_range(0.35, 0.55))
	var tail_inner := Vector2(tail + rng.randf_range(0.0, 3.5), span * rng.randf_range(0.25, 0.45))
	var pointed_stern := rng.randf() < 0.5

	var top: Array[Vector2] = [Vector2(nose, 0)]
	if has_shoulder:
		top.append(shoulder)
	top.append(Vector2(sweep, span))
	top.append(tail_inner)

	var pts := PackedVector2Array()
	for p in top:
		pts.append(p)
	if pointed_stern:
		pts.append(Vector2(tail, 0))
	for i in range(top.size() - 1, 0, -1):  # mirror, skipping the nose
		pts.append(Vector2(top[i].x, -top[i].y))
	return {"poly": pts, "tail": tail}

# --------------------------------------------------------------------------
# Juice: shake + kill popups
# --------------------------------------------------------------------------

## More shake the closer the blast is to the camera's center of attention.
func _add_shake(pos: Vector2, base: float) -> void:
	var falloff := clampf(1.0 - pos.distance_to(_camera.position) / 1600.0, 0.0, 1.0)
	_shake = minf(26.0, _shake + base * 16.0 * falloff)

func _add_kill_popup(killer_id: int, victim_id: int) -> void:
	var victim := session.world.ship_by_id(victim_id)
	var killer := session.world.ship_by_id(killer_id)
	if victim == null or killer == null:
		return
	var kname: String = session.ship_names.get(killer_id, "")
	if killer_id == session.human_ship_id:
		kname = "YOU"
	elif kname == "":
		kname = "BOT-%d" % killer_id
	_popups.append({"pos": victim.pos, "vel": Vector2(0, -46), "ttl": 1.7,
		"text": "+1  %s" % kname, "color": ship_color(killer)})

func _add_text_popup(pos: Vector2, text: String, color: Color) -> void:
	_popups.append({"pos": pos, "vel": Vector2(0, -40), "ttl": 1.4,
		"text": text, "color": color})

func _step_popups(dt: float) -> void:
	for p in _popups:
		p["ttl"] = float(p["ttl"]) - dt
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * dt
	while not _popups.is_empty() and float(_popups[0]["ttl"]) <= 0.0:
		_popups.pop_front()

func _draw_popups() -> void:
	for p in _popups:
		var c: Color = p["color"]
		c.a = clampf(float(p["ttl"]) / 0.6, 0.0, 1.0)
		var sz := int(18.0 * clampf(_ship_vis_scale * 0.7, 1.0, 2.0))
		draw_string(ThemeDB.fallback_font, (p["pos"] as Vector2) + Vector2(-60, 0),
			String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, 120, sz, c)

# --------------------------------------------------------------------------
# Particles
# --------------------------------------------------------------------------

func _spawn_burst(pos: Vector2, color: Color, amount: int, speed: float) -> void:
	var m := ParticleProcessMaterial.new()
	m.gravity = Vector3.ZERO
	m.spread = 180.0
	m.initial_velocity_min = speed * 0.25
	m.initial_velocity_max = speed
	m.damping_min = 80.0
	m.damping_max = 200.0
	m.scale_min = 1.5
	m.scale_max = 4.0
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r * 0.3, color.g * 0.2, color.b * 0.2, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	var p := GPUParticles2D.new()
	p.process_material = m
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = pos
	p.emitting = true
	add_child(p)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
