class_name Hud
extends CanvasLayer
## In-game HUD, built entirely in code: mode banner (with Movie Mode regen
## countdown), live scoreboard, fuel/ammo bars for the human ship, and a
## controls hint. Reads everything from the GameSession each frame.

var session: GameSession

var _banner: Label
var _score: RichTextLabel
var _bars: Control
var _feed_label: RichTextLabel
var _radar: Control
var _arrows: Control
var _respawn_label: Label
var _final_board: Label
var _debug_label: Label
var _edge_warn: Label
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

	_score = _make_rich(17)
	_score.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_score.position = Vector2(-16 - 320, 14)
	_score.custom_minimum_size = Vector2(320, 0)
	add_child(_score)

	# The three gauges (fuel / ammo / mines) sit top-center under the banner.
	# (No key-binding hint text — the menu's KEYS panel and the splash own that.)
	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bars.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bars.position = Vector2(-155, 52)
	_bars.size = Vector2(310, 74)
	_bars.draw.connect(_draw_bars)
	add_child(_bars)

	_feed_label = _make_rich(15)
	_feed_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_feed_label.position = Vector2(16, 14)
	_feed_label.custom_minimum_size = Vector2(360, 0)
	add_child(_feed_label)

	_debug_label = _make_label(14, Color(0.5, 1.0, 0.6, 0.9))
	_debug_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_debug_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_debug_label.position = Vector2(16, -150)
	_debug_label.visible = false
	add_child(_debug_label)

	# Lethal-boundary proximity warning, center-bottom, red and pulsing.
	_edge_warn = _make_label(30, Color(1.0, 0.25, 0.2))
	_edge_warn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_edge_warn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_edge_warn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_edge_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edge_warn.position.y = -120
	_edge_warn.visible = false
	add_child(_edge_warn)

	_arrows = Control.new()
	_arrows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrows.draw.connect(_draw_arrows)
	add_child(_arrows)

	_respawn_label = _make_label(44, Color(1.0, 0.85, 0.4))
	_respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_respawn_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_label.visible = false
	add_child(_respawn_label)

	# Final standings shown during the win screen.
	_final_board = _make_label(20, Color(0.9, 0.95, 1.0, 0.95))
	_final_board.set_anchors_preset(Control.PRESET_CENTER)
	_final_board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_final_board.grow_vertical = Control.GROW_DIRECTION_BOTH
	_final_board.position.y += 60
	_final_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_final_board.visible = false
	add_child(_final_board)

	# The classic minimap: bottom-left corner, fixed star-centered overview.
	_radar = Control.new()
	_radar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_radar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_radar.position = Vector2(16, -16 - RADAR_SIZE)
	_radar.size = Vector2(RADAR_SIZE, RADAR_SIZE)
	_radar.draw.connect(_draw_radar)
	add_child(_radar)

func set_debug(text: String) -> void:
	_debug_label.visible = text != ""
	_debug_label.text = text

func set_radar_visible(v: bool) -> void:
	_radar.visible = v

func radar_visible() -> bool:
	return _radar.visible

## BBCode label for color-coded HUD text (scoreboard, kill feed).
## Lethal-edge mode: shout when the wall of death is close (and closing).
func _update_edge_warning(human: SimShip) -> void:
	var w := session.world
	if w == null or not w.config.lethal_edges or human == null or not human.alive:
		_edge_warn.visible = false
		return
	var half := w.config.arena_size * 0.5
	var d := half - maxf(absf(human.pos.x), absf(human.pos.y))
	if d < 2500.0:
		_edge_warn.visible = true
		_edge_warn.text = "⚠ BOUNDARY  %d" % int(d)
		var pulse := 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 1000.0 * 6.0))
		_edge_warn.modulate.a = pulse
	else:
		_edge_warn.visible = false

func _make_rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", Color(0.85, 0.92, 1.0, 0.85))
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	r.add_theme_constant_override("outline_size", 4)
	return r

