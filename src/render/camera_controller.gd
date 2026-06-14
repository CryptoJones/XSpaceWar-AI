class_name CameraController
## Camera framing for WorldView, extracted from the renderer god-class (#26).
##
## Stateless: operates on the passed-in WorldView. The camera state (_cam_pos,
## _cam_zoom, _shake, _follow_*, _focus_*, _killcam_id, _ship_vis_scale) stays on
## WorldView so render interpolation in _process and the camera_probe test are
## unaffected — this just owns the per-tick framing decision and smoothing.

## Resolve WHO the camera is on this tick, in strict priority order: own living
## ship > explicit TAB watch target > killcam > action director. Returns
## {pos, zoom, clamp} — clamp is the followed ship's position (Vector2.INF =
## no bleed-zone clamp, director wide shots only).
static func resolve_target(view: WorldView, dt: float) -> Dictionary:
	var session := view.session
	var pilot := session.human_ship()

	# 1) Your own living ship.
	if pilot != null and pilot.alive:
		view._killcam_id = -1
		session.watch_ship_id = -1
		# Wrap/hyperspace: jump the camera by the same leap, never pan the map.
		if view._follow_id == pilot.id:
			var jump := pilot.pos - view._follow_pos
			var half := session.world.config.arena_size * 0.5
			if absf(jump.x) > half:
				view._cam_pos.x += signf(jump.x) * session.world.config.arena_size
				view._cam_pos_prev.x = view._cam_pos.x
			if absf(jump.y) > half:
				view._cam_pos.y += signf(jump.y) * session.world.config.arena_size
				view._cam_pos_prev.y = view._cam_pos.y
		view._follow_id = pilot.id
		view._follow_pos = pilot.pos
		var p := pilot.pos + pilot.render_pos_offset
		# Failsafe: never let the player lose their own ship — snap, don't pan.
		if view._cam_pos.distance_to(p) > 6000.0:
			push_warning("camera failsafe: snapped %s -> ship %s (gen %d tick %d)"
				% [view._cam_pos, p, session.generation, session.world.tick])
			view._cam_pos = p
			view._cam_pos_prev = p
		return {"pos": p, "zoom": 1.15, "clamp": p}

	# 2) An explicit TAB choice (spectate, replay, dead, eliminated).
	if session.watch_ship_id >= 0:
		var watched := session.world.ship_by_id(session.watch_ship_id)
		if watched != null and watched.alive:
			var wp := watched.pos + watched.render_pos_offset
			return {"pos": wp, "zoom": 1.0, "clamp": wp}

	# 3) Killcam: ride whoever got you until you respawn.
	if pilot != null and not pilot.alive and view._killcam_id >= 0:
		var killer := session.world.ship_by_id(view._killcam_id)
		if killer != null and killer.alive:
			var kp := killer.pos + killer.render_pos_offset
			return {"pos": kp, "zoom": 1.0, "clamp": kp}

	# 4) Action director: frame the best duel, recut every few seconds.
	var world := session.world
	view._focus_timer -= dt
	var fa := world.ship_by_id(view._focus_a)
	var fb := world.ship_by_id(view._focus_b)
	if view._focus_timer <= 0.0 or fa == null or not fa.alive \
			or (view._focus_b >= 0 and (fb == null or not fb.alive)):
		var duel := WorldView.pick_duel(world)
		view._focus_a = duel[0] if duel.size() > 0 else -1
		view._focus_b = duel[1] if duel.size() > 1 else -1
		view._focus_timer = WorldView.DUEL_SHOT_TIME
		fa = world.ship_by_id(view._focus_a)
		fb = world.ship_by_id(view._focus_b)
	var vp := view.get_viewport_rect().size
	if fa != null and fb != null:
		var span := (fa.pos - fb.pos).abs() + Vector2(750, 750)
		return {"pos": (fa.pos + fb.pos) * 0.5,
			"zoom": clampf(minf(vp.x / span.x, vp.y / span.y), 0.5, 1.15),
			"clamp": fa.pos}  # the primary duelist never leaves the screen
	if fa != null:
		return {"pos": fa.pos, "zoom": 0.9, "clamp": fa.pos}
	var primary := world.primary_body()
	return {"pos": primary.pos if primary != null else Vector2.ZERO,
		"zoom": 0.5, "clamp": Vector2.INF}

## Per-tick camera state update: _cam_pos/_cam_zoom are the simulation-rate
## truth; _process() blends prev->curr each display frame (interpolation).
static func update(view: WorldView, dt: float) -> void:
	view._cam_pos_prev = view._cam_pos
	view._cam_zoom_prev = view._cam_zoom

	var t := resolve_target(view, dt)
	var k := 1.0 - exp(-2.5 * dt)
	view._cam_pos = view._cam_pos.lerp(t["pos"], k)
	view._cam_zoom = lerpf(view._cam_zoom, float(t["zoom"]), k)

	# The bleed-zone rule (Aaron's): the FOLLOWED ship may NEVER leave the
	# screen. The lerp lags proportionally to speed; when the followed ship
	# reaches the outer buffer of the view, the map moves instead.
	var clamp_to: Vector2 = t["clamp"]
	if clamp_to.x != INF:
		var half_view := view.get_viewport_rect().size * 0.5 / view._cam_zoom
		var limit := half_view * 0.72
		var pre := view._cam_pos
		view._cam_pos = view._cam_pos.clamp(clamp_to - limit, clamp_to + limit)
		# A clamp that teleports the camera (target wrapped the map) must
		# not smear the interpolated frame across the arena.
		if view._cam_pos.distance_to(pre) > half_view.length() * 2.0:
			view._cam_pos_prev = view._cam_pos

	# Shake energy decays at sim rate (the offset itself is applied per
	# display frame in _process).
	if view._shake > 0.2:
		view._shake *= exp(-6.0 * dt)
	else:
		view._shake = 0.0
	# Keep ships readable when the camera pulls back: hulls draw bigger than
	# their (unchanged) physical radius, more so the further out we are.
	view._ship_vis_scale = clampf(1.6 * maxf(1.0, 0.55 / view._cam_zoom), 1.6, 3.2)

## More shake the closer the blast is to the camera's center of attention.
static func add_shake(view: WorldView, pos: Vector2, base: float) -> void:
	var falloff := clampf(1.0 - pos.distance_to(view._camera.position) / 1600.0, 0.0, 1.0)
	view._shake = minf(26.0, view._shake + base * 16.0 * falloff)
