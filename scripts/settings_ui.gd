class_name SettingsUI
extends PanelContainer
## The settings panel shared by the title screen and the in-game pause
## menu: music/SFX volume sliders and a full control-remapping list.
## Every action installed by the Game autoload can be rebound to a
## keyboard key, mouse button, or gamepad input; bindings are saved per
## user profile. "Reset controls" restores the defaults.

signal closed

var _rows: Dictionary = {} # action -> binding Button
var _capturing := ""
var _capture_button: Button
var _music_slider: HSlider
var _sfx_slider: HSlider
var _sync_edit: LineEdit


func _ready() -> void:
	custom_minimum_size = Vector2(600, 520)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func() -> void: closed.emit())
	header.add_child(close_button)
	vbox.add_child(header)

	_music_slider = _add_volume_row(vbox, "Music volume", "music_volume")
	_sfx_slider = _add_volume_row(vbox, "Sound effects volume", "sfx_volume")

	var sync_row := HBoxContainer.new()
	var sync_label := Label.new()
	sync_label.text = "Sync folder"
	sync_label.custom_minimum_size = Vector2(190, 0)
	sync_row.add_child(sync_label)
	_sync_edit = LineEdit.new()
	_sync_edit.placeholder_text = "Folder auto-exported after every save (Drive / OneDrive / USB / network share)"
	_sync_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync_row.add_child(_sync_edit)
	var sync_save := Button.new()
	sync_save.text = "Save"
	sync_save.pressed.connect(func() -> void:
		Game.set_sync_folder(_sync_edit.text.strip_edges()))
	sync_row.add_child(sync_save)
	vbox.add_child(sync_row)

	var controls_label := Label.new()
	controls_label.text = "Controls — select a binding, then press a key, mouse button, or gamepad input. Esc cancels."
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(controls_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 260)
	vbox.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	var actions := Game.ACTION_LABELS.keys()
	actions.sort()
	for action in actions:
		var label := Label.new()
		label.text = Game.ACTION_LABELS[action]
		grid.add_child(label)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_start_capture.bind(action, button))
		grid.add_child(button)
		_rows[action] = button

	var reset := Button.new()
	reset.text = "Reset controls to defaults"
	reset.pressed.connect(func() -> void:
		Game.reset_bindings()
		_refresh_bindings())
	vbox.add_child(reset)

	refresh()
	close_button.grab_focus.call_deferred()


func _add_volume_row(parent: VBoxContainer, text: String, kind: String) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		Game.set_volume(kind, value / 100.0))
	row.add_child(slider)
	parent.add_child(row)
	return slider


func refresh() -> void:
	_music_slider.value = float(Game.settings.get("music_volume", 0.7)) * 100.0
	_sfx_slider.value = float(Game.settings.get("sfx_volume", 0.9)) * 100.0
	_sync_edit.text = str(Game.settings.get("sync_folder", ""))
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action in _rows.keys():
		(_rows[action] as Button).text = Game.binding_summary(action)


func _start_capture(action: String, button: Button) -> void:
	_capturing = action
	_capture_button = button
	button.text = "Press an input… (Esc cancels)"


func _input(event: InputEvent) -> void:
	if _capturing == "":
		return
	var captured: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE and _capturing != "pause":
			_capturing = ""
			_refresh_bindings()
			get_viewport().set_input_as_handled()
			return
		captured = event
	elif event is InputEventMouseButton and event.pressed:
		captured = event
	elif event is InputEventJoypadButton and event.pressed:
		captured = event
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		captured = event
	if captured != null:
		Game.rebind_action(_capturing, captured)
		_capturing = ""
		_refresh_bindings()
		get_viewport().set_input_as_handled()