## A pilot's name wrapped in their ship color (dark red minimap identity
## stays on the map; here YOUR line is bold instead).
func _ship_bb(id: int) -> String:
	var ship := session.world.ship_by_id(id) if session.world != null else null
	var col := "#d8e6ff"
	if ship != null:
		col = "#" + WorldView.ship_color(ship).to_html(false)
	var nm := _ship_name(id)
	if id == session.human_ship_id:
		return "[b][color=%s]%s[/color][/b]" % [col, nm]
	return "[color=%s]%s[/color]" % [col, nm]

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
	_arrows.queue_redraw()
	var human := session.human_ship()
	_update_edge_warning(human)
	_bars.visible = human != null
	if human != null:
		_bars.queue_redraw()
	# Big center countdown while you're dead (skirmish only).
	if human != null and not human.alive and not session.match_over:
		_respawn_label.visible = true
		if session.is_eliminated(human):
			_respawn_label.text = "ELIMINATED — spectating (TAB cycles pilots)"
		else:
			_respawn_label.text = "RESPAWNING IN %d" % maxi(1, ceili(human.respawn_timer))
		_respawn_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
	else:
		_respawn_label.visible = false
	# Final standings under the winner banner during the victory lap.
	_final_board.visible = session.match_over
	if session.match_over:
		var lines: Array[String] = ["FINAL STANDINGS", ""]
		if session.mode == GameSession.Mode.TEAM:
			var totals := session.team_scores()
			var keys := totals.keys()
			keys.sort()
			for k in keys:
				if int(k) >= 0:
					lines.append("TEAM %d  —  %d" % [int(k) + 1, int(totals[k])])
			lines.append("")
		var rank := 1
		for s in session.leaderboard():
			lines.append("%d.  %s%s   %d   (%d kills / %d deaths)" % [rank, _ship_name(s.id),
				"" if s.team < 0 else "  [T%d]" % (s.team + 1), s.score, s.kills, s.deaths])
			rank += 1
		_final_board.text = "\n".join(lines)

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
					_push_feed("%s  ▸☠  %s" % [_ship_bb(int(ev["killer"])), _ship_bb(int(ev["victim"]))])
				"explosion":
					match String(ev.get("cause", "")):
						"body":
							_push_feed("%s  ✕  crashed" % _ship_bb(int(ev["ship"])))
						"ram":
							_push_feed("%s  ✕  collision" % _ship_bb(int(ev["ship"])))
						"hyperspace":
							_push_feed("%s  ✕  misjump" % _ship_bb(int(ev["ship"])))
						"edge":
							_push_feed("%s  ✕  hit the boundary" % _ship_bb(int(ev["ship"])))
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

## World units shown across the radar — the combat zone around the star, not
## the whole (mostly empty) arena.
const RADAR_WORLD_SPAN := 5200.0

