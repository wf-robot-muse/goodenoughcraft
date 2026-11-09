extends Node3D
## Title screen: a slowly swaying view of a floating island whose logo
## is built from the game's own blocks.
##
## Flow (reworked in v0.2.1): a minimal front screen with just Start and
## Settings. Start opens the home card: a big Continue button resumes
## the last played profile/world/slot, each world has its own Play
## button, profiles switch from a chip row, and full management
## (rename/delete/export/import) lives one level down under Manage —
## the original profiles → worlds → slots screens.
##
## All screens are button-driven and grab focus when shown, so a
## gamepad can navigate everything; name fields offer an on-screen
## keyboard when the last input device was a gamepad.

const TitleGen := preload("res://scripts/title_generator.gd")
const SettingsUIScript := preload("res://scripts/settings_ui.gd")
const OskScript := preload("res://scripts/osk.gd")

const LOGO_CENTER := Vector3(0, 9, -14)

var _camera: Camera3D
var _time := 0.0

var _screens: Dictionary = {}
var _current_screen := "front"
var _panel_center: CenterContainer
var _start_button: Button

var _home_header: Label
var _home_first_run: VBoxContainer
var _first_profile_edit: LineEdit
var _first_profile_button: Button
var _home_main: VBoxContainer
var _continue_button: Button
var _continue_ctx: Dictionary = {}
var _home_focus: Control
var _home_worlds_box: VBoxContainer
var _home_chips_box: HBoxContainer
var _active_user: Dictionary = {}

var _newworld_header: Label
var _nw_name_edit: LineEdit
var _nw_seed_edit: LineEdit
var _nw_create_button: Button

var _np_name_edit: LineEdit
var _np_create_button: Button

var _profiles_list: ItemList
var _profile_name_edit: LineEdit
var _worlds_list: ItemList
var _world_name_edit: LineEdit
var _world_seed_edit: LineEdit
var _worlds_header: Label
var _slots_list: ItemList
var _slot_name_edit: LineEdit
var _slots_header: Label
var _slots_back_target := "worlds"
var _status_label: Label
var _settings: SettingsUI
var _settings_center: CenterContainer
var _export_dialog: FileDialog
var _import_dialog: FileDialog
var _osk: OnScreenKeyboard
var _osk_center: CenterContainer

var _selected_user: Dictionary = {}
var _selected_world: Dictionary = {}
var _pending_delete := ""


func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_camera()
	_build_ui()
	_refresh_profiles()
	_init_active_user()
	_refresh_home()
	_show_screen("front")


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.0
	add_child(sun)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_material.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_material.ground_bottom_color = Color(0.2, 0.2, 0.25)
	sky_material.ground_horizon_color = Color(0.75, 0.85, 0.95)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.75, 0.85, 0.95)
	environment.fog_density = 0.0025
	environment.fog_sky_affect = 0.5
	world_environment.environment = environment
	add_child(world_environment)


func _build_terrain() -> void:
	var stream := VoxelStreamRegionFiles.new()
	stream.directory = "user://title_island"
	stream.save_generator_output = false
	var terrain := VoxelLodTerrain.new()
	terrain.name = "TitleTerrain"
	terrain.stream = stream
	terrain.generator = TitleGen.new()
	terrain.mesher = VoxelMesherBlocky.new()
	terrain.mesher.library = Blocks.build_library()
	terrain.material = Blocks.terrain_material()
	terrain.view_distance = 160
	terrain.lod_count = 3
	terrain.voxel_bounds = AABB(Vector3(-128, -32, -128), Vector3(256, 96, 256))
	terrain.generate_collisions = false
	add_child(terrain)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 160
	_camera.add_child(viewer)
	_update_camera()


func _process(delta: float) -> void:
	_time += delta
	_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	# A gentle sway in front of the logo wall: the logo stays readable at
	# all times while the view still feels alive. Radius 35 (was 42)
	# frames the logo bigger, per the approved v0.2.1 title treatment.
	var angle := sin(_time * 0.12) * 0.42
	var pos := LOGO_CENTER + Vector3(sin(angle) * 35.0, 11.5 + sin(_time * 0.05) * 1.2, cos(angle) * 35.0)
	_camera.global_position = pos
	_camera.look_at(LOGO_CENTER + Vector3(0, -0.5, 0), Vector3.UP)


