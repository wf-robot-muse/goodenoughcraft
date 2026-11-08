extends Node3D
## GoodEnoughCraft — the game scene: playable voxel sandbox core.
##
## A first-person voxel game on Godot 4.7 + Voxel Tools: streaming blocky
## terrain, walk/jump or fly, mine and place blocks from a hotbar, a
## day/night cycle, and a persistent world. Which user/world/save slot is
## being played comes from the Game autoload (set by the title screen);
## without a title context a throwaway dev world is used. World edits are
## stored by Voxel Tools' region-file stream in the active slot directory;
## player state (position, selection, time of day, flashlight) is stored
## in the slot's player.json. Autosaves run every 30 seconds and on exit.
## Everything is built in code so the project stays plain text.

const TerrainGen := preload("res://scripts/terrain_generator.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")

const DAY_LENGTH := 600.0 # seconds per full day/night cycle
const AUTOSAVE_INTERVAL := 30.0

var terrain: VoxelLodTerrain
var player: CharacterBody3D
var hud: CanvasLayer
var time_of_day := 0.30 # 0.25 = sunrise, 0.5 = noon, 0.75 = sunset

var _sun: DirectionalLight3D
var _environment: Environment
var _save_timer := 0.0
var _pause_menu: CanvasLayer
var _paused := false


func _ready() -> void:
	TerrainGen.active_seed = Game.active_seed()
	_build_environment()
	_build_terrain()
	_build_player()
	_build_hud()
	_build_pause_menu()
	_apply_time_of_day()


func _build_environment() -> void:
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)

	var world_environment := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_material.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_material.ground_bottom_color = Color(0.2, 0.2, 0.25)
	sky_material.ground_horizon_color = Color(0.75, 0.85, 0.95)
	sky.sky_material = sky_material
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.75, 0.85, 0.95)
	_environment.fog_density = 0.004
	_environment.fog_sky_affect = 0.5
	world_environment.environment = _environment
	add_child(world_environment)


func _build_terrain() -> void:
	var stream := VoxelStreamRegionFiles.new()
	stream.directory = Game.active_slot_dir()
	stream.save_generator_output = false

	terrain = VoxelLodTerrain.new()
	terrain.name = "VoxelTerrain"
	terrain.stream = stream
	terrain.generator = TerrainGen.new()
	terrain.mesher = VoxelMesherBlocky.new()
	terrain.mesher.library = Blocks.build_library()
	# The blocky mesher writes the model colors as vertex colors.
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	terrain.material = material
	terrain.view_distance = 96
	terrain.lod_count = 3
	terrain.voxel_bounds = AABB(Vector3(-512, -64, -512), Vector3(1024, 128, 1024))
	terrain.generate_collisions = true
	terrain.collision_lod_count = 1
	add_child(terrain)


func _build_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	player.terrain = terrain
	# Spawn (or restore) before entering the tree so the first physics
	# frame already has the player at the right place.
	var state := _load_state()
	if state.has("pos"):
		var pos: Array = state["pos"]
		player.position = Vector3(pos[0], pos[1], pos[2])
		# Sanity clamp: a save captured mid-fall (or from an older build)
		# must never leave the player below the terrain surface.
		var ground := TerrainGen.surface_height(int(floor(player.position.x)), int(floor(player.position.z)))
		if player.position.y < ground + 1.0:
			player.position.y = ground + 1.05
		time_of_day = float(state.get("time", time_of_day))
	else:
		player.position = _find_spawn()
	add_child(player)
	if state.has("yaw"):
		player.set_look(float(state["yaw"]), float(state.get("pitch", 0.0)))
	if state.has("sel"):
		player.selected_index = clampi(int(state["sel"]), 0, Blocks.HOTBAR.size() - 1)
	if state.has("fly"):
		player.flying = bool(state["fly"])
	player.set_flashlight(bool(state.get("lamp", false)))
	player.pause_requested.connect(_open_pause)


func _find_spawn() -> Vector3:
	# Prefer a grassy column (above the sand line) near the world origin so
	# the first thing a new player sees is the game's typical terrain.
	for dx in range(-24, 25):
		for dz in range(-24, 25):
			var x := 8 + dx
			var z := 8 + dz
			if TerrainGen.surface_height(x, z) >= 3 and not TerrainGen.is_tree_column(x, z):
				return Vector3(x + 0.5, TerrainGen.surface_height(x, z) + 1.05, z + 0.5)
	return Vector3(8.5, TerrainGen.surface_height(8, 8) + 1.05, 8.5)


func _build_hud() -> void:
	hud = HudScript.new()
	add_child(hud)
	player.selection_changed.connect(hud.set_selected)
	hud.set_selected(player.selected_index)


func _build_pause_menu() -> void:
	_pause_menu = PauseMenuScript.new()
	add_child(_pause_menu)
	_pause_menu.resume_requested.connect(_close_pause)
	_pause_menu.save_requested.connect(func() -> void:
		_save_state(true)
		_close_pause())
	_pause_menu.quit_requested.connect(_quit_to_title)


func _open_pause() -> void:
	if _paused:
		return
	_paused = true
	_save_state(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_menu.open()
	get_tree().paused = true


func _close_pause() -> void:
	_paused = false
	_pause_menu.close()
	get_tree().paused = false


func _quit_to_title() -> void:
	_save_state(false)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	_apply_time_of_day()
	_save_timer += delta
	if _save_timer >= AUTOSAVE_INTERVAL:
		_save_timer = 0.0
		_save_state(true)


func _apply_time_of_day() -> void:
	if _sun == null or _environment == null:
		return
	var sun_elev := sin((time_of_day - 0.25) * TAU)
	var daylight := clampf(sun_elev * 1.8 + 0.25, 0.0, 1.0)
	_sun.rotation_degrees = Vector3(-((time_of_day - 0.25) * 360.0), -30.0, 0.0)
	_sun.light_energy = clampf(sun_elev * 1.8, 0.02, 1.0)
	var warmth := clampf(sun_elev * 2.0, 0.0, 1.0)
	_sun.light_color = Color(1.0, lerpf(0.55, 1.0, warmth), lerpf(0.35, 0.95, warmth))
	_environment.background_energy_multiplier = lerpf(0.12, 1.0, daylight)
	_environment.fog_light_color = Color(0.03, 0.04, 0.09).lerp(Color(0.75, 0.85, 0.95), daylight)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_state(false)


func _load_state() -> Dictionary:
	var path := Game.active_player_path()
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _save_state(show_flash: bool) -> void:
	if terrain == null or player == null:
		return
	terrain.save_modified_blocks()
	var data := {
		"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
		"yaw": player.rotation.y,
		"pitch": player.get_pitch(),
		"sel": player.selected_index,
		"time": time_of_day,
		"fly": player.flying,
		"lamp": player.flashlight_on,
	}
	var file := FileAccess.open(Game.active_player_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
	Game.stamp_manifest()
	if show_flash and hud != null:
		hud.flash_message("World saved")
