class_name ReplaysPanel
extends RefCounted
## The REPLAYS modal: lists recorded .xsr tapes in the root's REPLAY_DIR with
## decoded metadata (mode · pilots · duration) and drives watch/delete.
## Extracted from main.gd's god-object (#2.4 decomposition). Starting playback
## stays on the root (_watch_replay wires the shared session/view/hud); this
## panel only owns the browser UI and calls back into the root to play.

var _m: Node                  ## root scene — playback (_watch_replay) + menu
var _panel: CanvasLayer
var _list: ItemList

func _init(root: Node) -> void:
	_m = root
	_build()

## True while the panel is up (the root's _modal_open() gates input on this).
func is_open() -> bool:
	return _panel.visible

## Hide the panel without touching the menu — used when a replay starts playing
## and on the shared multi-panel ESC path.
func dismiss() -> void:
	_panel.visible = false

## BACK button: hide and return to the menu (set_menu_visible refreshes the gate).
func close() -> void:
	_panel.visible = false
	_m.set_menu_visible(true)

func _build() -> void:
	_panel = CanvasLayer.new()
	_panel.layer = 25
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
	title.text = "REPLAYS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	v.add_child(title)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 220)
	_list.item_activated.connect(func(idx: int): _m._watch_replay(String(_list.get_item_metadata(idx))))
	v.add_child(_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(close)
	row.add_child(back)
	var del := Button.new()
	del.text = "DELETE"
	del.pressed.connect(_on_delete)
	row.add_child(del)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var watch := Button.new()
	watch.text = "WATCH"
	watch.pressed.connect(_on_watch)
	row.add_child(watch)
	v.add_child(row)
	_m.add_child(_panel)

func _files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(_m.REPLAY_DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if fname.ends_with(".xsr"):
			out.append(fname)
	out.sort()
	out.reverse()  # newest first (timestamps sort lexically)
	return out

func _refresh() -> void:
	_list.clear()
	for fname in _files():
		var path := "%s/%s" % [_m.REPLAY_DIR, fname]
		var rec := Replay.from_bytes(FileAccess.get_file_as_bytes(path))
		var label := fname.trim_suffix(".xsr")
		if rec != null:
			var secs := int(rec.duration_sec(1.0 / 60.0))
			label += "   —   %s · %d pilots · %d:%02d" % [
				"TEAM" if int(rec.header.get("mode", 0)) == GameSession.Mode.TEAM else "FFA",
				(rec.header.get("ros", []) as Array).size(), secs / 60, secs % 60]
		else:
			label += "   —   (unreadable)"
		var idx := _list.add_item(label)
		_list.set_item_metadata(idx, path)
	if _list.item_count == 0:
		_list.add_item("(no replays yet — enable 'Record matches' and play)", null, false)
	else:
		_list.select(0)

## OPTIONS → REPLAYS: refresh the tape list and show the panel.
func open() -> void:
	_refresh()
	_m.set_menu_visible(false)
	_panel.visible = true
	_m._refresh_input_gate()

func _selected_path() -> String:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return ""
	var meta: Variant = _list.get_item_metadata(sel[0])
	return String(meta) if meta != null else ""

func _on_watch() -> void:
	var path := _selected_path()
	if path != "":
		_m._watch_replay(path)

func _on_delete() -> void:
	var path := _selected_path()
	if path == "":
		return
	DirAccess.remove_absolute(path)
	_refresh()