# --------------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	# Front screen: just Start and Settings over the island view.
	var front_center := CenterContainer.new()
	front_center.set_anchors_preset(Control.PRESET_CENTER)
	front_center.offset_left = -200
	front_center.offset_right = 200
	front_center.offset_top = 118
	front_center.offset_bottom = 270
	root.add_child(front_center)
	var front_box := VBoxContainer.new()
	front_box.add_theme_constant_override("separation", 16)
	front_center.add_child(front_box)
	_start_button = _mk_button("Start", func() -> void: _show_screen("home"))
	_start_button.custom_minimum_size = Vector2(400, 66)
	_start_button.add_theme_font_size_override("font_size", 26)
	front_box.add_child(_start_button)
	var front_settings := _mk_button("Settings", _open_settings)
	front_settings.custom_minimum_size = Vector2(400, 66)
	front_settings.add_theme_font_size_override("font_size", 26)
	front_box.add_child(front_settings)
	_screens["front"] = front_center

	# Card screens (home, create forms, manage flow) share one panel.
	_panel_center = CenterContainer.new()
	_panel_center.set_anchors_preset(Control.PRESET_CENTER)
	_panel_center.offset_left = -290
	_panel_center.offset_right = 290
	_panel_center.offset_top = -160
	_panel_center.offset_bottom = 280
	root.add_child(_panel_center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 440)
	_panel_center.add_child(panel)

	_screens["home"] = _build_home_screen(panel)
	_screens["newworld"] = _build_newworld_screen(panel)
	_screens["newprofile"] = _build_newprofile_screen(panel)
	_screens["profiles"] = _build_profiles_screen(panel)
	_screens["worlds"] = _build_worlds_screen(panel)
	_screens["slots"] = _build_slots_screen(panel)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status_label.offset_left = -400
	_status_label.offset_right = 400
	_status_label.offset_top = -64
	_status_label.offset_bottom = -40
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(1, 1, 0.85))
	_status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	root.add_child(_status_label)

	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	layer.add_child(_settings_center)
	_settings = SettingsUIScript.new()
	_settings_center.add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings_center.visible = false
		_focus_current())

	_osk_center = CenterContainer.new()
	_osk_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_osk_center.visible = false
	layer.add_child(_osk_center)
	_osk = OskScript.new()
	_osk_center.add_child(_osk)
	_osk.finished.connect(func(_confirmed: bool) -> void: _osk_center.visible = false)

	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = PackedStringArray(["*.zip ; ZIP archive"])
	_export_dialog.title = "Export profile as zip"
	_export_dialog.file_selected.connect(_do_export)
	layer.add_child(_export_dialog)

	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.zip ; ZIP archive"])
	_import_dialog.title = "Import a profile zip"
	_import_dialog.file_selected.connect(_do_import)
	layer.add_child(_import_dialog)

	_wire_osk_fields()
	_wire_clicks(layer)


func _mk_button(text: String, on_press := Callable()) -> Button:
	# Click sounds: static buttons are wired once by _wire_clicks;
	# buttons created later (home world/chip rows) get _wire_sfx.
	var button := Button.new()
	button.text = text
	if on_press.is_valid():
		button.pressed.connect(on_press)
	return button


func _wire_sfx(button: Button) -> void:
	button.pressed.connect(_click_sfx)


func _wire_clicks(root_node: Node) -> void:
	for node in root_node.find_children("*", "Button", true, false):
		var button := node as Button
		if button.pressed.is_connected(_click_sfx):
			continue
		button.pressed.connect(_click_sfx)


func _click_sfx() -> void:
	Game.play_sfx("ui_click")


func _screen_box(panel: PanelContainer, header_text: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(540, 0)
	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 20)
	vbox.add_child(header)
	panel.add_child(vbox)
	vbox.visible = false
	return vbox


func _list() -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 132)
	return list


