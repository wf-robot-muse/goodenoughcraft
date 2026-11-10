extends CanvasLayer
## In-game pause menu: Resume, Settings (the shared settings panel),
## Save now, and Quit to title. Runs with PROCESS_MODE_ALWAYS so it works
## while the tree is paused; the pause action also resumes from here.

signal resume_requested
signal save_requested
signal quit_requested

const SettingsUIScript := preload("res://scripts/settings_ui.gd")

var _panel: CenterContainer
var _settings: SettingsUI
var _settings_center: CenterContainer
var _resume_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_panel = CenterContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var box := PanelContainer.new()
	_panel.add_child(box)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	box.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_resume_button = _add_button(vbox, "Resume", func() -> void: resume_requested.emit())
	_add_button(vbox, "Settings", _show_settings)
	_add_button(vbox, "Save now", func() -> void: save_requested.emit())
	_add_button(vbox, "Quit to title", func() -> void: quit_requested.emit())

	_settings = SettingsUIScript.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_panel.visible = true
		_resume_button.grab_focus())
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	# This wrapper must never intercept input: it is a full-screen
	# container sitting above the menu buttons, and with the default
	# mouse filter it swallowed every tap/click, leaving the pause
	# menu visible but unusable (Fire build issue #1). The settings
	# panel itself still stops input where it is drawn.
	_settings_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_center.add_child(_settings)
	add_child(_settings_center)

	for node in find_children("*", "Button", true, false):
		(node as Button).pressed.connect(func() -> void: Game.play_sfx("ui_click"))

	for container in [_panel, _settings_center]:
		container.resized.connect(func() -> void:
			container.pivot_offset = container.size * 0.5)
	Game.settings_changed.connect(_apply_scale)
	_apply_scale()
	visible = false


## Menus scale with the display and the user's menu-text setting
## (Fire build issue #4): the containers scale around the screen
## center, so every label and button inside grows together.
func _apply_scale() -> void:
	var factor := Game.ui_factor()
	if _panel != null:
		_panel.scale = Vector2.ONE * factor
		_panel.pivot_offset = _panel.size * 0.5
	if _settings_center != null:
		_settings_center.scale = Vector2.ONE * factor
		_settings_center.pivot_offset = _settings_center.size * 0.5


func _add_button(parent: VBoxContainer, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 0)
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


func _show_settings() -> void:
	_panel.visible = false
	_settings.refresh()
	_settings.visible = true
	_settings.focus_first()


func open() -> void:
	visible = true
	_panel.visible = true
	_settings.visible = false
	_apply_scale()
	_resume_button.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		if _settings.visible:
			_settings.visible = false
			_panel.visible = true
			_resume_button.grab_focus()
		else:
			resume_requested.emit()
		get_viewport().set_input_as_handled()