func _draw_radar() -> void:
	var world := session.world if session != null else null
	if world == null:
		return
	var size := _radar.size
	_radar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.07, 0.12, 0.55))
	_radar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.6, 1.0, 0.35), false, 1.0)
	# The classic fixed overview: centered on the star (the combat zone).
	# Anything outside the window — including YOUR ship — pins to the rim,
	# so the map is a stable picture of home and everyone's bearing from it.
	var primary := world.primary_body()
	var center := primary.pos if primary != null else Vector2.ZERO
	for b in world.bodies:
		var mp := _radar_map(b.pos, center, size)
		var off_map := not _radar_in_view(mp, size)
		mp = mp.clamp(Vector2(4, 4), size - Vector2(4, 4))
		match b.kind:
			SimBody.Kind.STAR:
				# The star ALWAYS shows — pinned to the edge when far, so you
				# can never lose the way home in the big arena.
				_radar.draw_circle(mp, 4.0, Color(1.0, 0.85, 0.4, 0.6 if off_map else 1.0))
				if off_map:
					_radar.draw_arc(mp, 6.5, 0.0, TAU, 10, Color(1.0, 0.85, 0.4, 0.5), 1.0)
			SimBody.Kind.PLANET:
				if not off_map:
					_radar.draw_circle(mp, 2.5, Color(0.6, 0.7, 0.9))
				else:
					_radar.draw_circle(mp, 1.8, Color(0.6, 0.7, 0.9, 0.4))
			SimBody.Kind.SATELLITE:
				if not off_map:
					_radar.draw_circle(mp, 1.5, Color(1.0, 0.4, 0.4, 0.8))
			_:
				pass  # moons/asteroids are clutter at this scale
	# Armed mines blink red; supply drops show in their kind's color.
	for m in world.mines:
		if m.age < world.config.mine_arm_time:
			continue
		var mmp := _radar_map(m.pos, center, size)
		if _radar_in_view(mmp, size):
			var blink := 0.4 + 0.6 * maxf(0.0, sin(Time.get_ticks_msec() / 1000.0 * 6.0 + float(m.id)))
			_radar.draw_circle(mmp, 1.6, Color(1.0, 0.2, 0.15, blink))
	for p in world.pickups:
		var pmp := _radar_map(p.pos, center, size)
		if _radar_in_view(pmp, size):
			_radar.draw_circle(pmp, 1.6, WorldView.PICKUP_COLORS[p.kind % WorldView.PICKUP_COLORS.size()])
	for s in world.ships:
		if not s.alive:
			continue
		var mp := _radar_map(s.pos, center, size)
		# Ships beyond the window pin to the radar edge so you can still
		# tell where everyone went in the big empty.
		var off_view := not _radar_in_view(mp, size)
		mp = mp.clamp(Vector2(3, 3), size - Vector2(3, 3))
		if s.id == session.human_ship_id:
			# YOUR ship is always DARK RED on the map — instantly findable.
			_radar.draw_circle(mp, 3.2, Color(0.62, 0.07, 0.07))
			_radar.draw_arc(mp, 5.5, 0.0, TAU, 12, Color(0.62, 0.07, 0.07, 0.75), 1.2)
		else:
			var c := WorldView.ship_color(s)
			_radar.draw_circle(mp, 2.2, Color(c.r, c.g, c.b, 0.5 if off_view else 1.0))

## Edge arrows pointing at off-screen ships (skirmish only): the 10x arena
## means fights can be anywhere — these keep them findable without staring
## at the radar. Enemies draw bright with a distance tag, teammates dim.
func _draw_arrows() -> void:
	var world := session.world if session != null else null
	if world == null or session.human_ship_id < 0:
		return
	var human := session.human_ship()
	if human == null:
		return
	var xform := _arrows.get_viewport().get_canvas_transform()
	var size := _arrows.size
	var margin := 46.0
	for s in world.ships:
		if not s.alive or s.id == session.human_ship_id:
			continue
		var sp := xform * s.pos
		if sp.x >= 0.0 and sp.y >= 0.0 and sp.x <= size.x and sp.y <= size.y:
			continue  # on screen already
		var clamped := sp.clamp(Vector2(margin, margin), size - Vector2(margin, margin))
		var dir := (sp - clamped).normalized()
		var teammate := s.team != -1 and s.team == human.team
		var c := WorldView.ship_color(s)
		if teammate:
			c.a = 0.35
		var tip := clamped + dir * 12.0
		var perp := Vector2(-dir.y, dir.x) * 7.0
		_arrows.draw_colored_polygon(
			PackedVector2Array([tip, clamped - dir * 4.0 + perp, clamped - dir * 4.0 - perp]), c)
		if not teammate:
			var dist := human.pos.distance_to(s.pos)
			_arrows.draw_string(ThemeDB.fallback_font, clamped - dir * 16.0 + Vector2(-18, 5),
				"%.1fk" % (dist / 1000.0), HORIZONTAL_ALIGNMENT_CENTER, 38, 12,
				Color(c.r, c.g, c.b, 0.8))

func _radar_map(p: Vector2, center: Vector2, size: Vector2) -> Vector2:
	return ((p - center) / RADAR_WORLD_SPAN + Vector2(0.5, 0.5)) * size

