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
var _diff_btn: OptionButton
var _ships_spin: SpinBox
var _limit_spin: SpinBox
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

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	view = WorldView.new()
	view.session = session
	add_child(view)

	hud = Hud.new()
	hud.session = session
	add_child(hud)

	_build_menu()
	_load_settings()
	var user := OS.get_environment("USER")
	_player_name = user.to_upper().left(12) if user != "" else "PILOT"
	_lan = LanDiscovery.listener()
	session.start_movie()
	set_menu_visible(true)

func _process(dt: float) -> void:
	# A dropped/refused connection bounces back to the menu over attract mode.
	if net_client != null and net_client.state == NetClient.State.FAILED:
		var why := net_client.error_msg
		_teardown_net()
		session.start_movie()
		set_menu_visible(true)
		_net_status.text = "Disconnected: %s" % why
	# Surface the relay room code once the relay assigns it.
	if net_host != null and net_host.room_code() != "" \
			and net_host.room_code() != _shown_room_code:
		_shown_room_code = net_host.room_code()
		_net_status.text = "Hosting online — room code: %s" % _shown_room_code
	if net_host != null and net_host.transport_failed():
		_net_status.text = "Relay link lost — clients can no longer reach this game."
	if _browser != null and not _browser.done:
		_browser.update(dt)
		if _browser.done:
			if _browser.error != "":
				_net_status.text = "Browse failed: %s" % _browser.error
			else:
				_relay_rooms = _browser.servers
				_net_status.text = "" if not _relay_rooms.is_empty() else "No online games right now."
			_server_repr = "force"  # rebuild the merged list
	if _menu.visible:
		_refresh_server_list(dt)

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
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 380
	margin.add_child(box)

	var title := Label.new()
	title.text = "XSPACEWAR-AI"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "a networked space-fighter, est. 1962"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	_mode_btn = OptionButton.new()
	_mode_btn.add_item("Free-for-all")
	_mode_btn.add_item("Team battle")
	box.add_child(_labelled("Mode", _mode_btn))

	_diff_btn = OptionButton.new()
	for n in ["Rookie", "Veteran", "Ace", "Insane"]:
		_diff_btn.add_item(n)
	_diff_btn.select(BotController.Difficulty.VETERAN)
	box.add_child(_labelled("AI difficulty", _diff_btn))

	_ships_spin = SpinBox.new()
	_ships_spin.min_value = 2
	_ships_spin.max_value = 12
	_ships_spin.value = 8
	box.add_child(_labelled("Ships", _ships_spin))

	_limit_spin = SpinBox.new()
	_limit_spin.min_value = 0
	_limit_spin.max_value = 50
	_limit_spin.value = 10
	_limit_spin.tooltip_text = "First to this score wins (0 = endless)"
	box.add_child(_labelled("Score limit", _limit_spin))

	var play := Button.new()
	play.text = "PLAY — Skirmish vs AI"
	play.pressed.connect(_on_play_pressed)
	box.add_child(play)

	var movie := Button.new()
	movie.text = "WATCH — Movie Mode"
	movie.pressed.connect(_on_movie_pressed)
	box.add_child(movie)

	box.add_child(HSeparator.new())

	var host_btn := Button.new()
	host_btn.text = "HOST — LAN skirmish"
	host_btn.pressed.connect(_on_host_pressed)
	box.add_child(host_btn)

	var join_row := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "host ip (or ip:port)"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)
	var join_btn := Button.new()
	join_btn.text = "JOIN IP"
	join_btn.pressed.connect(_on_join_ip_pressed)
	join_row.add_child(join_btn)
	box.add_child(join_row)

	var online_row := HBoxContainer.new()
	_relay_edit = LineEdit.new()
	var env_relay := OS.get_environment("XSW_RELAY")
	_relay_edit.text = env_relay if env_relay != "" else ""
	_relay_edit.placeholder_text = "relay address (ip[:port])"
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
	box.add_child(online_row)

	var code_row := HBoxContainer.new()
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "room code"
	_code_edit.max_length = RelayProtocol.CODE_LEN
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code_edit)
	var join_code_btn := Button.new()
	join_code_btn.text = "JOIN CODE"
	join_code_btn.pressed.connect(_on_join_code_pressed)
	code_row.add_child(join_code_btn)
	box.add_child(code_row)

	var lan_label := Label.new()
	lan_label.text = "Servers — LAN auto-discovered + online via BROWSE (double-click to join):"
	lan_label.add_theme_font_size_override("font_size", 13)
	lan_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.8))
	box.add_child(lan_label)

	_server_list = ItemList.new()
	_server_list.custom_minimum_size = Vector2(0, 84)
	_server_list.item_activated.connect(_on_server_activated)
	box.add_child(_server_list)

	_net_status = Label.new()
	_net_status.add_theme_font_size_override("font_size", 13)
	_net_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	_net_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_net_status)

	var settings_row := HBoxContainer.new()
	var vol_label := Label.new()
	vol_label.text = "Volume"
	settings_row.add_child(vol_label)
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0
	_vol_slider.max_value = 100
	_vol_slider.value = 80
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol_slider.value_changed.connect(_on_volume_changed)
	settings_row.add_child(_vol_slider)
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = "Fullscreen"
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	settings_row.add_child(_fullscreen_check)
	box.add_child(settings_row)

	var quit := Button.new()
	quit.text = "QUIT"
	quit.pressed.connect(_on_quit_pressed)
	box.add_child(quit)

	add_child(_menu)

