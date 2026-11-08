extends CanvasLayer
## In-game HUD, built in code: controls hint, crosshair, hotbar with the
## selected block highlighted, the selected block's name, and a transient
## message line (used for "World saved").

var _slots: Array[Panel] = []
var _name_label: Label
var _flash_label: Label
var _flash_time := 0.0

const HINT := "Click to capture the mouse — WASD move · Space jump · Shift sprint\nLeft click mine · Right click place · 1-0 / wheel select · F fly · L flashlight · Esc pause (all controls remappable in Settings)"


func _ready() -> void:
	var hint := Label.new()
	hint.text = HINT
	hint.position = Vector2(16, 12)
	hint.add_theme_color_override("font_color", Color(1, 1, 1))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	add_child(hint)

	_flash_label = Label.new()
	_flash_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_flash_label.offset_left = -240
	_flash_label.offset_right = -16
	_flash_label.offset_top = 12
	_flash_label.offset_bottom = 40
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_flash_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_flash_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_flash_label.modulate.a = 0.0
	add_child(_flash_label)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -12
	crosshair.offset_right = 12
	crosshair.offset_top = -16
	crosshair.offset_bottom = 16
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	crosshair.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	add_child(crosshair)

	_name_label = Label.new()
	_name_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name_label.offset_left = -200
	_name_label.offset_right = 200
	_name_label.offset_top = -104
	_name_label.offset_bottom = -80
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	add_child(_name_label)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -285
	bar.offset_right = 285
	bar.offset_top = -72
	bar.offset_bottom = -16
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)

	for i in Blocks.HOTBAR.size():
		var id := Blocks.HOTBAR[i]
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(52, 52)
		var fill := ColorRect.new()
		fill.color = Blocks.block_color(id)
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.offset_left = 6
		fill.offset_top = 6
		fill.offset_right = -6
		fill.offset_bottom = -6
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(fill)
		var number := Label.new()
		number.text = str(i + 1)
		number.position = Vector2(4, 0)
		number.add_theme_font_size_override("font_size", 11)
		number.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		number.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		panel.add_child(number)
		bar.add_child(panel)
		_slots.append(panel)
	set_selected(0)


func set_selected(index: int) -> void:
	for i in _slots.size():
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.45)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		if i == index:
			style.border_color = Color(1, 1, 1, 1)
			style.set_border_width_all(3)
		else:
			style.border_color = Color(1, 1, 1, 0.35)
			style.set_border_width_all(1)
		_slots[i].add_theme_stylebox_override("panel", style)
	if index >= 0 and index < Blocks.HOTBAR.size():
		_name_label.text = Blocks.block_name(Blocks.HOTBAR[index])


func flash_message(text: String) -> void:
	_flash_label.text = text
	_flash_label.modulate.a = 1.0
	_flash_time = 2.0


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time < 0.5:
			_flash_label.modulate.a = maxf(_flash_time / 0.5, 0.0)
		if _flash_time <= 0.0:
			_flash_label.modulate.a = 0.0
