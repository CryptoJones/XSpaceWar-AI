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
var _spec_hint: Label
var _feed: Array[Dictionary] = []   ## {"t": text, "ttl": seconds}
var _seen_tick := -1
var _seen_gen := -1
var _rtl := false                   ## true under a right-to-left locale (Arabic)
var _radar_span := 0.0              ## smoothed minimap world-units-across (0 = uninitialised)

const FEED_TTL := 12.0
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

	# Small, out-of-the-way watcher hint (bottom-right) — never blocks the action.
	_spec_hint = _make_label(14, Color(0.7, 0.85, 1.0, 0.75))
	_spec_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_spec_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_spec_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_spec_hint.position = Vector2(-16, -16)
	_spec_hint.visible = false
	add_child(_spec_hint)

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

	_apply_layout_direction()

## Mirror the corner HUD for right-to-left locales (Arabic): the text is already
## translated, this flips WHERE each panel sits. Scoreboard ⇄ feed swap sides,
## the radar moves to the opposite bottom corner, the watcher hint to the
## opposite bottom corner. Centered elements (banner, bars, respawn, final
## standings, edge warning) are symmetric; the off-screen arrows are
## world-relative; the F3 debug overlay is dev-facing — all left in place.
func _apply_layout_direction() -> void:
	if _score == null:
		return  # a translation-changed notification can arrive before _ready builds the HUD
	var ts := TextServerManager.get_primary_interface()
	_rtl = ts != null and ts.is_locale_right_to_left(TranslationServer.get_locale())
	# Use offset_* directly instead of position so placement is always correct
	# regardless of when the CanvasLayer resolves its viewport rect.  Setting
	# .position on an anchored Control recomputes the offsets from the live
	# parent size, which can place controls off-screen when anchors != (0,0).
	if _rtl:
		_score.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_score.grow_horizontal = Control.GROW_DIRECTION_END
		_score.offset_left = 16; _score.offset_top = 14
		_feed_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_feed_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_feed_label.offset_right = -16; _feed_label.offset_left = -16 - 360; _feed_label.offset_top = 14
		_radar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_radar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_radar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_radar.offset_right = -16; _radar.offset_left = -16 - RADAR_SIZE
		_radar.offset_bottom = -16; _radar.offset_top = -16 - RADAR_SIZE
		_spec_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_spec_hint.grow_horizontal = Control.GROW_DIRECTION_END
		_spec_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_spec_hint.offset_left = 16; _spec_hint.offset_bottom = -16
	else:
		_score.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_score.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_score.offset_right = -16; _score.offset_left = -16 - 320; _score.offset_top = 14
		_feed_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_feed_label.grow_horizontal = Control.GROW_DIRECTION_END
		_feed_label.offset_left = 16; _feed_label.offset_top = 14
		_radar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_radar.grow_horizontal = Control.GROW_DIRECTION_END
		_radar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_radar.offset_left = 16; _radar.offset_right = 16 + RADAR_SIZE
		_radar.offset_bottom = -16; _radar.offset_top = -16 - RADAR_SIZE
		_spec_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_spec_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_spec_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_spec_hint.offset_right = -16; _spec_hint.offset_bottom = -16
	_radar.size = Vector2(RADAR_SIZE, RADAR_SIZE)
	_score.custom_minimum_size = Vector2(320, 0)

## Re-mirror live when the player switches language (Arabic ⇄ LTR).
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_apply_layout_direction()

func set_debug(text: String) -> void:
	_debug_label.visible = text != ""
	_debug_label.text = text

var debug_echo := false   ## --debug: mirror feed lines to stdout
var banner_override := ""  ## non-empty: replaces the mode banner (race egg)

func set_feed_visible(v: bool) -> void:
	_feed_label.visible = v

func feed_visible() -> bool:
	return _feed_label.visible

func set_score_visible(v: bool) -> void:
	_score.visible = v

