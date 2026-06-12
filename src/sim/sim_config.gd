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

# --- Ship ---
var ship_radius: float = 12.0
var turn_rate: float = 3.4              ## radians / second
var thrust_accel: float = 900.0         ## world units / second^2
var max_fuel: float = 100.0
var thrust_fuel_per_sec: float = 12.0
var fuel_regen_per_sec: float = 6.0
var max_ammo: int = 24
var ammo_regen_interval: float = 1.5    ## seconds per +1 torpedo
var spawn_grace: float = 1.5            ## seconds of invulnerability after (re)spawn
var spawn_orbit_radius: float = 1100.0
var respawn_time: float = 6.0
var lives: int = 0                      ## deaths before elimination (0 = unlimited)

# --- Torpedoes ---
var fire_cooldown: float = 0.5          ## 2 shots / second (matches the original feel)
var torpedo_radius: float = 4.0
var torpedo_speed: float = 700.0        ## muzzle speed added to ship velocity
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
var hyperspace_base_risk: float = 0.08  ## self-destruct chance, grows per use
var hyperspace_risk_per_use: float = 0.05

# --- Modes / scoring ---
var friendly_fire: bool = false
var ship_collision_lethal: bool = true  ## ships ramming = both destroyed (else bounce)

static func from_seed(s: int) -> SimConfig:
	var c := SimConfig.new()
	c.seed = s
	return c
