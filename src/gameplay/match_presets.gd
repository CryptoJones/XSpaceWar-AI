class_name MatchPresets
extends RefCounted
## Friendly match recipes. The values live here so menu, dedicated server, and
## tests all apply exactly the same rules.

const CUSTOM := "custom"
const CLASSIC_FFA := "classic_ffa"
const QUICK_SKIRMISH := "quick_skirmish"
const TEAM_BATTLE := "team_battle"
const SURVIVAL := "survival"

const ORDER := [CLASSIC_FFA, QUICK_SKIRMISH, TEAM_BATTLE, SURVIVAL, CUSTOM]
const LABELS := {
	CLASSIC_FFA: "Classic FFA",
	QUICK_SKIRMISH: "Quick Skirmish",
	TEAM_BATTLE: "Team Battle",
	SURVIVAL: "Survival",
	CUSTOM: "Custom",
}
const SUMMARIES := {
	CLASSIC_FFA: "8 pilots · mixed skill · first to 10 · 40k wrap arena",
	QUICK_SKIRMISH: "4 pilots · Rookie · first to 5 · 3s respawn · fast pace",
	TEAM_BATTLE: "2 teams · Veteran · first to 15 · 40k wrap arena",
	SURVIVAL: "8 pilots · 3 lives · 60% asteroids · lethal edge",
	CUSTOM: "Advanced settings chosen by you",
}

static func label(id: String) -> String:
	return String(LABELS.get(id, LABELS[CUSTOM]))

static func summary(id: String) -> String:
	return String(SUMMARIES.get(id, SUMMARIES[CUSTOM]))

static func valid(id: String) -> bool:
	return ORDER.has(id)

static func apply(session: GameSession, id: String) -> void:
	if not valid(id) or id == CUSTOM:
		session.preset = CUSTOM
		return
	session.preset = id
	match id:
		CLASSIC_FFA:
			_configure(session, 8, GameSession.Mode.FFA, BotController.Difficulty.VETERAN,
				10, 40000.0, 0.30, 2, false, false, 4.0, 0, 75.0)
			# Classic FFA is what a first-time player picks, and eight uniform
			# VETERANs gave them no pecking order — nobody to beat and nobody to
			# fear, at 0.26s reaction and first-to-10. A ladder instead: two they
			# can hunt, four that fight back, one that punishes carelessness.
			session.difficulty_spread = [
				BotController.Difficulty.ROOKIE,
				BotController.Difficulty.VETERAN,
				BotController.Difficulty.VETERAN,
				BotController.Difficulty.ROOKIE,
				BotController.Difficulty.VETERAN,
				BotController.Difficulty.VETERAN,
				BotController.Difficulty.ACE,
			]
		QUICK_SKIRMISH:
			_configure(session, 4, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE,
				5, 12000.0, 0.10, 0, false, false, 3.0, 0, 90.0)
		TEAM_BATTLE:
			_configure(session, 8, GameSession.Mode.TEAM, BotController.Difficulty.VETERAN,
				15, 40000.0, 0.30, 2, false, false, 4.0, 0, 75.0)
		SURVIVAL:
			_configure(session, 8, GameSession.Mode.FFA, BotController.Difficulty.VETERAN,
				0, 40000.0, 0.60, 2, true, false, 4.0, 3, 60.0)

static func _configure(session: GameSession, ships: int, mode: int, diff: int,
		limit: int, map: float, hazards: float, planets: int, lethal: bool,
		friendly: bool, respawn: float, lives: int, pace: float) -> void:
	session.num_ships = ships
	session.mode = mode
	session.num_teams = 2 if mode == GameSession.Mode.TEAM else 1
	session.difficulty = diff
	session.score_limit = limit
	session.map_size = map
	session.hazard = hazards
	session.planet_count = planets
	session.lethal_edges = lethal
	session.friendly_fire = friendly
	session.respawn_seconds = respawn
	session.lives = lives
	session.flight_pace = pace
	# Presets are complete match recipes. Reset advanced values that are not
	# exposed by the recipe selector so a previous Custom match cannot leak
	# into the next selection.
	session.time_limit = 0.0
	session.torpedo_lifetime = 0.0
	session.mine_arm_seconds = 3.0
	session.mine_lifetime = 25.0
	session.star_scale = 1.0