func _button_row(parent: VBoxContainer, buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for spec in buttons:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(spec[1])
		row.add_child(button)
	parent.add_child(row)


# ------------------------------------------------------------------- home

func _build_home_screen(panel: PanelContainer) -> VBoxContainer:
	var vbox := _screen_box(panel, "GoodEnoughCraft")
	_home_header = vbox.get_child(0) as Label

	_home_first_run = VBoxContainer.new()
	_home_first_run.add_theme_constant_override("separation", 8)
	vbox.add_child(_home_first_run)
	var welcome := Label.new()
	welcome.text = "Create a profile to start playing."
	_home_first_run.add_child(welcome)
	_first_profile_edit = LineEdit.new()
	_first_profile_edit.placeholder_text = "Your name"
	_home_first_run.add_child(_first_profile_edit)
	_first_profile_button = _mk_button("Create profile", _create_first_profile)
	_home_first_run.add_child(_first_profile_button)

	_home_main = VBoxContainer.new()
	_home_main.add_theme_constant_override("separation", 8)
	_home_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_home_main)
	_continue_button = _mk_button("", _continue_play)
	_continue_button.custom_minimum_size = Vector2(0, 54)
	_continue_button.add_theme_font_size_override("font_size", 19)
	_home_main.add_child(_continue_button)
	var worlds_label := Label.new()
	worlds_label.text = "Worlds"
	worlds_label.add_theme_font_size_override("font_size", 17)
	_home_main.add_child(worlds_label)
	# The worlds list scrolls inside the fixed-height card, so any
	# number of worlds stays reachable without growing the panel.
	var worlds_scroll := ScrollContainer.new()
	worlds_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	worlds_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	worlds_scroll.custom_minimum_size = Vector2(0, 40)
	_home_main.add_child(worlds_scroll)
	_home_worlds_box = VBoxContainer.new()
	_home_worlds_box.add_theme_constant_override("separation", 6)
	_home_worlds_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	worlds_scroll.add_child(_home_worlds_box)
	var new_world := _mk_button("＋ New world", func() -> void: _show_screen("newworld"))
	_home_main.add_child(new_world)
	_home_main.add_child(HSeparator.new())
	var profiles_label := Label.new()
	profiles_label.text = "Profiles"
	profiles_label.add_theme_font_size_override("font_size", 17)
	_home_main.add_child(profiles_label)
	_home_chips_box = HBoxContainer.new()
	_home_chips_box.add_theme_constant_override("separation", 6)
	_home_main.add_child(_home_chips_box)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	_home_main.add_child(footer)
	footer.add_child(_mk_button("Manage profiles & worlds…", func() -> void:
		_selected_user = _active_user
		_refresh_profiles()
		_show_screen("profiles")))
	footer.add_child(_mk_button("Settings", _open_settings))
	footer.add_child(_mk_button("Quit", func() -> void: get_tree().quit()))
	return vbox


func _init_active_user() -> void:
	var ctx := Game.last_context()
	if not ctx.is_empty():
		_active_user = ctx["user"]
	elif not Game.profiles.is_empty():
		_active_user = Game.profiles[0]
	if not _active_user.is_empty():
		Game.select_user(_active_user)


func _set_active_user(user: Dictionary) -> void:
	_active_user = user
	Game.select_user(user)
	_refresh_home()


