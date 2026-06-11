class_name GameSession
extends RefCounted
## Owns a running match: the deterministic SimWorld, the AI controllers, the
## game mode, and (for Movie Mode) the periodic regeneration of a fresh arena +
## roster + teams. Pure logic — no rendering — so it stays headless-testable.
##
## A renderer/host drives it by calling `update(dt)` once per fixed step.

enum Mode { FFA, TEAM }

var world: SimWorld
var bots: Dictionary = {}                 ## ship_id -> BotController
var mode: int = Mode.FFA
var num_ships: int = 8
var num_teams: int = 2
var difficulty: int = BotController.Difficulty.VETERAN

# Movie Mode: all-AI spectator that regenerates everything on a timer.
var movie_mode: bool = false
var regen_interval: float = 1800.0        ## 30 minutes
var regen_timer: float = 0.0
var generation: int = 0                   ## increments each regeneration

# Skirmish: id of the human-controlled ship, or -1 in Movie Mode.
var human_ship_id: int = -1

var _rng := RandomNumberGenerator.new()
var on_regenerate: Callable = Callable()  ## optional hook for the renderer

func _init() -> void:
	_rng.seed = Time.get_ticks_usec()

# --------------------------------------------------------------------------
# Lifecycle
# --------------------------------------------------------------------------

## Start a Movie Mode session (all AI, auto-regenerating).
func start_movie() -> void:
	movie_mode = true
	human_ship_id = -1
	regen_timer = regen_interval
	_randomize_match_params()
	_build(_rng.randi())

## Start a skirmish with one human ship plus AI opponents.
func start_skirmish(p_num_ships: int, p_mode: int, p_difficulty: int) -> void:
	movie_mode = false
	num_ships = clampi(p_num_ships, 2, 12)
	mode = p_mode
	difficulty = p_difficulty
	_build(_rng.randi())

func _randomize_match_params() -> void:
	num_ships = _rng.randi_range(6, 12)
	mode = Mode.TEAM if _rng.randf() < 0.5 else Mode.FFA
	num_teams = _rng.randi_range(2, 3) if mode == Mode.TEAM else 1
	difficulty = _rng.randi_range(BotController.Difficulty.VETERAN, BotController.Difficulty.INSANE)

func _build(seed: int) -> void:
	var cfg := SimConfig.from_seed(seed)
	world = SimWorld.new(cfg)
	bots.clear()

	# Procedural arena — vary the layout a little by mode.
	ArenaGen.populate(world, {
		"star_count": 2 if _rng.randf() < 0.2 else 1,
		"planets": _rng.randi_range(1, 3),
		"asteroid_density": _rng.randi_range(40, 130),
		"satellites": _rng.randi_range(0, 3),
		"mirror": mode == Mode.TEAM,
	})

	for i in range(num_ships):
		var team := -1
		if mode == Mode.TEAM:
			team = i % num_teams
		var ship := world.add_ship(team)
		# In a skirmish the first ship is the human; everyone else is AI.
		if not movie_mode and i == 0:
			human_ship_id = ship.id
		else:
			bots[ship.id] = BotController.new(world, ship.id, difficulty)

	generation += 1
	if on_regenerate.is_valid():
		on_regenerate.call()

func regenerate() -> void:
	_randomize_match_params()
	_build(_rng.randi())
	regen_timer = regen_interval

# --------------------------------------------------------------------------
# Per-step update
# --------------------------------------------------------------------------

func update(dt: float) -> void:
	for sid in bots:
		(bots[sid] as BotController).update(dt)
	world.step(dt)

	if movie_mode:
		regen_timer -= dt
		if regen_timer <= 0.0:
			regenerate()

# --------------------------------------------------------------------------
# Queries (for HUD / scoreboard)
# --------------------------------------------------------------------------

func human_ship() -> SimShip:
	return world.ship_by_id(human_ship_id) if human_ship_id >= 0 else null

## Ships sorted by score, descending — for the scoreboard.
func leaderboard() -> Array[SimShip]:
	var arr: Array[SimShip] = world.ships.duplicate()
	arr.sort_custom(func(a, b): return a.score > b.score)
	return arr

func team_scores() -> Dictionary:
	var totals := {}
	for s in world.ships:
		totals[s.team] = int(totals.get(s.team, 0)) + s.score
	return totals
