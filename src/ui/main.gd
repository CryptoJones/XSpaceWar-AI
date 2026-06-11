extends Node2D
## Root of the game. Boots Movie Mode as an attract loop behind a simple menu
## (Movie Mode / Skirmish vs AI / Quit, with mode, difficulty, and ship-count
## selectors). The menu is built in code; ESC toggles it in-game.

var session := GameSession.new()
var view: WorldView
var hud: Hud

var _menu: CanvasLayer
var _mode_btn: OptionButton
var _diff_btn: OptionButton
var _ships_spin: SpinBox

func _ready() -> void:
	view = WorldView.new()
	view.session = session
	add_child(view)

	hud = Hud.new()
	hud.session = session
	add_child(hud)

	_build_menu()
	session.start_movie()
	set_menu_visible(true)

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

	var quit := Button.new()
	quit.text = "QUIT"
	quit.pressed.connect(func(): get_tree().quit())
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
	var mode := GameSession.Mode.TEAM if _mode_btn.selected == 1 else GameSession.Mode.FFA
	session.start_skirmish(int(_ships_spin.value), mode, _diff_btn.selected)
	set_menu_visible(false)

func _on_movie_pressed() -> void:
	session.start_movie()
	set_menu_visible(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		set_menu_visible(not _menu.visible)
