extends Node2D
## Root of the game. Boots Movie Mode as an attract loop behind a simple menu
## (Movie Mode / Skirmish vs AI / Quit, with mode, difficulty, and ship-count
## selectors). The menu is built in code; ESC toggles it in-game.

var session := GameSession.new()
var view: WorldView
var hud: Hud

var net_host: NetHost
var net_client: NetClient

var _menu: CanvasLayer
var _mode_btn: OptionButton
var _diff_slider: HSlider
var _ships_slider: HSlider
var _limit_slider: HSlider
var _time_slider: HSlider
var _respawn_slider: HSlider
var _lives_slider: HSlider
var _hazard_slider: HSlider
var _star_slider: HSlider
var _planets_slider: HSlider
var _map_slider: HSlider
var _edge_check: CheckButton
var _slider_readouts := {}         ## HSlider -> [readout LineEdit, fmt Callable]
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _server_list: ItemList
var _net_status: Label
var _lan: LanDiscovery
var _server_repr := ""
var _player_name := "PILOT"
var _relay_edit: LineEdit
var _code_edit: LineEdit
var _browser: RelayBrowser
var _relay_rooms: Array = []
var _shown_room_code := ""
var _vol_slider: HSlider
var _fullscreen_check: CheckButton
var _nebula_slider: HSlider
var _stars_slider: HSlider
var _far_check: CheckButton
var _record_check: CheckButton
var _lang_btn: OptionButton
var _language := "en"
var replay_player: ReplayPlayer
var _recorded_gen := -1
var _splash: CanvasLayer
var _splash_prompt: Label
var _credits: CanvasLayer
var _credits_box: VBoxContainer
var _credits_y := 0.0
var _credits_from_boot := false
var _replays_panel: CanvasLayer
var _replays_list: ItemList
var _players_panel: CanvasLayer
var _players_list: ItemList
var _players_note: Label
var _players_detail: Label
var _players_btn: Button
var _spec_check: CheckButton
var _music_check: CheckButton
var _debug_overlay := false
var _keys_panel: CanvasLayer
var _keybind_value_labels := {}    ## action -> Label showing the bound key
var _keys_status: Label
var _awaiting_rebind := ""
var _stats_panel: CanvasLayer
var _stats_list: ItemList
var _stats_detail: Label
var _stats_career: Label
var _stats_key := []               ## [session id, generation] last written to history
var _debug_dump_accum := 0.0
var _race_active := false
var _race_gate := 0          ## next gate index (4 gates x 2 laps = 8 passes)
var _race_t := 0.0

const BINDABLE := [
	["turn_left", "Turn left"],
	["turn_right", "Turn right"],
	["thrust", "Thrust"],
	["fire", "Fire torpedo"],
	["mine", "Drop mine"],
	["hyper", "Hyperspace"],
	["toggle_map", "Toggle minimap"],
	["toggle_feed", "Toggle kill feed"],
	["toggle_score", "Toggle scoreboard"],
]

## OPENING credits — the lineage this game stands on, rolled flat (no Star
## Wars tilt) at boot and replayable via the CREDITS button. The title leads
## at a size that dwarfs the screen, everything else at cinema scale.
## Format: [text, font_size, tier] — tier 0 title / 1 header / 2 name / 3 dim.
const CREDITS_LINES := [
	["XSpaceWar-AI", 229, 0],
	["a 2026 reimagining", 41, 3],
	["", 59, 3],
	["— STANDING ON THE SHOULDERS OF —", 59, 1],
	["", 23, 3],
	["SPACEWAR!   (1962, MIT PDP-1)", 65, 1],
	["Steve Russell · Martin Graetz · Wayne Wiitanen", 53, 2],
	["Peter Samson · Dan Edwards · Alan Kotok", 53, 2],
	["", 35, 3],
	["PDP-11 NETWORKED PORT   (1974)", 65, 1],
	["Bill Seiler · Larry Bryant", 53, 2],
	["", 35, 3],
	["XSPACEWAR 1.2   (1992, X11)", 65, 1],
	["Ron Frederick", 53, 2],
	["an early serverless networked multiplayer game", 41, 3],
	["github.com/ronf  ·  timeheart.net/spacewar", 41, 3],
	["", 59, 3],
	["— THIS GAME —", 59, 1],
	["", 35, 3],
	["ARCHITECTURE & DESIGN", 65, 1],
	["Aaron K. Clark (CryptoJones)", 53, 2],
	["", 35, 3],
	["PLAY TESTERS (ALPHABETICAL)", 65, 1],
	["Roger Bergling · Al Bredthauer · Samuel Bredthauer", 53, 2],
	["Kevin Christiansen (PE) · Brad Cramer · Claude Fable 5", 53, 2],
	["Trevor Flurry · Henry Hannah · Patrick Hannah", 53, 2],
	["Shannon (Learn) Koski · Beaux Onofrio · Nick Onofrio · Rob Orr", 53, 2],
	["Adam Testagrossa · Nate Tiller · John Van Lowe · Jeremy Zhao", 53, 2],
	["", 35, 3],
	["PROGRAMMING", 65, 1],
	["Claude Fable 5", 53, 2],
	["", 35, 3],
	["GITHUB / CODEBERG CONTRIBUTORS", 65, 1],
	["This Could Be You!", 53, 2],
	["", 35, 3],
	["engine: Godot 4 — every pixel and sound procedurally generated", 41, 3],
	["title font: Orbitron by Matt McInerney (SIL Open Font License 1.1)", 41, 3],
	["", 59, 3],
	["SPECIAL THANKS", 65, 1],
	["John Van Lowe (JVL)", 53, 2],
	["for all the nights gaming in 90s-era Dickinson, Texas", 41, 3],
	["HTMFPWGCBNOTDOD!", 41, 3],
	["", 59, 3],
	["Source Code Available At:", 41, 3],
	["https://github.com/CryptoJones/XSpaceWar-AI", 47, 2],
	["", 23, 3],
	["Apache 2.0 License", 41, 3],
]

const SETTINGS_PATH := "user://settings.cfg"
const REPLAY_DIR := "user://replays"

## Selectable UI languages: [locale code, endonym shown in its own language].
## "en" is the source language (no catalog — strings fall through to English).
## Each non-en entry must have a locale/<code>.po registered in project.godot
## under [internationalization]. Adding a language = add a .po + a row here.
const LOCALES := [
	["en", "English"],
	["es", "Español"],
	["fr", "Français"],
	["zh_CN", "简体中文"],
	["ar", "العربية"],
	["hi", "हिन्दी"],
]

var _title_font: Font

## Orbitron at bold weight — the futuristic display face used for titles
## (OFL-licensed; see assets/fonts/ and NOTICE). Falls back loudly to the
## default font if the import cache is missing the asset.
func _get_title_font() -> Font:
	if _title_font == null:
		var base: FontFile = load("res://assets/fonts/Orbitron.ttf")
		if base == null:
			push_warning("Orbitron not imported — run: godot --headless --path . --import")
			_title_font = ThemeDB.fallback_font
		else:
			var fv := FontVariation.new()
			fv.base_font = base
			# The variation dict is keyed by OpenType tag, not name.
			var ts := TextServerManager.get_primary_interface()
			fv.variation_opentype = {ts.name_to_tag("wght"): 700}
			_title_font = fv
	return _title_font

func _ready() -> void:
	_apply_startup_locale()
	_setup_font_fallbacks()
	view = WorldView.new()
	view.session = session
	add_child(view)

	hud = Hud.new()
	hud.session = session
	add_child(hud)

	_build_menu()
	_build_splash()
	_build_credits()
	_build_replays_panel()
	_build_stats_panel()
	_build_keys_panel()
	_build_players_panel()
	_load_settings()
	if _player_name == "PILOT" or _player_name == "":
		var user := OS.get_environment("USER")
		_player_name = user.to_upper().left(12) if user != "" else "PILOT"
	_name_edit.text = _player_name
	_lan = LanDiscovery.listener()
	if "--debug" in OS.get_cmdline_args() or "--debug" in OS.get_cmdline_user_args():
		_debug_overlay = true
		hud.debug_echo = true
		print("[debug] XSpaceWar-AI v%s — debug mode (F3 overlay on, logs verbose)"
			% str(ProjectSettings.get_setting("application/config/version", "?")))
		print("[debug] adapter: %s | renderer: %s" % [
			RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_method()])
	session.start_movie()
	# Boot sequence: credits roll -> splash (controls, press SPACE) -> menu.
	set_menu_visible(false)
	_start_credits(true)

