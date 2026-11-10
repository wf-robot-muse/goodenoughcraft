class_name SettingsUI
extends PanelContainer
## The settings panel shared by the title screen and the in-game pause
## menu, reorganized into category pages (Fire build issue #16):
## a root page lists the categories, each category opens its own page.
## The frame is capped relative to the screen (issue #12) — pages
## scroll internally instead of the panel ever outgrowing the display —
## and the controls carry an explicit high-contrast theme (issue #13).
##
## Pages: Interface (sizes, target marking), Controls (handedness,
## auto-jump, full input remapping), Audio & Music (volumes, music
## style, the user's own music files), Gameplay (day/night), and
## Profile & Data (sync folder). Bindings are saved per user profile.

signal closed

const CATEGORIES: Array = [
	["interface", "Interface"],
	["controls", "Controls"],
	["audio", "Audio & Music"],
	["gameplay", "Gameplay"],
	["profile", "Profile & Data"],
]
const MUSIC_STYLE_KEYS: Array[String] = ["meadow", "pines", "shore", "custom", "off"]
const MUSIC_STYLE_LABELS: Array[String] = [
	"Meadow Light (built-in)", "Deep Pines (built-in)",
	"Open Shore (built-in)", "My Music (my files)", "Off"]
const MARKING_KEYS: Array[String] = ["auto", "outline", "highlight", "off"]
const MARKING_LABELS: Array[String] = [
	"Auto (highlight on touch, outline with crosshair)",
	"Outline", "Highlight", "Off"]

var _rows: Dictionary = {} # action -> binding Button
var _capturing := ""
var _capture_button: Button
var _music_slider: HSlider
var _sfx_slider: HSlider
var _sync_edit: LineEdit
var _close_button: Button
var _back_button: Button
var _title_label: Label
var _pad_readout: Label
var _percent_sliders: Dictionary = {} # setting key -> HSlider
var _percent_labels: Dictionary = {} # setting key -> value Label
var _left_handed_check: CheckBox
var _auto_jump_check: CheckBox
var _day_night_check: CheckBox
var _music_style_option: OptionButton
var _marking_option: OptionButton
var _music_files_label: Label
var _file_dialog: FileDialog
var _pages: Dictionary = {} # page name -> ScrollContainer
var _category_buttons: Dictionary = {} # page name -> Button
var _current_page := "root"


func _ready() -> void:
	_apply_contrast_theme()
	custom_minimum_size = Vector2(600, 520)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var header := HBoxContainer.new()
	_back_button = Button.new()
	_back_button.text = "< Back"
	_back_button.pressed.connect(func() -> void: show_page("root"))
	header.add_child(_back_button)
	_title_label = Label.new()
	_title_label.text = "Settings"
	_title_label.add_theme_font_size_override("font_size", 24)
	header.add_child(_title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func() -> void: closed.emit())
	header.add_child(_close_button)
	vbox.add_child(header)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	_build_root_page(body)
	_build_interface_page(body)
	_build_controls_page(body)
	_build_audio_page(body)
	_build_gameplay_page(body)
	_build_profile_page(body)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "Choose music files"
	_file_dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; Music files"])
	_file_dialog.files_selected.connect(_on_music_files_selected)
	add_child(_file_dialog)

	Game.settings_changed.connect(_on_settings_changed)
	visibility_changed.connect(func() -> void: _fit_frame.call_deferred())
	show_page("root")
	refresh()
	_fit_frame.call_deferred()


# ------------------------------------------------------------- theming

