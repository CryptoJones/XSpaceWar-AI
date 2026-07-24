class_name SimConfig
extends RefCounted
## Tunable parameters for the deterministic simulation.
##
## A SimConfig is created from a seed + arena/mode options and handed to a
## SimWorld. Everything that affects gameplay determinism lives here so that
## the host, predicting clients, AI, and replays all run the identical sim.

# --- Determinism ---
var seed: int = 0

# --- Arena ---
var arena_size: float = 40000.0         ## square arena edge length (world units)
var wrap_edges: bool = true             ## toroidal wrap at the (distant) edges
var lethal_edges: bool = false          ## alternative: the border destroys ships

# --- Physics ---
var gravity_constant: float = 6.0e5     ## tuned so star gravity reads well on-screen
var fixed_dt: float = 1.0 / 60.0        ## simulation step (seconds)

# --- Flight pacing -------------------------------------------------------
## Synchronized with the host/replay. A zero envelope is reserved for legacy
## tapes which predate the configurable arcade flight envelope.
const BASE_THRUST_ACCEL := 1150.0
const BASE_TORPEDO_SPEED := 900.0
const BASE_MAX_SHIP_SPEED := 3300.0
var flight_pace: float = 75.0
var max_ship_speed: float = BASE_MAX_SHIP_SPEED * 0.75

# --- Ship ---
var ship_radius: float = 12.0
var turn_rate: float = 4.2              ## radians / second (snappier dogfighting)
var thrust_accel: float = BASE_THRUST_ACCEL * 0.75 ## world units / second^2
var max_fuel: float = 130.0
var thrust_fuel_per_sec: float = 11.0
var fuel_regen_per_sec: float = 8.0
var max_ammo: int = 32
var ammo_regen_interval: float = 1.2    ## seconds per +1 torpedo
var spawn_grace: float = 1.5            ## seconds of invulnerability after (re)spawn
var spawn_orbit_radius: float = 1250.0
var respawn_time: float = 4.0
var lives: int = 0                      ## deaths before elimination (0 = unlimited)

## ---- Wire serialization -------------------------------------------------
## EVERY config override a session applies must round-trip here: the net
## welcome, replay headers, and any future carrier call these instead of
## hand-syncing field lists (drift here shipped two desync bugs).
func to_wire() -> Dictionary:
	return {
		"seed": seed,
		"rs": respawn_time,
		"le": lethal_edges,
		"as": arena_size,
		"so": spawn_orbit_radius,
		"lv": lives,
		"tl": torpedo_life,
		"ml": mine_life,
		"ma": mine_arm_time,
		"mr": manual_respawn,
		"fp": flight_pace,
		"fs": max_ship_speed,
	}

static func from_wire(d: Dictionary) -> SimConfig:
	var cfg := SimConfig.from_seed(int(d.get("seed", 0)))
	cfg.respawn_time = float(d.get("rs", cfg.respawn_time))
	cfg.lethal_edges = bool(d.get("le", false))
	cfg.wrap_edges = not cfg.lethal_edges
	cfg.arena_size = float(d.get("as", cfg.arena_size))
	cfg.spawn_orbit_radius = float(d.get("so", cfg.spawn_orbit_radius))
	cfg.lives = int(d.get("lv", 0))
	cfg.torpedo_life = float(d.get("tl", cfg.torpedo_life))
	cfg.mine_life = float(d.get("ml", cfg.mine_life))
	cfg.mine_arm_time = float(d.get("ma", cfg.mine_arm_time))
	# Absent in pre-feature tapes/peers -> false = the old auto-respawn rule.
	cfg.manual_respawn = bool(d.get("mr", false))
	if d.has("fp") or d.has("fs"):
		cfg.set_flight_pace(float(d.get("fp", 75.0)))
		cfg.max_ship_speed = maxf(0.0, float(d.get("fs", cfg.max_ship_speed)))
	else:
		# Old recordings must retain their unbounded movement behavior.
		cfg.flight_pace = 100.0
		cfg.thrust_accel = BASE_THRUST_ACCEL
		cfg.torpedo_speed = BASE_TORPEDO_SPEED
		cfg.max_ship_speed = 0.0
	return cfg

func set_flight_pace(value: float) -> void:
	flight_pace = clampf(round(value / 5.0) * 5.0, 60.0, 100.0)
	var scale := flight_pace / 100.0
	thrust_accel = BASE_THRUST_ACCEL * scale
	torpedo_speed = BASE_TORPEDO_SPEED * scale
	max_ship_speed = BASE_MAX_SHIP_SPEED * scale

# --- Torpedoes ---
var fire_cooldown: float = 0.35         ## ~3 shots / second (busier dogfights)
var torpedo_radius: float = 4.0
var torpedo_speed: float = BASE_TORPEDO_SPEED * 0.75 ## muzzle speed added to ship velocity
var torpedo_life: float = 0.0           ## 0 = NEVER expires (Aaron's rule: fly until impact)
var torpedo_gravity: bool = true        ## modern accuracy: gravity affects torpedoes too

# --- Mines ---
var max_mines: int = 3
var mine_regen_interval: float = 9.0    ## seconds per +1 mine
var mine_drop_cooldown: float = 1.0
var mine_radius: float = 6.0
var mine_life: float = 25.0
var mine_arm_time: float = 0.7          ## proximity fuse inert before this age
var mine_trigger_radius: float = 55.0
var mine_blast_radius: float = 95.0

# --- Pickups (dropped by shot asteroids) ---
var pickup_chance: float = 0.35         ## chance a destroyed rock drops cargo
var pickup_ttl: float = 20.0
var pickup_radius: float = 10.0
var pickup_fuel_amount: float = 50.0
var pickup_ammo_amount: int = 8
var pickup_mines_amount: int = 2

# --- Hyperspace ---
var hyperspace_cooldown: float = 4.0
var hyperspace_base_risk: float = 0.05  ## self-destruct chance, grows per use
var hyperspace_risk_per_use: float = 0.03

# --- Modes / scoring ---
var friendly_fire: bool = false
var ship_collision_lethal: bool = true  ## ships ramming = both destroyed (else bounce)
## When true, a ship whose respawn timer has elapsed stays dead until its fire
## input is held — players must press to respawn; bots hold fire automatically.
## Default false preserves the old auto-respawn rule for pre-feature replays.
var manual_respawn: bool = false

static func from_seed(s: int) -> SimConfig:
	var c := SimConfig.new()
	c.seed = s
	return c