func _process(dt: float) -> void:
	# Credits roll scrolls up and ends past its own height; splash prompt blinks.
	if _credits.visible:
		var vp := get_viewport().get_visible_rect().size
		_credits_y -= 190.0 * dt  # cinema-scale text wants a brisker roll
		_credits_box.position = Vector2((vp.x - _credits_box.size.x) * 0.5, _credits_y)
		if _credits_y < -_credits_box.size.y - 40.0:
			_end_credits()
	if _splash.visible:
		_splash_prompt.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	# Record finished matches to the history (once per match, authoritative
	# or synced view alike — but only matches we actually flew in).
	var active := view.session
	var stats_key := [active.get_instance_id(), active.generation]
	if active.match_over and replay_player == null and active.human_ship_id >= 0 \
			and _stats_key != stats_key:
		_stats_key = stats_key
		MatchStats.append_entry(MatchStats.entry_from_session(active,
			Time.get_datetime_string_from_system(false, true)))
	# Rotate recordings across auto-restarts; bounce to menu when a replay ends.
	if session.finished_recorder != null \
			or (session.recorder != null and session.generation != _recorded_gen):
		_finalize_recording()
		_maybe_start_recording()
	if replay_player != null and replay_player.finished:
		_teardown_net()
		session.start_movie()
		set_menu_visible(true)
		_net_status.text = tr("Replay finished.")
	# A dropped/refused connection bounces back to the menu over attract mode.
	if net_client != null and net_client.state == NetClient.State.FAILED:
		var why := net_client.error_msg
		_teardown_net()
		session.start_movie()
		set_menu_visible(true)
		_net_status.text = tr("Disconnected: %s") % why
	# Surface the relay room code once the relay assigns it.
	if net_host != null and net_host.room_code() != "" \
			and net_host.room_code() != _shown_room_code:
		_shown_room_code = net_host.room_code()
		_net_status.text = tr("Hosting online — room code: %s") % _shown_room_code
	if net_host != null and net_host.transport_failed():
		_net_status.text = tr("Relay link lost — clients can no longer reach this game.")
	if _browser != null and not _browser.done:
		_browser.update(dt)
		if _browser.done:
			if _browser.error != "":
				_net_status.text = tr("Browse failed: %s") % _browser.error
			else:
				_relay_rooms = _browser.servers
				_net_status.text = "" if not _relay_rooms.is_empty() else tr("No online games right now.")
			_server_repr = "force"  # rebuild the merged list
	if _menu.visible:
		_refresh_server_list(dt)
	_update_race(dt)
	if _debug_overlay:
		hud.set_debug(_debug_text())
		if hud.debug_echo:
			_debug_dump_accum += dt
			if _debug_dump_accum >= 5.0:
				_debug_dump_accum = 0.0
				print("[debug] ", _debug_text().replace("\n", " | "))

# --------------------------------------------------------------------------
# Menu
# --------------------------------------------------------------------------

func _build_menu() -> void:
	_menu = CanvasLayer.new()
	_menu.layer = 20

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "XSpaceWar-AI"
	title.add_theme_font_override("font", _get_title_font())
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("a networked space-fighter, est. 1962  ·  v%s") \
		% str(ProjectSettings.get_setting("application/config/version", "?"))
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(subtitle)
	# ----------------------------------------------------------------------
	# (psst: nothing to see here. certainly not a stock car race in space.)
	var secret := Button.new()
	secret.flat = true
	secret.text = ""
	secret.custom_minimum_size = Vector2(54, 18)
	secret.focus_mode = Control.FOCUS_NONE
	secret.mouse_default_cursor_shape = Control.CURSOR_ARROW
	secret.pressed.connect(_start_race_egg)
	subtitle.add_child(secret)
	secret.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	secret.position += Vector2(-92, -9)

	# Three calm tabs instead of one crowded column.
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(580, 420)
	outer.add_child(tabs)
	tabs.add_child(_build_match_tab())
	tabs.add_child(_build_net_tab())
	tabs.add_child(_build_options_tab())

	_net_status = Label.new()
	_net_status.add_theme_font_size_override("font_size", 13)
	_net_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	_net_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_net_status)

	# Bottom row, always visible: QUIT and CREDITS left/center, PLAY right.
	var bottom_row := HBoxContainer.new()
	var quit := Button.new()
	quit.text = "QUIT"
	quit.pressed.connect(_on_quit_pressed)
	_apply_button_border(quit, 3, false)
	bottom_row.add_child(quit)
	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer_l)
	var credits_btn := Button.new()
	credits_btn.text = "CREDITS"
	credits_btn.pressed.connect(_on_credits_pressed)
	_apply_button_border(credits_btn, 3, false)
	bottom_row.add_child(credits_btn)
	var keys_btn := Button.new()
	keys_btn.text = "KEY BINDINGS"
	keys_btn.pressed.connect(_on_keys_pressed)
	_apply_button_border(keys_btn, 3, false)
	bottom_row.add_child(keys_btn)
	# Host-only: manage connected players (kick/ban). Hidden until hosting.
	_players_btn = Button.new()
	_players_btn.text = "PLAYERS"
	_players_btn.pressed.connect(_on_players_pressed)
	_apply_button_border(_players_btn, 3, false)
	_players_btn.visible = false
	bottom_row.add_child(_players_btn)
	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer_r)
	var play := Button.new()
	play.text = "PLAY \u2014 Skirmish vs AI"
	play.pressed.connect(_on_play_pressed)
	play.add_theme_font_size_override("font_size", 18)
	_apply_button_border(play, 4, true)
	bottom_row.add_child(play)
	outer.add_child(bottom_row)

	add_child(_menu)

## A labelled slider row with a live value readout (the standard control for
## every numeric match option — sliders everywhere, per Aaron).
func _slider_row(grid: GridContainer, text: String, lo: float, hi: float,
		step: float, init: float, fmt: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = init
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(s)
	# The readout doubles as an integer input: click, type an exact value,
	# Enter (or click away) applies it — the slider follows.
	var readout := LineEdit.new()
	readout.custom_minimum_size.x = 92
	readout.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 14)
	readout.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	readout.text = String(fmt.call(init))
	box.add_child(readout)
	_slider_readouts[s] = [readout, fmt]
	s.value_changed.connect(func(v: float): readout.text = String(fmt.call(v)))
	var apply_text := func() -> void:
		var digits := ""
		for ch in readout.text:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != "":
			s.value = clampf(float(int(digits)), s.min_value, s.max_value)
		readout.text = String(fmt.call(s.value))
	readout.focus_entered.connect(func(): readout.text = str(int(s.value)); readout.select_all.call_deferred())
	readout.text_submitted.connect(func(_t: String): apply_text.call(); readout.release_focus())
	readout.focus_exited.connect(apply_text)
	_grid_row(grid, text, box)
	return s

func _refresh_slider_readouts() -> void:
	for s in _slider_readouts:
		var pair: Array = _slider_readouts[s]
		(pair[0] as LineEdit).text = String((pair[1] as Callable).call((s as HSlider).value))

## One labelled row in a settings grid: fixed label column, control expands.
func _grid_row(grid: GridContainer, text: String, control: Control) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 150
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)

func _tab_page(tab_name: String) -> Array:
	var page := MarginContainer.new()
	page.name = tab_name
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		page.add_theme_constant_override(side, 18)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	page.add_child(v)
	return [page, v]

func _build_match_tab() -> Control:
	var parts := _tab_page("MATCH")
	var v: VBoxContainer = parts[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)

	_mode_btn = OptionButton.new()
	_mode_btn.add_item("Free-for-all")
	_mode_btn.add_item("Team battle")
	_grid_row(grid, "Mode", _mode_btn)

	_diff_slider = _slider_row(grid, "AI difficulty", 0, 3, 1,
		BotController.Difficulty.VETERAN,
		func(x: float) -> String: return tr(["Rookie", "Veteran", "Ace", "Insane"][int(x)]))
	_ships_slider = _slider_row(grid, "Ships", 1, 16, 1, 8,
		func(x: float) -> String: return tr("1 (solo)") if int(x) == 1 else str(int(x)))
	_limit_slider = _slider_row(grid, "Score limit", 0, 1024, 1, 10,
		func(x: float) -> String: return tr("endless") if int(x) == 0 else str(int(x)))
	_time_slider = _slider_row(grid, "Time limit", 0, 30, 1, 0,
		func(x: float) -> String: return tr("no clock") if int(x) == 0 else tr("%d min") % int(x))
	_respawn_slider = _slider_row(grid, "Respawn", 1, 15, 1, 6,
		func(x: float) -> String: return tr("%d s") % int(x))
	_lives_slider = _slider_row(grid, "Lives", 0, 64, 1, 0,
		func(x: float) -> String: return tr("unlimited") if int(x) == 0 else str(int(x)))
	_hazard_slider = _slider_row(grid, "Asteroids", 0, 100, 1, 30,
		func(x: float) -> String: return tr("none") if int(x) == 0 else tr("%d%%") % int(x))
	_star_slider = _slider_row(grid, "Star size", 5, 100, 1, 25,
		func(x: float) -> String: return tr("%d (classic)") % int(x) if int(x) == 25 else str(int(x)))
	_planets_slider = _slider_row(grid, "Planets", 0, 6, 1, 2,
		func(x: float) -> String: return tr("none") if int(x) == 0 else str(int(x)))
	_map_slider = _slider_row(grid, "Map size", 2601, 40000, 1000, 40000,
		func(x: float) -> String: return tr("%d u") % int(x))

	_edge_check = CheckButton.new()
	_edge_check.text = "Lethal map edge"
	_edge_check.tooltip_text = "Off: the map wraps around · On: the border destroys ships"
	_grid_row(grid, "Boundary", _edge_check)

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stretch)

	var movie := Button.new()
	movie.text = "WATCH — Movie Mode"
	movie.pressed.connect(_on_movie_pressed)
	v.add_child(movie)
	return parts[0]

