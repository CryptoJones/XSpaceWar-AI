class_name Hud
extends CanvasLayer
## In-game HUD, built entirely in code: mode banner (with Movie Mode regen
## countdown), live scoreboard, fuel/ammo bars for the human ship, and a
## controls hint. Reads everything from the GameSession each frame.

var session: GameSession

var _banner: Label
var _score: Label
var _hint: Label
var _bars: Control
var _feed_label: Label
var _radar: Control
var _feed: Array[Dictionary] = []   ## {"t": text, "ttl": seconds}
var _seen_tick := -1
var _seen_gen := -1

const FEED_TTL := 6.0
const FEED_MAX := 6
const RADAR_SIZE := 170.0

func _ready() -> void:
	layer = 5

	_banner = _make_label(24, Color(0.9, 0.95, 1.0, 0.9))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = 14
	add_child(_banner)

	_score = _make_label(17, Color(0.85, 0.92, 1.0, 0.85))
	_score.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score.position = Vector2(-16, 14)
	add_child(_score)

	_hint = _make_label(15, Color(0.7, 0.78, 0.9, 0.55))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position = Vector2(-16, -14)
	_hint.text = "A/D turn   W thrust   SPACE fire   SHIFT hyperspace   ESC menu"
	add_child(_hint)

	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bars.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bars.position = Vector2(16, -64)
	_bars.size = Vector2(300, 50)
	_bars.draw.connect(_draw_bars)
	add_child(_bars)

	_feed_label = _make_label(15, Color(0.95, 0.85, 0.75, 0.9))
	_feed_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_feed_label.position = Vector2(16, 14)
	add_child(_feed_label)

	_radar = Control.new()
	_radar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_radar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_radar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_radar.position = Vector2(-16 - RADAR_SIZE, -44 - RADAR_SIZE)
	_radar.size = Vector2(RADAR_SIZE, RADAR_SIZE)
	_radar.draw.connect(_draw_radar)
	add_child(_radar)

func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _process(dt: float) -> void:
	if session == null or session.world == null:
		return
	if session.generation != _seen_gen:
		_seen_gen = session.generation
		_feed.clear()
		_seen_tick = -1
	_update_banner()
	_update_scoreboard()
	_update_feed(dt)
	_radar.queue_redraw()
	var human := session.human_ship()
	_bars.visible = human != null
	_hint.visible = human != null
	if human != null:
		_bars.queue_redraw()

## Resolve a ship id to what the local player should read.
func _ship_name(id: int) -> String:
	if id == session.human_ship_id:
		return "YOU"
	var n: String = session.ship_names.get(id, "")
	return n if n != "" else "BOT-%d" % id

func _update_feed(dt: float) -> void:
	# Consume each sim step's events exactly once (idle vs physics rates differ).
	if session.world.tick != _seen_tick:
		_seen_tick = session.world.tick
		for ev in session.world.events:
			match String(ev.get("type", "")):
				"kill":
					_push_feed("%s  ▸☠  %s" % [_ship_name(int(ev["killer"])), _ship_name(int(ev["victim"]))])
				"explosion":
					match String(ev.get("cause", "")):
						"body":
							_push_feed("%s  ✕  crashed" % _ship_name(int(ev["ship"])))
						"ram":
							_push_feed("%s  ✕  collision" % _ship_name(int(ev["ship"])))
						"hyperspace":
							_push_feed("%s  ✕  misjump" % _ship_name(int(ev["ship"])))
	for e in _feed:
		e["ttl"] = float(e["ttl"]) - dt
	while not _feed.is_empty() and float(_feed[0]["ttl"]) <= 0.0:
		_feed.pop_front()
	var lines: Array[String] = []
	for e in _feed:
		lines.append(String(e["t"]))
	_feed_label.text = "\n".join(lines)

func _push_feed(text: String) -> void:
	_feed.append({"t": text, "ttl": FEED_TTL})
	while _feed.size() > FEED_MAX:
		_feed.pop_front()

