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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(_settings)
	add_child(center)

	visible = false


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


func open() -> void:
	visible = true
	_panel.visible = true
	_settings.visible = false
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