func score_visible() -> bool:
	return _score.visible

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
		_edge_warn.text = tr("⚠ BOUNDARY  %d") % int(d)
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
	# Auto-zoom the minimap: ease its world-span toward the target for the
	# player's distance from the star — whole-map when there's no player
	# (movie mode / spectator / replay). Star is the minimap centre.
	var star := session.world.primary_body()
	var star_pos := star.pos if star != null else Vector2.ZERO
	var span_target := session.world.config.arena_size
	if human != null:
		span_target = radar_target_span(human.pos - star_pos, session.world.config.arena_size)
	if _radar_span < 1.0:
		_radar_span = span_target  # snap on the first frame
	else:
		_radar_span = lerpf(_radar_span, span_target, 1.0 - exp(-RADAR_ZOOM_SMOOTH * dt))
	_update_edge_warning(human)
	_bars.visible = human != null
	if human != null:
		_bars.queue_redraw()
	# Big center countdown while you're dead (skirmish only).
	if human != null and not human.alive and not session.match_over \
			and not session.is_eliminated(human):
		_respawn_label.visible = true
		# Once the timer is up under manual respawn, prompt for the fire press
		# instead of a countdown; otherwise show the seconds remaining.
		if session.world.config.manual_respawn and human.respawn_timer <= 0.0:
			_respawn_label.text = tr("PRESS FIRE TO RESPAWN")
		else:
			_respawn_label.text = tr("RESPAWNING IN %d") % maxi(1, ceili(human.respawn_timer))
		_respawn_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
	else:
		_respawn_label.visible = false
	# Watcher hint: small, corner, persistent — eliminated pilots and movie
	# viewers learn TAB without a billboard over the dogfight.
	if human != null and session.is_eliminated(human) and not session.match_over:
		_spec_hint.visible = true
		_spec_hint.text = tr("ELIMINATED  ·  TAB follows the next pilot")
	elif (session.movie_mode or (human != null and not human.alive)) \
			and session.world != null and not session.match_over:
		_spec_hint.visible = true
		_spec_hint.text = tr("TAB follows a pilot")
	else:
		_spec_hint.visible = false
	# Final standings under the winner banner during the victory lap.
	_final_board.visible = session.match_over
	if session.match_over:
		var lines: Array[String] = [tr("FINAL STANDINGS"), ""]
		if session.mode == GameSession.Mode.TEAM:
			var totals := session.team_scores()
			var keys := totals.keys()
			keys.sort()
			for k in keys:
				if int(k) >= 0:
					lines.append(tr("TEAM %d  —  %d") % [int(k) + 1, int(totals[k])])
			lines.append("")
		var rank := 1
		for s in session.leaderboard():
			lines.append(tr("%d.  %s%s   %d   (%d kills / %d deaths)") % [rank, _ship_name(s.id),
				"" if s.team < 0 else "  [T%d]" % (s.team + 1), s.score, s.kills, s.deaths])
			rank += 1
		_final_board.text = "\n".join(lines)

## Resolve a ship id to what the local player should read.
func _ship_name(id: int) -> String:
	return session.display_name(id)