func _build_net_tab() -> Control:
	var parts := _tab_page("MULTIPLAYER")
	var v: VBoxContainer = parts[1]

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = "Pilot name"
	name_label.custom_minimum_size.x = 150
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "shown on every scoreboard"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t: String):
		var clean := NetProtocol.sanitize_name(t)
		_player_name = clean
		if t != clean and t.strip_edges() != "":
			var col := _name_edit.caret_column
			_name_edit.text = clean
			_name_edit.caret_column = mini(col, clean.length()))
	_name_edit.focus_exited.connect(_save_settings)
	name_row.add_child(_name_edit)
	v.add_child(name_row)

	var host_btn := Button.new()
	host_btn.text = "HOST \u2014 LAN skirmish"
	host_btn.pressed.connect(_on_host_pressed)
	v.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "host ip (or ip:port)"
	_ip_edit.tooltip_text = "Game port defaults to UDP 24642"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)
	var join_btn := Button.new()
	join_btn.text = "JOIN IP"
	join_btn.pressed.connect(_on_join_ip_pressed)
	join_row.add_child(join_btn)
	_spec_check = CheckButton.new()
	_spec_check.text = "Spectate"
	_spec_check.tooltip_text = "Join without taking a ship \u2014 the action camera directs"
	join_row.add_child(_spec_check)
	v.add_child(join_row)

	v.add_child(HSeparator.new())

	var online_row := HBoxContainer.new()
	online_row.add_theme_constant_override("separation", 8)
	_relay_edit = LineEdit.new()
	var env_relay := OS.get_environment("XSW_RELAY")
	_relay_edit.text = env_relay if env_relay != "" else ""
	_relay_edit.placeholder_text = "relay address (ip[:port])"
	_relay_edit.tooltip_text = "Relay port defaults to UDP 24645"
	_relay_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	online_row.add_child(_relay_edit)
	var host_online_btn := Button.new()
	host_online_btn.text = "HOST ONLINE"
	host_online_btn.pressed.connect(_on_host_online_pressed)
	online_row.add_child(host_online_btn)
	var browse_btn := Button.new()
	browse_btn.text = "BROWSE"
	browse_btn.pressed.connect(_on_browse_pressed)
	online_row.add_child(browse_btn)
	v.add_child(online_row)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "room code"
	_code_edit.max_length = RelayProtocol.CODE_LEN
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code_edit)
	var join_code_btn := Button.new()
	join_code_btn.text = "JOIN CODE"
	join_code_btn.pressed.connect(_on_join_code_pressed)
	code_row.add_child(join_code_btn)
	v.add_child(code_row)

	var lan_label := Label.new()
	lan_label.text = "Servers \u2014 LAN auto-discovered + online via BROWSE (double-click to join):"
	lan_label.add_theme_font_size_override("font_size", 13)
	lan_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.8))
	v.add_child(lan_label)

	_server_list = ItemList.new()
	_server_list.custom_minimum_size = Vector2(0, 120)
	_server_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_server_list.item_activated.connect(_on_server_activated)
	v.add_child(_server_list)
	return parts[0]

func _build_options_tab() -> Control:
	var parts := _tab_page("OPTIONS")
	var v: VBoxContainer = parts[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)

	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0
	_vol_slider.max_value = 100
	_vol_slider.value = 80
	_vol_slider.value_changed.connect(_on_volume_changed)
	_grid_row(grid, "Volume", _vol_slider)

	_nebula_slider = HSlider.new()
	_nebula_slider.min_value = 0
	_nebula_slider.max_value = 100
	_nebula_slider.value = 100
	_nebula_slider.tooltip_text = "Colored nebula wisps (0 = pure black space)"
	_nebula_slider.value_changed.connect(func(_v: float): _apply_sky(); _save_settings())
	_grid_row(grid, "Nebula", _nebula_slider)

	_stars_slider = HSlider.new()
	_stars_slider.min_value = 0
	_stars_slider.max_value = 100
	_stars_slider.value = 9
	_stars_slider.tooltip_text = "Background star brightness"
	_stars_slider.value_changed.connect(func(_v: float): _apply_sky(); _save_settings())
	_grid_row(grid, "Stars", _stars_slider)

	_lang_btn = OptionButton.new()
	# Endonyms always render in their own language — never auto-translated.
	_lang_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for pair in LOCALES:
		_lang_btn.add_item(String(pair[1]))
	_lang_btn.item_selected.connect(_on_language_selected)
	_grid_row(grid, "Language", _lang_btn)

	v.add_child(HSeparator.new())

	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 14)
	_music_check = CheckButton.new()
	_music_check.text = "Music"
	_music_check.set_pressed_no_signal(true)
	_music_check.toggled.connect(func(on: bool): view.set_music_enabled(on); _save_settings())
	toggles.add_child(_music_check)
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = "Fullscreen"
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	toggles.add_child(_fullscreen_check)
	_far_check = CheckButton.new()
	_far_check.text = "Far stars"
	_far_check.tooltip_text = "Extra layer of large, slow distant stars"
	_far_check.toggled.connect(func(_on: bool): _apply_sky(); _save_settings())
	toggles.add_child(_far_check)
	_record_check = CheckButton.new()
	_record_check.text = "Record matches"
	_record_check.tooltip_text = "Save input recordings (tiny files; bit-exact playback)"
	_record_check.toggled.connect(func(_on: bool): _save_settings())
	toggles.add_child(_record_check)
	v.add_child(toggles)

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stretch)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var replay_btn := Button.new()
	replay_btn.text = "REPLAYS\u2026"
	replay_btn.pressed.connect(_on_replays_browse_pressed)
	buttons.add_child(replay_btn)
	var stats_btn := Button.new()
	stats_btn.text = "MATCH HISTORY\u2026"
	stats_btn.pressed.connect(_on_stats_pressed)
	buttons.add_child(stats_btn)
	v.add_child(buttons)
	return parts[0]

func _apply_button_border(btn: Button, width: int, bright: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		if bright:
			sb.bg_color = Color(0.10, 0.22, 0.30) if state != "hover" else Color(0.14, 0.30, 0.40)
			sb.border_color = Color(0.55, 0.95, 1.0) if state != "pressed" else Color(1.0, 1.0, 1.0)
		else:
			sb.bg_color = Color(0.09, 0.13, 0.18) if state != "hover" else Color(0.12, 0.18, 0.24)
			sb.border_color = Color(0.40, 0.55, 0.70) if state != "pressed" else Color(0.8, 0.9, 1.0)
		sb.set_border_width_all(width)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 18.0
		sb.content_margin_right = 18.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state, sb)

# --------------------------------------------------------------------------
# Splash + credits (boot: credits roll -> splash -> menu)
# --------------------------------------------------------------------------

func _build_splash() -> void:
	_splash = CanvasLayer.new()
	_splash.layer = 30
	_splash.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 32)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var title := Label.new()
	title.text = "XSpaceWar-AI"
	title.add_theme_font_override("font", _get_title_font())
	title.add_theme_font_size_override("font_size", 138)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "a networked space-fighter, est. 1962"
	subtitle.add_theme_font_size_override("font_size", 42)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(subtitle)
	v.add_child(HSeparator.new())
	v.add_child(_build_controls_panel())
	v.add_child(HSeparator.new())
	_splash_prompt = Label.new()
	_splash_prompt.text = "PRESS SPACE BAR TO CONTINUE"
	_splash_prompt.add_theme_font_size_override("font_size", 66)
	_splash_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_splash_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_splash_prompt)
	add_child(_splash)

