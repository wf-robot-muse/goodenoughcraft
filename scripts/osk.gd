class_name OnScreenKeyboard
extends PanelContainer
## On-screen keyboard for entering text with a gamepad (or mouse):
## opened for a target LineEdit, letters are picked button by button,
## Done confirms, Cancel restores the text the field started with.
## Built for the title screen's name fields (profiles, worlds, slots).

signal finished(confirmed: bool)

const ROWS := [
	"ABCDEFGHIJKLM",
	"NOPQRSTUVWXYZ",
	"abcdefghijklm",
	"nopqrstuvwxyz",
	"0123456789-_.",
]

var return_focus: Control

var _target: LineEdit
var _original := ""
var _first_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(600, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	var hint := Label.new()
	hint.text = "On-screen keyboard — pick letters, then Done."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	for row_text in ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(row)
		for i in row_text.length():
			var button := Button.new()
			button.text = row_text[i]
			button.custom_minimum_size = Vector2(38, 38)
			button.pressed.connect(_type_char.bind(row_text[i]))
			row.add_child(button)
			if _first_button == null:
				_first_button = button
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(actions)
	_add_action(actions, "Space", func() -> void: _type_char(" "))
	_add_action(actions, "⌫ Back", _backspace)
	_add_action(actions, "Clear", func() -> void:
		if _target != null:
			_target.text = "")
	_add_action(actions, "Done", func() -> void: _close(true))
	_add_action(actions, "Cancel", func() -> void: _close(false))
	visible = false


func _add_action(row: HBoxContainer, text: String, on_press: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(96, 38)
	button.pressed.connect(on_press)
	row.add_child(button)


func open_for(edit: LineEdit, focus_back: Control) -> void:
	_target = edit
	_original = edit.text
	return_focus = focus_back
	visible = true
	if _first_button != null:
		_first_button.grab_focus.call_deferred()


func _close(confirmed: bool) -> void:
	if not confirmed and _target != null:
		_target.text = _original
	visible = false
	finished.emit(confirmed)
	if return_focus != null:
		return_focus.grab_focus.call_deferred()


func _type_char(c: String) -> void:
	if _target != null:
		_target.text += c


func _backspace() -> void:
	if _target != null and not _target.text.is_empty():
		_target.text = _target.text.left(_target.text.length() - 1)
