extends Node3D
## Title screen: a slowly orbiting view of a floating island whose logo
## is built from the game's own blocks, plus the profile → world → save
## slot flow, settings, and quit. Profiles, worlds, and slots all live in
## the Game autoload; this scene only presents them.
##
## Flow: pick (or create) a named profile, pick (or create) one of that
## profile's worlds, pick (or create) a save slot in that world, Play.
## Profiles and worlds can be renamed/deleted; slots can be deleted.
## Deletes need a second press to confirm.

const TitleGen := preload("res://scripts/title_generator.gd")
const SettingsUIScript := preload("res://scripts/settings_ui.gd")

const LOGO_CENTER := Vector3(0, 9, -14)

var _camera: Camera3D
var _time := 0.0

var _screens: Dictionary = {}
var _profiles_list: ItemList
var _profile_name_edit: LineEdit
var _worlds_list: ItemList
var _world_name_edit: LineEdit
var _world_seed_edit: LineEdit
var _worlds_header: Label
var _slots_list: ItemList
var _slot_name_edit: LineEdit
var _slots_header: Label
var _status_label: Label
var _settings: SettingsUI
var _settings_center: CenterContainer

var _selected_user: Dictionary = {}
var _selected_world: Dictionary = {}
var _pending_delete := ""


func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_camera()
	_build_ui()
	_refresh_profiles()
	_show_screen("profiles")


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
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	terrain.material = material
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
	# all times while the view still feels alive.
	var angle := sin(_time * 0.12) * 0.42
	var pos := LOGO_CENTER + Vector3(sin(angle) * 42.0, 11.5 + sin(_time * 0.05) * 1.2, cos(angle) * 42.0)
	_camera.global_position = pos
	_camera.look_at(LOGO_CENTER + Vector3(0, -0.5, 0), Vector3.UP)


# --------------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	var title := Label.new()
	title.text = "GoodEnoughCraft"
	title.add_theme_font_size_override("font_size", 44)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = 26
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	root.add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -290
	center.offset_right = 290
	center.offset_top = 30
	center.offset_bottom = 420
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)

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

	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.offset_left = 16
	bottom.offset_top = -52
	bottom.offset_right = 320
	bottom.offset_bottom = -16
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_open_settings)
	bottom.add_child(settings_button)
	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	bottom.add_child(quit_button)

	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	layer.add_child(_settings_center)
	_settings = SettingsUIScript.new()
	_settings_center.add_child(_settings)
	_settings.closed.connect(func() -> void: _settings_center.visible = false)


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
	return vbox


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
		["← Worlds", func() -> void: _show_screen("worlds")],
	])
	return vbox


func _show_screen(screen_name: String) -> void:
	for key in _screens.keys():
		(_screens[key] as Control).visible = key == screen_name
	_pending_delete = ""
	if screen_name == "profiles":
		_profiles_list.grab_focus.call_deferred()
	elif screen_name == "worlds":
		_worlds_list.grab_focus.call_deferred()
	else:
		_slots_list.grab_focus.call_deferred()


func _status(text: String) -> void:
	_status_label.text = text


# --------------------------------------------------------------- profiles

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