## Keyboard + gamepad reference, side by side (shown on the splash).
func _build_controls_panel() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.add_child(_controls_column("KEYBOARD", [
		["%s / %s  or  ◄ ►" % [_key_name("turn_left"), _key_name("turn_right")], "turn"],
		["%s  or  ▲" % _key_name("thrust"), "thrust"],
		[_key_name("fire"), "fire torpedo"],
		["%s  or  ▼" % _key_name("mine"), "drop mine"],
		["%s or ENTER" % _key_name("hyper"), "hyperspace"],
		[_key_name("toggle_map"), "toggle minimap"],
		["ESC", "menu"],
	]))
	row.add_child(VSeparator.new())
	row.add_child(_controls_column("GAMEPAD", [
		["LEFT STICK", "turn"],
		["A / RT", "thrust"],
		["X / RB", "fire torpedo"],
		["B / LT", "drop mine"],
		["Y / LB", "hyperspace"],
		["START", "menu"],
	]))
	return row

func _key_name(action: String) -> String:
	return OS.get_keycode_string(int(view.key_binds[action]))

func _controls_column(header: String, rows: Array) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var h := Label.new()
	h.text = header
	h.add_theme_font_size_override("font_size", 48)
	h.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	v.add_child(h)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 54)
	grid.add_theme_constant_override("v_separation", 9)
	for r in rows:
		var key := Label.new()
		key.text = String(r[0])
		key.add_theme_font_size_override("font_size", 45)
		key.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
		grid.add_child(key)
		var what := Label.new()
		what.text = String(r[1])
		what.add_theme_font_size_override("font_size", 45)
		what.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 0.9))
		grid.add_child(what)
	v.add_child(grid)
	return v

func _build_credits() -> void:
	_credits = CanvasLayer.new()
	_credits.layer = 35
	_credits.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits.add_child(dim)
	var clip := Control.new()
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits.add_child(clip)
	_credits_box = VBoxContainer.new()
	_credits_box.add_theme_constant_override("separation", 8)
	clip.add_child(_credits_box)
	for entry in CREDITS_LINES:
		var l := Label.new()
		l.text = String(entry[0])
		l.add_theme_font_size_override("font_size", int(entry[1]))
		match int(entry[2]):
			0:
				l.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
				l.add_theme_font_override("font", _get_title_font())
			1:
				l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			2:
				l.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
			_:
				l.add_theme_color_override("font_color", Color(0.6, 0.68, 0.8, 0.85))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_credits_box.add_child(l)
	var skip := Label.new()
	skip.text = "SPACE to skip"
	skip.add_theme_font_size_override("font_size", 14)
	skip.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.6))
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skip.position = Vector2(-18, -14)
	_credits.add_child(skip)
	add_child(_credits)

func _start_credits(from_boot: bool) -> void:
	_credits_from_boot = from_boot
	_credits_y = get_viewport().get_visible_rect().size.y + 30.0
	_credits_box.position = Vector2(0.0, _credits_y)
	_credits.visible = true

func _end_credits() -> void:
	_refresh_input_gate_deferred()
	if not _credits.visible:
		return
	_credits.visible = false
	if _credits_from_boot:
		_splash.visible = true
	else:
		set_menu_visible(true)

func _dismiss_splash() -> void:
	_refresh_input_gate_deferred()
	_splash.visible = false
	set_menu_visible(true)

func _on_credits_pressed() -> void:
	set_menu_visible(false)
	_start_credits(false)

## True while ANY modal UI sits over the game: the menu, a panel, the
## credits roll, or the splash. Ship input must never flow then.
func _modal_open() -> bool:
	return _menu.visible or _keys_panel.visible or _replays_panel.visible \
		or _stats_panel.visible or _credits.visible or _splash.visible \
		or _players_panel.visible

## Re-derive the input/pause gates from modal state. Call after ANY
## menu/panel visibility change — keystrokes in a rebind panel must not
## fly the live ship (solo OR networked).
func _refresh_input_gate() -> void:
	var blocked := _modal_open()
	view.input_enabled = not blocked and session.human_ship_id >= 0
	# Modal UI pauses SOLO skirmishes only — Movie Mode keeps playing as the
	# attract backdrop, and net/replay sessions own their own time.
	view.sim_paused = blocked and session.human_ship_id >= 0 \
		and net_host == null and net_client == null and replay_player == null

func _refresh_input_gate_deferred() -> void:
	_refresh_input_gate.call_deferred()

func set_menu_visible(v: bool) -> void:
	_menu.visible = v
	# On macOS, LineEdit nodes retain keyboard focus after their parent hides,
	# silently consuming letter-key events (M, B, K…) before _unhandled_input
	# sees them. Releasing GUI focus whenever the menu closes fixes this.
	if not v:
		get_viewport().gui_release_focus()
	# The kick/ban entry only exists while THIS process is the authoritative host.
	if _players_btn != null:
		_players_btn.visible = net_host != null
	_refresh_input_gate()

## THE one place menu sliders become a running match — every start path
## (solo, LAN host, relay host) calls this; adding a MATCH option means
## touching exactly here plus the slider itself.
## EASTER EGG — THE NEBRASKA 500. Click the year in the subtitle: you,
## alone with the star, four glowing gates, two laps. Gentlemen, etc.
func _start_race_egg() -> void:
	_teardown_net()
	_finalize_recording()
	session.score_limit = 0
	session.time_limit = 0.0
	session.lives = 0
	session.hazard = 0.0
	session.lethal_edges = false
	session.star_scale = 1.0
	session.planet_count = 0
	session.map_size = 12000.0
	session.respawn_seconds = 2.0
	session.host_name = _player_name
	session.start_skirmish(1, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var star := session.world.primary_body()
	var c: Vector2 = star.pos if star != null else Vector2.ZERO
	var r: float = session.world.config.spawn_orbit_radius * 1.5
	view.race_gates = [c + Vector2(r, 0), c + Vector2(0, r),
		c + Vector2(-r, 0), c + Vector2(0, -r)]
	view.race_next_gate = 1   # spawn ring is near gate 0's radius; head for E
	_race_active = true
	_race_gate = 1
	_race_t = 0.0
	set_menu_visible(false)

func _update_race(dt: float) -> void:
	if not _race_active:
		return
	if session.match_over or session.world == null or _menu.visible:
		_end_race(false)
		return
	_race_t += dt
	var human := session.human_ship()
	if human == null:
		return
	var total := 8   # 4 gates x 2 laps
	var gate: Vector2 = view.race_gates[_race_gate % 4]
	hud.banner_override = "🏁 THE NEBRASKA 500 — LAP %d/2 · GATE %d/4 · %.1fs" % [
		((_race_gate - 1) / 4) + 1, ((_race_gate - 1) % 4) + 1, _race_t]
	if human.alive and human.pos.distance_to(gate) < 150.0:
		_race_gate += 1
		view.race_next_gate = _race_gate
		if _race_gate >= total + 1:
			hud.banner_override = ""
			_net_status.text = "🏁 NEBRASKA 500 WON — %.1fs. (You found it.)" % _race_t
			session.match_over = true
			session.winner_ship = session.human_ship_id
			session.restart_timer = GameSession.RESTART_DELAY
			_end_race(true)

func _end_race(won: bool) -> void:
	_race_active = false
	hud.banner_override = ""
	view.race_gates = []
	view.race_next_gate = 0

func _start_configured_match() -> void:
	var mode := GameSession.Mode.TEAM if _mode_btn.selected == 1 else GameSession.Mode.FFA
	session.score_limit = int(_limit_slider.value)
	session.time_limit = _time_slider.value * 60.0
	session.hazard = _hazard_slider.value / 100.0
	session.respawn_seconds = _respawn_slider.value
	session.lethal_edges = _edge_check.button_pressed
	session.star_scale = _star_slider.value / 25.0
	session.map_size = _map_slider.value
	session.lives = int(_lives_slider.value)
	session.planet_count = int(_planets_slider.value)
	_save_settings()
	session.host_name = _player_name
	session.start_skirmish(int(_ships_slider.value), mode, int(_diff_slider.value))

func _on_play_pressed() -> void:
	_teardown_net()
	_finalize_recording()
	_start_configured_match()
	_maybe_start_recording()
	set_menu_visible(false)

func _on_movie_pressed() -> void:
	_teardown_net()
	_finalize_recording()
	session.start_movie()
	set_menu_visible(false)

func _on_quit_pressed() -> void:
	_finalize_recording()
	_teardown_net()
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	var key_pressed: bool = event is InputEventKey and event.pressed and not event.echo
	var pad_pressed: bool = event is InputEventJoypadButton and event.pressed
	# Key-rebind panel: capture the next keypress for the awaited action.
	if _keys_panel != null and _keys_panel.visible:
		if key_pressed:
			if _awaiting_rebind != "":
				var k: int = event.physical_keycode
				if k == KEY_ESCAPE:
					_awaiting_rebind = ""
					_keys_status.text = ""
				elif k in [KEY_F3, KEY_TAB, KEY_N]:
					_keys_status.text = tr("That key is reserved (camera/debug) — pick another.")
				else:
					# Refuse a key already bound to a different action: silent
					# double-binding permanently coupled weapons before.
					var clash := ""
					for action in view.key_binds:
						if action != _awaiting_rebind and int(view.key_binds[action]) == k:
							clash = String(action)
							break
					if clash != "":
						_keys_status.text = tr("Already bound to '%s' — pick another (ESC cancels).") % clash
					else:
						view.key_binds[_awaiting_rebind] = k
						_awaiting_rebind = ""
						_keys_status.text = ""
						_refresh_keybind_labels()
						_save_settings()
			elif event.physical_keycode == KEY_ESCAPE:
				_close_keys_panel()
		return
	# Credits roll: SPACE (or ESC/ENTER/pad A/START) skips.
	if _credits.visible:
		if (key_pressed and event.physical_keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER]) \
				or (pad_pressed and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]):
			_end_credits()
		return
	# Splash: stays up until SPACE (pad A/START also works).
	if _splash.visible:
		if (key_pressed and event.physical_keycode == KEY_SPACE) \
				or (pad_pressed and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]):
			_dismiss_splash()
		return
	# Replay browser / match history / player management: ESC backs to the menu.
	if _replays_panel.visible or _stats_panel.visible or _players_panel.visible:
		if (key_pressed and event.physical_keycode == KEY_ESCAPE) \
				or (pad_pressed and event.button_index == JOY_BUTTON_START):
			_replays_panel.visible = false
			_refresh_input_gate()
			_stats_panel.visible = false
			_players_panel.visible = false
			_refresh_input_gate()
			set_menu_visible(true)
		return
	if key_pressed and event.physical_keycode == KEY_F3:
		_debug_overlay = not _debug_overlay
		if not _debug_overlay:
			hud.set_debug("")
	elif key_pressed and event.physical_keycode == int(view.key_binds["toggle_map"]):
		hud.set_radar_visible(not hud.radar_visible())
		_save_settings()
	elif key_pressed and event.physical_keycode == int(view.key_binds["toggle_feed"]):
		hud.set_feed_visible(not hud.feed_visible())
		_save_settings()
	elif key_pressed and event.physical_keycode == int(view.key_binds["toggle_score"]):
		hud.set_score_visible(not hud.score_visible())
		_save_settings()
	elif key_pressed and event.physical_keycode == KEY_ESCAPE:
		set_menu_visible(not _menu.visible)
	elif pad_pressed and event.button_index == JOY_BUTTON_START:
		set_menu_visible(not _menu.visible)
	elif key_pressed \
			and (event.physical_keycode == KEY_TAB or event.physical_keycode == KEY_N) \
			and not _menu.visible \
			and (replay_player != null
				or (net_client != null and net_client.spectate)
				or view.session.movie_mode
				or (view.session.human_ship() != null
					and not view.session.human_ship().alive)):
		# TAB (or N) cycles the follow-cam anywhere you're a watcher:
		# movie mode, spectating, replays, or eliminated.
		_cycle_watch_target()
	elif replay_player != null and key_pressed:
		if event.physical_keycode == KEY_P:
			replay_player.paused = not replay_player.paused
		elif event.physical_keycode == KEY_F:
			replay_player.speed = 2.0 if replay_player.speed == 1.0 \
				else (4.0 if replay_player.speed == 2.0 else 1.0)
		elif event.physical_keycode == KEY_LEFT:
			replay_player.seek_relative(-600)  # 10s back
		elif event.physical_keycode == KEY_RIGHT:
			replay_player.seek_relative(600)   # 10s ahead