## Issue #13: the default theme's unchecked checkbox and slider
## elements wash out against the panel. Give the whole panel explicit
## high-contrast control art: bright-bordered checkbox states, a
## bright slider fill and grabber, and bordered buttons throughout.
## Theme overrides on this panel propagate to every child control.
func _apply_contrast_theme() -> void:
	# Issue #9: explicit, fully opaque panel backing.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.11, 1.0)
	panel_style.border_color = Color(0.65, 0.68, 0.72, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_top = 14.0
	panel_style.content_margin_right = 16.0
	panel_style.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", panel_style)
	add_theme_color_override("font_color", Color(0.94, 0.95, 0.97))
	add_theme_font_size_override("font_size", 17)

	# Per-control overrides apply only to this panel itself, so the
	# control art is carried by a Theme resource, which children DO
	# inherit through the tree.
	var theme := Theme.new()
	var ink := Color(0.94, 0.95, 0.97)
	theme.set_icon("checked", "CheckBox", _make_checkbox_texture(true))
	theme.set_icon("unchecked", "CheckBox", _make_checkbox_texture(false))
	theme.set_color("font_color", "CheckBox", ink)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.13, 0.14, 0.17, 1.0)
	track.border_color = Color(0.78, 0.81, 0.85, 1.0)
	track.set_border_width_all(1)
	track.set_corner_radius_all(5)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	theme.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.38, 0.68, 1.0, 1.0)
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 6.0
	fill.content_margin_bottom = 6.0
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grabber := _make_grabber_texture()
	theme.set_icon("grabber", "HSlider", grabber)
	theme.set_icon("grabber_highlight", "HSlider", grabber)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.21, 0.23, 0.27, 1.0)
	btn_normal.border_color = Color(0.72, 0.75, 0.80, 1.0)
	btn_normal.set_border_width_all(2)
	btn_normal.set_corner_radius_all(6)
	btn_normal.content_margin_left = 12.0
	btn_normal.content_margin_right = 12.0
	btn_normal.content_margin_top = 7.0
	btn_normal.content_margin_bottom = 7.0
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.29, 0.32, 0.37, 1.0)
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.15, 0.16, 0.19, 1.0)
	btn_pressed.border_color = Color(0.38, 0.68, 1.0, 1.0)
	var btn_focus := btn_normal.duplicate() as StyleBoxFlat
	btn_focus.bg_color = Color(0.21, 0.23, 0.27, 1.0)
	btn_focus.border_color = Color(1.0, 0.95, 0.60, 1.0)
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, btn_normal)
		theme.set_stylebox("hover", type_name, btn_hover)
		theme.set_stylebox("pressed", type_name, btn_pressed)
		theme.set_stylebox("focus", type_name, btn_focus)
		theme.set_color("font_color", type_name, ink)
	theme.set_color("font_color", "Label", ink)
	var edit_box := StyleBoxFlat.new()
	edit_box.bg_color = Color(0.12, 0.13, 0.16, 1.0)
	edit_box.border_color = Color(0.72, 0.75, 0.80, 1.0)
	edit_box.set_border_width_all(2)
	edit_box.set_corner_radius_all(6)
	edit_box.content_margin_left = 8.0
	edit_box.content_margin_right = 8.0
	theme.set_stylebox("normal", "LineEdit", edit_box)
	theme.set_stylebox("focus", "LineEdit", btn_focus)
	theme.set_color("font_color", "LineEdit", ink)
	self.theme = theme


func _plot(img: Image, x: int, y: int, size: int, color: Color) -> void:
	for dx in range(size):
		for dy in range(size):
			var px := x + dx
			var py := y + dy
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, color)


func _make_checkbox_texture(checked: bool) -> Texture2D:
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	if checked:
		img.fill(Color(0.30, 0.72, 0.35, 1.0))
		for i in range(40):
			for t in range(3):
				img.set_pixel(i, t, Color(0.14, 0.42, 0.18, 1.0))
				img.set_pixel(i, 39 - t, Color(0.14, 0.42, 0.18, 1.0))
				img.set_pixel(t, i, Color(0.14, 0.42, 0.18, 1.0))
				img.set_pixel(39 - t, i, Color(0.14, 0.42, 0.18, 1.0))
		# Bold dark check mark: two thick segments.
		for k in range(9):
			_plot(img, 8 + k, 20 + int(float(k) * 0.9), 5, Color(0.04, 0.10, 0.05, 1.0))
		for k in range(15):
			_plot(img, 15 + k, 27 - int(float(k) * 1.1), 5, Color(0.04, 0.10, 0.05, 1.0))
	else:
		img.fill(Color(0, 0, 0, 0))
		var border := Color(0.93, 0.95, 0.98, 1.0)
		for i in range(40):
			for t in range(5):
				img.set_pixel(i, t, border)
				img.set_pixel(i, 39 - t, border)
				img.set_pixel(t, i, border)
				img.set_pixel(39 - t, i, border)
	return ImageTexture.create_from_image(img)