func _update_feed(dt: float) -> void:
	# Consume each event exactly once: events accumulate with tick stamps,
	# so multi-step frames (fast replay, sub-60fps) lose nothing.
	if session.world.tick != _seen_tick:
		var last_seen := _seen_tick
		_seen_tick = session.world.tick
		for ev in session.world.events:
			if int(ev.get("tk", -1)) < last_seen:
				continue  # (events of step N are stamped N; tick is N+1 after)
			match String(ev.get("type", "")):
				"kill":
					var killer := int(ev["killer"]); var victim := int(ev["victim"])
					var mine := killer == session.human_ship_id or victim == session.human_ship_id
					_push_feed("%s  ▸☠  %s" % [_ship_bb(killer), _ship_bb(victim)], mine)
				"explosion":
					var ship := int(ev["ship"])
					var is_mine := ship == session.human_ship_id
					var self_kill := int(ev.get("killer", -1)) < 0
					match String(ev.get("cause", "")):
						"body":
							_push_feed("%s  ✕  crashed" % _ship_bb(ship), is_mine)
						"ram":
							_push_feed("%s  ✕  collision" % _ship_bb(ship), is_mine)
						"hyperspace":
							_push_feed("%s  ✕  misjump" % _ship_bb(ship), is_mine)
						"edge":
							_push_feed("%s  ✕  hit the boundary" % _ship_bb(ship), is_mine)
						"mine":
							if self_kill:
								_push_feed("%s  ✕  own mine" % _ship_bb(ship), is_mine)
						"torpedo":
							if self_kill:
								_push_feed("%s  ✕  own torpedo" % _ship_bb(ship), is_mine)
	for e in _feed:
		e["ttl"] = float(e["ttl"]) - dt
	while not _feed.is_empty() and float(_feed[0]["ttl"]) <= 0.0:
		_feed.pop_front()
	var lines: Array[String] = []
	for e in _feed:
		lines.append(String(e["t"]))
	_feed_label.text = "\n".join(lines)

func _push_feed(text: String, big: bool = false) -> void:
	if debug_echo:
		var rx := RegEx.create_from_string("\\[/?[^\\]]*\\]")
		print("[feed] ", rx.sub(text, "", true))
	var line := "[font_size=30]%s[/font_size]" % text if big else text
	_feed.append({"t": line, "ttl": FEED_TTL})
	while _feed.size() > FEED_MAX:
		_feed.pop_front()

## The minimap auto-zooms with your distance from the star: most zoomed-in at
## the star (you see 1/RADAR_MIN_ZOOM_DIV of the map width), widening smoothly
## to the WHOLE arena at the map edge — and it scales with the (user-set) map
## size, so it feels identical on every map. Span is eased per frame.
const RADAR_MIN_ZOOM_DIV := 8.0      ## at the star: window = arena_size / this
const RADAR_ZOOM_SMOOTH := 3.0       ## span easing rate (cf. camera_controller.gd)
const RADAR_DETAIL_SPAN_FRAC := 0.4  ## reveal asteroids/moons/torpedoes while span <= arena*this
const RADAR_STAR_EXAGGERATION := 4.0 ## draw the star this much bigger than its true scale
# MINIMAP-ONLY colours (the main view keeps each ship's random/team colour):
# a flat friend/enemy scheme is far easier to read at a glance than 16 hues.
const RADAR_ENEMY_COLOR := Color(1.0, 0.28, 0.28)   ## bright red — hostile ships
const RADAR_FRIEND_COLOR := Color(0.45, 0.75, 1.0)  ## light blue — your teammates
const RADAR_PLANET_COLOR := Color(0.35, 0.9, 0.45)  ## green — planets

## The minimap world-span we WANT for a ship at `rel` (its offset from the star)
## on an arena of edge `arena_size`. Star-centred and square, so we scale on the
## max-axis (Chebyshev) distance: 0 at the star -> arena/MIN_ZOOM_DIV (zoomed in),
## reaching the full arena the moment the ship touches any edge. Pure + testable.
static func radar_target_span(rel: Vector2, arena_size: float) -> float:
	var half := maxf(arena_size * 0.5, 1.0)
	var t := clampf(maxf(absf(rel.x), absf(rel.y)) / half, 0.0, 1.0)
	return lerpf(arena_size / RADAR_MIN_ZOOM_DIV, arena_size, t)