# --------------------------------------------------------------------------
# Networking (M3: LAN host / join / discovery)
# --------------------------------------------------------------------------

func _on_host_pressed() -> void:
	_teardown_net()
	_finalize_recording()
	_start_configured_match()
	net_host = NetHost.new(session)
	# If the default port is squatted (another host, another app), walk up a
	# small range — LAN discovery advertises the ACTUAL port, so joins still
	# work automatically; manual joiners use ip:port from the status line.
	var err := ERR_CANT_CREATE
	var bound_port := NetHost.DEFAULT_PORT
	for try in range(8):
		bound_port = NetHost.DEFAULT_PORT + try
		err = net_host.open(bound_port, true, "%s's arena" % _player_name)
		if err == OK:
			break
	if err != OK:
		_net_status.text = tr("Host failed (error %d) — UDP %d-%d all busy.") \
			% [err, NetHost.DEFAULT_PORT, NetHost.DEFAULT_PORT + 7]
		net_host = null
		return
	view.external_driver = func(dt: float): net_host.update(dt,
		view.gather_local_input() if not _modal_open() else {})
	_maybe_start_recording()
	_net_status.text = tr("Hosting LAN on UDP %d%s — players on your network see you automatically.") \
		% [bound_port, "" if bound_port == NetHost.DEFAULT_PORT else tr(" (default was busy)")]
	set_menu_visible(false)

func _on_join_ip_pressed() -> void:
	var addr := NetProtocol.parse_addr(_ip_edit.text, NetHost.DEFAULT_PORT)
	if addr.is_empty():
		_net_status.text = tr("Enter a host IP first.")
		return
	var ip: String = addr["ip"]
	var port: int = addr["port"]
	_join(ip, port)

func _on_server_activated(index: int) -> void:
	var srv: Variant = _server_list.get_item_metadata(index)
	if typeof(srv) != TYPE_DICTIONARY:
		return
	var d: Dictionary = srv
	if d.has("code"):
		_join_relay(String(d["code"]))
	else:
		_join(String(d["ip"]), int(d.get("port", NetHost.DEFAULT_PORT)))

func _join(ip: String, port: int) -> void:
	_teardown_net()
	net_client = NetClient.new()
	var err := net_client.open(ip, port, _player_name, _spec_check.button_pressed)
	if err != OK:
		_net_status.text = tr("Join failed (error %d).") % err
		net_client = null
		return
	view.session = net_client.session
	hud.session = net_client.session
	view.external_driver = func(dt: float): net_client.update(dt,
		view.gather_local_input() if not _modal_open() else {})
	_net_status.text = ""
	_save_settings()
	set_menu_visible(false)

func _refresh_server_list(dt: float) -> void:
	var found: Array = []
	if _lan != null and _lan.bind_ok:
		found = _lan.poll(dt)
	var entries: Array = []
	var lines: Array[String] = []
	for srv in found:
		entries.append(srv)
		lines.append("[LAN] %s — %s:%d  (%d/%d)" % [String(srv.get("name", "?")),
			String(srv["ip"]), int(srv.get("port", NetHost.DEFAULT_PORT)),
			int(srv.get("players", 0)), int(srv.get("max", 0))])
	for room in _relay_rooms:
		entries.append(room)
		lines.append("[ONLINE] %s — room %s  (%d/%d)" % [String(room.get("name", "?")),
			String(room.get("code", "????")),
			int(room.get("players", 0)), int(room.get("max", 0))])
	var repr := "\n".join(lines)
	if repr == _server_repr:
		return
	_server_repr = repr
	_server_list.clear()
	if entries.is_empty():
		var why := tr("searching LAN…") if (_lan != null and _lan.bind_ok) else tr("LAN discovery unavailable")
		_server_list.add_item(tr("(%s — BROWSE checks the relay)") % why, null, false)
	else:
		for i in range(entries.size()):
			var idx := _server_list.add_item(lines[i])
			_server_list.set_item_metadata(idx, entries[i])

## Parse the relay address field: "ip" or "ip:port". Empty -> error.
func _relay_addr() -> Dictionary:
	return NetProtocol.parse_addr(_relay_edit.text, RelayProtocol.DEFAULT_PORT)

func _on_host_online_pressed() -> void:
	var addr := _relay_addr()
	if addr.is_empty():
		_net_status.text = tr("Enter a relay address first (or set XSW_RELAY).")
		return
	_teardown_net()
	_start_configured_match()
	net_host = NetHost.new(session)
	var err: Error = net_host.open_relay(String(addr["ip"]), int(addr["port"]),
		"%s's arena" % _player_name)
	if err != OK:
		_net_status.text = tr("Relay host failed (error %d).") % err
		net_host = null
		return
	_shown_room_code = ""
	view.external_driver = func(dt: float): net_host.update(dt,
		view.gather_local_input() if not _modal_open() else {})
	_maybe_start_recording()
	_net_status.text = tr("Registering with relay…")
	_save_settings()
	set_menu_visible(false)