func _refresh_home() -> void:
	if not _active_user.is_empty():
		var found := Game.find_user(str(_active_user.get("id", "")))
		if found.is_empty():
			_active_user = {}
		else:
			_active_user = found
	if _active_user.is_empty() and not Game.profiles.is_empty():
		_active_user = Game.profiles[0]
		Game.select_user(_active_user)

	var no_profiles := Game.profiles.is_empty()
	_home_first_run.visible = no_profiles
	_home_main.visible = not no_profiles
	_home_focus = null
	if no_profiles:
		_home_header.text = "Welcome to GoodEnoughCraft"
		_home_focus = _first_profile_button
		return
	_home_header.text = "Profile: " + str(_active_user.get("name", ""))

	_continue_ctx = Game.last_context()
	if _continue_ctx.is_empty():
		_continue_button.visible = false
	else:
		_continue_button.visible = true
		var label := "▶ Continue — " + str(_continue_ctx["world"].get("name", "")) \
			+ " · " + str(_continue_ctx["slot"])
		if str(_continue_ctx["user"].get("id", "")) != str(_active_user.get("id", "")):
			label += " (" + str(_continue_ctx["user"].get("name", "")) + ")"
		_continue_button.text = label
		_home_focus = _continue_button

	for child in _home_worlds_box.get_children():
		_home_worlds_box.remove_child(child)
		child.queue_free()
	for world in Game.list_worlds(_active_user["id"]):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_home_worlds_box.add_child(row)
		var play := _mk_button("▶ " + str(world.get("name", "")), _play_world.bind(world))
		_wire_sfx(play)
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.add_theme_font_size_override("font_size", 17)
		row.add_child(play)
		if _home_focus == null:
			_home_focus = play
		var slots_button := _mk_button("Slots…", _open_slots_for.bind(world))
		_wire_sfx(slots_button)
		row.add_child(slots_button)

	for child in _home_chips_box.get_children():
		_home_chips_box.remove_child(child)
		child.queue_free()
	for user in Game.profiles:
		var chip_text := str(user.get("name", ""))
		if str(user.get("id", "")) == str(_active_user.get("id", "")):
			chip_text = "● " + chip_text
		var chip := _mk_button(chip_text, _set_active_user.bind(user))
		_wire_sfx(chip)
		_home_chips_box.add_child(chip)
	var new_chip := _mk_button("＋ New", func() -> void: _show_screen("newprofile"))
	_wire_sfx(new_chip)
	_home_chips_box.add_child(new_chip)


func _create_first_profile() -> void:
	var user_name := _first_profile_edit.text.strip_edges()
	if user_name == "":
		_status("Type your name first.")
		return
	var user := Game.create_user(user_name)
	_first_profile_edit.text = ""
	_set_active_user(user)
	_status("Profile created: " + user_name)


func _continue_play() -> void:
	if _continue_ctx.is_empty():
		return
	_selected_user = _continue_ctx["user"]
	_selected_world = _continue_ctx["world"]
	_play(str(_continue_ctx["slot"]))


func _play_world(world: Dictionary) -> void:
	_selected_user = _active_user
	_selected_world = world
	var slot := Game.preferred_slot(_active_user, world)
	if slot == "":
		slot = "Slot1"
	_play(slot)


func _open_slots_for(world: Dictionary) -> void:
	_selected_user = _active_user
	_selected_world = world
	_slots_back_target = "home"
	_slots_header.text = "Save slots — " + str(world.get("name", ""))
	_refresh_slots()
	_show_screen("slots")


# -------------------------------------------------------------- create forms

func _build_newworld_screen(panel: PanelContainer) -> VBoxContainer:
	var vbox := _screen_box(panel, "New world")
	_newworld_header = vbox.get_child(0) as Label
	_nw_name_edit = LineEdit.new()
	_nw_name_edit.placeholder_text = "World name"
	vbox.add_child(_nw_name_edit)
	_nw_seed_edit = LineEdit.new()
	_nw_seed_edit.placeholder_text = "Seed (blank = random)"
	vbox.add_child(_nw_seed_edit)
	_nw_create_button = _mk_button("Create & play", _create_world_and_play)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_nw_create_button)
	row.add_child(_mk_button("← Back", func() -> void: _show_screen("home")))
	vbox.add_child(row)
	return vbox


func _create_world_and_play() -> void:
	if _active_user.is_empty():
		return
	var world_name := _nw_name_edit.text.strip_edges()
	if world_name == "":
		_status("Type a name for the new world first.")
		return
	var seed_value: int
	if _nw_seed_edit.text.strip_edges() == "":
		seed_value = int(randi())
	else:
		seed_value = int(_nw_seed_edit.text.strip_edges().hash())
	var world := Game.create_world(_active_user["id"], world_name, seed_value)
	_nw_name_edit.text = ""
	_nw_seed_edit.text = ""
	_selected_user = _active_user
	_selected_world = world
	_play("Slot1")