func _radar_in_view(mp: Vector2, size: Vector2) -> bool:
	return mp.x >= 0.0 and mp.y >= 0.0 and mp.x <= size.x and mp.y <= size.y

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
		# (The respawn countdown gets its own big center overlay.)
		var mode_name := "TEAM BATTLE" if session.mode == GameSession.Mode.TEAM else "FREE-FOR-ALL"
		if session.time_limit > 0.0:
			var left := maxf(0.0, session.time_limit - session.match_time)
			mode_name += "  —  %d:%02d" % [int(left) / 60, int(left) % 60]
		if session.net_rtt_ms >= 0:
			mode_name += "  ·  %d ms" % session.net_rtt_ms
		if session.human_ship_id >= 0:
			_banner.text = mode_name
		else:
			var spec := "SPECTATING — " + mode_name
			if session.watch_ship_id >= 0:
				spec += "  ·  following " + _ship_name(session.watch_ship_id)
			_banner.text = spec

func _update_scoreboard() -> void:
	var lines: Array[String] = ["[right]  SCORE  K  D"]
	if session.mode == GameSession.Mode.TEAM:
		var totals := session.team_scores()
		var keys := totals.keys()
		keys.sort()
		var team_bits: Array[String] = []
		for k in keys:
			if int(k) >= 0:
				var tc := "#" + WorldView.TEAM_COLORS[int(k) % WorldView.TEAM_COLORS.size()].to_html(false)
				team_bits.append("[color=%s]Team %d: %d[/color]" % [tc, int(k) + 1, totals[k]])
		lines.append("  ".join(team_bits))
	for s in session.leaderboard():
		var team_tag := "" if s.team < 0 else " [T%d]" % (s.team + 1)
		var dead := "" if s.alive else " †"
		lines.append("%s%s  %d  %d/%d%s" % [_ship_bb(s.id), team_tag, s.score, s.kills, s.deaths, dead])
	_score.text = "\n".join(lines) + "[/right]"

func _draw_bars() -> void:
	var human := session.human_ship() if session != null else null
	if human == null:
		return
	var cfg := session.world.config
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
	# Fuel bar (flashes red + LOW under 20%).
	var w := 260.0
	var low_fuel := human.fuel < cfg.max_fuel * 0.2
	_bars.draw_string(ThemeDB.fallback_font, Vector2(0, 12), "FUEL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.8))
	_bars.draw_rect(Rect2(50, 2, w, 12), Color(1, 1, 1, 0.12))
	var frac := clampf(human.fuel / cfg.max_fuel, 0.0, 1.0)
	var fuel_col := Color(0.4, 1.0, 0.5)
	if low_fuel:
		fuel_col = Color(1.0, 0.25 + 0.35 * pulse, 0.2)
	elif frac <= 0.3:
		fuel_col = Color(1.0, 0.5, 0.3)
	_bars.draw_rect(Rect2(50, 2, w * frac, 12), fuel_col)
	if low_fuel:
		_bars.draw_string(ThemeDB.fallback_font, Vector2(50 + w + 8, 12), "LOW",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.3, 0.2, 0.5 + 0.5 * pulse))
	# Ammo pips (frame flashes when empty).
	_bars.draw_string(ThemeDB.fallback_font, Vector2(0, 36), "AMMO",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.8))
	var pip_w := w / float(cfg.max_ammo)
	for i in range(cfg.max_ammo):
		var c := Color(1.0, 0.9, 0.4) if i < human.ammo else Color(1, 1, 1, 0.10)
		_bars.draw_rect(Rect2(50 + i * pip_w, 26, pip_w - 2.0, 12), c)
	if human.ammo == 0:
		_bars.draw_rect(Rect2(49, 25, w + 2, 14), Color(1.0, 0.3, 0.2, 0.3 + 0.5 * pulse), false, 1.5)
	# Mine pips.
	_bars.draw_string(ThemeDB.fallback_font, Vector2(0, 60), "MINE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.8))
	var mine_w := 30.0
	for i in range(cfg.max_mines):
		var c2 := Color(1.0, 0.45, 0.25) if i < human.mines else Color(1, 1, 1, 0.10)
		_bars.draw_rect(Rect2(50 + i * (mine_w + 4.0), 50, mine_w, 12), c2)