func _on_browse_pressed() -> void:
	var addr := _relay_addr()
	if addr.is_empty():
		_net_status.text = tr("Enter a relay address first (or set XSW_RELAY).")
		return
	_browser = RelayBrowser.new()
	if _browser.open(String(addr["ip"]), int(addr["port"])) != OK:
		_net_status.text = tr("Could not reach the relay.")
		_browser = null
		return
	_net_status.text = tr("Browsing online games…")

func _on_join_code_pressed() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	if code.length() != RelayProtocol.CODE_LEN:
		_net_status.text = tr("Room codes are %d characters.") % RelayProtocol.CODE_LEN
		return
	_join_relay(code)

func _join_relay(code: String) -> void:
	var addr := _relay_addr()
	if addr.is_empty():
		_net_status.text = tr("Enter a relay address first (or set XSW_RELAY).")
		return
	_teardown_net()
	net_client = NetClient.new()
	var err: Error = net_client.open_relay(String(addr["ip"]), int(addr["port"]),
		code, _player_name, _spec_check.button_pressed)
	if err != OK:
		_net_status.text = tr("Relay join failed (error %d).") % err
		net_client = null
		return
	view.session = net_client.session
	hud.session = net_client.session
	view.external_driver = func(dt: float): net_client.update(dt,
		view.gather_local_input() if not _modal_open() else {})
	_net_status.text = ""
	set_menu_visible(false)

# --------------------------------------------------------------------------
# Settings (volume / fullscreen, persisted to user://settings.cfg)
# --------------------------------------------------------------------------

func _on_volume_changed(value: float) -> void:
	# 0..100 -> dB; 0 is a true mute.
	var db := linear_to_db(maxf(0.0001, value / 100.0)) if value > 0.0 else -80.0
	AudioServer.set_bus_volume_db(0, db)
	_save_settings()

func _on_fullscreen_toggled(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()

func _apply_sky() -> void:
	view.set_background_prefs(_nebula_slider.value / 100.0,
		_stars_slider.value / 100.0 * 1.5, _far_check.button_pressed)

# --------------------------------------------------------------------------
# Localization (Godot i18n — catalogs in locale/*.po, auto-loaded via
# project.godot [internationalization]. Static Control text auto-translates
# live; format templates / drawn strings are wrapped in tr() at their call
# sites; this just owns the active-locale choice.)
# --------------------------------------------------------------------------

## Boot-time locale: the saved preference if any, else the closest available
## match to the OS locale, else English. Runs before any UI is built so the
## first frame is already in the right language.
func _apply_startup_locale() -> void:
	var cfg := ConfigFile.new()
	var lang := ""
	if cfg.load(SETTINGS_PATH) == OK:
		lang = String(cfg.get_value("i18n", "language", ""))
	if lang == "" or not _locale_available(lang):
		lang = _best_locale()
	_language = lang
	TranslationServer.set_locale(lang)

func _locale_available(code: String) -> bool:
	for pair in LOCALES:
		if String(pair[0]) == code:
			return true
	return false

## Narrow the OS locale (e.g. "es_ES", "fr_CA") to one of our offered
## languages by its language sub-tag; default to English when unmatched.
func _best_locale() -> String:
	var lang := OS.get_locale().split("_")[0].split("-")[0]
	for pair in LOCALES:
		if String(pair[0]) == OS.get_locale() or String(pair[0]).begins_with(lang):
			return String(pair[0])
	return "en"

## Attach script-coverage fonts as per-glyph fallbacks on the default UI font,
## so localized text outside the Latin range (CJK / Devanagari / Arabic) renders
## instead of tofu. The base font is left untouched — Latin and every HUD symbol
## look exactly as before; a Noto fallback is consulted only for glyphs the base
## lacks. The subsets are tiny, built from the catalogs (see tools/build_fonts.sh).
func _setup_font_fallbacks() -> void:
	var base := ThemeDB.fallback_font
	if not (base is FontFile):
		return
	var chain: Array[Font] = []
	for path in [
		"res://assets/fonts/NotoSansSC-subset.ttf",          # CJK (zh)
		"res://assets/fonts/NotoSansDevanagari-subset.ttf",  # Devanagari (hi)
		"res://assets/fonts/NotoSansArabic-subset.ttf",      # Arabic (ar)
	]:
		if ResourceLoader.exists(path):
			var f: Font = load(path)
			if f != null:
				chain.append(f)
	(base as FontFile).fallbacks = chain

## Live language switch from the OPTIONS selector. Static labels re-translate
## themselves on the locale-changed notification; the slider readouts hold
## already-composed strings, so re-run their formatters explicitly.
func _on_language_selected(index: int) -> void:
	_language = String(LOCALES[index][0])
	TranslationServer.set_locale(_language)
	_refresh_slider_readouts()
	_save_settings()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_vol_slider.set_value_no_signal(float(cfg.get_value("audio", "volume", 80.0)))
		_fullscreen_check.set_pressed_no_signal(bool(cfg.get_value("video", "fullscreen", false)))
		_relay_edit.text = String(cfg.get_value("net", "relay", _relay_edit.text))
		var saved_name := String(cfg.get_value("net", "player_name", ""))
		if saved_name != "":
			_player_name = saved_name
		_nebula_slider.set_value_no_signal(float(cfg.get_value("display", "nebula", 100.0)))
		_stars_slider.set_value_no_signal(float(cfg.get_value("display", "stars", 9.0)))
		_far_check.set_pressed_no_signal(bool(cfg.get_value("display", "far_stars", false)))
		_record_check.set_pressed_no_signal(bool(cfg.get_value("replay", "record", false)))
		_music_check.set_pressed_no_signal(bool(cfg.get_value("audio", "music", true)))
		hud.set_radar_visible(bool(cfg.get_value("display", "minimap", true)))
		hud.set_feed_visible(bool(cfg.get_value("display", "kill_feed", true)))
		hud.set_score_visible(bool(cfg.get_value("display", "scoreboard", true)))
		# Match setup: restore the player's favorite configuration.
		_mode_btn.select(int(cfg.get_value("match", "mode", 0)))
		_diff_slider.set_value_no_signal(float(cfg.get_value("match", "difficulty", BotController.Difficulty.VETERAN)))
		_ships_slider.set_value_no_signal(float(cfg.get_value("match", "ships", 8.0)))
		_limit_slider.set_value_no_signal(float(cfg.get_value("match", "score_limit", 10.0)))
		_time_slider.set_value_no_signal(float(cfg.get_value("match", "time_limit", 0.0)))
		_respawn_slider.set_value_no_signal(float(cfg.get_value("match", "respawn", 6.0)))
		_hazard_slider.set_value_no_signal(float(cfg.get_value("match", "hazard", 30.0)))
		_star_slider.set_value_no_signal(float(cfg.get_value("match", "star_size", 25.0)))
		_planets_slider.set_value_no_signal(float(cfg.get_value("match", "planets", 2.0)))
		_edge_check.set_pressed_no_signal(bool(cfg.get_value("match", "lethal_edges", false)))
		_map_slider.set_value_no_signal(float(cfg.get_value("match", "map_size", 40000.0)))
		_lives_slider.set_value_no_signal(float(cfg.get_value("match", "lives", 0.0)))
		_refresh_slider_readouts()
		var binds_changed := false
		for pair in BINDABLE:
			var action := String(pair[0])
			var saved := int(cfg.get_value("keys", action, int(view.key_binds[action])))
			if saved != int(view.key_binds[action]):
				view.key_binds[action] = saved
				binds_changed = true
		if binds_changed:
			_rebuild_splash()
	# Apply whatever we ended up with (defaults or loaded).
	var v := _vol_slider.value
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, v / 100.0)) if v > 0.0 else -80.0)
	if _fullscreen_check.button_pressed and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_apply_sky()
	view.set_music_enabled(_music_check.button_pressed)
	# Reflect the locale chosen at boot (_apply_startup_locale) in the selector.
	for i in range(LOCALES.size()):
		if String(LOCALES[i][0]) == _language:
			_lang_btn.select(i)
			break

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", _vol_slider.value)
	cfg.set_value("video", "fullscreen", _fullscreen_check.button_pressed)
	cfg.set_value("net", "relay", _relay_edit.text.strip_edges())
	cfg.set_value("net", "player_name", _player_name)
	cfg.set_value("i18n", "language", _language)
	cfg.set_value("display", "nebula", _nebula_slider.value)
	cfg.set_value("display", "stars", _stars_slider.value)
	cfg.set_value("display", "far_stars", _far_check.button_pressed)
	cfg.set_value("replay", "record", _record_check.button_pressed)
	cfg.set_value("audio", "music", _music_check.button_pressed)
	cfg.set_value("display", "minimap", hud.radar_visible())
	cfg.set_value("display", "kill_feed", hud.feed_visible())
	cfg.set_value("display", "scoreboard", hud.score_visible())
	for pair in BINDABLE:
		cfg.set_value("keys", String(pair[0]), int(view.key_binds[String(pair[0])]))
	cfg.set_value("match", "mode", _mode_btn.selected)
	cfg.set_value("match", "difficulty", int(_diff_slider.value))
	cfg.set_value("match", "ships", _ships_slider.value)
	cfg.set_value("match", "score_limit", _limit_slider.value)
	cfg.set_value("match", "time_limit", _time_slider.value)
	cfg.set_value("match", "respawn", _respawn_slider.value)
	cfg.set_value("match", "hazard", _hazard_slider.value)
	cfg.set_value("match", "star_size", _star_slider.value)
	cfg.set_value("match", "planets", _planets_slider.value)
	cfg.set_value("match", "lethal_edges", _edge_check.button_pressed)
	cfg.set_value("match", "map_size", _map_slider.value)
	cfg.set_value("match", "lives", _lives_slider.value)
	cfg.save(SETTINGS_PATH)

