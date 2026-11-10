extends CanvasLayer
## In-game HUD, built in code: controls hint, crosshair, hotbar with the
## selected block highlighted, the selected block's name, and a transient
## message line (used for "World saved").

signal slot_tapped(index: int)

var _slots: Array[Panel] = []
var _fills: Array[ColorRect] = []
var _number_labels: Array[Label] = []
var _bar: HBoxContainer
var _crosshair: Label
var _slot_size := 52.0
var _name_label: Label
var _flash_label: Label
var _hint_label: Label
var _flash_time := 0.0

const HINT := "Click to capture the mouse — WASD move · Space jump · Shift sprint\nLeft click mine · Right click place · 1-0 / wheel select · F fly · L flashlight · Esc pause (all controls remappable in Settings)"
const TOUCH_HINT_R := "Left thumb: move stick · Right side: drag to look · Tap: place · Hold: mine\nPush the stick fully forward to sprint · Tap the hotbar to choose a block"
const TOUCH_HINT_L := "Right thumb: move stick · Left side: drag to look · Tap: place · Hold: mine\nPush the stick fully forward to sprint · Tap the hotbar to choose a block"


func _ready() -> void:
	var hint := Label.new()
	hint.text = HINT
	hint.position = Vector2(16, 12)
	hint.add_theme_color_override("font_color", Color(1, 1, 1))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	add_child(hint)
	_hint_label = hint

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

	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_crosshair.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_crosshair)

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

	_bar = HBoxContainer.new()
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_bar)
	var bar := _bar

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
		_fills.append(fill)
		var number := Label.new()
		number.text = str(i + 1)
		number.position = Vector2(4, 0)
		number.add_theme_font_size_override("font_size", 11)
		number.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		number.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		panel.add_child(number)
		_number_labels.append(number)
		# Tapping a hotbar slot selects it (tablets); desktop input is
		# unaffected — only genuine touch presses are handled here.
		# The index is bound with .bind(): passing it as connect()'s
		# second argument set the connection FLAGS instead and the
		# handler never ran (Fire build issue #2).
		panel.gui_input.connect(_on_slot_gui_input.bind(i))
		bar.add_child(panel)
		_slots.append(panel)
	set_selected(0)
	Game.settings_changed.connect(apply_ui_scale)
	apply_ui_scale()


func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		slot_tapped.emit(index)


## Distance from the bottom of the screen the touch zones must keep
## clear: hotbar (scaled) plus the selected-block name above it.
func bottom_clearance() -> float:
	return 16.0 + _slot_size + 64.0


## Re-derive every scale-dependent size from the Game settings:
## menu text factor for the readouts, hotbar factor for the slots,
## and a bigger, outlined crosshair (Fire build issues #4, #5, #7).
func apply_ui_scale() -> void:
	var base := Game.ui_base_factor()
	var menu_f := Game.ui_factor()
	_hint_label.add_theme_font_size_override("font_size", int(round(16.0 * menu_f)))
	# In the left-handed layout the pause button sits at the top left,
	# where the hint lives — shift the hint right to clear it.
	_hint_label.position.x = 88.0 if Game.left_handed() else 16.0
	_flash_label.add_theme_font_size_override("font_size", int(round(16.0 * menu_f)))

	var cross := 34.0 * base
	_crosshair.add_theme_font_size_override("font_size", int(round(cross)))
	_crosshair.add_theme_constant_override("outline_size", int(round(8.0 * base)))
	var ch := cross * 0.8
	_crosshair.offset_left = -ch
	_crosshair.offset_right = ch
	_crosshair.offset_top = -ch
	_crosshair.offset_bottom = ch

	var hf := Game.hotbar_factor()
	_slot_size = round(52.0 * hf)
	var sep := maxf(2.0, round(4.0 * hf))
	_bar.add_theme_constant_override("separation", int(sep))
	var width := 10.0 * _slot_size + 9.0 * sep
	_bar.offset_left = -width / 2.0
	_bar.offset_right = width / 2.0
	_bar.offset_bottom = -16.0
	_bar.offset_top = -(16.0 + _slot_size + 8.0)
	var inset := maxf(2.0, round(6.0 * hf))
	var number_size := int(round(11.0 * Game.hotbar_text_factor()))
	for i in _slots.size():
		_slots[i].custom_minimum_size = Vector2(_slot_size, _slot_size)
		_fills[i].offset_left = inset
		_fills[i].offset_top = inset
		_fills[i].offset_right = -inset
		_fills[i].offset_bottom = -inset
		_number_labels[i].add_theme_font_size_override("font_size", number_size)
		_number_labels[i].position = Vector2(4.0 * hf, 0)

	var text_f: float = float(Game.settings.get("hotbar_text_scale", 1.0))
	_name_label.add_theme_font_size_override("font_size", int(round(18.0 * base * text_f)))
	var name_h: float = round(26.0 * base * text_f)
	_name_label.offset_top = _bar.offset_top - name_h - 4.0
	_name_label.offset_bottom = _bar.offset_top - 4.0


func set_touch_hint() -> void:
	if _hint_label != null:
		_hint_label.text = TOUCH_HINT_L if Game.left_handed() else TOUCH_HINT_R


func set_selected(index: int) -> void:
	var hf := Game.hotbar_factor()
	var radius := int(round(4.0 * hf))
	for i in _slots.size():
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.45)
		style.corner_radius_top_left = radius
		style.corner_radius_top_right = radius
		style.corner_radius_bottom_left = radius
		style.corner_radius_bottom_right = radius
		if i == index:
			style.border_color = Color(1, 1, 1, 1)
			style.set_border_width_all(maxi(2, int(round(3.0 * hf))))
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
