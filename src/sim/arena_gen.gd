class_name ArenaGen
extends RefCounted
## Procedurally generates a match arena (stars, planets, moons, asteroid
## fields, satellites) from a single seed, so every peer and the AI build the
## byte-identical world. Bodies are added to a SimWorld; their per-body seeds
## also drive the procedural renderer (surface shaders, silhouettes).
##
## All randomness uses a private RNG seeded from the arena seed, independent of
## the world's gameplay RNG, so the layout is reproducible regardless of how
## many ships later spawn.

# Default generation parameters. Override any subset via `populate(..., params)`.
const DEFAULTS := {
	"star_count": 1,          # 0 = no sun, 1 = single, 2 = binary
	"star_mass": 1000.0,
	"star_scale": 1.0,        # multiplies mass (gravity) and size together
	"planets": 2,             # planets orbiting the primary
	"moons_max": 2,           # max moons per planet
	"asteroid_belts": 1,
	"asteroid_density": 40,   # asteroids per belt
	"satellites": 2,          # small orbiting hazards
	"mirror": false,          # mirror layout for fair team play
}

# Planet orbital LINEAR speed = min(PLANET_MAX_LINEAR, PLANET_LINEAR_SCALE/orbit_r).
# Capped at 1/8 the max ship (the fastest case — small maps / inner orbits) and
# otherwise falling off proportional to 1/orbit_r; because orbit radii scale with
# MAP SIZE, planets on the biggest map barely crawl. Angular = linear/orbit_r.
const PLANET_LINEAR_SCALE := 880000.0             ## tuned so the outer planet on a 160k map drifts ~12 u/s

# No planet ever orbits inside this central square (edge length, world units)
# around the star — a fixed clear zone regardless of map size.
const PLANET_EXCLUSION_BOX := 10000.0