func _build_newprofile_screen(panel: PanelContainer) -> VBoxContainer:
	var vbox := _screen_box(panel, "New profile")
	_np_name_edit = LineEdit.new()
	_np_name_edit.placeholder_text = "Profile name"
	vbox.add_child(_np_name_edit)
	_np_create_button = _mk_button("Create profile", _create_profile_from_form)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_np_create_button)
	row.add_child(_mk_button("← Back", func() -> void: _show_screen("home")))
	vbox.add_child(row)
	return vbox


func _create_profile_from_form() -> void:
	var user_name := _np_name_edit.text.strip_edges()
	if user_name == "":
		_status("Type a name for the new profile first.")
		return
	var user := Game.create_user(user_name)
	_np_name_edit.text = ""
	_set_active_user(user)
	_show_screen("home")
	_status("Profile created: " + user_name)


# ------------------------------------------------------------ screen flow

func _show_screen(screen_name: String) -> void:
	_current_screen = screen_name
	_pending_delete = ""
	if screen_name == "home":
		_refresh_home()
	if screen_name == "newworld" and not _active_user.is_empty():
		_newworld_header.text = "New world — " + str(_active_user.get("name", ""))
	_panel_center.visible = screen_name != "front"
	for key in _screens.keys():
		(_screens[key] as Control).visible = key == screen_name
	_focus_current()


func _focus_current() -> void:
	var target: Control = null
	match _current_screen:
		"front":
			target = _start_button
		"home":
			target = _home_focus if _home_focus != null else _continue_button
		"newworld":
			target = _nw_name_edit
		"newprofile":
			target = _np_name_edit
		"profiles":
			target = _profiles_list
		"worlds":
			target = _worlds_list
		"slots":
			target = _slots_list
	if target != null:
		target.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	# Safety net: if gamepad input arrives while nothing owns focus
	# (e.g. after a dialog closed), restart navigation at the current
	# screen's default control instead of leaving the pad dead.
	if _settings_center.visible or _osk_center.visible:
		return
	var pad_input := false
	if event is InputEventJoypadButton and event.pressed:
		pad_input = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
		pad_input = true
	if pad_input and get_viewport().gui_get_focus_owner() == null:
		_focus_current()


func _status(text: String) -> void:
	_status_label.text = text


# --------------------------------------------------------------------- OSK

func _wire_osk_fields() -> void:
	_wire_osk(_first_profile_edit, _first_profile_button)
	_wire_osk(_nw_name_edit, _nw_create_button)
	_wire_osk(_nw_seed_edit, _nw_create_button)
	_wire_osk(_np_name_edit, _np_create_button)
	_wire_osk(_profile_name_edit, _profiles_list)
	_wire_osk(_world_name_edit, _worlds_list)
	_wire_osk(_world_seed_edit, _worlds_list)
	_wire_osk(_slot_name_edit, _slots_list)


func _wire_osk(edit: LineEdit, back: Control) -> void:
	edit.focus_entered.connect(func() -> void:
		if Game.pad_mode:
			_osk.open_for(edit, back)
			_osk_center.visible = true)


# ------------------------------------------------- manage: profiles flow

func _build_profiles_screen(panel: PanelContainer) -> VBoxContainer:
	var vbox := _screen_box(panel, "Player profiles")
	_profiles_list = _list()
	_profiles_list.item_activated.connect(func(_i: int) -> void: _select_profile())
	vbox.add_child(_profiles_list)
	_profile_name_edit = LineEdit.new()
	_profile_name_edit.placeholder_text = "Profile name (for a new profile, or a rename)"
	vbox.add_child(_profile_name_edit)
	_button_row(vbox, [
		["Create profile", _create_profile],
		["Select profile →", _select_profile],
		["Rename", _rename_profile],
		["Delete", _delete_profile],
	])
	_button_row(vbox, [
		["Export profile…", _export_profile],
		["Import profile…", _import_profile],
		["← Home", func() -> void: _show_screen("home")],
	])
	return vbox


