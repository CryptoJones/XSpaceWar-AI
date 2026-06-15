class_name PlayersPanel
extends RefCounted
## The MANAGE PLAYERS modal (host moderation, #4): lists connected pilots with
## the aim-anomaly ⚠ warning, shows the selected pilot's verdict (a warning to
## review — never an automatic ban; see AimAnalyzer), and drives kick/ban
## through the host's NetHost. Extracted from main.gd's god-object (#2.4); only
## reachable while THIS process is the authoritative host (net_host != null).

var _m: Node                  ## root scene — net_host, status line, menu/gate
var _panel: CanvasLayer
var _list: ItemList
var _note: Label
var _detail: Label

func _init(root: Node) -> void:
	_m = root
	_build()

## True while the panel is up (the root's _modal_open() gates input on this).
func is_open() -> bool:
	return _panel.visible

## Hide without touching the menu (shared multi-panel ESC path).
func dismiss() -> void:
	_panel.visible = false

func _build() -> void:
	_panel = CanvasLayer.new()
	_panel.layer = 26
	_panel.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
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
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.85))
	v.add_child(_note)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 180)
	# Callsigns are user content — never run a player's name through tr().
	_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_list.item_selected.connect(_on_selected)
	v.add_child(_list)
	# Aim-anomaly detail for the selected pilot (host-side warning, never a ban).
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0, 56)
	v.add_child(_detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func(): _panel.visible = false; _m._refresh_input_gate(); _m.set_menu_visible(true))
	row.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var kick := Button.new()
	kick.text = "KICK"
	kick.pressed.connect(func(): _moderate(false))
	row.add_child(kick)
	var ban := Button.new()
	ban.text = "BAN"
	ban.tooltip_text = "Kick and block this callsign (and address, on LAN) from rejoining"
	ban.pressed.connect(func(): _moderate(true))
	row.add_child(ban)
	v.add_child(row)
	_m.add_child(_panel)

## NET tab → MANAGE PLAYERS. No-op unless this process hosts.
func open() -> void:
	if _m.net_host == null:
		return
	_refresh()
	_m.set_menu_visible(false)
	_panel.visible = true
	_m._refresh_input_gate()

func _refresh() -> void:
	_list.clear()
	var host: NetHost = _m.net_host
	if host == null:
		return
	var players := host.connected_players()
	var flagged := 0
	for p in players:
		var sid := int(p["sid"])
		var warn := host.is_aim_flagged(sid)
		if warn:
			flagged += 1
		var idx := _list.add_item(("⚠ " if warn else "") + String(p["name"]))
		_list.set_item_metadata(idx, sid)
	if players.is_empty():
		_list.add_item(tr("(no players connected — bots hold every slot)"), null, false)
		_detail.text = ""
	else:
		_list.select(0)
		_on_selected(0)
	_note.text = tr("%d connected · %d banned · %d flagged") \
		% [players.size(), host.ban_list().size(), flagged]

## Show the selected pilot's aim-anomaly verdict (a warning to review, not a
## ban — see AimAnalyzer). Clean pilots get a reassuring line.
func _on_selected(idx: int) -> void:
	var host: NetHost = _m.net_host
	if host == null:
		return
	var meta: Variant = _list.get_item_metadata(idx)
	if typeof(meta) != TYPE_INT:
		_detail.text = ""
		return
	var reasons := host.aim_reasons(int(meta))
	if reasons.is_empty():
		_detail.text = tr("Aim looks human — nothing flagged.")
	else:
		_detail.text = "⚠ " + "\n⚠ ".join(reasons)

func _moderate(ban: bool) -> void:
	var host: NetHost = _m.net_host
	if host == null:
		return
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var meta: Variant = _list.get_item_metadata(sel[0])
	if typeof(meta) != TYPE_INT:
		return
	var sid := int(meta)
	var pname := ""
	for p in host.connected_players():
		if int(p["sid"]) == sid:
			pname = String(p["name"])
			break
	if host.kick_ship(sid, "Banned by the host." if ban else "Kicked by the host.", ban):
		_m._net_status.text = (tr("Banned %s.") if ban else tr("Kicked %s.")) % pname
	_refresh()
