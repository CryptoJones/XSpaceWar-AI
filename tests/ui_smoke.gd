extends SceneTree
## Headless UI smoke for the extracted main.gd sub-controllers (#2.4
## decomposition): boot the real scene, then open/close the MATCH HISTORY and
## REPLAYS panels and assert the modal plumbing (is_open / dismiss / close /
## menu return) toggles without script errors. scene_smoke covers panel
## CONSTRUCTION in _ready(); this covers panel OPERATION.
##
## Run with:
##   godot --headless --path . --script res://tests/ui_smoke.gd

var _frames := 0
var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — UI smoke (panel sub-controllers) ===")
	var packed: PackedScene = load("res://src/ui/main.tscn")
	if packed == null:
		print("  [FAIL] main.tscn failed to load")
		quit(1)
		return
	root.add_child(packed.instantiate())
	process_frame.connect(_on_frame)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")

func _on_frame() -> void:
	_frames += 1
	if _frames < 3:
		return  # let _ready() and a couple of attract frames settle
	var m := root.get_node_or_null("Main")
	if m == null:
		_check("main node present", false)
		quit(1)
		return
	_check("sub-controllers constructed", m._history != null and m._replays != null)

	# MATCH HISTORY: open gates input, _on_selected tolerates the empty-state
	# placeholder, dismiss() hides it without crashing.
	m._history.open()
	_check("history: open shows the panel", m._history.is_open())
	m._history._on_selected(0)  # placeholder row has no dict metadata — must no-op
	m._history.dismiss()
	_check("history: dismiss hides the panel", not m._history.is_open())

	# REPLAYS: open refreshes + shows; close() hides and returns to the menu.
	m._replays.open()
	_check("replays: open shows the panel", m._replays.is_open())
	_check("replays: open path threads REPLAY_DIR", typeof(m._replays._selected_path()) == TYPE_STRING)
	m._replays.close()
	_check("replays: close hides it and restores the menu",
		not m._replays.is_open() and m._menu.visible)

	# MANAGE PLAYERS: constructed, and open() is a safe no-op when not hosting.
	_check("players: sub-controller constructed", m._players != null)
	m._on_players_pressed()  # no net_host → must not open or crash
	_check("players: open is a no-op without a host", not m._players.is_open())
	m._players.dismiss()
	_check("players: dismiss is safe", not m._players.is_open())

	# INPUT BINDINGS: panel exposes both keyboard and controller labels, and a
	# synthetic joypad-button rebind updates settings/InputMap without crashing.
	m._on_keys_pressed()
	_check("bindings: panel opens", m._keys_panel.visible)
	_check("bindings: key labels present", m._keybind_value_labels.has("fire"))
	_check("bindings: pad labels present", m._padbind_value_labels.has("fire"))
	m._awaiting_rebind = "fire"
	m._awaiting_rebind_kind = "pad"
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_RIGHT_SHOULDER
	ev.pressed = true
	m._unhandled_input(ev)
	_check("bindings: pad rebind applies", int(m.view.pad_binds["fire"]) == JOY_BUTTON_RIGHT_SHOULDER)
	var fire_has_pad := false
	for input_ev in InputMap.action_get_events("xsw_fire"):
		if input_ev is InputEventJoypadButton \
				and input_ev.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			fire_has_pad = true
			break
	_check("bindings: pad rebind syncs InputMap", fire_has_pad)
	m._close_keys_panel()
	_check("bindings: close restores menu", not m._keys_panel.visible and m._menu.visible)

	# The input gate still resolves with all panels closed (no stale refs).
	_check("modal gate resolves after panel use", typeof(m._modal_open()) == TYPE_BOOL)

	# Match recipes and the three-state radar are intentionally exercised via
	# the real menu/HUD objects, not a duplicate test harness.
	m._on_preset_selected(MatchPresets.ORDER.find(MatchPresets.QUICK_SKIRMISH))
	_check("presets: selecting Quick Skirmish updates controls",
		int(m._ships_slider.value) == 4 and int(m._limit_slider.value) == 5
		and int(m._pace_slider.value) == 90)
	m._mark_custom()
	_check("presets: editing after selection switches to Custom",
		m._preset_btn.selected == MatchPresets.ORDER.find(MatchPresets.CUSTOM))
	m.hud.set_radar_mode(Hud.RadarMode.TACTICAL)
	_check("radar: tactical mode is visible", m.hud.radar_mode() == Hud.RadarMode.TACTICAL
		and m.hud.radar_visible())
	m.hud.cycle_radar_mode()
	_check("radar: M cycle reaches overview", m.hud.radar_mode() == Hud.RadarMode.OVERVIEW)
	m.hud.cycle_radar_mode()
	_check("radar: M cycle reaches hidden", m.hud.radar_mode() == Hud.RadarMode.HIDDEN
		and not m.hud.radar_visible())

	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