func _refresh_profiles() -> void:
	_profiles_list.clear()
	for user in Game.profiles:
		_profiles_list.add_item(user.get("name", "?"))
	if Game.profiles.size() > 0:
		_profiles_list.select(0)


func _picked_user() -> Dictionary:
	var selected := _profiles_list.get_selected_items()
	if selected.is_empty():
		return {}
	return Game.profiles[selected[0]]


func _create_profile() -> void:
	var user_name := _profile_name_edit.text.strip_edges()
	if user_name == "":
		_status("Type a name for the new profile first.")
		return
	var user := Game.create_user(user_name)
	_profile_name_edit.text = ""
	_refresh_profiles()
	Game.select_user(user)
	_status("Profile created: " + user_name)


func _select_profile() -> void:
	var user := _picked_user()
	if user.is_empty():
		_status("No profile selected. Create one first.")
		return
	_selected_user = user
	Game.select_user(user)
	_worlds_header.text = "Worlds — " + user.get("name", "")
	_refresh_worlds()
	_show_screen("worlds")


func _rename_profile() -> void:
	var user := _picked_user()
	var new_name := _profile_name_edit.text.strip_edges()
	if user.is_empty() or new_name == "":
		_status("Select a profile and type its new name.")
		return
	Game.rename_user(user["id"], new_name)
	_profile_name_edit.text = ""
	_refresh_profiles()
	_status("Profile renamed to " + new_name)


func _delete_profile() -> void:
	var user := _picked_user()
	if user.is_empty():
		return
	if _pending_delete != "user:" + user["id"]:
		_pending_delete = "user:" + user["id"]
		_status("Press Delete again to permanently delete profile '" + user.get("name", "") + "' and all its worlds and saves.")
		return
	Game.delete_user(user["id"])
	_pending_delete = ""
	_refresh_profiles()
	_status("Profile deleted.")


# ----------------------------------------------------------------- worlds

func _build_worlds_screen(panel: PanelContainer) -> VBoxContainer:
	var vbox := _screen_box(panel, "Worlds")
	_worlds_header = vbox.get_child(0) as Label
	_worlds_list = _list()
	_worlds_list.item_activated.connect(func(_i: int) -> void: _select_world())
	vbox.add_child(_worlds_list)
	_world_name_edit = LineEdit.new()
	_world_name_edit.placeholder_text = "New world name"
	vbox.add_child(_world_name_edit)
	_world_seed_edit = LineEdit.new()
	_world_seed_edit.placeholder_text = "Seed (blank = random)"
	vbox.add_child(_world_seed_edit)
	_button_row(vbox, [
		["Create world", _create_world],
		["Select world →", _select_world],
		["Delete world", _delete_world],
		["← Profiles", func() -> void: _show_screen("profiles")],
	])
	return vbox


func _refresh_worlds() -> void:
	_worlds_list.clear()
	if _selected_user.is_empty():
		return
	var worlds := Game.list_worlds(_selected_user["id"])
	for world in worlds:
		_worlds_list.add_item(world.get("name", "?") + "  (seed " + str(world.get("seed", 0)) + ")")
	if worlds.size() > 0:
		_worlds_list.select(0)


func _picked_world() -> Dictionary:
	var selected := _worlds_list.get_selected_items()
	if selected.is_empty() or _selected_user.is_empty():
		return {}
	return Game.list_worlds(_selected_user["id"])[selected[0]]


func _create_world() -> void:
	if _selected_user.is_empty():
		return
	var world_name := _world_name_edit.text.strip_edges()
	if world_name == "":
		_status("Type a name for the new world first.")
		return
	var seed_value: int
	if _world_seed_edit.text.strip_edges() == "":
		seed_value = int(randi())
	else:
		seed_value = int(_world_seed_edit.text.strip_edges().hash())
	var world := Game.create_world(_selected_user["id"], world_name, seed_value)
	_world_name_edit.text = ""
	_world_seed_edit.text = ""
	_refresh_worlds()
	_status("World created: " + world_name + " (seed " + str(world.get("seed", 0)) + ")")


