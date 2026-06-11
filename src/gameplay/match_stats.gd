class_name MatchStats
extends RefCounted
## Match history: one JSON line per finished match, appended to a stats file.
## Pure static helpers so the format is unit-testable without the UI.

const DEFAULT_PATH := "user://stats.jsonl"

## Snapshot a finished match (call when match_over fires). `when` is a
## display timestamp supplied by the caller.
static func entry_from_session(session: GameSession, when: String) -> Dictionary:
	var players := []
	for s in session.leaderboard():
		var pname: String = session.ship_names.get(s.id, "")
		if pname == "":
			pname = "BOT-%d" % s.id
		players.append({"n": pname, "s": s.score, "k": s.kills, "d": s.deaths,
			"you": s.id == session.human_ship_id, "t": s.team})
	var winner := ""
	if session.winner_team >= 0:
		winner = "TEAM %d" % (session.winner_team + 1)
	elif session.winner_ship >= 0:
		winner = String(session.ship_names.get(session.winner_ship, "BOT-%d" % session.winner_ship))
		if session.winner_ship == session.human_ship_id:
			winner += " (you)"
	return {
		"when": when,
		"mode": "TEAM" if session.mode == GameSession.Mode.TEAM else "FFA",
		"dur": session.match_time,
		"winner": winner,
		"won": session.winner_ship == session.human_ship_id
			or (session.winner_team >= 0 and session.winner_team == _human_team(session)),
		"players": players,
	}

static func _human_team(session: GameSession) -> int:
	var h := session.human_ship()
	return h.team if h != null else -2

static func append_entry(entry: Dictionary, path := DEFAULT_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(entry))
	f.close()

## Newest-first list of up to `limit` recorded matches.
static func load_recent(limit := 50, path := DEFAULT_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var v: Variant = JSON.parse_string(line)
		if typeof(v) == TYPE_DICTIONARY:
			out.append(v)
	f.close()
	out.reverse()
	if out.size() > limit:
		out.resize(limit)
	return out

## Career aggregates for the local player across all recorded matches.
static func career(path := DEFAULT_PATH) -> Dictionary:
	var matches := 0
	var wins := 0
	var kills := 0
	var deaths := 0
	for e in load_recent(100000, path):
		matches += 1
		if bool(e.get("won", false)):
			wins += 1
		for p in e.get("players", []):
			if bool(p.get("you", false)):
				kills += int(p.get("k", 0))
				deaths += int(p.get("d", 0))
	return {"matches": matches, "wins": wins, "kills": kills, "deaths": deaths}
