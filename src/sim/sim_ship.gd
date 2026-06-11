class_name SimShip
extends RefCounted
## A player- or AI-controlled ship in the deterministic simulation.
##
## Holds only simulation state — no rendering. The `in_*` fields are the
## control inputs applied on the next step (set by a human controller, the AI,
## or a decoded network packet).

var id: int = -1
var team: int = -1                      ## -1 = free-for-all (no team)
var hull_seed: int = 0                  ## drives procedural ship silhouette

# --- Kinematic state ---
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var angle: float = 0.0                  ## facing, radians

# --- Resources ---
var fuel: float = 0.0
var ammo: int = 0
var ammo_timer: float = 0.0
var mines: int = 0
var mine_timer: float = 0.0
var mine_cooldown: float = 0.0

# --- Status / timers ---
var alive: bool = true
var respawn_timer: float = 0.0
var fire_cooldown: float = 0.0
var hyperspace_cooldown: float = 0.0
var hyperspace_uses: int = 0
var spawn_grace: float = 0.0
var radius: float = 12.0

# --- Stats ---
var score: int = 0
var kills: int = 0
var deaths: int = 0

# --- Render-only (never read or written by the simulation) ---
## Net-client snapshot-correction smoothing: the renderer draws the ship at
## pos + render_pos_offset while the offset decays to zero.
var render_pos_offset: Vector2 = Vector2.ZERO

# --- Control inputs (applied next step) ---
var in_turn: float = 0.0                ## -1 (CCW) .. +1 (CW)
var in_thrust: bool = false
var in_fire: bool = false
var in_hyper: bool = false
var in_mine: bool = false

func facing() -> Vector2:
	return Vector2(cos(angle), sin(angle))

func clear_inputs() -> void:
	in_turn = 0.0
	in_thrust = false
	in_fire = false
	in_hyper = false
	in_mine = false