func _select_world() -> void:
	var world := _picked_world()
	if world.is_empty():
		_status("No world selected. Create one first.")
		return
	_selected_world = world
	_slots_back_target = "worlds"
	_slots_header.text = "Save slots — " + world.get("name", "")
	_refresh_slots()
	_show_screen("slots")


func _delete_world() -> void:
	var world := _picked_world()
	if world.is_empty():
		return
	if _pending_delete != "world:" + world["id"]:
		_pending_delete = "world:" + world["id"]
		_status("Press Delete world again to permanently delete '" + world.get("name", "") + "' and all its save slots.")
		return
	Game.delete_world(_selected_user["id"], world["id"])
	_pending_delete = ""
	_refresh_worlds()
	_status("World deleted.")


# ------------------------------------------------------------------ slots

func _build_slots_screen(panel: PanelContainer) -> VBoxContainer:
	var vbox := _screen_box(panel, "Save slots")
	_slots_header = vbox.get_child(0) as Label
	_slots_list = _list()
	_slots_list.item_activated.connect(func(_i: int) -> void: _play_selected_slot())
	vbox.add_child(_slots_list)
	_slot_name_edit = LineEdit.new()
	_slot_name_edit.placeholder_text = "New slot name (then Create & Play)"
	vbox.add_child(_slot_name_edit)
	_button_row(vbox, [
		["▶ Play", _play_selected_slot],
		["Create slot & play", _create_slot_and_play],
		["Delete slot", _delete_slot],
		["← Back", func() -> void: _show_screen(_slots_back_target)],
	])
	return vbox


func _refresh_slots() -> void:
	_slots_list.clear()
	if _selected_user.is_empty() or _selected_world.is_empty():
		return
	var slots := Game.list_slots(_selected_user["id"], _selected_world["id"])
	for slot in slots:
		_slots_list.add_item(slot)
	if slots.size() > 0:
		_slots_list.select(0)


func _play_selected_slot() -> void:
	var selected := _slots_list.get_selected_items()
	if selected.is_empty():
		_status("No save slot selected. Create one below.")
		return
	_play(_slots_list.get_item_text(selected[0]))


func _create_slot_and_play() -> void:
	var slot := Game.sanitize_slot_name(_slot_name_edit.text.strip_edges())
	Game.ensure_slot(_selected_user["id"], _selected_world["id"], slot)
	_play(slot)


func _delete_slot() -> void:
	var selected := _slots_list.get_selected_items()
	if selected.is_empty():
		return
	var slot := _slots_list.get_item_text(selected[0])
	if _pending_delete != "slot:" + slot:
		_pending_delete = "slot:" + slot
		_status("Press Delete slot again to permanently delete slot '" + slot + "'.")
		return
	Game.delete_slot(_selected_user["id"], _selected_world["id"], slot)
	_pending_delete = ""
	_refresh_slots()
	_status("Slot deleted.")


func _play(slot: String) -> void:
	Game.set_context(_selected_user, _selected_world, slot)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _open_settings() -> void:
	_settings.refresh()
	_settings_center.visible = true
	_settings.focus_first()


# ---------------------------------------------------------- export/import

func _export_profile() -> void:
	var user := _picked_user()
	if user.is_empty():
		_status("Select a profile to export first.")
		return
	_export_dialog.set_meta("user_id", user["id"])
	_export_dialog.current_file = "GoodEnoughCraft-" + str(
		user.get("name", "profile")).validate_filename() + ".zip"
	_export_dialog.popup_centered_ratio(0.6)


func _do_export(path: String) -> void:
	if Game.export_profile(str(_export_dialog.get_meta("user_id", "")), path):
		_status("Profile exported: " + path)
	else:
		_status("Export failed — could not write that file.")


func _import_profile() -> void:
	var folder := Game.global_sync_folder()
	if folder != "":
		_import_dialog.current_dir = folder
	_import_dialog.popup_centered_ratio(0.6)


func _do_import(path: String) -> void:
	var user := Game.import_profile(path)
	if user.is_empty():
		_status("That file is not a GoodEnoughCraft profile export.")
	else:
		_refresh_profiles()
		_status("Imported profile: " + str(user.get("name", "")))
