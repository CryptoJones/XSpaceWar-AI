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
## Dedicated-server session: NO slot is reserved for a local pilot — every
## ship is a bot until a remote player takes it (survives auto-restarts).
var dedicated: bool = false
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
var time_limit := 0.0              ## seconds; 0 = no clock
var hazard := 0.3                  ## asteroid slider 0..1 (1 = every 3rd cell)
var respawn_seconds := 6.0         ## death cooldown (player-configurable)
var lethal_edges := false          ## border kills instead of wrapping
var star_scale := 1.0              ## star size+gravity multiplier (slider 25 = 1.0)
var map_size := 40000.0            ## arena edge length (slider 2000-40000)
var lives := 0                     ## deaths before elimination (0 = unlimited)
var planet_count := 2              ## planets orbiting the star (0 = none)
var net_rtt_ms := -1               ## display-only: client's measured ping
var watch_ship_id := -1            ## spectator/replay follow-cam target (-1 = director)
var match_time := 0.0              ## seconds elapsed this match
var match_over := false
var winner_ship := -1              ## FFA winner's ship id
var winner_team := -1              ## TEAM winner, -1 in FFA
var restart_timer := 0.0

## A finished match's recorder, parked here at restart for main.gd to
## finalize — capture must never run against the rebuilt world.
var finished_recorder: Replay = null

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
	num_ships = clampi(p_num_ships, 1, 16)  # 1 = solo practice
	mode = p_mode
	difficulty = p_difficulty
	_build(_rng.randi())

func _randomize_match_params() -> void:
	# Skirmish-only settings must not leak into the attract loop (a lethal
	# boundary or 1s respawn from the last match would contaminate it).
	lethal_edges = false
	respawn_seconds = 6.0
	score_limit = 0
	time_limit = 0.0
	num_ships = _rng.randi_range(6, 16)
	hazard = _rng.randf_range(0.1, 0.6)
	star_scale = _rng.randf_range(0.5, 2.5)
	map_size = float(_rng.randi_range(6, 40)) * 1000.0
	planet_count = _rng.randi_range(0, 3)
	mode = Mode.TEAM if _rng.randf() < 0.5 else Mode.FFA
	num_teams = _rng.randi_range(2, 3) if mode == Mode.TEAM else 1
	difficulty = _rng.randi_range(BotController.Difficulty.VETERAN, BotController.Difficulty.INSANE)

func _build(seed: int) -> void:
	var cfg := SimConfig.from_seed(seed)
	cfg.arena_size = clampf(map_size, 2601.0, 40000.0)
	# Spawn ring scales down with small maps (and never sits outside them).
	cfg.spawn_orbit_radius = clampf(cfg.arena_size * 0.035, 550.0, 1400.0)
	cfg.respawn_time = clampf(respawn_seconds, 1.0, 15.0)
	cfg.lives = maxi(0, lives) if not movie_mode else 0
	cfg.lethal_edges = lethal_edges
	cfg.wrap_edges = not lethal_edges
	world = SimWorld.new(cfg)
	bots.clear()
	ship_names.clear()

	# Procedural arena — vary the layout a little by mode. Kept sparse:
	# space should read as mostly empty with hazards, not an obstacle course.
	# Star mass is SIZED TO THE ARENA (pure level-design parameter, not a
	# physics fudge): pick the base mass so inverse-square gravity at the
	# spawn ring is a comfortable fraction of engine thrust on every map.
	# This is what makes small maps playable — a smaller arena gets a
	# smaller star — while gravity stays exactly Newtonian (see README).
	var base_star_mass := (cfg.thrust_accel * 0.35) \
		* cfg.spawn_orbit_radius * cfg.spawn_orbit_radius / cfg.gravity_constant
	arena_params = ArenaGen.populate(world, {
		"star_count": 1,  # exactly one gravity well per map
		"star_mass": base_star_mass,
		"star_scale": clampf(star_scale, 0.2, 4.0),
		"planets": clampi(planet_count, 0, 6),
		"hazard": clampf(hazard, 0.0, 1.0),
		"satellites": _rng.randi_range(0, 2),
		"mirror": mode == Mode.TEAM,
	})

	for i in range(num_ships):
		var team := -1
		if mode == Mode.TEAM:
			team = i % num_teams
		var ship := world.add_ship(team)
		# In a skirmish the first ship is the human; everyone else is AI.
		# Movie Mode mixes pilot skill (rookies crashing among aces makes
		# better television than a uniform roster).
		if not movie_mode and not dedicated and i == 0:
			human_ship_id = ship.id
		else:
			var bot_diff := difficulty
			if movie_mode:
				bot_diff = _rng.randi_range(BotController.Difficulty.ROOKIE,
					BotController.Difficulty.INSANE)
			bots[ship.id] = BotController.new(world, ship.id, bot_diff)
			ship_names[ship.id] = BotController.callsign(ship.hull_seed)

	match_over = false
	winner_ship = -1
	winner_team = -1
	restart_timer = 0.0
	match_time = 0.0
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
			if recorder != null:
				finished_recorder = recorder
				recorder = null
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
	else:
		match_time += dt
		if score_limit > 0:
			_check_match_over()
		if not match_over and lives > 0:
			_check_elimination()
		if not match_over and time_limit > 0.0 and match_time >= time_limit:
			_time_out()

## Clock expired: whoever leads right now takes the match.
func _time_out() -> void:
	match_over = true
	restart_timer = RESTART_DELAY
	if mode == Mode.TEAM:
		var totals := team_scores()
		var best_team := -1
		var best := -2147483648
		for t in totals:
			if int(t) >= 0 and int(totals[t]) > best:
				best = int(totals[t])
				best_team = int(t)
		winner_team = best_team
	else:
		var lead := leaderboard()
		if not lead.is_empty():
			winner_ship = lead[0].id

## Lives mode: a pilot with no lives left is out of the match for good.
func is_eliminated(s: SimShip) -> bool:
	return world.config.lives > 0 and s.deaths >= world.config.lives

## Last one standing (or last team with a live pilot) takes the match.
func _check_elimination() -> void:
	if mode == Mode.TEAM:
		var teams_left := {}
		for s in world.ships:
			if not is_eliminated(s):
				teams_left[s.team] = true
		if teams_left.size() == 1:
			match_over = true
			winner_team = int(teams_left.keys()[0])
			restart_timer = RESTART_DELAY
		elif teams_left.is_empty():
			# Mutual annihilation on the same tick: score decides — the
			# match MUST end (nobody can respawn out of lives).
			match_over = true
			restart_timer = RESTART_DELAY
			var totals := team_scores()
			var best := -2147483648
			for t in totals:
				if int(t) >= 0 and int(totals[t]) > best:
					best = int(totals[t])
					winner_team = int(t)
	else:
		var left: Array[SimShip] = []
		for s in world.ships:
			if not is_eliminated(s):
				left.append(s)
		# Solo practice (1-ship rosters) never "wins by survival".
		if world.ships.size() > 1 and left.size() <= 1:
			match_over = true
			if left.size() == 1:
				winner_ship = left[0].id
			elif not leaderboard().is_empty():
				winner_ship = leaderboard()[0].id
			restart_timer = RESTART_DELAY

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

## The one authority for what a pilot is CALLED on screen — the HUD
## scoreboard/feed and the kill popups must never disagree.
func display_name(id: int) -> String:
	if id == human_ship_id:
		return "YOU"
	var n := String(ship_names.get(id, ""))
	return n if n != "" else "BOT-%d" % id

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