## F3 diagnostics: everything needed to pin down a bug report in one glance.
func _debug_text() -> String:
	var s := view.session
	var lines: Array[String] = ["fps %d" % Engine.get_frames_per_second()]
	if s.world != null:
		var alive := 0
		for sh in s.world.ships:
			if sh.alive:
				alive += 1
		lines.append("tick %d  gen %d  alive %d/%d  torps %d  mines %d" % [s.world.tick,
			s.generation, alive, s.world.ships.size(), s.world.torpedoes.size(),
			s.world.mines.size()])
		var human := s.human_ship()
		if human != null:
			lines.append("ship (%.0f, %.0f)  v %.0f u/s  alive=%s" % [human.pos.x,
				human.pos.y, human.vel.length(), str(human.alive)])
	lines.append(view.debug_summary())
	var role := "solo"
	if net_host != null:
		role = "host: %d players%s" % [net_host.player_count(),
			"" if net_host.room_code() == "" else "  room " + net_host.room_code()]
	elif net_client != null:
		role = "client: state %d%s%s" % [net_client.state,
			"  (spectator)" if net_client.spectate else "",
			"" if net_client.rtt_ms < 0 else "  rtt %dms" % net_client.rtt_ms]
	elif replay_player != null:
		role = "replay: tick %d / %d  speed %.0fx" % [replay_player.session.world.tick,
			replay_player.replay.final_tick, replay_player.speed]
	lines.append(role + ("  paused" if view.sim_paused else ""))
	return "\n".join(lines)

## TAB while spectating or in a replay: lock the camera to each pilot in
## turn, then hand back to the action director after the last.
func _cycle_watch_target() -> void:
	var s := view.session
	if s.world == null:
		return
	var ids: Array[int] = []
	for ship in s.world.ships:
		if ship.alive:
			ids.append(ship.id)
	if ids.is_empty():
		s.watch_ship_id = -1
		return
	ids.sort()
	var pos := ids.find(s.watch_ship_id)
	if pos == -1 or pos == ids.size() - 1:
		s.watch_ship_id = -1 if pos == ids.size() - 1 else ids[0]
	else:
		s.watch_ship_id = ids[pos + 1]
	if s.watch_ship_id < 0:
		_net_status.text = tr("Camera: action director")
	else:
		var nm: String = s.ship_names.get(s.watch_ship_id, "BOT-%d" % s.watch_ship_id)
		_net_status.text = tr("Camera: following %s (TAB cycles)") % nm

func _teardown_net() -> void:
	if net_host != null:
		net_host.close()
		net_host = null
	if net_client != null:
		net_client.close()
		net_client = null
	replay_player = null
	_shown_room_code = ""
	view.external_driver = Callable()
	view.session = session
	hud.session = session

# --------------------------------------------------------------------------
# Replays (record on the authoritative side; play back bit-exact)
# --------------------------------------------------------------------------

func _maybe_start_recording() -> void:
	# Record solo skirmishes and hosted matches — anywhere this process runs
	# the authoritative sim (clients don't; the host's recording is the match).
	if _record_check.button_pressed and not session.movie_mode \
			and session.human_ship_id >= 0 and net_client == null:
		session.recorder = Replay.begin(session)
		_recorded_gen = session.generation

func _finalize_recording() -> void:
	# Prefer the tape the session parked at a match restart (it must never
	# be captured into the rebuilt world); fall back to a live recorder
	# (menu exit / teardown paths).
	var r := session.finished_recorder
	session.finished_recorder = null
	if r == null:
		r = session.recorder
		session.recorder = null
	if r == null:
		return
	if r.final_tick < 300:
		return  # < 5 seconds of match — not worth keeping
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/%s.xsr" % [REPLAY_DIR, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(r.to_bytes())
		f.close()
		_net_status.text = tr("Replay saved (%.0fs): %s") % [r.duration_sec(1.0 / 60.0), path.get_file()]

# --------------------------------------------------------------------------
# Host moderation — kick/ban connected players (#4). Only reachable while THIS
# process is the authoritative host (net_host != null); the dedicated server
# drives the same NetHost API from its console instead.
# --------------------------------------------------------------------------

func _build_players_panel() -> void:
	_players_panel = CanvasLayer.new()
	_players_panel.layer = 26
	_players_panel.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_players_panel.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(460, 0)
	margin.add_child(v)
	var title := Label.new()
	title.text = "MANAGE PLAYERS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	v.add_child(title)
	_players_note = Label.new()
	_players_note.add_theme_font_size_override("font_size", 14)
	_players_note.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.85))
	v.add_child(_players_note)
	_players_list = ItemList.new()
	_players_list.custom_minimum_size = Vector2(0, 180)
	# Callsigns are user content — never run a player's name through tr().
	_players_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_players_list.item_selected.connect(_on_player_selected)
	v.add_child(_players_list)
	# Aim-anomaly detail for the selected pilot (host-side warning, never a ban).
	_players_detail = Label.new()
	_players_detail.add_theme_font_size_override("font_size", 13)
	_players_detail.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	_players_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_players_detail.custom_minimum_size = Vector2(0, 56)
	v.add_child(_players_detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func(): _players_panel.visible = false; _refresh_input_gate(); set_menu_visible(true))
	row.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var kick := Button.new()
	kick.text = "KICK"
	kick.pressed.connect(func(): _moderate_selected(false))
	row.add_child(kick)
	var ban := Button.new()
	ban.text = "BAN"
	ban.tooltip_text = "Kick and block this callsign (and address, on LAN) from rejoining"
	ban.pressed.connect(func(): _moderate_selected(true))
	row.add_child(ban)
	v.add_child(row)
	add_child(_players_panel)

func _on_players_pressed() -> void:
	if net_host == null:
		return
	_refresh_players_list()
	set_menu_visible(false)
	_players_panel.visible = true
	_refresh_input_gate()

func _refresh_players_list() -> void:
	_players_list.clear()
	if net_host == null:
		return
	var players := net_host.connected_players()
	var flagged := 0
	for p in players:
		var sid := int(p["sid"])
		var warn := net_host.is_aim_flagged(sid)
		if warn:
			flagged += 1
		var idx := _players_list.add_item(("⚠ " if warn else "") + String(p["name"]))
		_players_list.set_item_metadata(idx, sid)
	if players.is_empty():
		_players_list.add_item(tr("(no players connected — bots hold every slot)"), null, false)
		_players_detail.text = ""
	else:
		_players_list.select(0)
		_on_player_selected(0)
	_players_note.text = tr("%d connected · %d banned · %d flagged") \
		% [players.size(), net_host.ban_list().size(), flagged]

## Show the selected pilot's aim-anomaly verdict (a warning to review, not a
## ban — see AimAnalyzer). Clean pilots get a reassuring line.
func _on_player_selected(idx: int) -> void:
	if net_host == null:
		return
	var meta: Variant = _players_list.get_item_metadata(idx)
	if typeof(meta) != TYPE_INT:
		_players_detail.text = ""
		return
	var reasons := net_host.aim_reasons(int(meta))
	if reasons.is_empty():
		_players_detail.text = tr("Aim looks human — nothing flagged.")
	else:
		_players_detail.text = "⚠ " + "\n⚠ ".join(reasons)

func _moderate_selected(ban: bool) -> void:
	if net_host == null:
		return
	var sel := _players_list.get_selected_items()
	if sel.is_empty():
		return
	var meta: Variant = _players_list.get_item_metadata(sel[0])
	if typeof(meta) != TYPE_INT:
		return
	var sid := int(meta)
	var pname := ""
	for p in net_host.connected_players():
		if int(p["sid"]) == sid:
			pname = String(p["name"])
			break
	if net_host.kick_ship(sid, "Banned by the host." if ban else "Kicked by the host.", ban):
		_net_status.text = (tr("Banned %s.") if ban else tr("Kicked %s.")) % pname
	_refresh_players_list()

