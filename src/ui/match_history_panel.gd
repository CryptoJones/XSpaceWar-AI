class_name MatchHistoryPanel
extends RefCounted
## The MATCH HISTORY modal: a list of finished matches (from MatchStats) with a
## per-match scoreboard detail. Extracted from main.gd's god-object as part of
## the #2.4 decomposition. The root scene owns one, opens it from the OPTIONS
## tab, and routes the input gate (is_open) and ESC handling (dismiss) through
## it. Menu/gate transitions stay the root's job — this only owns the panel UI.

var _m: Node                  ## root scene — menu + input-gate services
var _panel: CanvasLayer
var _list: ItemList
var _detail: Label
var _career: Label

func _init(root: Node) -> void:
	_m = root
	_build()

## True while the panel is up (the root's _modal_open() gates input on this).
func is_open() -> bool:
	return _panel.visible

## Hide the panel without touching the menu (shared multi-panel ESC path).
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
	v.custom_minimum_size = Vector2(560, 0)
	margin.add_child(v)
	var title := Label.new()
	title.text = "MATCH HISTORY"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	v.add_child(title)
	_career = Label.new()
	_career.add_theme_font_size_override("font_size", 15)
	_career.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	v.add_child(_career)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 180)
	_list.item_selected.connect(_on_selected)
	v.add_child(_list)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 14)
	_detail.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.9))
	_detail.custom_minimum_size = Vector2(0, 120)
	v.add_child(_detail)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(close)
	v.add_child(back)
	_m.add_child(_panel)

## OPTIONS → MATCH HISTORY: populate career totals + the recent-match list.
func open() -> void:
	var career := MatchStats.career()
	_career.text = tr("Career:  %d matches  ·  %d wins  ·  %d kills / %d deaths") \
		% [career["matches"], career["wins"], career["kills"], career["deaths"]]
	_list.clear()
	_detail.text = ""
	var recent := MatchStats.load_recent(50)
	if recent.is_empty():
		_list.add_item("(no finished matches yet — set a score or time limit and play)", null, false)
	for e in recent:
		var idx := _list.add_item("%s   %s   %d:%02d   winner: %s%s" % [
			String(e.get("when", "?")), String(e.get("mode", "?")),
			int(e.get("dur", 0)) / 60, int(e.get("dur", 0)) % 60,
			String(e.get("winner", "?")),
			"   ★" if bool(e.get("won", false)) else ""])
		_list.set_item_metadata(idx, e)
	_m.set_menu_visible(false)
	_panel.visible = true
	_m._refresh_input_gate()

func _on_selected(idx: int) -> void:
	var e: Variant = _list.get_item_metadata(idx)
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
	_detail.text = "\n".join(lines)
