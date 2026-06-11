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

func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _process(_dt: float) -> void:
	if session == null or session.world == null:
		return
	_update_banner()
	_update_scoreboard()
	var human := session.human_ship()
	_bars.visible = human != null
	_hint.visible = human != null
	if human != null:
		_bars.queue_redraw()

func _update_banner() -> void:
	if session.match_over:
		var who := ""
		if session.winner_team >= 0:
			who = "TEAM %d" % (session.winner_team + 1)
		elif session.winner_ship == session.human_ship_id:
			who = "YOU"
		else:
			who = String(session.ship_names.get(session.winner_ship,
				"BOT-%d" % session.winner_ship))
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
		var name: String = session.ship_names.get(s.id, "")
		if s.id == session.human_ship_id:
			name = "YOU"
		elif name == "":
			name = "BOT-%d" % s.id
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
