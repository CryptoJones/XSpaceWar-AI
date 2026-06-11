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
var _ip_edit: LineEdit
var _server_list: ItemList
var _net_status: Label
var _lan: LanDiscovery
var _server_repr := ""
var _player_name := "PILOT"

func _ready() -> void:
	view = WorldView.new()
	view.session = session
	add_child(view)

	hud = Hud.new()
	hud.session = session
	add_child(hud)

	_build_menu()
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

	var lan_label := Label.new()
	lan_label.text = "LAN servers (double-click to join):"
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
	session.start_skirmish(int(_ships_spin.value), mode, _diff_btn.selected)
	session.ship_names[session.human_ship_id] = _player_name
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
	if typeof(srv) == TYPE_DICTIONARY:
		_join(String(srv["ip"]), int(srv.get("port", NetHost.DEFAULT_PORT)))

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
	set_menu_visible(false)

func _refresh_server_list(dt: float) -> void:
	if _lan == null or not _lan.bind_ok:
		if _server_repr != "unavailable":
			_server_repr = "unavailable"
			_server_list.clear()
			_server_list.add_item("(LAN discovery unavailable — port in use?)", null, false)
		return
	var found := _lan.poll(dt)
	var lines: Array[String] = []
	for srv in found:
		lines.append("%s — %s:%d  (%d/%d)" % [String(srv.get("name", "?")),
			String(srv["ip"]), int(srv.get("port", NetHost.DEFAULT_PORT)),
			int(srv.get("players", 0)), int(srv.get("max", 0))])
	var repr := "\n".join(lines)
	if repr == _server_repr:
		return
	_server_repr = repr
	_server_list.clear()
	if found.is_empty():
		_server_list.add_item("(searching LAN…)", null, false)
	else:
		for i in range(found.size()):
			var idx := _server_list.add_item(lines[i])
			_server_list.set_item_metadata(idx, found[i])

func _teardown_net() -> void:
	if net_host != null:
		net_host.close()
		net_host = null
	if net_client != null:
		net_client.close()
		net_client = null
	view.external_driver = Callable()
	view.session = session
	hud.session = session