func _labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 130
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func set_menu_visible(v: bool) -> void:
	_menu.visible = v
	# Human input only flows when the menu is closed during a skirmish.
	view.input_enabled = not v and session.human_ship_id >= 0

func _on_play_pressed() -> void:
	_teardown_net()
	var mode := GameSession.Mode.TEAM if _mode_btn.selected == 1 else GameSession.Mode.FFA
	session.score_limit = int(_limit_spin.value)
	session.host_name = _player_name
	session.start_skirmish(int(_ships_spin.value), mode, _diff_btn.selected)
	set_menu_visible(false)

func _on_movie_pressed() -> void:
	_teardown_net()
	session.start_movie()
	set_menu_visible(false)

func _on_quit_pressed() -> void:
	_teardown_net()
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		set_menu_visible(not _menu.visible)

# --------------------------------------------------------------------------
# Networking (M3: LAN host / join / discovery)
# --------------------------------------------------------------------------

func _on_host_pressed() -> void:
	_teardown_net()
	var mode := GameSession.Mode.TEAM if _mode_btn.selected == 1 else GameSession.Mode.FFA
	session.score_limit = int(_limit_spin.value)
	session.host_name = _player_name
	session.start_skirmish(int(_ships_spin.value), mode, _diff_btn.selected)
	net_host = NetHost.new(session)
	var err := net_host.open(NetHost.DEFAULT_PORT, true, "%s's arena" % _player_name)
	if err != OK:
		_net_status.text = "Host failed (error %d) — is another host on port %d?" \
			% [err, NetHost.DEFAULT_PORT]
		net_host = null
		return
	view.external_driver = func(dt: float): net_host.update(dt,
		view.gather_local_input() if not _menu.visible else {})
	_net_status.text = ""
	set_menu_visible(false)

func _on_join_ip_pressed() -> void:
	var txt := _ip_edit.text.strip_edges()
	if txt == "":
		_net_status.text = "Enter a host IP first."
		return
	var ip := txt
	var port := NetHost.DEFAULT_PORT
	if ":" in txt:
		var parts := txt.rsplit(":", false, 1)
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = int(parts[1])
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
	var err := net_client.open(ip, port, _player_name)
	if err != OK:
		_net_status.text = "Join failed (error %d)." % err
		net_client = null
		return
	view.session = net_client.session
	hud.session = net_client.session
	view.external_driver = func(dt: float): net_client.update(dt,
		view.gather_local_input() if not _menu.visible else {})
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
		var why := "searching LAN…" if (_lan != null and _lan.bind_ok) else "LAN discovery unavailable"
		_server_list.add_item("(%s — BROWSE checks the relay)" % why, null, false)
	else:
		for i in range(entries.size()):
			var idx := _server_list.add_item(lines[i])
			_server_list.set_item_metadata(idx, entries[i])

