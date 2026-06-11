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

## The full merged dict ArenaGen actually used — sent to joining clients so
## they rebuild the byte-identical arena from the seed.
var arena_params: Dictionary = {}
## Optional display names by ship id (multiplayer); missing/empty = bot.
var ship_names := {}
## The local player's name, re-applied to the human ship across rebuilds.
var host_name := ""

# Match flow (skirmish only): first to score_limit wins, the win screen
# plays out for RESTART_DELAY seconds, then the match restarts on a fresh
# arena with the same settings.
const RESTART_DELAY := 8.0
var score_limit := 10              ## 0 = endless
var match_over := false
var winner_ship := -1              ## FFA winner's ship id
var winner_team := -1              ## TEAM winner, -1 in FFA
var restart_timer := 0.0

var _rng := RandomNumberGenerator.new()
var on_regenerate: Callable = Callable()  ## optional hook for the renderer
var recorder: Replay = null               ## when set, captures inputs each step

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
	ship_names.clear()

	# Procedural arena — vary the layout a little by mode. Kept sparse:
	# space should read as mostly empty with hazards, not an obstacle course.
	arena_params = ArenaGen.populate(world, {
		"star_count": 1,  # exactly one gravity well per map
		"planets": _rng.randi_range(1, 2),
		"asteroid_density": _rng.randi_range(16, 55),
		"satellites": _rng.randi_range(0, 2),
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
			ship_names[ship.id] = BotController.callsign(ship.hull_seed)

	match_over = false
	winner_ship = -1
	winner_team = -1
	restart_timer = 0.0
	if host_name != "" and human_ship_id >= 0:
		ship_names[human_ship_id] = host_name

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
	if match_over:
		# Victory lap: the sim keeps running (no bot pilots) while the win
		# banner shows, then the match restarts with the same settings.
		if recorder != null:
			recorder.capture(world)
		world.step(dt)
		restart_timer -= dt
		if restart_timer <= 0.0:
			start_skirmish(num_ships, mode, difficulty)
		return

	for sid in bots:
		(bots[sid] as BotController).update(dt)
	if recorder != null:
		recorder.capture(world)
	world.step(dt)

	if movie_mode:
		regen_timer -= dt
		if regen_timer <= 0.0:
			regenerate()
	elif score_limit > 0:
		_check_match_over()

func _check_match_over() -> void:
	if mode == Mode.TEAM:
		var totals := team_scores()
		for t in totals:
			if int(t) >= 0 and int(totals[t]) >= score_limit:
				match_over = true
				winner_team = int(t)
				restart_timer = RESTART_DELAY
				return
	else:
		for s in world.ships:
			if s.score >= score_limit:
				match_over = true
				winner_ship = s.id
				restart_timer = RESTART_DELAY
				return

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