## Build an arena into `world` from `world.config.seed`. Returns a small
## metadata dictionary (e.g. the chosen parameters) for UI/debug.
static func populate(world: SimWorld, params: Dictionary = {}) -> Dictionary:
	var p := DEFAULTS.duplicate()
	for k in params:
		p[k] = params[k]

	var rng := RandomNumberGenerator.new()
	rng.seed = world.config.seed ^ 0x5EED_A2EA  # decorrelate from gameplay RNG

	var center := Vector2.ZERO
	var arena := world.config.arena_size

	# --- Stars ---
	var primary: SimBody = null
	match int(p["star_count"]):
		0:
			pass
		2:
			var sep := arena * 0.10
			var m := float(p["star_mass"]) * float(p["star_scale"]) * 0.6
			primary = _make_star(world, center + Vector2(-sep, 0), m, rng)
			var s2 := _make_star(world, center + Vector2(sep, 0), m, rng)
			# Make them orbit the barycenter.
			s2.parent_id = primary.id
			s2.orbit_radius = sep * 2.0
			s2.orbit_angle = 0.0
			s2.orbit_speed = 0.10
		_:
			primary = _make_star(world, center, float(p["star_mass"]) * float(p["star_scale"]), rng)

	# --- Planets (+ moons) ---
	# Generate FARTHEST FIRST (i=0 = outermost): the outermost planet rides the
	# very EDGE of the map at ~1.9x the star's radius, and each planet inward is
	# 12% smaller than the one outside it (geometric). Orbit radii are driven by
	# MAP SIZE — the innermost still sits well out (30% of the half-map), so
	# planets never share the sun's central square.
	if primary != null:
		var n_planets := int(p["planets"])
		var spread := wrapf(float(world.config.seed) * 0.6180339887, 0.0, TAU)
		var half := arena * 0.5
		# Outermost = 1.9x the star (doubled), capped so it can't swallow a tiny map.
		var max_planet_r := minf(primary.radius * 1.9, half * 0.3)
		# Inner orbit: outside the central PLANET_EXCLUSION_BOX (orbit = the box's
		# half-diagonal so a circular orbit fully clears the square) AND at least
		# 30% of the half-map out, so planets don't bunch near the star on a huge
		# arena. If the box is bigger than the map (small maps), enforcing it would
		# shove planets off-screen, so there we ring just outside the edge instead.
		var box_clear := PLANET_EXCLUSION_BOX * 0.5 * sqrt(2.0)   # ~7071 for a 10000 box
		var inner: float
		if box_clear < half:
			inner = maxf(box_clear, half * 0.30)
		else:
			inner = half + max_planet_r + 120.0
		var outer := maxf(inner + 200.0, minf(half * 0.92, half - max_planet_r - 80.0))
		for i in range(n_planets):
			var frac := 1.0 if n_planets <= 1 else 1.0 - float(i) / float(n_planets - 1)
			var orbit_r := lerpf(inner, outer, frac) + rng.randf_range(-60.0, 60.0)
			var planet_r := max_planet_r * pow(0.88, float(i))   # 12% smaller per step inward
			var pl := _make_orbiting(world, primary, orbit_r, rng,
				SimBody.Kind.PLANET, rng.randf_range(40.0, 140.0), planet_r)
			# Even angular slot; snap pos so any moons orbit from the corrected
			# spot. It still moves — _make_orbiting set a slow orbit_speed.
			pl.orbit_angle = wrapf(spread + float(i) * TAU / float(maxi(n_planets, 1)), 0.0, TAU)
			# Clockwise (positive = angle increases). Linear speed capped at 1/8 the
			# max ship and otherwise ∝ 1/orbit_r — and since orbit_r scales with the
			# map, planets on a huge map barely move. Angular = linear / orbit_r.
			var max_ship := world.config.max_ship_speed if world.config.max_ship_speed > 0.0 \
				else SimConfig.BASE_MAX_SHIP_SPEED
			var v := minf(max_ship / 8.0, PLANET_LINEAR_SCALE / orbit_r)
			pl.orbit_speed = v / orbit_r
			pl.pos = primary.pos + Vector2(cos(pl.orbit_angle), sin(pl.orbit_angle)) * pl.orbit_radius
			var n_moons := rng.randi_range(0, int(p["moons_max"]))
			for _m in range(n_moons):
				# Moon orbit clears the (now size-varying) planet surface.
				_make_orbiting(world, pl, pl.radius + rng.randf_range(80.0, 200.0), rng,
					SimBody.Kind.MOON, rng.randf_range(6.0, 18.0), rng.randf_range(10.0, 20.0))

	# --- Satellites (small fast orbiting hazards) ---
	if primary != null:
		for _i in range(int(p["satellites"])):
			var orbit_r := rng.randf_range(world.config.spawn_orbit_radius * 0.5, world.config.spawn_orbit_radius * 1.3)
			var sat := _make_orbiting(world, primary, orbit_r, rng,
				SimBody.Kind.SATELLITE, 0.0, rng.randf_range(5.0, 9.0))
			sat.gravity = false  # too small to pull, but still a lethal hazard

	# --- Asteroids ---
	var hazard := float(p.get("hazard", -1.0))
	if hazard >= 0.0:
		# Hazard-slider mode (Aaron's spec): scatter on a grid over the combat
		# zone — at hazard 1.0 roughly every THIRD cell holds a randomized
		# rock; at 0.0 space is clean. A clear disk around the star stays
		# rock-free so spawning isn't a death sentence.
		# Spread the field across the WHOLE map (scales with map size) instead of
		# bunching it near the star. The grid CELL scales with the map too, so the
		# rock count stays bounded — a fixed 240u cell on a 160k arena would spawn
		# hundreds of thousands of rocks.
		var reach := arena * 0.45                 # ~90% of the half-arena
		var cell := reach * 2.0 / 24.0            # ~24 cells across at any map size
		var jitter := cell * 0.4                  # scatter within the cell, not grid-locked
		var star_clear := (primary.radius + 280.0) if primary != null else 0.0
		var yi := -reach
		while yi <= reach:
			var xi := -reach
			while xi <= reach:
				if rng.randf() < hazard / 3.0:
					var pos := center + Vector2(xi, yi) \
						+ Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
					if pos.distance_to(center) > star_clear:
						var rock := SimBody.new()
						rock.kind = SimBody.Kind.ASTEROID
						rock.pos = pos
						rock.mass = 0.0
						rock.gravity = false
						rock.lethal = true
						rock.radius = rng.randf_range(6.0, 16.0)
						rock.seed = rng.randi()
						world.add_body(rock)
				xi += cell
			yi += cell
	else:
		# Legacy belt mode (used by older tests / direct callers).
		for belt in range(int(p["asteroid_belts"])):
			var belt_r := world.config.spawn_orbit_radius * (1.3 + 0.5 * belt) + rng.randf_range(-80.0, 80.0)
			var count := int(p["asteroid_density"])
			for a in range(count):
				var ang := rng.randf() * TAU
				if bool(p["mirror"]) and a % 2 == 1:
					ang = PI - ang  # mirror across the Y axis for symmetry
				var jitter := rng.randf_range(-belt_r * 0.15, belt_r * 0.15)
				var pos := center + Vector2(cos(ang), sin(ang)) * (belt_r + jitter)
				var rock := SimBody.new()
				rock.kind = SimBody.Kind.ASTEROID
				rock.pos = pos
				rock.mass = 0.0
				rock.gravity = false
				rock.lethal = true
				rock.radius = rng.randf_range(6.0, 16.0)
				rock.seed = rng.randi()
				world.add_body(rock)

	return p

static func _make_star(world: SimWorld, pos: Vector2, mass: float, rng: RandomNumberGenerator) -> SimBody:
	var b := SimBody.new()
	b.kind = SimBody.Kind.STAR
	b.pos = pos
	b.mass = mass
	# Radius tracks mass so a heavy star LOOKS heavy (and its kill zone and
	# gravity grow together); wide clamps allow dwarfs through giants.
	b.radius = clampf(mass * 0.08, 30.0, 480.0)
	b.gravity = true
	b.lethal = true
	b.seed = rng.randi()
	return world.add_body(b)

static func _make_orbiting(world: SimWorld, parent: SimBody, orbit_r: float,
		rng: RandomNumberGenerator, kind: int, mass: float, radius: float) -> SimBody:
	var b := SimBody.new()
	b.kind = kind
	b.mass = mass
	b.radius = radius
	b.gravity = mass > 0.0
	b.lethal = true
	b.seed = rng.randi()
	b.parent_id = parent.id
	b.orbit_radius = orbit_r
	b.orbit_angle = rng.randf() * TAU
	# Orbit speed roughly Keplerian (slower further out), random direction.
	var dir := 1.0 if rng.randf() < 0.5 else -1.0
	b.orbit_speed = dir * clampf(120.0 / orbit_r, 0.05, 0.6)
	b.pos = parent.pos + Vector2(cos(b.orbit_angle), sin(b.orbit_angle)) * orbit_r
	return world.add_body(b)