## Parse the relay address field: "ip" or "ip:port". Empty -> error.
func _relay_addr() -> Dictionary:
	var txt := _relay_edit.text.strip_edges()
	if txt == "":
		return {}
	var ip := txt
	var port := RelayProtocol.DEFAULT_PORT
	if ":" in txt:
		var parts := txt.rsplit(":", false, 1)
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = int(parts[1])
	return {"ip": ip, "port": port}

func _on_host_online_pressed() -> void:
	var addr := _relay_addr()
	if addr.is_empty():
		_net_status.text = "Enter a relay address first (or set XSW_RELAY)."
		return
	_teardown_net()
	var mode := GameSession.Mode.TEAM if _mode_btn.selected == 1 else GameSession.Mode.FFA
	session.score_limit = int(_limit_spin.value)
	session.host_name = _player_name
	session.start_skirmish(int(_ships_spin.value), mode, _diff_btn.selected)
	net_host = NetHost.new(session)
	var err: Error = net_host.open_relay(String(addr["ip"]), int(addr["port"]),
		"%s's arena" % _player_name)
	if err != OK:
		_net_status.text = "Relay host failed (error %d)." % err
		net_host = null
		return
	_shown_room_code = ""
	view.external_driver = func(dt: float): net_host.update(dt,
		view.gather_local_input() if not _menu.visible else {})
	_net_status.text = "Registering with relay…"
	_save_settings()
	set_menu_visible(false)

func _on_browse_pressed() -> void:
	var addr := _relay_addr()
	if addr.is_empty():
		_net_status.text = "Enter a relay address first (or set XSW_RELAY)."
		return
	_browser = RelayBrowser.new()
	if _browser.open(String(addr["ip"]), int(addr["port"])) != OK:
		_net_status.text = "Could not reach the relay."
		_browser = null
		return
	_net_status.text = "Browsing online games…"

func _on_join_code_pressed() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	if code.length() != RelayProtocol.CODE_LEN:
		_net_status.text = "Room codes are %d characters." % RelayProtocol.CODE_LEN
		return
	_join_relay(code)

func _join_relay(code: String) -> void:
	var addr := _relay_addr()
	if addr.is_empty():
		_net_status.text = "Enter a relay address first (or set XSW_RELAY)."
		return
	_teardown_net()
	net_client = NetClient.new()
	var err: Error = net_client.open_relay(String(addr["ip"]), int(addr["port"]),
		code, _player_name)
	if err != OK:
		_net_status.text = "Relay join failed (error %d)." % err
		net_client = null
		return
	view.session = net_client.session
	hud.session = net_client.session
	view.external_driver = func(dt: float): net_client.update(dt,
		view.gather_local_input() if not _menu.visible else {})
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

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_vol_slider.set_value_no_signal(float(cfg.get_value("audio", "volume", 80.0)))
		_fullscreen_check.set_pressed_no_signal(bool(cfg.get_value("video", "fullscreen", false)))
		_relay_edit.text = String(cfg.get_value("net", "relay", _relay_edit.text))
	# Apply whatever we ended up with (defaults or loaded).
	var v := _vol_slider.value
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, v / 100.0)) if v > 0.0 else -80.0)
	if _fullscreen_check.button_pressed and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", _vol_slider.value)
	cfg.set_value("video", "fullscreen", _fullscreen_check.button_pressed)
	cfg.set_value("net", "relay", _relay_edit.text.strip_edges())
	cfg.save(SETTINGS_PATH)

func _teardown_net() -> void:
	if net_host != null:
		net_host.close()
		net_host = null
	if net_client != null:
		net_client.close()
		net_client = null
	_shown_room_code = ""
	view.external_driver = Callable()
	view.session = session
	hud.session = session