func _make_grabber_texture() -> Texture2D:
	var img := Image.create(26, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(26):
		for y in range(26):
			var d := Vector2(x - 12.5, y - 12.5).length()
			if d <= 11.0:
				img.set_pixel(x, y, Color(0.96, 0.97, 0.99, 1.0) if d > 8.5
					else Color(0.85, 0.88, 0.92, 1.0))
	return ImageTexture.create_from_image(img)


# --------------------------------------------------------- frame/pages

## Issue #12: the parents scale this panel by Game.ui_factor() (up to
## ~2.7x on the Fire), which is what pushed the old panel off-screen.
## Size the frame in UNSCALED units so that after that scaling it
## occupies at most ~92% of the screen in each dimension.
func _fit_frame() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var factor := maxf(Game.ui_factor(), 0.05)
	custom_minimum_size = Vector2(
		minf(vp.x * 0.92, 980.0) / factor,
		minf(vp.y * 0.92, 820.0) / factor)


func _make_page(body: Control, page_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.visible = false
	body.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	_pages[page_name] = scroll
	return vbox


func show_page(page_name: String) -> void:
	_current_page = page_name
	for key in _pages.keys():
		(_pages[key] as Control).visible = key == page_name
	_back_button.visible = page_name != "root"
	if page_name == "root":
		_title_label.text = "Settings"
		_refresh_summaries()
		if not _category_buttons.is_empty():
			(_category_buttons["interface"] as Button).grab_focus.call_deferred()
	else:
		for entry in CATEGORIES:
			if entry[0] == page_name:
				_title_label.text = str(entry[1])
		_back_button.grab_focus.call_deferred()


func _build_root_page(body: Control) -> void:
	var vbox := _make_page(body, "root")
	var intro := Label.new()
	intro.text = "Choose a category. Most-used values are shown on each button."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(intro)
	for entry in CATEGORIES:
		var page_name := str(entry[0])
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 58)
		button.pressed.connect(func() -> void: show_page(page_name))
		vbox.add_child(button)
		_category_buttons[page_name] = button
	_refresh_summaries()


func _refresh_summaries() -> void:
	if _category_buttons.is_empty():
		return
	var s := Game.settings
	(_category_buttons["interface"] as Button).text = "Interface\nText %d%%  ·  Hotbar %d%%  ·  Target marking: %s" % [
		int(round(float(s.get("menu_text_scale", 1.0)) * 100.0)),
		int(round(float(s.get("hotbar_scale", 1.0)) * 100.0)),
		MARKING_LABELS[MARKING_KEYS.find(str(s.get("target_marking", "auto")))].split(" (")[0]]
	(_category_buttons["controls"] as Button).text = "Controls\nLeft-handed: %s  ·  Auto-jump: %s  ·  Bindings: %d actions" % [
		"On" if Game.left_handed() else "Off",
		"On" if Game.auto_jump_enabled() else "Off",
		Game.ACTION_LABELS.size()]
	(_category_buttons["audio"] as Button).text = "Audio & Music\nMusic: %s  ·  Music %d%%  ·  Effects %d%%" % [
		MUSIC_STYLE_LABELS[MUSIC_STYLE_KEYS.find(Game.music_style())],
		int(round(float(s.get("music_volume", 0.7)) * 100.0)),
		int(round(float(s.get("sfx_volume", 0.9)) * 100.0))]
	(_category_buttons["gameplay"] as Button).text = "Gameplay\nDay/night cycle: %s" % (
		"On" if Game.day_night_cycle_enabled() else "Off (always day)")
	(_category_buttons["profile"] as Button).text = "Profile & Data\nSync folder: %s" % (
		"set" if str(s.get("sync_folder", "")) != "" else "not set")


func _build_interface_page(body: Control) -> void:
	var vbox := _make_page(body, "interface")
	_add_percent_row(vbox, "Menu text size", "menu_text_scale", 80, 150)
	_add_percent_row(vbox, "Hotbar size", "hotbar_scale", 80, 160)
	_add_percent_row(vbox, "Hotbar text size", "hotbar_text_scale", 80, 160)
	_marking_option = _add_option_row(vbox, "Target marking", MARKING_LABELS,
		func(index: int) -> void: Game.set_setting("target_marking", MARKING_KEYS[index]))


func _build_controls_page(body: Control) -> void:
	var vbox := _make_page(body, "controls")
	_left_handed_check = _add_toggle_row(vbox,
		"Left-handed touch controls (mirror the touch layout)", "left_handed")
	_auto_jump_check = _add_toggle_row(vbox,
		"Auto-jump (step up one block automatically)", "auto_jump")

	var controls_label := Label.new()
	controls_label.text = "Bindings — select a binding, then press a key, mouse button, or gamepad input. Esc cancels."
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(controls_label)

	_pad_readout = Label.new()
	_pad_readout.text = "Last gamepad input: (none yet — press any gamepad button or move a stick)"
	_pad_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_pad_readout)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

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