func _draw_radar() -> void:
	var world := session.world if session != null else null
	if world == null:
		return
	var size := _radar.size
	_radar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.07, 0.12, 0.55))
	_radar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.6, 1.0, 0.35), false, 1.0)
	var arena := world.config.arena_size
	for b in world.bodies:
		var mp := (b.pos / arena + Vector2(0.5, 0.5)) * size
		match b.kind:
			SimBody.Kind.STAR:
				_radar.draw_circle(mp, 4.0, Color(1.0, 0.85, 0.4))
			SimBody.Kind.PLANET:
				_radar.draw_circle(mp, 2.5, Color(0.6, 0.7, 0.9))
			SimBody.Kind.SATELLITE:
				_radar.draw_circle(mp, 1.5, Color(1.0, 0.4, 0.4, 0.8))
			_:
				pass  # moons/asteroids are clutter at this scale
	for s in world.ships:
		if not s.alive:
			continue
		var mp := (s.pos / arena + Vector2(0.5, 0.5)) * size
		if s.id == session.human_ship_id:
			_radar.draw_circle(mp, 3.0, Color.WHITE)
			_radar.draw_arc(mp, 5.5, 0.0, TAU, 12, Color(1, 1, 1, 0.6), 1.0)
		else:
			_radar.draw_circle(mp, 2.2, WorldView.ship_color(s))

func _update_banner() -> void:
	if session.match_over:
		var who := ""
		if session.winner_team >= 0:
			who = "TEAM %d" % (session.winner_team + 1)
		else:
			who = _ship_name(session.winner_ship)
		_banner.text = "★ %s WIN%s ★ — next round in %d" \
			% [who, "" if who == "YOU" else "S", maxi(0, ceili(session.restart_timer))]
		return
	if session.movie_mode:
		var t := maxf(0.0, session.regen_timer)
		_banner.text = "MOVIE MODE — arena %d — next regeneration in %02d:%02d" \
			% [session.generation, int(t) / 60, int(t) % 60]
	else:
		var mode_name := "TEAM BATTLE" if session.mode == GameSession.Mode.TEAM else "FREE-FOR-ALL"
		var human := session.human_ship()
		if human != null and not human.alive:
			_banner.text = "%s — respawning in %.1f…" % [mode_name, maxf(0.0, human.respawn_timer)]
		else:
			_banner.text = mode_name

func _update_scoreboard() -> void:
	var lines: Array[String] = ["  SCORE  K  D"]
	if session.mode == GameSession.Mode.TEAM:
		var totals := session.team_scores()
		var keys := totals.keys()
		keys.sort()
		var team_bits: Array[String] = []
		for k in keys:
			team_bits.append("Team %d: %d" % [int(k) + 1, totals[k]])
		lines.append("  ".join(team_bits))
	for s in session.leaderboard():
		var name := _ship_name(s.id)
		var team_tag := "" if s.team < 0 else " [T%d]" % (s.team + 1)
		var dead := "" if s.alive else " †"
		lines.append("%s%s  %d  %d/%d%s" % [name, team_tag, s.score, s.kills, s.deaths, dead])
	_score.text = "\n".join(lines)

func _draw_bars() -> void:
	var human := session.human_ship() if session != null else null
	if human == null:
		return
	var cfg := session.world.config
	# Fuel bar.
	var w := 260.0
	_bars.draw_string(ThemeDB.fallback_font, Vector2(0, 12), "FUEL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.8))
	_bars.draw_rect(Rect2(50, 2, w, 12), Color(1, 1, 1, 0.12))
	var frac := clampf(human.fuel / cfg.max_fuel, 0.0, 1.0)
	var fuel_col := Color(0.4, 1.0, 0.5) if frac > 0.3 else Color(1.0, 0.5, 0.3)
	_bars.draw_rect(Rect2(50, 2, w * frac, 12), fuel_col)
	# Ammo pips.
	_bars.draw_string(ThemeDB.fallback_font, Vector2(0, 36), "AMMO",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.8))
	var pip_w := w / float(cfg.max_ammo)
	for i in range(cfg.max_ammo):
		var c := Color(1.0, 0.9, 0.4) if i < human.ammo else Color(1, 1, 1, 0.10)
		_bars.draw_rect(Rect2(50 + i * pip_w, 26, pip_w - 2.0, 12), c)