func _build_keys_panel() -> void:
	_keys_panel = CanvasLayer.new()
	_keys_panel.layer = 26
	_keys_panel.visible = false
	_refresh_input_gate()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_keys_panel.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	var title := Label.new()
	title.text = "KEY BINDINGS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	v.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	for pair in BINDABLE:
		var action := String(pair[0])
		var name_l := Label.new()
		name_l.text = String(pair[1])
		name_l.custom_minimum_size.x = 130
		grid.add_child(name_l)
		var key_l := Label.new()
		key_l.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
		grid.add_child(key_l)
		_keybind_value_labels[action] = key_l
		var btn := Button.new()
		btn.text = "REBIND"
		btn.pressed.connect(func():
			_awaiting_rebind = action
			_keys_status.text = tr("Press a key for %s… (ESC cancels)") % tr(String(pair[1]))
			btn.release_focus())
		grid.add_child(btn)
	v.add_child(grid)
	_keys_status = Label.new()
	_keys_status.add_theme_font_size_override("font_size", 14)
	_keys_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	v.add_child(_keys_status)
	var note := Label.new()
	note.text = "Arrows / Enter always work as alternates."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.7))
	v.add_child(note)
	var close := Button.new()
	close.text = "DONE"
	close.pressed.connect(_close_keys_panel)
	v.add_child(close)
	add_child(_keys_panel)
	_refresh_keybind_labels()

func _refresh_keybind_labels() -> void:
	for action in _keybind_value_labels:
		(_keybind_value_labels[action] as Label).text = \
			OS.get_keycode_string(int(view.key_binds[action]))

func _on_keys_pressed() -> void:
	_refresh_keybind_labels()
	_keys_status.text = ""
	_awaiting_rebind = ""
	set_menu_visible(false)
	_keys_panel.visible = true
	_refresh_input_gate()

func _close_keys_panel() -> void:
	_keys_panel.visible = false
	_refresh_input_gate()
	_awaiting_rebind = ""
	_save_settings()
	_rebuild_splash()
	set_menu_visible(true)

## Splash shows live binds, so rebuild it after they change.
func _rebuild_splash() -> void:
	var was_visible := _splash.visible
	_splash.queue_free()
	_build_splash()
	_splash.visible = was_visible

func _build_stats_panel() -> void:
	_stats_panel = CanvasLayer.new()
	_stats_panel.layer = 25
	_stats_panel.visible = false
	_refresh_input_gate()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_panel.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(560, 0)
	margin.add_child(v)
	var title := Label.new()
	title.text = "MATCH HISTORY"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	v.add_child(title)
	_stats_career = Label.new()
	_stats_career.add_theme_font_size_override("font_size", 15)
	_stats_career.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	v.add_child(_stats_career)
	_stats_list = ItemList.new()
	_stats_list.custom_minimum_size = Vector2(0, 180)
	_stats_list.item_selected.connect(_on_stats_selected)
	v.add_child(_stats_list)
	_stats_detail = Label.new()
	_stats_detail.add_theme_font_size_override("font_size", 14)
	_stats_detail.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.9))
	_stats_detail.custom_minimum_size = Vector2(0, 120)
	v.add_child(_stats_detail)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func(): _stats_panel.visible = false; set_menu_visible(true))
	v.add_child(back)
	add_child(_stats_panel)

func _on_stats_pressed() -> void:
	var career := MatchStats.career()
	_stats_career.text = tr("Career:  %d matches  ·  %d wins  ·  %d kills / %d deaths") \
		% [career["matches"], career["wins"], career["kills"], career["deaths"]]
	_stats_list.clear()
	_stats_detail.text = ""
	var recent := MatchStats.load_recent(50)
	if recent.is_empty():
		_stats_list.add_item("(no finished matches yet — set a score or time limit and play)", null, false)
	for e in recent:
		var idx := _stats_list.add_item("%s   %s   %d:%02d   winner: %s%s" % [
			String(e.get("when", "?")), String(e.get("mode", "?")),
			int(e.get("dur", 0)) / 60, int(e.get("dur", 0)) % 60,
			String(e.get("winner", "?")),
			"   ★" if bool(e.get("won", false)) else ""])
		_stats_list.set_item_metadata(idx, e)
	set_menu_visible(false)
	_stats_panel.visible = true
	_refresh_input_gate()

func _on_stats_selected(idx: int) -> void:
	var e: Variant = _stats_list.get_item_metadata(idx)
	if typeof(e) != TYPE_DICTIONARY:
		return
	var lines: Array[String] = []
	var rank := 1
	for p in e.get("players", []):
		lines.append("%d.  %s%s   %d   (%d/%d)%s" % [rank, String(p.get("n", "?")),
			"" if int(p.get("t", -1)) < 0 else " [T%d]" % (int(p["t"]) + 1),
			int(p.get("s", 0)), int(p.get("k", 0)), int(p.get("d", 0)),
			"   ← you" if bool(p.get("you", false)) else ""])
		rank += 1
	_stats_detail.text = "\n".join(lines)

func _build_replays_panel() -> void:
	_replays_panel = CanvasLayer.new()
	_replays_panel.layer = 25
	_replays_panel.visible = false
	_refresh_input_gate()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_replays_panel.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(460, 0)
	margin.add_child(v)
	var title := Label.new()
	title.text = "REPLAYS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	v.add_child(title)
	_replays_list = ItemList.new()
	_replays_list.custom_minimum_size = Vector2(0, 220)
	_replays_list.item_activated.connect(func(idx: int): _watch_replay(String(_replays_list.get_item_metadata(idx))))
	v.add_child(_replays_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func(): _replays_panel.visible = false; set_menu_visible(true))
	row.add_child(back)
	var del := Button.new()
	del.text = "DELETE"
	del.pressed.connect(_on_replay_delete_pressed)
	row.add_child(del)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var watch := Button.new()
	watch.text = "WATCH"
	watch.pressed.connect(_on_replay_watch_pressed)
	row.add_child(watch)
	v.add_child(row)
	add_child(_replays_panel)

func _replay_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if fname.ends_with(".xsr"):
			out.append(fname)
	out.sort()
	out.reverse()  # newest first (timestamps sort lexically)
	return out

func _refresh_replays_list() -> void:
	_replays_list.clear()
	for fname in _replay_files():
		var path := "%s/%s" % [REPLAY_DIR, fname]
		var rec := Replay.from_bytes(FileAccess.get_file_as_bytes(path))
		var label := fname.trim_suffix(".xsr")
		if rec != null:
			var secs := int(rec.duration_sec(1.0 / 60.0))
			label += "   —   %s · %d pilots · %d:%02d" % [
				"TEAM" if int(rec.header.get("mode", 0)) == GameSession.Mode.TEAM else "FFA",
				(rec.header.get("ros", []) as Array).size(), secs / 60, secs % 60]
		else:
			label += "   —   (unreadable)"
		var idx := _replays_list.add_item(label)
		_replays_list.set_item_metadata(idx, path)
	if _replays_list.item_count == 0:
		_replays_list.add_item("(no replays yet — enable 'Record matches' and play)", null, false)
	else:
		_replays_list.select(0)

func _on_replays_browse_pressed() -> void:
	_refresh_replays_list()
	set_menu_visible(false)
	_replays_panel.visible = true
	_refresh_input_gate()

func _selected_replay_path() -> String:
	var sel := _replays_list.get_selected_items()
	if sel.is_empty():
		return ""
	var meta: Variant = _replays_list.get_item_metadata(sel[0])
	return String(meta) if meta != null else ""

func _on_replay_watch_pressed() -> void:
	var path := _selected_replay_path()
	if path != "":
		_watch_replay(path)

func _on_replay_delete_pressed() -> void:
	var path := _selected_replay_path()
	if path == "":
		return
	DirAccess.remove_absolute(path)
	_refresh_replays_list()

func _watch_replay(path: String) -> void:
	_finalize_recording()
	_teardown_net()
	_replays_panel.visible = false
	_refresh_input_gate()
	var rec := Replay.from_bytes(FileAccess.get_file_as_bytes(path))
	if rec == null:
		_net_status.text = tr("Could not read %s.") % path.get_file()
		set_menu_visible(true)
		return
	replay_player = ReplayPlayer.new()
	if not replay_player.load_replay(rec):
		_net_status.text = tr("Replay is out of sync with this game version.")
		replay_player = null
		set_menu_visible(true)
		return
	view.session = replay_player.session
	hud.session = replay_player.session
	var rp := replay_player
	view.external_driver = func(dt: float): rp.update(dt)
	_net_status.text = tr("Replaying %s — P pause, F speed, ◄/► seek 10s, ESC menu") % path.get_file()
	set_menu_visible(false)