func _draw_radar() -> void:
	var world := session.world if session != null else null
	if world == null:
		return
	var size := _radar.size
	_radar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.07, 0.12, 0.55))
	_radar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.6, 1.0, 0.35), false, 1.0)
	# Star-centred and auto-zoomed (see _process): the window spans the combat
	# zone near the star and widens to the whole arena as you fly out. Ships
	# outside the window pin to the rim. When zoomed in we also draw the fine
	# detail that's normally hidden as clutter.
	var primary := world.primary_body()
	var center := primary.pos if primary != null else Vector2.ZERO
	var detail := _radar_span <= world.config.arena_size * RADAR_DETAIL_SPAN_FRAC
	for b in world.bodies:
		var mp := _radar_map(b.pos, center, size)
		var off_map := not _radar_in_view(mp, size)
		mp = mp.clamp(Vector2(4, 4), size - Vector2(4, 4))
		match b.kind:
			SimBody.Kind.STAR:
				# The star is the minimap centre — drawn relative to its real
				# size in the current window (one world unit = size.x/_radar_span
				# px), then EXAGGERATED so it reads clearly: big when zoomed in
				# close, a dot at full zoom-out. Floored so it never vanishes,
				# capped so it can't overrun the map.
				var star_px := clampf(
					b.radius / maxf(_radar_span, 1.0) * size.x * RADAR_STAR_EXAGGERATION,
					2.0, size.x * 0.5)
				_radar.draw_circle(mp, star_px, Color(1.0, 0.85, 0.4))
			SimBody.Kind.PLANET:
				# Drawn at ~a third of the star's apparent size (½ then −33%) and
				# scaling the same way — bigger as you zoom in close (the planets
				# now ring the star), a dot at full zoom-out. Floored so it never
				# vanishes.
				var star_r := primary.radius if primary != null else b.radius
				var planet_px := clampf(
					star_r / maxf(_radar_span, 1.0) * size.x * (RADAR_STAR_EXAGGERATION * 0.335),
					1.5, size.x * 0.5)
				_radar.draw_circle(mp, planet_px,
					Color(RADAR_PLANET_COLOR, 0.5 if off_map else 1.0))
			SimBody.Kind.SATELLITE:
				if not off_map:
					_radar.draw_circle(mp, 1.5, Color(1.0, 0.4, 0.4, 0.8))
			_:
				# Moons/asteroids: clutter at far-out zoom, faint dots once you
				# are zoomed in close ("all the info" for the area around you).
				if detail and not off_map:
					_radar.draw_circle(mp, 1.2, Color(0.55, 0.55, 0.6, 0.7))
	# Torpedoes in flight — tracers, only when zoomed in (a swarm of dots far out).
	if detail:
		for t in world.torpedoes:
			var tmp := _radar_map(t.pos, center, size)
			if _radar_in_view(tmp, size):
				_radar.draw_circle(tmp, 1.0, Color(1.0, 0.9, 0.5, 0.8))
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
	var me := session.human_ship()
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
			# Flat friend/enemy scheme (minimap only): teammates light blue,
			# everyone else bright red. The main view keeps each ship's colour.
			var friend := me != null and s.team != -1 and s.team == me.team
			var c := RADAR_FRIEND_COLOR if friend else RADAR_ENEMY_COLOR
			_radar.draw_circle(mp, 2.2, Color(c, 0.5 if off_view else 1.0))

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
	return ((p - center) / maxf(_radar_span, 1.0) + Vector2(0.5, 0.5)) * size

func _radar_in_view(mp: Vector2, size: Vector2) -> bool:
	return mp.x >= 0.0 and mp.y >= 0.0 and mp.x <= size.x and mp.y <= size.y

