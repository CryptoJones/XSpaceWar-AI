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

## Local hull space: +X = facing, roughly ±19 units, scaled by radius/12.

var session: GameSession
var input_enabled := false

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
	if RenderingServer.get_current_rendering_method() == "forward_plus":
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

func _physics_process(dt: float) -> void:
	if session == null:
		return
	_thrusting.clear()
	if external_driver.is_valid():
		external_driver.call(dt)
	elif session.world != null:
		_read_human_input()
		session.update(dt)
	if session.world == null:
		return
	if session.generation != _seen_generation:
		_on_new_generation()

	for ev in session.world.events:
		_audio.play_event(ev)
		match ev.get("type", ""):
			"thrust":
				_thrusting[ev["ship"]] = true
			"explosion":
				_spawn_burst(ev["pos"], Color(2.4, 1.5, 0.5), 56, 420.0)
			"hyperspace":
				_spawn_burst(ev["pos"], Color(0.7, 1.2, 2.4), 28, 240.0)
	_audio.update(dt, session.world)

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
	if _audio != null:
		_audio.reset()
	# Re-seed the nebula and tint it per-arena so every match looks distinct.
	var s := session.world.config.seed
	_bg_mat.set_shader_parameter("seed", float(absi(s) % 100000) * 0.001)
	var h1 := float(absi(s) % 997) / 997.0
	var h2 := wrapf(h1 + 0.35, 0.0, 1.0)
	_bg_mat.set_shader_parameter("tint_a", Color.from_hsv(h1, 0.65, 0.30))
	_bg_mat.set_shader_parameter("tint_b", Color.from_hsv(h2, 0.55, 0.26))

# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

## Read the local keyboard into a NetProtocol input payload ({u, t, f, h}).
## Used directly for solo play and forwarded over the wire for net play.
func gather_local_input() -> Dictionary:
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		turn -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		turn += 1.0
	return {
		"u": turn,
		"t": Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP),
		"f": Input.is_physical_key_pressed(KEY_SPACE),
		"h": Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SHIFT),
	}

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
	var target_pos := _camera.position
	var target_zoom := _cam_zoom
	var human := session.human_ship()

	if human != null:
		# When the followed ship wraps the toroidal edge (or hyperspaces), jump
		# the camera by the same leap instead of lerping across the whole map.
		if _follow_id == human.id:
			var jump := human.pos - _follow_pos
			var half := session.world.config.arena_size * 0.5
			if absf(jump.x) > half:
				_camera.position.x += signf(jump.x) * session.world.config.arena_size
			if absf(jump.y) > half:
				_camera.position.y += signf(jump.y) * session.world.config.arena_size
		_follow_id = human.id
		_follow_pos = human.pos
		target_pos = human.pos + human.render_pos_offset
		target_zoom = 1.15
	else:
		# Movie Mode: frame the bounding box of alive ships (fit zoom).
		var pts: Array[Vector2] = []
		for s in session.world.ships:
			if s.alive:
				pts.append(s.pos)
		if pts.is_empty():
			var primary := session.world.primary_body()
			pts.append(primary.pos if primary != null else Vector2.ZERO)
		var lo := pts[0]
		var hi := pts[0]
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		target_pos = (lo + hi) * 0.5
		var span := (hi - lo) + Vector2(900, 900)  # margin
		var vp := get_viewport_rect().size
		target_zoom = clampf(minf(vp.x / span.x, vp.y / span.y), 0.3, 1.15)

	var k := 1.0 - exp(-2.5 * dt)
	_camera.position = _camera.position.lerp(target_pos, k)
	_cam_zoom = lerpf(_cam_zoom, target_zoom, k)
	_camera.zoom = Vector2(_cam_zoom, _cam_zoom)
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
	for t in world.torpedoes:
		for off in _ghost_offsets(t.pos, wrap, half, 80.0):
			_draw_torpedo(t, off)
	for s in world.ships:
		if s.alive:
			for off in _ghost_offsets(s.pos + s.render_pos_offset, wrap, half, 240.0):
				_draw_ship(s, world.time, off)

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

func _draw_torpedo(t: SimTorpedo, ghost: Vector2 = Vector2.ZERO) -> void:
	var p := t.pos + ghost
	var m := clampf(_ship_vis_scale * 0.7, 1.0, 2.2)
	var dir := t.vel.normalized() if t.vel.length() > 1.0 else Vector2.RIGHT
	draw_line(p - dir * 16.0 * m, p, Color(1.6, 1.2, 0.4, 0.35), 2.0 * m)
	draw_circle(p, t.radius * 0.8 * m, Color(2.6, 2.2, 1.4))

func _draw_ship(s: SimShip, t: float, ghost: Vector2 = Vector2.ZERO) -> void:
	var col := ship_color(s)
	var k := s.radius / 12.0 * _ship_vis_scale
	draw_set_transform(s.pos + s.render_pos_offset + ghost, s.angle, Vector2(k, k))

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

static func ship_color(s: SimShip) -> Color:
	if s.team >= 0:
		return TEAM_COLORS[s.team % TEAM_COLORS.size()]
	return Color.from_hsv(float(s.hull_seed % 997) / 997.0, 0.65, 1.0)

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