func _build_audio_page(body: Control) -> void:
	var vbox := _make_page(body, "audio")
	_music_slider = _add_volume_row(vbox, "Music volume", "music_volume")
	_sfx_slider = _add_volume_row(vbox, "Sound effects volume", "sfx_volume")
	_music_style_option = _add_option_row(vbox, "Music style", MUSIC_STYLE_LABELS,
		func(index: int) -> void: Game.set_music_style(MUSIC_STYLE_KEYS[index]))
	var files_button := Button.new()
	files_button.text = "Choose my music files..."
	files_button.pressed.connect(func() -> void: _file_dialog.popup_centered_ratio(0.75))
	vbox.add_child(files_button)
	_music_files_label = Label.new()
	_music_files_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_music_files_label)
	_refresh_music_files_label()


func _build_gameplay_page(body: Control) -> void:
	var vbox := _make_page(body, "gameplay")
	_day_night_check = _add_toggle_row(vbox,
		"Day/night cycle (off = always day)", "day_night_cycle")


func _build_profile_page(body: Control) -> void:
	var vbox := _make_page(body, "profile")
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


# -------------------------------------------------------------- widgets

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


func _add_percent_row(parent: VBoxContainer, text: String, key: String,
		min_pct: int, max_pct: int) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_pct
	slider.max_value = max_pct
	slider.step = 5
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		(_percent_labels[key] as Label).text = str(int(value)) + "%"
		Game.set_setting(key, value / 100.0, false))
	slider.drag_ended.connect(func(_changed: bool) -> void:
		Game.save_settings())
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48, 0)
	row.add_child(value_label)
	parent.add_child(row)
	_percent_sliders[key] = slider
	_percent_labels[key] = value_label


func _add_toggle_row(parent: VBoxContainer, text: String, key: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.toggled.connect(func(on: bool) -> void:
		Game.set_setting(key, on))
	parent.add_child(check)
	return check


func _add_option_row(parent: VBoxContainer, text: String, options: Array,
		on_select: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in options:
		option.add_item(str(item))
	option.item_selected.connect(on_select)
	row.add_child(option)
	parent.add_child(row)
	return option


func _on_music_files_selected(paths: PackedStringArray) -> void:
	Game.set_music_files(Array(paths))
	_refresh_music_files_label()


func _refresh_music_files_label() -> void:
	if _music_files_label == null:
		return
	var files := Game.custom_music_files()
	if files.is_empty():
		_music_files_label.text = "My Music: no files chosen yet. Built-in music plays until you choose files (mp3, ogg, or wav)."
	else:
		_music_files_label.text = "My Music: %d file(s) chosen — they play in order as a playlist." % files.size()


func _on_settings_changed() -> void:
	_fit_frame()
	if _current_page == "root":
		_refresh_summaries()
	_refresh_music_files_label()


func refresh() -> void:
	_music_slider.set_value_no_signal(float(Game.settings.get("music_volume", 0.7)) * 100.0)
	_sfx_slider.set_value_no_signal(float(Game.settings.get("sfx_volume", 0.9)) * 100.0)
	for key in _percent_sliders.keys():
		var pct: int = int(round(float(Game.settings.get(key, 1.0)) * 100.0))
		(_percent_sliders[key] as HSlider).set_value_no_signal(pct)
		(_percent_labels[key] as Label).text = str(pct) + "%"
	_left_handed_check.set_pressed_no_signal(Game.left_handed())
	_auto_jump_check.set_pressed_no_signal(Game.auto_jump_enabled())
	_day_night_check.set_pressed_no_signal(Game.day_night_cycle_enabled())
	_music_style_option.select(maxi(MUSIC_STYLE_KEYS.find(Game.music_style()), 0))
	_marking_option.select(maxi(MARKING_KEYS.find(
		str(Game.settings.get("target_marking", "auto"))), 0))
	_sync_edit.text = str(Game.settings.get("sync_folder", ""))
	_refresh_music_files_label()
	_refresh_summaries()
	_refresh_bindings()


## Give the panel a focus owner so gamepad navigation works the moment
## it opens (Close is a safe, always-present target).
func focus_first() -> void:
	if _close_button != null:
		_close_button.grab_focus.call_deferred()


func _refresh_bindings() -> void:
	for action in _rows.keys():
		(_rows[action] as Button).text = Game.binding_summary(action)


func _start_capture(action: String, button: Button) -> void:
	_capturing = action
	_capture_button = button
	button.text = "Press an input… (Esc cancels)"


func _input(event: InputEvent) -> void:
	if visible and _pad_readout != null:
		if event is InputEventJoypadButton and event.pressed:
			_pad_readout.text = "Last gamepad input: " + event.as_text()
		elif event is InputEventJoypadMotion \
				and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
			_pad_readout.text = "Last gamepad input: " + event.as_text()
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