func _update_banner() -> void:
	if banner_override != "":
		_banner.text = banner_override
		return
	if session.match_over:
		var who := ""
		if session.winner_team >= 0:
			who = tr("TEAM %d") % (session.winner_team + 1)
		else:
			who = _ship_name(session.winner_ship)
		_banner.text = tr("★ %s WIN%s ★ — next round in %d") \
			% [who, "" if who == "YOU" else "S", maxi(0, ceili(session.restart_timer))]
		return
	if session.movie_mode:
		var t := maxf(0.0, session.regen_timer)
		_banner.text = tr("MOVIE MODE — arena %d — next regeneration in %02d:%02d") \
			% [session.generation, int(t) / 60, int(t) % 60]
	else:
		# (The respawn countdown gets its own big center overlay.)
		var mode_name := tr("TEAM BATTLE") if session.mode == GameSession.Mode.TEAM else tr("FREE-FOR-ALL")
		if session.time_limit > 0.0:
			var left := maxf(0.0, session.time_limit - session.match_time)
			mode_name += "  —  %d:%02d" % [int(left) / 60, int(left) % 60]
		if session.net_rtt_ms >= 0:
			mode_name += "  ·  %d ms" % session.net_rtt_ms
		if session.human_ship_id >= 0:
			_banner.text = mode_name
		else:
			var spec := tr("SPECTATING — ") + mode_name
			if session.watch_ship_id >= 0:
				spec += tr("  ·  following ") + _ship_name(session.watch_ship_id)
			_banner.text = spec

func _update_scoreboard() -> void:
	# Right-aligned in the top-right corner (LTR); left-aligned once it moves to
	# the top-left for RTL, so the columns hug the screen edge either way.
	var align := "left" if _rtl else "right"
	var lines: Array[String] = ["[%s]  " % align + tr("SCORE  K  D")]
	if session.mode == GameSession.Mode.TEAM:
		var totals := session.team_scores()
		var keys := totals.keys()
		keys.sort()
		var team_bits: Array[String] = []
		for k in keys:
			if int(k) >= 0:
				var tc := "#" + WorldView.TEAM_COLORS[int(k) % WorldView.TEAM_COLORS.size()].to_html(false)
				team_bits.append("[color=%s]%s[/color]" % [tc, tr("Team %d: %d") % [int(k) + 1, totals[k]]])
		lines.append("  ".join(team_bits))
	for s in session.leaderboard():
		var team_tag := "" if s.team < 0 else " [lb]T%d]" % (s.team + 1)
		var dead := "" if s.alive else " †"
		lines.append("%s%s  %d  %d/%d%s" % [_ship_bb(s.id), team_tag, s.score, s.kills, s.deaths, dead])
	_score.text = "\n".join(lines) + "[/%s]" % align

func _draw_bars() -> void:
	var human := session.human_ship() if session != null else null
	if human == null:
		return
	var cfg := session.world.config
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
	# Fuel bar (flashes red + LOW under 20%).
	var w := 260.0
	var low_fuel := human.fuel < cfg.max_fuel * 0.2
	_bars.draw_string(ThemeDB.fallback_font, Vector2(0, 12), tr("FUEL"),
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
		_bars.draw_string(ThemeDB.fallback_font, Vector2(50 + w + 8, 12), tr("LOW"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.3, 0.2, 0.5 + 0.5 * pulse))
	# Ammo pips (frame flashes when empty).
	_bars.draw_string(ThemeDB.fallback_font, Vector2(0, 36), tr("AMMO"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.8))
	var pip_w := w / float(cfg.max_ammo)
	for i in range(cfg.max_ammo):
		var c := Color(1.0, 0.9, 0.4) if i < human.ammo else Color(1, 1, 1, 0.10)
		_bars.draw_rect(Rect2(50 + i * pip_w, 26, pip_w - 2.0, 12), c)
	if human.ammo == 0:
		_bars.draw_rect(Rect2(49, 25, w + 2, 14), Color(1.0, 0.3, 0.2, 0.3 + 0.5 * pulse), false, 1.5)
	# Mine pips.
	_bars.draw_string(ThemeDB.fallback_font, Vector2(0, 60), tr("MINE"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.8))
	var mine_w := 30.0
	for i in range(cfg.max_mines):
		var c2 := Color(1.0, 0.45, 0.25) if i < human.mines else Color(1, 1, 1, 0.10)
		_bars.draw_rect(Rect2(50 + i * (mine_w + 4.0), 50, mine_w, 12), c2)
