# Brief: Code Review of XSpaceWar-AI (main branch)

You are one lane of an independent FlatlineRoundtable review panel.
Answer only from what is provided below; do not attempt to read the filesystem or shell out.
Be concise, direct, and adversarial. Lead with concrete findings. Say "unsure" or "no defect found" rather than speculating.

## Context & Architecture

- **Project**: XSpaceWar-AI (https://github.com/CryptoJones/XSpaceWar-AI)
- **Branch**: main (commit 20c5697, release v5.0.0+)
- **Engine**: Godot 4.6.3 (GDScript), headless-capable, running at fixed 60Hz physics / 20Hz net snapshots.
- **Domain**: Newtonian space-fighter combat (Spacewar! / xspacewar clean-room reimagining).
- **Core Architecture**:
  1. **Deterministic Sim**: Pure headless `SimWorld` in `src/sim/` with fixed pipeline order: Gravity -> Spawn -> Torpedo/Mine -> Ship Kinematics -> Pickups -> Swept Collisions -> Wrap with Slingshot. Arena geometry is toroidal (`Torus`). Deterministic RNG (`SimWorld.rng`).
  2. **Host-Authoritative Netcode**: Clients send sequenced inputs (`q`), host processes and broadcasts snapshots (`a`). Safe deserialization via `bytes_to_var` (objects rejected). Strict DoS bounds: `MAX_CLIENT_PACKET = 4096`, `MAX_PEERS_PER_IP = 4`, `MAX_PACKETS_PER_PUMP_PER_PEER = 8`, `MAX_INPUT_SEQ_GAP = 1024`.
  3. **Multiplayer & Moderation**: In-game `PlayersPanel`, dedicated console `/kick`, `/ban`, `/unban`, persistent `--banfile`. Heuristic `AimAnalyzer` for cheat monitoring (surface warnings only; never auto-bans).
  4. **AI & Difficulty**: `BotController` + `BotBehaviors` with skill tiers (Rookie, Veteran, Ace, Insane). Enemy ship visual size scales inversely with difficulty (Rookies fly larger, easier targets).
  5. **Dedicated Server**: `server/dedicated_main.gd` headless server for Linux/macOS/Windows VPS.

## Deliberate Decisions (Do NOT litigate these)
- Engine is Godot 4 / GDScript. Do not propose rewriting in C++, Rust, or C#.
- Visuals and audio are 100% procedural (no sprite/audio asset dependencies).
- Anticheat relies on host-authoritative simulation + aim anomaly heuristics + moderation tooling. Kernel anticheat is an explicit non-goal.
- Relay server provides zero-config NAT traversal; direct online hole-punching is not required.

## Review Questions

Evaluate the provided codebase against these 5 concrete, falsifiable questions:

1. **Sim Determinism & Arithmetic Edge Cases**:
   - In `sim_world.gd`, `torus.gd`, `collision_system.gd`, or `spawn_system.gd`, are there division-by-zero vulnerabilities (e.g. `r == 0` or near-zero distance to star/planets/mines), NaN/Inf propagation, or unseeded random calls?
   - Can toroidal wrapping or swept collision tunneling cause entities to escape the arena or create infinite loops?

2. **Netcode & Packet Security**:
   - In `net_protocol.gd` and `net_host.gd`, can a malicious client crash the host, cause memory leaks, trigger unbounded dictionary growth, spoof another player's ship/slot, or bypass packet/rate limits?
   - Is `NetHost`'s input sequence gap guard (`MAX_INPUT_SEQ_GAP = 1024`) vulnerable to wrap-around or sequence exhaustion over long-running matches?

3. **Bot AI & Behavior Trees**:
   - In `bot_behaviors.gd`, are there failure modes where bots freeze, fail to acquire targets, loop infinitely, crash on null/dead targets, or miscalculate toroidal lead aim across the arena wrap?
   - Does difficulty scaling introduce any edge-case game breaks?

4. **Dedicated Server, Moderation & Persistence**:
   - In `dedicated_main.gd` and `aim_analyzer.gd`, are there concurrency/lifecycle bugs, file corruption risks with `--banfile` under concurrent or interrupted writes, command injection in the moderation console, or memory leaks over multi-hour matches?

5. **Dead Code, Missing Guards & Fragile Constructs**:
   - What error conditions or state transitions are unhandled or fragile across these load-bearing files before shipping a major public release?

---

## File: `src/sim/sim_world.gd` — Simulation Core (SimWorld)

```gdscript
class_name SimWorld
extends RefCounted
## The authoritative, deterministic, render-free game simulation.
##
## Fixed-timestep Newtonian physics: ships and torpedoes coast, are pulled by
## the inverse-square gravity of every massive body, and are destroyed on
## contact with bodies, torpedoes, or each other. Hyperspace teleports a ship
## to a fresh orbit at the risk of self-destruction.
##
## Determinism: integration order is fixed, and all randomness goes through a
## single seeded RNG, so the same config + same input stream reproduces the
## same end state bit-for-bit on a given platform. This one class backs the
## host's authoritative sim, client-side prediction, AI, and replays.
##
## The per-phase logic lives in the stateless systems under src/sim/systems/
## (GravitySystem, SpawnSystem, MineSystem, PickupSystem, CollisionSystem,
## WrapSystem) — extracted from this god-class in issue #18. SimWorld owns the
## state and drives the fixed-order step() pipeline across those systems; a few
## methods are kept here as thin forwarders for external callers.

var config: SimConfig
var rng := RandomNumberGenerator.new()

var bodies: Array[SimBody] = []
var ships: Array[SimShip] = []
var torpedoes: Array[SimTorpedo] = []
var mines: Array[SimMine] = []
var pickups: Array[SimPickup] = []
## Ids of bodies destroyed mid-match (shot asteroids) — replicated to net
## clients so their locally-generated arenas lose the same rocks.
var removed_body_ids: Array[int] = []

var time: float = 0.0
var tick: int = 0
var _next_id: int = 1

## Transient list of things that happened this step, for the renderer/audio
## layer to consume (explosions, fires, hyperspace warps, kills). Cleared at
## the start of every step.
var events: Array[Dictionary] = []

func _init(cfg: SimConfig = null) -> void:
	config = cfg if cfg != null else SimConfig.new()
	rng.seed = config.seed

func alloc_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func add_body(b: SimBody) -> SimBody:
	if b.id < 0:
		b.id = alloc_id()
	bodies.append(b)
	return b

func add_ship(team: int = -1) -> SimShip:
	var s := SimShip.new()
	s.id = alloc_id()
	s.team = team
	s.radius = config.ship_radius
	s.hull_seed = rng.randi()
	s.palette_idx = ships.size()
	place_in_orbit(s)
	ships.append(s)
	return s

func body_by_id(bid: int) -> SimBody:
	for b in bodies:
		if b.id == bid:
			return b
	return null

func ship_by_id(sid: int) -> SimShip:
	for s in ships:
		if s.id == sid:
			return s
	return null

## The most massive gravitating body — the "sun" everything orbits.
func primary_body() -> SimBody:
	var best: SimBody = null
	for b in bodies:
		if b.gravity and (best == null or b.mass > best.mass):
			best = b
	return best

# --------------------------------------------------------------------------
# Stepping — the fixed-order pipeline across the systems. The call order here
# is determinism-critical (it fixes the RNG-consumption order); do not reorder.
# --------------------------------------------------------------------------

func step(dt: float = -1.0) -> void:
	if dt < 0.0:
		dt = config.fixed_dt
	# Events ACCUMULATE (tick-stamped) instead of clearing per step: when a
	# driver runs several steps per consumer pass (fast replay, sub-60fps
	# frames) nothing is lost. Consumers track the last tick they processed;
	# the cap below bounds memory for consumer-less worlds (dedicated).

	GravitySystem.advance_bodies(self, dt)

	for s in ships:
		SpawnSystem.step_ship(self, s, dt)

	GravitySystem.integrate_ships(self, dt)
	_step_torpedoes(dt)
	MineSystem.step_mines(self, dt)
	PickupSystem.step_pickups(self, dt)
	CollisionSystem.resolve(self, dt)

	if config.wrap_edges:
		WrapSystem.wrap_positions(self)
	elif config.lethal_edges:
		WrapSystem.enforce_lethal_edges(self)

	if events.size() > 512:
		events = events.slice(events.size() - 256)

	time += dt
	tick += 1

## Torpedo drift/expiry. Kept on SimWorld (issue #18 listed no torpedo system);
## a small projectile-stepping helper that leans on Gravity/Wrap systems.
func _step_torpedoes(dt: float) -> void:
	var survivors: Array[SimTorpedo] = []
	for t in torpedoes:
		t.age += dt
		# A configured fuse still works (and old replays need it), but the
		# default is 0: torpedoes fly FOREVER until they hit something.
		if config.torpedo_life > 0.0:
			t.life -= dt
			if t.life <= 0.0:
				continue
		if config.torpedo_gravity:
			t.vel += GravitySystem.accel(self, t.pos) * dt
		t.pos += t.vel * dt
		if config.wrap_edges:
			var wb_t := WrapSystem.wrap_with_boost(self, t.pos, t.vel)
			if not wb_t.is_empty():
				t.pos = wb_t[0]
				t.vel = wb_t[1]
		survivors.append(t)
	torpedoes = survivors

## Advance one ship's pilot kinematics (turn / thrust+fuel / gravity /
## position / wrap) exactly as a full step would, without weapons, timers, or
## collisions. Used by net clients to predict the local ship: the order
## matches SpawnSystem.step_ship -> GravitySystem.integrate_ships for one ship.
func step_ship_kinematics(s: SimShip, turn: float, thrust: bool, dt: float) -> void:
	s.angle = wrapf(s.angle + clampf(turn, -1.0, 1.0) * config.turn_rate * dt, -PI, PI)
	if thrust and s.fuel > 0.0:
		s.vel += s.facing() * config.thrust_accel * dt
		s.fuel = maxf(0.0, s.fuel - config.thrust_fuel_per_sec * dt)
	else:
		s.fuel = minf(config.max_fuel, s.fuel + config.fuel_regen_per_sec * dt)
	s.vel += GravitySystem.accel(self, s.pos) * dt
	clamp_ship_velocity(s)
	s.pos += s.vel * dt
	if config.wrap_edges:
		var wb := WrapSystem.wrap_with_boost(self, s.pos, s.vel)
		if not wb.is_empty():
			s.pos = wb[0]
			s.vel = wb[1]

# --------------------------------------------------------------------------
# Thin forwarders kept for external callers (net_client, tests, scene_smoke)
# so the extraction in issue #18 preserves the public API.
# --------------------------------------------------------------------------

func gravity_accel(p: Vector2) -> Vector2:
	return GravitySystem.accel(self, p)

func clamp_ship_velocity(s: SimShip) -> void:
	if config.max_ship_speed > 0.0 \
			and s.vel.length_squared() > config.max_ship_speed * config.max_ship_speed:
		s.vel = s.vel.limit_length(config.max_ship_speed)

func _advance_bodies(dt: float) -> void:
	GravitySystem.advance_bodies(self, dt)

func place_in_orbit(s: SimShip) -> void:
	SpawnSystem.place_in_orbit(self, s)

func _hyperspace(s: SimShip) -> void:
	SpawnSystem.hyperspace(self, s)

func _destroy_ship(s: SimShip, killer_id: int, cause: String) -> void:
	CollisionSystem.destroy_ship(self, s, killer_id, cause)

```

## File: `src/sim/torus.gd` — Toroidal Arena Math (Torus)

```gdscript
class_name TorusMath
extends RefCounted
## Shared shortest-path math for the square toroidal arena.

static func shortest_delta(from: Vector2, to: Vector2, size: float) -> Vector2:
	var d := to - from
	if size <= 0.0:
		return d
	var half := size * 0.5
	if d.x > half:
		d.x -= size
	elif d.x < -half:
		d.x += size
	if d.y > half:
		d.y -= size
	elif d.y < -half:
		d.y += size
	return d

static func distance_squared(a: Vector2, b: Vector2, size: float) -> float:
	return shortest_delta(a, b, size).length_squared()

static func distance(a: Vector2, b: Vector2, size: float) -> float:
	return sqrt(distance_squared(a, b, size))

static func wrap_point(p: Vector2, size: float) -> Vector2:
	if size <= 0.0:
		return p
	var half := size * 0.5
	return Vector2(fposmod(p.x + half, size) - half,
		fposmod(p.y + half, size) - half)

## Test a moving point against a circle while respecting seam crossings.
static func swept_hits_circle(p0: Vector2, p1: Vector2, center: Vector2,
		radius: float, size: float) -> bool:
	var local0 := shortest_delta(center, p0, size)
	var local1 := local0 + shortest_delta(p0, p1, size)
	var d := local1 - local0
	var len_sq := d.length_squared()
	if len_sq < 0.000001:
		return local0.length_squared() <= radius * radius
	var t := clampf(-local0.dot(d) / len_sq, 0.0, 1.0)
	return (local0 + d * t).length_squared() <= radius * radius

static func swept_hits_moving_circle(p0: Vector2, p1: Vector2, c0: Vector2,
		c1: Vector2, radius: float, size: float) -> bool:
	var local0 := shortest_delta(c0, p0, size)
	var d := shortest_delta(p0, p1, size) - shortest_delta(c0, c1, size)
	var len_sq := d.length_squared()
	if len_sq < 0.000001:
		return local0.length_squared() <= radius * radius
	var t := clampf(-local0.dot(d) / len_sq, 0.0, 1.0)
	return (local0 + d * t).length_squared() <= radius * radius

```

## File: `src/sim/systems/collision_system.gd` — Collision System & Swept Physics

```gdscript
class_name CollisionSystem
## Swept collision detection and resolution for the deterministic sim:
## torpedoes vs bodies/ships, mines (delegated), ships vs bodies/ships, plus
## the rock-shatter, ship-destroy, and elastic-bounce helpers.
##
## Stateless: operates on a passed-in SimWorld. Extracted from SimWorld (issue
## #18). Scan order and the RNG draws in break_rock are unchanged.

const SELF_HIT_GRACE := 0.30  ## a torpedo can't hit its own ship before this age

## True if the swept path p0->p1 passes within r of c. Degenerates to a
## point test for tiny displacement; callers must teleport-guard wraps.
static func segment_hits_circle(p0: Vector2, p1: Vector2, c: Vector2, r: float) -> bool:
	var d := p1 - p0
	var len_sq := d.length_squared()
	if len_sq < 0.000001:
		return p0.distance_to(c) <= r
	var t := clampf((c - p0).dot(d) / len_sq, 0.0, 1.0)
	return (p0 + d * t).distance_to(c) <= r

static func resolve(world: SimWorld, dt: float) -> void:
	var config := world.config
	# Torpedoes vs bodies. Stars/planets simply eat torpedoes; ASTEROIDS are
	# destructible — the rock shatters and sometimes drops its cargo.
	var torp_survivors: Array[SimTorpedo] = []
	var broken_rocks: Array[SimBody] = []
	for t in world.torpedoes:
		var hit_body := false
		var t_prev := t.pos - t.vel * dt
		for b in world.bodies:
			if not b.lethal:
				continue
			if TorusMath.swept_hits_circle(t_prev, t.pos, b.pos,
					b.radius + t.radius, config.arena_size):
				hit_body = true
				if b.kind == SimBody.Kind.ASTEROID and not broken_rocks.has(b):
					broken_rocks.append(b)
				break
		if not hit_body:
			torp_survivors.append(t)
	world.torpedoes = torp_survivors
	for rock in broken_rocks:
		break_rock(world, rock)

	# Torpedoes vs ships.
	var remaining: Array[SimTorpedo] = []
	for t in world.torpedoes:
		var consumed := false
		for s in world.ships:
			if not s.alive or s.spawn_grace > 0.0:
				continue
			if s.id == t.owner_id and (t.age < SELF_HIT_GRACE or not config.friendly_fire):
				continue
			if s.id != t.owner_id and s.team == t.team and s.team != -1 and not config.friendly_fire:
				continue
			var t_prev := t.pos - t.vel * dt
			var s_prev := s.pos - s.vel * dt
			if TorusMath.swept_hits_moving_circle(t_prev, t.pos, s_prev, s.pos,
					s.radius + t.radius, config.arena_size):
				var killer := -1 if s.id == t.owner_id else t.owner_id
				destroy_ship(world, s, killer, "torpedo")
				consumed = true
				break
		if not consumed:
			remaining.append(t)
	world.torpedoes = remaining

	MineSystem.resolve_mines(world)

	# Ships vs bodies.
	for s in world.ships:
		if not s.alive or s.spawn_grace > 0.0:
			continue
		var s_prev := s.pos - s.vel * dt
		for b in world.bodies:
			if not b.lethal:
				continue
			if TorusMath.swept_hits_circle(s_prev, s.pos, b.pos,
					b.radius + s.radius, config.arena_size):
				destroy_ship(world, s, -1, "body")
				break

	# Ships vs ships.
	for i in range(world.ships.size()):
		var a := world.ships[i]
		if not a.alive or a.spawn_grace > 0.0:
			continue
		for j in range(i + 1, world.ships.size()):
			var b := world.ships[j]
			if not b.alive or b.spawn_grace > 0.0:
				continue
			var ship_clearance := a.radius + b.radius
			if TorusMath.distance_squared(a.pos, b.pos, config.arena_size) > ship_clearance * ship_clearance:
				continue
			if a.team == b.team and a.team != -1 and not config.friendly_fire:
				continue
			if config.ship_collision_lethal:
				destroy_ship(world, a, -1, "ram")
				destroy_ship(world, b, -1, "ram")
			else:
				bounce(a, b, config.arena_size)

static func break_rock(world: SimWorld, rock: SimBody) -> void:
	var config := world.config
	var rng := world.rng
	world.bodies.erase(rock)
	world.removed_body_ids.append(rock.id)
	world.events.append({"tk": world.tick, "type": "rock_break", "pos": rock.pos})
	if rng.randf() < config.pickup_chance:
		var p := SimPickup.new()
		p.id = world.alloc_id()
		p.kind = rng.randi() % SimPickup.Kind.size()
		p.pos = rock.pos
		var ang := rng.randf() * TAU
		p.vel = Vector2(cos(ang), sin(ang)) * rng.randf_range(10.0, 50.0)
		p.ttl = config.pickup_ttl
		p.radius = config.pickup_radius
		world.pickups.append(p)

static func bounce(a: SimShip, b: SimShip, arena_size: float) -> void:
	# Equal-mass elastic bounce along the contact normal.
	var n := TorusMath.shortest_delta(a.pos, b.pos, arena_size)
	if n.length() < 0.0001:
		return
	n = n.normalized()
	var va := a.vel.dot(n)
	var vb := b.vel.dot(n)
	a.vel += n * (vb - va)
	b.vel += n * (va - vb)
	# Separate so they don't stick.
	var overlap := (a.radius + b.radius) - TorusMath.distance(a.pos, b.pos, arena_size)
	if overlap > 0.0:
		a.pos -= n * overlap * 0.5
		b.pos += n * overlap * 0.5

static func destroy_ship(world: SimWorld, s: SimShip, killer_id: int, cause: String) -> void:
	if not s.alive:
		return
	if s.frozen or s.invulnerable:
		return  # DEBUG: frozen (parked) or immortal — can't be killed
	s.alive = false
	s.deaths += 1
	s.respawn_timer = world.config.respawn_time
	world.events.append({"tk": world.tick, "type": "explosion", "ship": s.id, "pos": s.pos, "vel": s.vel, "cause": cause, "killer": killer_id})
	if killer_id >= 0 and killer_id != s.id:
		var killer := world.ship_by_id(killer_id)
		if killer != null:
			killer.kills += 1
			killer.score += 1
			world.events.append({"tk": world.tick, "type": "kill", "killer": killer_id, "victim": s.id})
	elif cause == "torpedo" or cause == "hyperspace" or cause == "mine":
		s.score -= 1  # suicide / self-destruct penalty

```

## File: `src/sim/systems/spawn_system.gd` — Spawn System & Grace Geometry

```gdscript
class_name SpawnSystem
## Ship spawning/respawn, per-ship pilot input, firing, and hyperspace for the
## deterministic sim.
##
## Stateless: operates on a passed-in SimWorld. Extracted from SimWorld (issue
## #18); RNG draw order (spawn angle jitter, clearance re-rolls, orbit
## direction, hyperspace risk) is unchanged so the sim stays deterministic.

static func place_in_orbit(world: SimWorld, s: SimShip, emit_respawn := false) -> void:
	var config := world.config
	var rng := world.rng
	var center := Vector2.ZERO
	var m := 0.0
	var primary := world.primary_body()
	if primary != null:
		center = primary.pos
		m = primary.mass
	# Teams spawn (and respawn) together in their own sector of the ring —
	# golden-angle spacing keeps any team count spread apart. FFA ships use
	# the whole circle.
	var ang: float
	if s.team >= 0:
		ang = wrapf(float(s.team) * 2.399963 + rng.randf_range(-0.6, 0.6), 0.0, TAU)
	else:
		ang = rng.randf() * TAU
	# The ring respects the ACTUAL star: a maxed star-size slider must not
	# leave pilots spawning inside the well (and never at the map's wall).
	var r := config.spawn_orbit_radius
	if primary != null:
		r = maxf(r, primary.radius * 3.0 + 200.0)
	r = minf(r, config.arena_size * 0.5 * 0.85)
	# Clearance checks cover static hazards and the moving hazards that used to
	# make a respawn look like a surprise kill. Sample deterministic candidates,
	# accept the first safe one, and retain the safest candidate as a fallback
	# for crowded arenas so this routine always produces a valid spawn.
	var chosen := center + Vector2(cos(ang), sin(ang)) * r
	var best_clearance := -INF
	for attempt in range(12):
		if attempt > 0:
			ang = rng.randf() * TAU
		var probe := center + Vector2(cos(ang), sin(ang)) * r
		var clearance := _spawn_clearance(world, s, probe)
		if clearance > best_clearance:
			best_clearance = clearance
			chosen = probe
		if clearance >= 0.0:
			chosen = probe
			break
	s.pos = chosen
	ang = (chosen - center).angle()
	# Circular-orbit speed, perpendicular to the radius, random direction.
	var speed := 0.0
	if m > 0.0:
		# True circular-orbit speed (Keplerian, pure 1/r^2): a still pilot
		# orbits a stable closed ellipse forever.
		speed = sqrt(config.gravity_constant * m / r)
	if config.max_ship_speed > 0.0:
		speed = minf(speed, config.max_ship_speed)
	var dir := Vector2(-sin(ang), cos(ang))
	if rng.randf() < 0.5:
		dir = -dir
	s.vel = dir * speed
	s.angle = dir.angle()
	s.fuel = config.max_fuel
	s.ammo = config.max_ammo
	s.ammo_timer = 0.0
	s.mines = config.max_mines
	s.mine_timer = 0.0
	s.mine_cooldown = 0.0
	s.alive = true
	s.respawn_timer = 0.0
	s.fire_cooldown = 0.0
	s.spawn_grace = config.spawn_grace
	s.hyper_chord_prev = s.in_hyper and s.in_fire
	if emit_respawn:
		world.events.append({"tk": world.tick, "type": "respawn", "ship": s.id, "pos": s.pos})

static func _spawn_clearance(world: SimWorld, s: SimShip, probe: Vector2) -> float:
	var best := INF
	var size := world.config.arena_size
	for b in world.bodies:
		if b.lethal:
			var clearance := b.radius + s.radius + 60.0
			best = minf(best, TorusMath.distance_squared(probe, b.pos, size)
				- clearance * clearance)
	for other in world.ships:
		if other != s and other.alive:
			var clearance := other.radius + s.radius + 240.0
			best = minf(best, TorusMath.distance_squared(probe, other.pos, size)
				- clearance * clearance)
	for t in world.torpedoes:
		var clearance := t.radius + s.radius + 180.0
		best = minf(best, TorusMath.distance_squared(probe, t.pos, size)
			- clearance * clearance)
	for m in world.mines:
		if m.age >= world.config.mine_arm_time:
			var clearance := m.radius + s.radius + 180.0
			best = minf(best, TorusMath.distance_squared(probe, m.pos, size)
				- clearance * clearance)
	return best

static func step_ship(world: SimWorld, s: SimShip, dt: float) -> void:
	var config := world.config
	if not s.alive:
		# Lives mode: out of lives means out of the match — no respawn.
		if config.lives > 0 and s.deaths >= config.lives:
			s.clear_inputs()
			return
		s.respawn_timer -= dt
		# Once the timer elapses, auto-respawn unless manual_respawn is on — then
		# the ship waits for its fire input (players press; dead bots hold fire).
		if s.respawn_timer <= 0.0 and (not config.manual_respawn or s.in_fire):
			place_in_orbit(world, s, true)
		s.clear_inputs()
		return

	# Timers / resource regen.
	s.spawn_grace = maxf(0.0, s.spawn_grace - dt)
	s.fire_cooldown = maxf(0.0, s.fire_cooldown - dt)
	s.hyperspace_cooldown = maxf(0.0, s.hyperspace_cooldown - dt)
	s.mine_cooldown = maxf(0.0, s.mine_cooldown - dt)
	if s.ammo < config.max_ammo:
		s.ammo_timer += dt
		while s.ammo_timer >= config.ammo_regen_interval and s.ammo < config.max_ammo:
			s.ammo_timer -= config.ammo_regen_interval
			s.ammo += 1
	if s.mines < config.max_mines:
		s.mine_timer += dt
		while s.mine_timer >= config.mine_regen_interval and s.mines < config.max_mines:
			s.mine_timer -= config.mine_regen_interval
			s.mines += 1

	# Rotation.
	s.angle = wrapf(s.angle + s.in_turn * config.turn_rate * dt, -PI, PI)

	# Thrust (fuel-limited). Integration of velocity happens in
	# GravitySystem.integrate_ships alongside gravity; here we just apply the
	# thrust impulse and burn fuel.
	if s.in_thrust and s.fuel > 0.0:
		s.vel += s.facing() * config.thrust_accel * dt
		s.fuel = maxf(0.0, s.fuel - config.thrust_fuel_per_sec * dt)
		world.events.append({"tk": world.tick, "type": "thrust", "ship": s.id, "pos": s.pos})
	else:
		s.fuel = minf(config.max_fuel, s.fuel + config.fuel_regen_per_sec * dt)

	# Fire.
	if s.in_fire and s.fire_cooldown <= 0.0 and s.ammo > 0:
		fire_torpedo(world, s)

	# Drop a mine behind us.
	if s.in_mine and s.mine_cooldown <= 0.0 and s.mines > 0:
		MineSystem.drop_mine(world, s)

	# Hyperspace is a rising edge of the Hyper+Fire chord. Holding both
	# controls therefore cannot jump again when the cooldown expires.
	var hyper_chord := s.in_hyper and s.in_fire
	var hyper_pressed := hyper_chord and not s.hyper_chord_prev
	s.hyper_chord_prev = hyper_chord
	if hyper_pressed and s.hyperspace_cooldown <= 0.0:
		hyperspace(world, s)

	s.clear_inputs()

static func fire_torpedo(world: SimWorld, s: SimShip) -> void:
	var config := world.config
	var t := SimTorpedo.new()
	t.id = world.alloc_id()
	t.owner_id = s.id
	t.team = s.team
	t.radius = config.torpedo_radius
	var fwd := s.facing()
	t.pos = s.pos + fwd * (s.radius + t.radius + 2.0)
	t.vel = s.vel + fwd * config.torpedo_speed
	t.life = config.torpedo_life
	world.torpedoes.append(t)
	s.ammo -= 1
	s.fire_cooldown = config.fire_cooldown
	world.events.append({"tk": world.tick, "type": "fire", "ship": s.id, "pos": t.pos})

static func hyperspace(world: SimWorld, s: SimShip) -> void:
	var config := world.config
	s.hyperspace_uses += 1
	s.hyperspace_cooldown = config.hyperspace_cooldown
	world.events.append({"tk": world.tick, "type": "hyperspace", "ship": s.id, "pos": s.pos})
	var risk := config.hyperspace_base_risk + config.hyperspace_risk_per_use * float(s.hyperspace_uses - 1)
	if world.rng.randf() < risk:
		CollisionSystem.destroy_ship(world, s, -1, "hyperspace")
		return
	# place_in_orbit is a SPAWN helper (full resupply + grace); a jump is
	# just a relocation — keep the pilot's resources and grant no shield.
	var keep := [s.fuel, s.ammo, s.ammo_timer, s.mines, s.mine_timer,
		s.mine_cooldown, s.fire_cooldown]
	place_in_orbit(world, s)
	s.fuel = keep[0]
	s.ammo = keep[1]
	s.ammo_timer = keep[2]
	s.mines = keep[3]
	s.mine_timer = keep[4]
	s.mine_cooldown = keep[5]
	s.fire_cooldown = keep[6]
	s.spawn_grace = 0.0

```

## File: `src/net/net_protocol.gd` — Net Protocol & Safe Unpack

```gdscript
class_name NetProtocol
extends RefCounted
## Wire protocol for host-authoritative multiplayer.
##
## Messages are `[type, payload]` arrays encoded with var_to_bytes (and decoded
## with bytes_to_var — never the *_with_objects variants, so a hostile packet
## can't smuggle in scripts/objects). Channel 0 carries reliable control
## traffic (hello/welcome/reject); channel 1 carries the unreliable-sequenced
## state stream (inputs up, snapshots down).
##
## The host runs the only authoritative SimWorld. Clients rebuild the arena
## locally from the seed + params (ArenaGen is deterministic), then apply
## snapshots on top and dead-reckon between them.

# BUMP THIS on ANY wire-schema change (welcome/snapshot/input fields) —
# the strict equality check is the only thing standing between mixed
# builds and silent desync.
const VERSION := 8

## Callsign whitelist: A-Z 0-9 space dash underscore, max 16, never empty.
## Applied authoritatively on the HOST (clients can send anything) — this is
## what keeps BBCode injection, control characters, and unrenderable glyphs
## out of every scoreboard and kill feed.
## Parse "ip" / "ip:port" (one home for the three places that need it —
## the dedicated server's copy had already drifted a validation guard).
static func parse_addr(txt: String, default_port: int) -> Dictionary:
	var t := txt.strip_edges()
	if t == "":
		return {}
	var ip := t
	var port := default_port
	if ":" in t:
		var parts := t.rsplit(":", false, 1)
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = int(parts[1])
	return {"ip": ip, "port": port}

static func filter_name(raw: String) -> String:
	var up := raw.strip_edges().to_upper()
	var out := ""
	for ch in up:
		var c := ch.unicode_at(0)
		if (c >= 65 and c <= 90) or (c >= 48 and c <= 57) \
				or ch == " " or ch == "-" or ch == "_":
			out += ch
		if out.length() >= 16:
			break
	return out.strip_edges()

static func sanitize_name(raw: String) -> String:
	var out := filter_name(raw)
	return out if out != "" else "PILOT"

enum {
	MSG_HELLO = 1,      ## client -> host: {v, name, spec?}
	MSG_WELCOME = 2,    ## host -> client: {v, id, seed, prm, mode, dif, gen, ros}
	MSG_REJECT = 3,     ## host -> client: {why}
	MSG_INPUT = 4,      ## client -> host: {q, u, t, f, h, m} (q = input sequence)
	MSG_SNAPSHOT = 5,   ## host -> client: see snapshot_of()
	MSG_PING = 6,       ## client -> host: {t} (sender's ticks_msec, echoed back)
	MSG_PONG = 7,       ## host -> client: {t} (echo)
}

const CH_CONTROL := 0
const CH_STATE := 1
const CHANNELS := 2

## Renderer-relevant events forwarded inside snapshots.
const FORWARDED_EVENTS := ["explosion", "hyperspace", "fire", "kill", "respawn"]

static func pack(type: int, payload: Dictionary) -> PackedByteArray:
	return var_to_bytes([type, payload])

## Largest inbound packet the host will deserialize from a client. Client
## hellos/inputs/pings are all well under 1 KB; anything bigger is a large-
## packet DoS attempt and is rejected before bytes_to_var() (issue #13).
const MAX_CLIENT_PACKET := 4096

## Decode a packet. Returns {"type": int, "data": Dictionary} or {} on garbage.
## ``max_bytes`` rejects oversized packets before the expensive bytes_to_var()
## deserialization; the host passes MAX_CLIENT_PACKET, clients keep the larger
## default to allow full snapshots.
static func unpack(bytes: PackedByteArray, max_bytes: int = 1048576) -> Dictionary:
	if bytes.size() > max_bytes:
		return {}
	var v: Variant = bytes_to_var(bytes)
	if typeof(v) != TYPE_ARRAY:
		return {}
	var arr: Array = v
	if arr.size() != 2 or typeof(arr[0]) != TYPE_INT or typeof(arr[1]) != TYPE_DICTIONARY:
		return {}
	return {"type": int(arr[0]), "data": arr[1] as Dictionary}

# --------------------------------------------------------------------------
# Inputs
# --------------------------------------------------------------------------

## Apply a {u, t, f, h} input payload onto a ship for the upcoming step.
static func apply_input(ship: SimShip, inp: Dictionary) -> void:
	ship.in_turn = clampf(float(inp.get("u", 0.0)), -1.0, 1.0)
	ship.in_thrust = bool(inp.get("t", false))
	ship.in_fire = bool(inp.get("f", false))
	ship.in_hyper = bool(inp.get("h", false))
	ship.in_mine = bool(inp.get("m", false))

# --------------------------------------------------------------------------
# Welcome / roster
# --------------------------------------------------------------------------

static func welcome_of(session: GameSession, your_ship_id: int) -> Dictionary:
	var roster := []
	for s in session.world.ships:
		roster.append([s.id, s.team, s.hull_seed, String(session.ship_names.get(s.id, ""))])
	var out := session.world.config.to_wire()
	out.merge({
		"v": VERSION,
		"id": your_ship_id,
		"prm": session.arena_params,
		"mode": session.mode,
		"dif": session.difficulty,
		"gen": session.generation,
		"ros": roster,
	})
	return out

# --------------------------------------------------------------------------
# Snapshots
# --------------------------------------------------------------------------

## Capture the authoritative world state. `thrust_ids` are ships that thrust
## on the most recent step; `events` are one-shots accumulated since the
## previous snapshot (already filtered to FORWARDED_EVENTS); `acks` maps
## player ship id -> last input sequence applied, for client reconciliation.
static func snapshot_of(world: SimWorld, thrust_ids: Array, events: Array,
		acks: Dictionary = {}) -> Dictionary:
	var ships := []
	for s in world.ships:
		ships.append([s.id, s.pos, s.vel, s.angle, s.fuel, s.ammo, 1 if s.alive else 0,
			s.spawn_grace, s.respawn_timer, s.score, s.kills, s.deaths,
			s.hyperspace_cooldown, 1 if s.hyper_chord_prev else 0])
	var torps := []
	for t in world.torpedoes:
		torps.append([t.id, t.owner_id, t.team, t.pos, t.vel, t.age])
	var mines := []
	for m in world.mines:
		mines.append([m.id, m.owner_id, m.team, m.pos, m.vel, m.age])
	var picks := []
	for p in world.pickups:
		picks.append([p.id, p.kind, p.pos, p.vel, p.age])
	var bodies := []
	for b in world.bodies:
		if b.is_orbiting():
			bodies.append([b.id, b.orbit_angle])
	return {
		"k": world.tick, "t": world.time,
		"s": ships, "p": torps, "mn": mines, "pk": picks, "b": bodies,
		"rb": world.removed_body_ids,
		"e": events, "th": thrust_ids, "a": acks,
	}

## Match-flow state rider for snapshots (kept separate from snapshot_of so
## SimWorld stays session-agnostic).
static func match_state_of(session: GameSession) -> Array:
	return [1 if session.match_over else 0, session.restart_timer,
		session.winner_ship, session.winner_team,
		session.match_time, session.time_limit]

static func apply_match_state(session: GameSession, mo: Array) -> void:
	if mo.size() < 4:
		return
	session.match_over = int(mo[0]) == 1
	session.restart_timer = float(mo[1])
	session.winner_ship = int(mo[2])
	session.winner_team = int(mo[3])
	if mo.size() >= 6:
		session.match_time = float(mo[4])
		session.time_limit = float(mo[5])

## Apply a snapshot onto a client-side world. Returns the snapshot's one-shot
## events ("e") and thrusting ship ids ("th") for the renderer.
static func apply_snapshot(world: SimWorld, snap: Dictionary) -> Dictionary:
	world.tick = int(snap.get("k", world.tick))
	world.time = float(snap.get("t", world.time))

	for entry in snap.get("s", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 13:
			continue  # truncated/corrupt entry — skip rather than crash
		var s := world.ship_by_id(int(entry[0]))
		if s == null:
			continue
		s.pos = entry[1]
		s.vel = entry[2]
		s.angle = float(entry[3])
		s.fuel = float(entry[4])
		s.ammo = int(entry[5])
		s.alive = int(entry[6]) == 1
		s.spawn_grace = float(entry[7])
		s.respawn_timer = float(entry[8])
		s.score = int(entry[9])
		s.kills = int(entry[10])
		s.deaths = int(entry[11])
		s.hyperspace_cooldown = float(entry[12])
		if entry.size() >= 14:
			s.hyper_chord_prev = int(entry[13]) == 1

	world.torpedoes.clear()
	for entry in snap.get("p", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 6:
			continue
		var t := SimTorpedo.new()
		t.id = int(entry[0])
		t.owner_id = int(entry[1])
		t.team = int(entry[2])
		t.pos = entry[3]
		t.vel = entry[4]
		t.age = float(entry[5])
		t.life = world.config.torpedo_life
		t.radius = world.config.torpedo_radius
		world.torpedoes.append(t)

	world.mines.clear()
	for entry in snap.get("mn", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 6:
			continue
		var m := SimMine.new()
		m.id = int(entry[0])
		m.owner_id = int(entry[1])
		m.team = int(entry[2])
		m.pos = entry[3]
		m.vel = entry[4]
		m.age = float(entry[5])
		m.life = world.config.mine_life
		m.radius = world.config.mine_radius
		world.mines.append(m)

	world.pickups.clear()
	for entry in snap.get("pk", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 5:
			continue
		var p := SimPickup.new()
		p.id = int(entry[0])
		p.kind = int(entry[1])
		p.pos = entry[2]
		p.vel = entry[3]
		p.age = float(entry[4])
		p.ttl = world.config.pickup_ttl
		p.radius = world.config.pickup_radius
		world.pickups.append(p)

	# Destroyed asteroids: locally-generated arenas lose the same rocks.
	for rid in snap.get("rb", []):
		if not world.removed_body_ids.has(int(rid)):
			var rb := world.body_by_id(int(rid))
			if rb != null:
				world.bodies.erase(rb)
			world.removed_body_ids.append(int(rid))

	for entry in snap.get("b", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 2:
			continue
		var b := world.body_by_id(int(entry[0]))
		if b == null or not b.is_orbiting():
			continue
		b.orbit_angle = float(entry[1])
		var parent := world.body_by_id(b.parent_id)
		if parent != null:
			b.pos = parent.pos + Vector2(cos(b.orbit_angle), sin(b.orbit_angle)) * b.orbit_radius

	return {"e": snap.get("e", []), "th": snap.get("th", []), "a": snap.get("a", {})}

```

## File: `src/net/net_host.gd` — Host-Authoritative Network Host

```gdscript
class_name NetHost
extends RefCounted
## Authoritative game host. Wraps a running GameSession: pumps its transport,
## hands joining players a bot's ship (and hands it back to a bot when they
## leave), applies remote inputs, steps the session, and broadcasts state
## snapshots at a fixed rate.
##
## Runs over either transport: `open()` binds a direct ENet socket (LAN play,
## with UDP discovery advertising) and `open_relay()` registers a room on a
## relay server for internet play (room code via `room_code()`). Peers are
## opaque transport keys. Drive it from the renderer (or a headless test) by
## calling `update(dt, local_input)` once per fixed step.

const DEFAULT_PORT := 24642
const SNAPSHOT_INTERVAL := 1.0 / 20.0

var session: GameSession
var port := DEFAULT_PORT
## Trusted-server mode: a joiner whose name matches a connected player
## KICKS that session (ghost or otherwise) and inherits its ship — score,
## lives, everything. Default OFF: on public servers a name is not an
## identity, and reclaim would let anyone hijack by typing your name.
var reclaim_names := false
var _names_hash := 0          ## last broadcast roster-names hash
var _failure_handled := false ## transport-death cleanup ran
var _ev_tick := -1            ## last world tick whose events were forwarded
var server_name := "XSpaceWar"

var _t = null                 ## duck-typed host transport (direct or relay)
var _open := false
var _peers := {}              ## transport peer key -> ship_id
var _names := {}              ## transport peer key -> player name (survives rebuilds)
var _inputs := {}             ## ship_id -> latest input payload
var _acked := {}              ## ship_id -> highest input sequence received
var _ban_names := {}          ## UPPERCASED banned callsign -> true
var _ban_addrs := {}          ## banned peer address (direct/LAN only) -> true
var aim := AimAnalyzer.new()  ## host-side aim-anomaly heuristics (warnings only)
var _advertiser: LanDiscovery
var _event_accum: Array = []  ## forwarded events since the last snapshot
var _snap_accum := 0.0
var _last_hello_tick := {}    ## remote IP -> sim tick of last processed hello (flood throttle)

# Inbound DoS hardening (issue #13). Loopback/relay are exempt from per-IP
# limits (see _skip_ip_limits) so local play and relay clients are unaffected.
const MAX_PEERS_PER_IP := 4              ## established-connection cap per remote IP
const MAX_PACKETS_PER_PUMP_PER_PEER := 8 ## drop a peer's packet flood within one pump
const MIN_HELLO_GAP_TICKS := 3           ## min sim-ticks between processed hellos per IP
## Largest plausible jump in a client's input sequence. The client increments
## `q` by one per tick and buffers ~120 unacked inputs, so even a multi-second
## packet-loss burst stays well under this. A jump past it is a buggy or hostile
## client (e.g. q=2^31): we refuse to advance _acked that far so it can't pin the
## counter high and make us drop the ship's later legitimate inputs.
const MAX_INPUT_SEQ_GAP := 1024

func _init(p_session: GameSession) -> void:
	session = p_session
	# When the session rebuilds (match restart), every connected player needs
	# a ship in the NEW world and a fresh WELCOME describing it.
	session.on_regenerate = _on_session_rebuilt

func _on_session_rebuilt() -> void:
	if not _open or _peers.is_empty():
		return
	_inputs.clear()
	_acked.clear()
	_ev_tick = -1
	aim.reset()   # ship ids are reassigned in the rebuilt world
	for peer in _peers.keys():
		if int(_peers[peer]) < 0:
			# Spectators just need the new arena recipe.
			_t.send(peer,
				NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, -1)),
				true, NetProtocol.CH_CONTROL)
			continue
		var bot_ids := session.bots.keys()
		if bot_ids.is_empty():
			_reject(peer, "no ship available after restart")
			continue
		var sid: int = bot_ids[0]
		session.bots.erase(sid)
		_peers[peer] = sid
		session.ship_names[sid] = String(_names.get(peer, "PILOT-%d" % sid))
		_t.send(peer,
			NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, sid)),
			true, NetProtocol.CH_CONTROL)

func open(p_port := DEFAULT_PORT, advertise := true, p_server_name := "XSpaceWar",
		bind_address := "*") -> Error:
	port = p_port
	server_name = p_server_name
	_t = DirectHostTransport.new()
	var err: Error = _t.open({"port": port, "bind": bind_address, "max_peers": 32})
	if err != OK:
		return err
	_open = true
	if advertise:
		_advertiser = LanDiscovery.advertiser({
			"name": server_name, "port": port,
			"max": session.num_ships, "mode": session.mode, "players": 1,
		})
	return OK

## Host an internet game through a relay server (see server/relay_main.gd).
func open_relay(relay_ip: String, relay_port: int, p_server_name := "XSpaceWar") -> Error:
	server_name = p_server_name
	_t = RelayHostTransport.new()
	var err: Error = _t.open({"ip": relay_ip, "port": relay_port,
		"name": server_name, "max": session.num_ships, "mode": session.mode})
	if err != OK:
		return err
	_open = true
	return OK

## Relay room code ("" until the relay assigns one / for direct hosting).
func room_code() -> String:
	return _t.room_code() if _open and _t is RelayHostTransport else ""

## True when the transport has irrecoverably failed (e.g. relay link lost).
func transport_failed() -> bool:
	return _open and bool(_t.failed)

func update(dt: float, local_input: Dictionary) -> void:
	if not _open:
		return
	_pump()
	# Relay-link death emits no per-peer disconnects — without this, every
	# joined ship stays assigned to an unreachable peer (stale inputs
	# reapplied forever). Hand them all back to bots once.
	if bool(_t.failed) and not _failure_handled:
		_failure_handled = true
		for peer in _peers.keys():
			_drop_peer(peer)

	# Inputs apply even to dead ships: a dead ship ignores everything but the
	# fire press that requests a respawn (manual_respawn). Stale inputs from a
	# dropped peer are cleared by _drop_peer, so this can't auto-revive ghosts.
	var human := session.human_ship()
	if human != null and not local_input.is_empty():
		NetProtocol.apply_input(human, local_input)
	for sid in _inputs:
		var ship := session.world.ship_by_id(sid)
		if ship != null:
			NetProtocol.apply_input(ship, _inputs[sid])

	session.update(dt)
	# Watch every connected human pilot for impossible aim (warnings, not bans).
	aim.observe(session.world, _watched_ids())

	for ev in session.world.events:
		if int(ev.get("tk", -1)) < _ev_tick:
			continue  # forward exactly once (stamps lag the post-step tick by one)
		if String(ev.get("type", "")) in NetProtocol.FORWARDED_EVENTS:
			_event_accum.append(ev)
	_ev_tick = session.world.tick

	_snap_accum += dt
	if _snap_accum >= SNAPSHOT_INTERVAL:
		_snap_accum = 0.0
		_broadcast_snapshot()

	if _advertiser != null:
		_advertiser.advertise(dt, player_count())
	_t.tick(dt, player_count())

func player_count() -> int:
	# Dedicated servers have no host pilot — count only real humans.
	var n := 1 if session.human_ship_id >= 0 else 0
	for peer in _peers:
		if int(_peers[peer]) >= 0:
			n += 1
	return n

func _spectator_count() -> int:
	var n := 0
	for peer in _peers:
		if int(_peers[peer]) < 0:
			n += 1
	return n

func _broadcast_snapshot() -> void:
	_event_accum = _event_accum.slice(maxi(0, _event_accum.size() - 64))  # bound backlog
	if _peers.is_empty():
		_event_accum.clear()
		return
	var thrust_ids: Array = []
	for ev in session.world.events:
		if String(ev.get("type", "")) == "thrust":
			thrust_ids.append(ev["ship"])
	var snap := NetProtocol.snapshot_of(session.world, thrust_ids, _event_accum, _acked)
	snap["g"] = session.generation
	# Roster names ride snapshots whenever they change (joins, reclaims,
	# restarts) — previously only YOUR OWN welcome carried them, so other
	# players saw newcomers as bot callsigns forever.
	var names_now := hash(session.ship_names)
	if names_now != _names_hash:
		_names_hash = names_now
		snap["nm"] = session.ship_names.duplicate()
	snap["mo"] = NetProtocol.match_state_of(session)
	var bytes := NetProtocol.pack(NetProtocol.MSG_SNAPSHOT, snap)
	_event_accum = []
	for peer in _peers:
		_t.send(peer, bytes, false, NetProtocol.CH_STATE)

func _pump() -> void:
	var per_peer := {}  # peer -> data packets handled this pump (flood cap)
	for ev in _t.poll():
		match String(ev["t"]):
			"connect":
				pass  # ship assigned on MSG_HELLO, not on raw connect
			"disconnect":
				_drop_peer(ev["peer"])
			"data":
				var peer = ev["peer"]
				var n := int(per_peer.get(peer, 0))
				if n >= MAX_PACKETS_PER_PUMP_PER_PEER:
					continue  # this peer is flooding — drop the rest this frame
				per_peer[peer] = n + 1
				_on_packet(peer, ev["bytes"])

## True for addresses we don't apply per-IP limits to: loopback (local play /
## tests) and relay (which hides client addresses as "").
func _skip_ip_limits(addr: String) -> bool:
	return addr == "" or addr == "127.0.0.1" or addr == "::1"

func _on_packet(peer, bytes: PackedByteArray) -> void:
	var msg := NetProtocol.unpack(bytes, NetProtocol.MAX_CLIENT_PACKET)
	if msg.is_empty():
		return
	var data: Dictionary = msg["data"]
	match int(msg["type"]):
		NetProtocol.MSG_HELLO:
			_on_hello(peer, data)
		NetProtocol.MSG_PING:
			_t.send(peer, NetProtocol.pack(NetProtocol.MSG_PONG, data),
				true, NetProtocol.CH_CONTROL)
		NetProtocol.MSG_INPUT:
			if _peers.has(peer):
				var sid: int = _peers[peer]
				if sid < 0:
					return  # spectators don't drive ships
				var q := int(data.get("q", 0))
				var last := int(_acked.get(sid, -1))
				# Accept the first input, an in-order advance within a sane
				# window (tolerates packet loss), or a far-below value — the
				# latter is a sequence reset (rejoin / match restart), so we
				# re-base to it rather than ignore the ship forever. A jump far
				# PAST `last` is refused: see MAX_INPUT_SEQ_GAP.
				if last < 0 \
						or (q >= last and q - last <= MAX_INPUT_SEQ_GAP) \
						or (last - q > MAX_INPUT_SEQ_GAP):
					_acked[sid] = q
					_inputs[sid] = data

## Dedicated-server mode: the host machine flies nothing — its pilot slot
## becomes one more bot for joiners to take over. Call again after each
## auto-restart (regeneration recreates the human slot).
static func convert_to_dedicated(p_session: GameSession) -> void:
	p_session.dedicated = true   # rebuilds keep every slot botted (no kick on restart)
	var hid := p_session.human_ship_id
	if hid < 0:
		return
	p_session.human_ship_id = -1
	var hship := p_session.world.ship_by_id(hid)
	if hship == null:
		return
	p_session.bots[hid] = BotController.new(p_session.world, hid, p_session.difficulty)
	p_session.ship_names[hid] = BotController.callsign(hship.hull_seed)

func _on_hello(peer, data: Dictionary) -> void:
	if _peers.has(peer):
		return
	if int(data.get("v", -1)) != NetProtocol.VERSION:
		_reject(peer, "protocol version mismatch")
		return
	# Banned callsign or address (direct/LAN) — turned away before any slot.
	if _is_banned(peer, String(data.get("name", ""))):
		_reject(peer, "You are banned from this server.")
		return
	# Inbound DoS hardening (issue #13), direct/LAN only — relay/loopback exempt.
	var addr := _peer_addr(peer)
	if not _skip_ip_limits(addr):
		# Throttle rapid reconnect/hello spam from one address.
		var now_tick := session.world.tick
		if now_tick - int(_last_hello_tick.get(addr, -1000000)) < MIN_HELLO_GAP_TICKS:
			_reject(peer, "connecting too fast")
			return
		_last_hello_tick[addr] = now_tick
		# Cap simultaneous connections from one address (anti connection-flood).
		var same_ip := 0
		for p in _peers:
			if _peer_addr(p) == addr:
				same_ip += 1
		if same_ip >= MAX_PEERS_PER_IP:
			_reject(peer, "too many connections from your address")
			return
	# Spectators get snapshots but no ship (sid -1).
	if bool(data.get("spec", false)):
		if _spectator_count() >= 8:
			_reject(peer, "spectator slots full")
			return
		_peers[peer] = -1
		_t.send(peer,
			NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, -1)),
			true, NetProtocol.CH_CONTROL)
		return
	# A joining player takes over a bot's ship; no bots left = server full.
	var bot_ids := session.bots.keys()
	if bot_ids.is_empty():
		_reject(peer, "server full")
		return
	var sid: int = bot_ids[0]
	session.bots.erase(sid)
	_peers[peer] = sid
	var pname := NetProtocol.sanitize_name(String(data.get("name", "")))
	if pname == "":
		pname = "PILOT-%d" % sid
	# Trusted reclaim: same name = same pilot. Kick the old session (a
	# ghost that hasn't timed out, usually) and hand over its ship intact.
	if reclaim_names:
		for old_peer in _peers.keys():
			if String(_names.get(old_peer, "")).to_upper() == pname.to_upper() \
					and int(_peers[old_peer]) >= 0:
				var keep_sid: int = _peers[old_peer]
				_t.kick(old_peer)
				_peers.erase(old_peer)
				_names.erase(old_peer)
				_inputs.erase(keep_sid)
				_acked.erase(keep_sid)
				_peers[peer] = keep_sid
				_names[peer] = pname
				session.ship_names[keep_sid] = pname
				# Give back the bot ship we grabbed before matching: without
				# this every reclaim orphaned one slot for the whole match.
				session.bots[sid] = BotController.new(session.world, sid, session.difficulty)
				_t.send(peer, NetProtocol.pack(NetProtocol.MSG_WELCOME,
					NetProtocol.welcome_of(session, keep_sid)), true, NetProtocol.CH_CONTROL)
				return
	# A name already on the roster (live player, ghost not yet timed out,
	# or a bot callsign) gets a random four-digit tag: PILOT-4827.
	var taken := {}
	for n in session.ship_names.values():
		taken[String(n).to_upper()] = true
	if taken.has(pname.to_upper()):
		var base := pname.left(11)   # tag fits the 16-char name invariant
		var tagged := pname
		while taken.has(tagged.to_upper()):
			tagged = "%s-%04d" % [base, randi_range(0, 9999)]
		pname = tagged
	_names[peer] = pname
	session.ship_names[sid] = pname
	_t.send(peer,
		NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, sid)),
		true, NetProtocol.CH_CONTROL)

func _reject(peer, why: String) -> void:
	_t.send(peer, NetProtocol.pack(NetProtocol.MSG_REJECT, {"why": why}),
		true, NetProtocol.CH_CONTROL)
	# Forget the peer NOW: a reject mid-rebuild otherwise leaves a stale
	# old-generation sid in _peers, and the kick's later disconnect event
	# would hand that sid "back" to a bot — hijacking whichever live ship
	# owns the id in the new world.
	var sid: int = _peers.get(peer, -1)
	_peers.erase(peer)
	_names.erase(peer)
	if sid >= 0:
		_inputs.erase(sid)
		_acked.erase(sid)
	_t.kick(peer)

func _drop_peer(peer) -> void:
	if not _peers.has(peer):
		return
	var sid: int = _peers[peer]
	_peers.erase(peer)
	_names.erase(peer)
	if sid < 0:
		return  # spectator: nothing to hand back
	_inputs.erase(sid)
	_acked.erase(sid)
	aim.forget(sid)   # drop the departed pilot's aim tallies
	# Hand the ship back to a bot (with its own callsign again).
	session.bots[sid] = BotController.new(session.world, sid, session.difficulty)
	var ship := session.world.ship_by_id(sid)
	session.ship_names[sid] = BotController.callsign(ship.hull_seed) if ship != null else ""

# --------------------------------------------------------------------------
# Moderation (host kick / ban). The architecture is already host-authoritative
# — this is the removal lever the host UI and the dedicated console drive.
# Names are not identities (a kicked griefer can rename and rejoin), so a ban
# also pins the peer's address WHEN the transport exposes one (direct/LAN); on
# the relay only the name is bannable. Deliberately commodity-grade — see #4.
# --------------------------------------------------------------------------

## Real (non-spectator) players currently connected, sorted by ship id:
## [{"sid": int, "name": String}]. The host UI lists these.
func connected_players() -> Array:
	var out: Array = []
	for peer in _peers:
		var sid: int = _peers[peer]
		if sid >= 0:
			out.append({"sid": sid,
				"name": String(_names.get(peer, session.ship_names.get(sid, "PILOT-%d" % sid)))})
	out.sort_custom(func(a, b): return int(a["sid"]) < int(b["sid"]))
	return out

func _peer_for_ship(sid: int):
	for peer in _peers:
		if int(_peers[peer]) == sid:
			return peer
	return null

## Ship ids of the connected human pilots — who the aim analyzer watches.
func _watched_ids() -> Array:
	var ids: Array = []
	for peer in _peers:
		if int(_peers[peer]) >= 0:
			ids.append(int(_peers[peer]))
	return ids

## Aim-anomaly surface for the host UI / dedicated console.
func aim_report() -> Array:
	return aim.report()

func is_aim_flagged(sid: int) -> bool:
	return aim.is_flagged(sid)

func aim_reasons(sid: int) -> Array:
	return aim.reasons_for(sid)

func _peer_addr(peer) -> String:
	return String(_t.peer_address(peer)) if _t != null and _t.has_method("peer_address") else ""

## Remove the player flying `sid`. `ban` also blocks their callsign (and
## address, on direct/LAN) from rejoining. Returns true if someone was removed.
func kick_ship(sid: int, reason := "Kicked by the host.", ban := false) -> bool:
	var peer = _peer_for_ship(sid)
	if peer == null:
		return false
	if ban:
		_ban_peer(peer)
	# REJECT rides a reliable channel and kick() flushes before disconnecting,
	# so the leaver sees WHY; _drop_peer hands the ship back to a fresh bot.
	_t.send(peer, NetProtocol.pack(NetProtocol.MSG_REJECT, {"why": reason}),
		true, NetProtocol.CH_CONTROL)
	_drop_peer(peer)
	_t.kick(peer)
	return true

## Kick every connected player whose callsign matches (case-insensitive) — the
## dedicated console's `/kick NAME`. Returns how many were removed. With
## `ban`, also blocks the name for absent griefers.
func kick_name(name: String, ban := false) -> int:
	var up := name.strip_edges().to_upper()
	var hits: Array[int] = []
	for p in connected_players():
		if String(p["name"]).to_upper() == up:
			hits.append(int(p["sid"]))
	var reason := "Banned by the host." if ban else "Kicked by the host."
	var n := 0
	for s in hits:
		if kick_ship(s, reason, ban):
			n += 1
	if ban:
		ban_name(name)
	return n

func ban_name(name: String) -> void:
	var up := NetProtocol.filter_name(name).to_upper()
	if up != "":
		_ban_names[up] = true

func unban_name(name: String) -> bool:
	return _ban_names.erase(NetProtocol.filter_name(name).to_upper())

func ban_list() -> Array:
	return _ban_names.keys()

func _ban_peer(peer) -> void:
	var nm := String(_names.get(peer, ""))
	if nm != "":
		_ban_names[nm.to_upper()] = true
	var addr := _peer_addr(peer)
	if addr != "":
		_ban_addrs[addr] = true

## True if this joiner is banned — by the callsign they asked for (matched
## against the sanitized request, not the post-tag name) or by address.
func _is_banned(peer, requested_name: String) -> bool:
	if _peer_addr(peer) in _ban_addrs and not _ban_addrs.is_empty():
		return true
	var up := NetProtocol.filter_name(requested_name).to_upper()
	return up != "" and _ban_names.has(up)

func close() -> void:
	if not _open:
		return
	for peer in _peers:
		_t.kick(peer)
	_t.close()
	_open = false
	_peers.clear()
	_inputs.clear()
	_acked.clear()
	if _advertiser != null:
		_advertiser.close()
		_advertiser = null

```

## File: `src/gameplay/aim_analyzer.gd` — Aim Anomaly Heuristics

```gdscript
class_name AimAnalyzer
extends RefCounted
## Host-side aim-anomaly heuristics (issue #4). The host runs the authoritative
## sim and sees every input, so it can watch for statistically impossible play:
##   * near-zero aim variance — shots that are perfectly on-target far more
##     often than a human hand manages while both ships maneuver;
##   * sub-human acquisition — firing within the human reaction floor of a
##     target first entering the aim cone;
##   * seam tracking — aim that stays glued to a target as it teleports across
##     the toroidal wrap edge (a human loses it for a beat).
##
## This NEVER bans. It raises a host-side warning a human reviews — and here a
## flag is genuinely just a prompt to look: perfect input isn't even winning
## play (a frame-perfect bot went 1W-9L vs Veterans), so anomalous aim is a
## curiosity, not a verdict. Thresholds are deliberately conservative and only
## trip on a meaningful sample. Feed it one authoritative step at a time via
## observe(); read report()/flagged() for the surface.

const FIRE_CONE := deg_to_rad(12.0)   ## "on target" cone, for acquisition timing
const TIGHT_AIM := deg_to_rad(3.0)    ## a near-perfect firing solution
const REACTION_TICKS := 7             ## ~117ms @60Hz — below the human floor
const MIN_SHOTS := 20                 ## never flag on thin data
const TIGHT_FRAC_FLAG := 0.9          ## >=90% sub-3 degree shots = inhuman
const FAST_FRAC_FLAG := 0.5           ## >=50% shots inside the reaction floor
const SEAM_FLAG := 3                  ## locked aim across N wrap seams

## Per-ship running tallies (kept tiny — sums, not sample arrays).
class Track:
	var shots := 0
	var tight_shots := 0
	var fast_acquire := 0
	var seam_locks := 0
	var err_sum := 0.0
	var err_sqsum := 0.0
	var target := -1            ## ship currently held in the aim cone (-1 = none)
	var cone_since := -1        ## world tick that target entered the cone
	var cur_err := PI           ## this tick's aim error, stashed for fire matching
	var last_target := -1
	var last_target_pos := Vector2.ZERO
	var has_last := false

var _tracks := {}              ## ship_id -> Track
var _seen_tick := -1
var _fire_tick := -1           ## highest fire-event tick already counted

func _track(sid: int) -> Track:
	if not _tracks.has(sid):
		_tracks[sid] = Track.new()
	return _tracks[sid]

## Observe one authoritative step. `player_ids` are the human-controlled ships
## to watch (bots are never suspects). Idempotent per world tick; safe to call
## every host update.
func observe(world: SimWorld, player_ids: Array) -> void:
	if world == null or world.tick == _seen_tick:
		return
	_seen_tick = world.tick
	var size := world.config.arena_size
	var wrap := world.config.wrap_edges
	var watch := {}
	for sid in player_ids:
		watch[int(sid)] = true

	# 1) Aim geometry, cone-acquisition clock, and seam-lock detection.
	for sid in watch:
		var s := world.ship_by_id(int(sid))
		var tr := _track(int(sid))
		if s == null or not s.alive:
			tr.target = -1; tr.cone_since = -1; tr.has_last = false
			continue
		var e := _nearest_enemy(world, s)
		if e == null:
			tr.target = -1; tr.cone_since = -1; tr.has_last = false
			continue
		var d := _delta(s.pos, e.pos, size, wrap)
		var err := absf(angle_difference(s.angle, d.angle()))
		tr.cur_err = err
		if err <= FIRE_CONE:
			if tr.target != e.id or tr.cone_since < 0:
				tr.target = e.id
				tr.cone_since = world.tick
		else:
			tr.target = -1
			tr.cone_since = -1
		# Seam lock: the target jumped across a wrap edge this tick, yet aim
		# stayed tight on it — a human can't follow through the seam instantly.
		if wrap and tr.has_last and tr.last_target == e.id:
			var raw := e.pos - tr.last_target_pos
			if (absf(raw.x) > size * 0.5 or absf(raw.y) > size * 0.5) and err <= TIGHT_AIM:
				tr.seam_locks += 1
		tr.last_target = e.id
		tr.last_target_pos = e.pos
		tr.has_last = true

	# 2) Score each new fire as an aim sample (events accumulate -> dedup by tick).
	for ev in world.events:
		var tk := int(ev.get("tk", -1))
		if tk <= _fire_tick or String(ev.get("type", "")) != "fire":
			continue
		var fsid := int(ev.get("ship", -1))
		if not watch.has(fsid):
			continue
		var tr: Track = _tracks.get(fsid)
		if tr == null:
			continue
		var err: float = tr.cur_err
		tr.shots += 1
		tr.err_sum += err
		tr.err_sqsum += err * err
		if err <= TIGHT_AIM:
			tr.tight_shots += 1
		if tr.cone_since >= 0 and (world.tick - tr.cone_since) < REACTION_TICKS:
			tr.fast_acquire += 1
	_fire_tick = world.tick - 1   # fire events stamp the pre-increment tick

## Per-watched-player suspicion summary, sorted by ship id. Each entry:
##   {sid, shots, aim_mean_deg, aim_sd_deg, tight_frac, fast_frac, seam_locks,
##    flagged: bool, reasons: Array[String]}
func report() -> Array:
	var out: Array = []
	for sid in _tracks:
		var tr: Track = _tracks[sid]
		if tr.shots == 0 and tr.seam_locks == 0:
			continue
		var n := maxi(1, tr.shots)
		var mean := tr.err_sum / n
		var variance := maxf(0.0, tr.err_sqsum / n - mean * mean)
		var tight_frac := float(tr.tight_shots) / n
		var fast_frac := float(tr.fast_acquire) / n
		var reasons: Array[String] = []
		if tr.shots >= MIN_SHOTS and tight_frac >= TIGHT_FRAC_FLAG:
			reasons.append("inhuman aim — %.0f%% of %d shots under 3 degrees" % [tight_frac * 100.0, tr.shots])
		if tr.shots >= MIN_SHOTS and fast_frac >= FAST_FRAC_FLAG:
			reasons.append("sub-human acquisition — %.0f%% of shots under %dms" % [fast_frac * 100.0, int(REACTION_TICKS * 1000.0 / 60.0)])
		if tr.seam_locks >= SEAM_FLAG:
			reasons.append("aim tracked a target through %d wrap seams" % tr.seam_locks)
		out.append({
			"sid": sid, "shots": tr.shots,
			"aim_mean_deg": rad_to_deg(mean), "aim_sd_deg": rad_to_deg(sqrt(variance)),
			"tight_frac": tight_frac, "fast_frac": fast_frac, "seam_locks": tr.seam_locks,
			"flagged": not reasons.is_empty(), "reasons": reasons,
		})
	out.sort_custom(func(a, b): return int(a["sid"]) < int(b["sid"]))
	return out

## Only the flagged players — the host warning surface.
func flagged() -> Array:
	return report().filter(func(r): return bool(r["flagged"]))

## True if this ship currently trips any heuristic (cheap lookup for UI rows).
func is_flagged(sid: int) -> bool:
	for r in report():
		if int(r["sid"]) == sid:
			return bool(r["flagged"])
	return false

## Reasons this ship is flagged (empty if clean / unknown).
func reasons_for(sid: int) -> Array:
	for r in report():
		if int(r["sid"]) == sid:
			return r["reasons"]
	return []

## Drop a ship's tallies — call when a player leaves or is removed.
func forget(sid: int) -> void:
	_tracks.erase(sid)

## Wipe everything — call on a match rebuild (ship ids are reassigned).
func reset() -> void:
	_tracks.clear()
	_seen_tick = -1
	_fire_tick = -1

func _nearest_enemy(world: SimWorld, s: SimShip) -> SimShip:
	var best: SimShip = null
	var best_d := INF
	var size := world.config.arena_size
	var wrap := world.config.wrap_edges
	for o in world.ships:
		if o == s or not o.alive:
			continue
		if s.team >= 0 and o.team == s.team:
			continue   # teammate
		var d := _delta(s.pos, o.pos, size, wrap).length_squared()
		if d < best_d:
			best_d = d
			best = o
	return best

## Shortest vector from -> to, taking the toroidal wrap when it is enabled.
func _delta(from: Vector2, to: Vector2, size: float, wrap: bool) -> Vector2:
	var d := to - from
	if wrap:
		if absf(d.x) > size * 0.5:
			d.x -= signf(d.x) * size
		if absf(d.y) > size * 0.5:
			d.y -= signf(d.y) * size
	return d

```

## File: `src/gameplay/ai/bot_behaviors.gd` — AI Bot Behaviors & Difficulty

```gdscript
class_name BotBehaviors
## Priority-ordered steering behaviors for BotController, extracted from the
## _decide() priority chain (issue #21).
##
## Evaluated in order with EARLY-EXIT — deliberately NOT utility scoring. The
## chain's RNG draws are CONDITIONAL (the chase roll fires only when a target
## exists; the approach-thrust roll only when out of range), so scoring every
## behavior each tick would change RNG consumption and break determinism.
##
## Each behavior's decide(bot, ship, ctx) returns true to CLAIM the decision
## (setting bot._want_angle / bot._want_thrust) or false to defer to the next.
## ctx carries the per-tick reads {primary, star_pos, star_r, dist_star, aggr,
## target} so behaviors don't recompute them. (bot/ship are left untyped to
## avoid a cyclic class dependency with BotController.)

## 0.5) Lethal boundary: never fly off the map — burn back toward the well.
class Boundary extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		if not bot.world.config.lethal_edges:
			return false
		var half: float = bot.world.config.arena_size * 0.5
		var ahead: Vector2 = ship.pos + ship.vel * 1.5
		if absf(ahead.x) > half - 300.0 or absf(ahead.y) > half - 300.0:
			bot._want_angle = TorusMath.shortest_delta(ship.pos, ctx["star_pos"],
				bot.world.config.arena_size).angle()
			bot._want_thrust = true
			return true
		return false

## 1) Survival: Veteran+ pilots dodge an imminent body or armed mine.
class HazardDodge extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		if bot.difficulty < BotController.Difficulty.VETERAN:
			return false
		var hz_pos := Vector2.INF
		var hazard = bot._imminent_hazard(ship)
		if hazard != null:
			hz_pos = hazard.pos
		else:
			var mz = bot._imminent_mine(ship)
			if mz != null:
				hz_pos = mz.pos
		if hz_pos.is_finite():
			var lateral := Vector2(-ship.vel.y, ship.vel.x).normalized()
			if lateral.dot(TorusMath.shortest_delta(ship.pos, hz_pos,
					bot.world.config.arena_size)) > 0.0:
				lateral = -lateral
			bot._want_angle = lateral.angle()
			bot._want_thrust = true
			return true
		return false

## 1) Survival: everyone burns away from the star's kill zone.
class StarEscape extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		if float(ctx["dist_star"]) < float(ctx["star_r"]) + 260.0:
			bot._want_angle = TorusMath.shortest_delta(ctx["star_pos"], ship.pos,
				bot.world.config.arena_size).angle()
			bot._want_thrust = true
			return true
		return false

## 1.6) Fear: timid pilots flee nearby ships (snapping shots via _apply).
class Fear extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		var target = ctx["target"]
		if target != null:
			var dist_t: float = sqrt(TorusMath.distance_squared(ship.pos, target.pos,
				bot.world.config.arena_size))
			var flee_r := lerpf(1500.0, 0.0, float(ctx["aggr"]))
			if dist_t < flee_r:
				bot._want_angle = TorusMath.shortest_delta(target.pos, ship.pos,
					bot.world.config.arena_size).angle() + bot._aim_noise
				bot._want_thrust = true
				return true
		return false

## 1.7) Logistics: detour to a nearby supply drop when not already engaged.
class Logistics extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		var target = ctx["target"]
		if target == null or TorusMath.distance_squared(ship.pos, target.pos,
				bot.world.config.arena_size) > bot._fire_range * bot._fire_range:
			var want_pickup = bot._wanted_pickup(ship)
			if want_pickup != null:
				var lead: Vector2 = TorusMath.shortest_delta(ship.pos, want_pickup.pos,
					bot.world.config.arena_size) + want_pickup.vel * 0.4
				bot._want_angle = lead.angle()
				bot._want_thrust = true
				return true
		return false

## 1.8) Patrol the preferred ring unless we roll to chase. The chase roll
## consumes RNG ONLY when a target exists (short-circuit preserved exactly).
class Patrol extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		var target = ctx["target"]
		var chase: bool = target != null and bot._rng.randf() < maxf(0.12, float(ctx["aggr"]))
		if target == null or not chase:
			var want_r: float = bot._roam_radius(float(ctx["star_r"]))
			var dist_now := maxf(1.0, float(ctx["dist_star"]))
			if absf(dist_now - want_r) > 280.0:
				var dir: Vector2 = TorusMath.shortest_delta(ctx["star_pos"], ship.pos,
					bot.world.config.arena_size) / dist_now
				var ring_point: Vector2 = ctx["star_pos"] + dir.rotated(0.55) * want_r
				bot._want_angle = TorusMath.shortest_delta(ship.pos, ring_point,
					bot.world.config.arena_size).angle()
				bot._want_thrust = true
			else:
				bot._want_angle = ship.vel.angle()
				bot._want_thrust = ship.vel.length() < 120.0
			return true
		return false  # chasing — RNG already drawn; defer to LeadAimRange

## 2-3) Terminal: lead-aim the target with range/slingshot management. Only
## reached when Patrol deferred (target != null and chase succeeded).
class LeadAimRange extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		var target = ctx["target"]
		var rel: Vector2 = TorusMath.shortest_delta(ship.pos, target.pos,
			bot.world.config.arena_size)
		var aim := Vector2.from_angle(bot._lead_angle(ship, target))
		bot._want_angle = aim.angle() + bot._aim_noise
		var dist := rel.length()
		if bot._sling > 0.0 and dist > bot._preferred_range * 1.7 and ctx["primary"] != null:
			var away := TorusMath.shortest_delta(ship.pos, ctx["star_pos"],
				bot.world.config.arena_size).normalized()
			var blended := aim.normalized().lerp(away, bot._sling)
			bot._want_angle = blended.angle() + bot._aim_noise
		# Approach-thrust roll consumes RNG ONLY when out of range (short-circuit).
		bot._want_thrust = dist > bot._preferred_range and bot._rng.randf() < maxf(0.15, float(ctx["aggr"]))
		return true

## Build the cascade in priority order (one instance set per bot).
static func make_cascade() -> Array:
	return [Boundary.new(), HazardDodge.new(), StarEscape.new(), Fear.new(),
		Logistics.new(), Patrol.new(), LeadAimRange.new()]

```

## File: `server/dedicated_main.gd` — Dedicated Server & Moderation Console

```gdscript
extends SceneTree
## Standalone DEDICATED GAME SERVER — the authoritative host with no human
## pilot, for a VPS or spare box. Players join over LAN, direct IP, or a
## relay; bots hold every slot until a human takes it (and resume when they
## leave a match restart later). Run:
##
##   godot --headless --path . --script res://server/dedicated_main.gd -- \
##       --port 24642 --name "Nebraska Arena" --ships 12 --score 15
##
## Options (all optional):
##   --port N         UDP game port (default 24642)
##   --relay ip[:p]   ALSO register on a relay so internet players can join
##   --name S         server name in browsers (default "Dedicated Arena")
##   --ships N        roster size 2-16 (default 12)
##   --mode ffa|team  (default ffa)        --diff 0-3      (default 1 Veteran)
##   --preset classic_ffa|quick_skirmish|team_battle|survival
##   --pace 60-100   flight pace in 5% steps (overrides the preset)
##   --score N        first-to-N, 0=endless (default 10)
##   --time MIN       match clock, 0=off    --lives N       0=unlimited
##   --hazard 0-100   asteroid level        --star 5-100    star size (25=classic)
##   --planets 0-12   (default 2)           --map 4000-160000 arena edge
##   --respawn SEC    1-15 (default 4)      --edges          lethal boundary
##   --reclaim        TRUSTED servers: rejoining with the same name kicks
##                    the old session (ghosts) and inherits its ship/score.
##                    Leave OFF for public servers — names are not identity.
##   --ban NAME       Ban a callsign at boot (repeatable; also accepts a
##                    comma-separated list). --banfile PATH loads one per line
##                    AND is rewritten when bans change, so console ban/unban
##                    persist across restarts (the file is the ban store).
##   --record [DIR]   Record every match as a bit-exact replay for cheating
##                    adjudication (DIR default user://replays, see #4).
##
## Live moderation console (when stdin is a terminal): type `help`, or
##   kick <name> | ban <name> | unban <name> | players | watch | bans
## (`watch` lists pilots the aim-anomaly heuristics flagged — warnings only.)

var host: NetHost
var session := GameSession.new()
var _last_usec := 0
var _status_accum := 0.0
var _accum := 0.0
var _announced_code := false
var _seen_gen := -1
# Live moderation console (background stdin reader -> command queue).
var _console: Thread
var _cmd_mutex := Mutex.new()
var _cmd_queue: Array = []
# Replay-based adjudication: record every match to disk as evidence (#4).
var _record := false
var _record_dir := "user://replays"
var _record_gen := -1
# --banfile doubles as the persistent ban store: loaded at boot, rewritten on
# every console ban/unban so runtime moderation survives a restart ("" = none).
var _banfile := ""

func _initialize() -> void:
	var a := {}
	var bans: Array[String] = []
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i].begins_with("--"):
			var key := args[i].substr(2)
			var val: String = args[i + 1] if i + 1 < args.size() else "1"
			if key == "ban":
				bans.append(val)   # repeatable; comma-lists split later
			else:
				a[key] = val

	if a.has("preset"):
		MatchPresets.apply(session, String(a["preset"]))
	if a.has("score"):
		session.score_limit = int(a["score"])
	if a.has("time"):
		session.time_limit = float(a["time"]) * 60.0
	if a.has("lives"):
		session.lives = int(a["lives"])
	if a.has("hazard"):
		session.hazard = clampf(float(a["hazard"]) / 100.0, 0.0, 1.0)
	if a.has("star"):
		session.star_scale = clampf(float(a["star"]) / 25.0, 0.2, 4.0)
	if a.has("planets"):
		session.planet_count = int(a["planets"])
	if a.has("map"):
		session.map_size = clampf(float(a["map"]), 4000.0, 160000.0)
	if a.has("respawn"):
		session.respawn_seconds = float(a["respawn"])
	if a.has("pace"):
		session.flight_pace = clampf(float(a["pace"]), 60.0, 100.0)
	if a.has("edges"):
		session.lethal_edges = true
	var mode := session.mode
	if a.has("mode"):
		mode = GameSession.Mode.TEAM if String(a["mode"]) == "team" else GameSession.Mode.FFA
	var ships := session.num_ships if a.has("preset") else 12
	if a.has("ships"):
		ships = clampi(int(a["ships"]), 2, 16)
	var diff := session.difficulty if a.has("preset") else BotController.Difficulty.VETERAN
	if a.has("diff"):
		diff = clampi(int(a["diff"]), 0, 3)
	session.start_skirmish(ships, mode, diff)
	NetHost.convert_to_dedicated(session)
	_seen_gen = session.generation

	host = NetHost.new(session)
	host.reclaim_names = a.has("reclaim")
	var server_name := String(a.get("name", "Dedicated Arena"))
	var err: Error
	if a.has("relay"):
		var addr := NetProtocol.parse_addr(String(a["relay"]), RelayProtocol.DEFAULT_PORT)
		err = host.open_relay(String(addr.get("ip", "")), int(addr.get("port", RelayProtocol.DEFAULT_PORT)), server_name)
		if err == OK:
			print("dedicated: hosting via relay %s:%d" % [String(addr.get("ip", "")),
				int(addr.get("port", RelayProtocol.DEFAULT_PORT))])
	else:
		var port := int(a.get("port", str(NetHost.DEFAULT_PORT)))
		err = host.open(port, true, server_name)
		if err == OK:
			print("dedicated: hosting on UDP %d" % port)
	if err != OK:
		printerr("dedicated: failed to open transport (error %d)" % err)
		quit(1)
		return
	print("dedicated: '%s' — %d slots, mode %s, score %d, lives %d" % [server_name,
		session.num_ships, "TEAM" if mode == GameSession.Mode.TEAM else "FFA",
		session.score_limit, session.lives])
	# Replay-based adjudication: record every match as bit-exact evidence (#4).
	_record = a.has("record")
	if _record:
		var rd := String(a.get("record", ""))
		if rd != "" and rd != "1" and not rd.begins_with("--"):
			_record_dir = rd
		DirAccess.make_dir_recursive_absolute(_record_dir)
		print("dedicated: recording matches to %s (cheating-adjudication evidence)" % _record_dir)
		_maybe_start_recording()
	# Moderation: seed the ban list, then open the live stdin console.
	_banfile = String(a.get("banfile", ""))
	_seed_bans(bans, _banfile)
	_start_console()
	_last_usec = Time.get_ticks_usec()
	process_frame.connect(_tick)

func _tick() -> void:
	var now := Time.get_ticks_usec()
	var wall := clampf(float(now - _last_usec) / 1_000_000.0, 0.0, 0.25)
	_last_usec = now
	# Fixed-step accumulator: the deterministic sim integrates ONLY whole
	# fixed_dt steps — exactly like the GUI host's _physics_process — so
	# client prediction reconciles against identical integration.
	_accum = minf(_accum + wall, 0.25)
	var fixed: float = session.world.config.fixed_dt
	while _accum >= fixed:
		host.update(fixed, {})
		_accum -= fixed
	# Auto-restarts: the session.dedicated flag keeps rebuilds all-bot, so
	# this is just bookkeeping/logging now.
	_drain_commands()
	# Rotate replay evidence across auto-restarts (mirror of the GUI host).
	if _record and (session.finished_recorder != null \
			or (session.recorder != null and session.generation != _record_gen)):
		_finalize_recording()
		_maybe_start_recording()
	if session.generation != _seen_gen:
		_seen_gen = session.generation
		print("dedicated: new match (gen %d)" % session.generation)
	if not _announced_code and host.room_code() != "":
		_announced_code = true
		print("dedicated: ROOM CODE %s — share this with players" % host.room_code())
	_status_accum += wall
	if _status_accum >= 30.0:
		_status_accum = 0.0
		print("dedicated: players %d  tick %d  gen %d  room %s" % [host.player_count(),
			session.world.tick, session.generation,
			host.room_code() if host.room_code() != "" else "-"])
		var ps := host.connected_players()
		if not ps.is_empty():
			var names: Array[String] = []
			for p in ps:
				names.append("%s[%d]" % [String(p["name"]), int(p["sid"])])
			print("dedicated: connected — %s" % ", ".join(names))
	OS.delay_msec(4)  # service loop; the accumulator owns sim timing

# --------------------------------------------------------------------------
# Moderation console + ban seeding + replay evidence
# --------------------------------------------------------------------------

## Seed the host ban list from --ban (comma-lists ok) and an optional --banfile
## (one callsign per line, # comments allowed).
func _seed_bans(bans: Array, banfile: String) -> void:
	var n := 0
	for entry in bans:
		for nm in String(entry).split(",", false):
			if String(nm).strip_edges() != "":
				host.ban_name(String(nm)); n += 1
	if banfile != "":
		var f := FileAccess.open(banfile, FileAccess.READ)
		if f == null:
			printerr("dedicated: cannot read banfile %s" % banfile)
		else:
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line != "" and not line.begins_with("#"):
					host.ban_name(line); n += 1
	if n > 0:
		print("dedicated: %d ban(s) seeded — %s" % [n, str(host.ban_list())])

## Rewrite the banfile with the current ban list so console ban/unban survive a
## restart. No-op unless --banfile was given — that file IS the persistence
## store (read at boot by _seed_bans, written here on change). Address bans are
## transport-ephemeral by nature and intentionally not persisted; callsign bans
## are the portable identity.
func _persist_bans() -> void:
	if _banfile == "":
		return
	var f := FileAccess.open(_banfile, FileAccess.WRITE)
	if f == null:
		printerr("dedicated: cannot write banfile %s (runtime bans won't persist)" % _banfile)
		return
	f.store_line("# XSpaceWar-AI ban list — one callsign per line, rewritten on change.")
	for nm in host.ban_list():
		f.store_line(String(nm))
	f.close()

## Start the background stdin reader. It blocks on input; lines land on a
## queue drained by _tick. EOF (piped/no-tty input) just ends the thread.
func _start_console() -> void:
	_console = Thread.new()
	_console.start(_console_loop)
	print("dedicated: console — kick <name> | ban <name> | unban <name> | players | watch | bans | help")

func _console_loop() -> void:
	while true:
		var line := OS.read_string_from_stdin(1024)
		if line == "":
			break  # EOF: no interactive terminal, so no console
		line = line.strip_edges()
		if line == "":
			continue
		_cmd_mutex.lock()
		_cmd_queue.append(line)
		_cmd_mutex.unlock()

func _drain_commands() -> void:
	_cmd_mutex.lock()
	var cmds := _cmd_queue.duplicate()
	_cmd_queue.clear()
	_cmd_mutex.unlock()
	for line in cmds:
		_run_command(String(line))

func _run_command(line: String) -> void:
	if line.begins_with("/"):
		line = line.substr(1)
	var parts := line.split(" ", false, 1)
	if parts.is_empty():
		return  # blank / whitespace-only line — nothing to run. The console loop
		# already skips these; guard the entry point so any direct/empty call is
		# crash-safe ("".split(" ", false) yields an empty array).
	var cmd := String(parts[0]).to_lower()
	var arg: String = String(parts[1]).strip_edges() if parts.size() > 1 else ""
	match cmd:
		"kick":
			if arg == "":
				print("usage: kick <name>"); return
			print("dedicated: kicked %d player(s) matching '%s'" % [host.kick_name(arg, false), arg])
		"ban":
			if arg == "":
				print("usage: ban <name>"); return
			print("dedicated: banned '%s' (removed %d connected)" % [arg, host.kick_name(arg, true)])
			_persist_bans()
		"unban":
			if arg == "":
				print("usage: unban <name>"); return
			print("dedicated: unban '%s' — %s" % [arg, "removed" if host.unban_name(arg) else "not in list"])
			_persist_bans()
		"players":
			var ps := host.connected_players()
			print("dedicated: %d player(s) connected" % ps.size())
			for p in ps:
				var flag := "  ⚠ FLAGGED" if host.is_aim_flagged(int(p["sid"])) else ""
				print("  [%d] %s%s" % [int(p["sid"]), String(p["name"]), flag])
		"watch":
			var flagged := host.aim_report().filter(func(r): return bool(r["flagged"]))
			if flagged.is_empty():
				print("dedicated: no aim anomalies flagged (warnings only — never auto-banned)")
			for r in flagged:
				var nm := ""
				for p in host.connected_players():
					if int(p["sid"]) == int(r["sid"]):
						nm = String(p["name"])
				print("  ⚠ [%d] %s — %s" % [int(r["sid"]), nm, ", ".join(r["reasons"])])
		"bans":
			print("dedicated: bans — %s" % str(host.ban_list()))
		"help":
			print("commands: kick <name> | ban <name> | unban <name> | players | watch | bans | help")
		_:
			print("dedicated: unknown command '%s' (try: help)" % cmd)

func _maybe_start_recording() -> void:
	if _record and not session.movie_mode and session.world != null:
		session.recorder = Replay.begin(session)
		_record_gen = session.generation

func _finalize_recording() -> void:
	var r := session.finished_recorder
	session.finished_recorder = null
	if r == null:
		r = session.recorder
		session.recorder = null
	if r == null or r.final_tick < 300:
		return  # < 5s of match — not worth keeping as evidence
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/dedicated-%s.xsr" % [_record_dir, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(r.to_bytes())
		f.close()
		print("dedicated: match recorded — %s (%.0fs)" % [path.get_file(),
			r.duration_sec(1.0 / 60.0)])

```
