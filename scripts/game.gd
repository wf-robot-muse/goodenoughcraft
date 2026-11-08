extends Node
## Game — autoload holding everything that spans scenes: user profiles,
## worlds, save slots, per-user settings (volumes, input bindings, sync
## folder), and the session context the title screen hands to the game
## scene (which user / world / slot is being played).
##
## Data layout under user:// :
##   profiles.json                       — [{id, name}]
##   users/<user_id>/settings.json       — volumes, bindings, sync folder
##   users/<user_id>/worlds.json         — [{id, name, seed, created}]
##   users/<user_id>/worlds/<world_id>/slots/<slot>/ — region files,
##       player.json, manifest.json (save_format_version stamped on save)
##
## If no title context was set (the game scene run directly, e.g. by the
## smoke test), a throwaway dev context under user://dev_world is used.

const SAVE_FORMAT_VERSION := 2
const GAME_VERSION := "0.2.0"

const PROFILES_PATH := "user://profiles.json"
const DEV_SLOT_DIR := "user://dev_world/slot"

# action name -> list of default events, each a compact spec Array:
#   ["key", physical_keycode] ["mouse", button_index]
#   ["joybtn", button_index]  ["joyaxis", axis, direction]
const DEFAULT_BINDINGS := {
	"move_forward": [["key", KEY_W], ["joyaxis", JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [["key", KEY_S], ["joyaxis", JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [["key", KEY_A], ["joyaxis", JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [["key", KEY_D], ["joyaxis", JOY_AXIS_LEFT_X, 1.0]],
	"look_up": [["joyaxis", JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [["joyaxis", JOY_AXIS_RIGHT_Y, 1.0]],
	"look_left": [["joyaxis", JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [["joyaxis", JOY_AXIS_RIGHT_X, 1.0]],
	"jump": [["key", KEY_SPACE], ["joybtn", JOY_BUTTON_A]],
	"sprint": [["key", KEY_SHIFT], ["joybtn", JOY_BUTTON_LEFT_STICK]],
	"fly_toggle": [["key", KEY_F], ["joybtn", JOY_BUTTON_Y]],
	"fly_up": [["key", KEY_SPACE], ["joybtn", JOY_BUTTON_RIGHT_SHOULDER]],
	"fly_down": [["key", KEY_CTRL], ["joybtn", JOY_BUTTON_LEFT_SHOULDER]],
	"flashlight": [["key", KEY_L], ["joybtn", JOY_BUTTON_RIGHT_STICK]],
	"mine": [["mouse", MOUSE_BUTTON_LEFT], ["joyaxis", JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"place": [["mouse", MOUSE_BUTTON_RIGHT], ["joyaxis", JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"hotbar_next": [["mouse", MOUSE_BUTTON_WHEEL_DOWN], ["joybtn", JOY_BUTTON_DPAD_RIGHT]],
	"hotbar_prev": [["mouse", MOUSE_BUTTON_WHEEL_UP], ["joybtn", JOY_BUTTON_DPAD_LEFT]],
	"hotbar_1": [["key", KEY_1]],
	"hotbar_2": [["key", KEY_2]],
	"hotbar_3": [["key", KEY_3]],
	"hotbar_4": [["key", KEY_4]],
	"hotbar_5": [["key", KEY_5]],
	"hotbar_6": [["key", KEY_6]],
	"hotbar_7": [["key", KEY_7]],
	"hotbar_8": [["key", KEY_8]],
	"hotbar_9": [["key", KEY_9]],
	"hotbar_10": [["key", KEY_0]],
	"pause": [["key", KEY_ESCAPE], ["joybtn", JOY_BUTTON_START]],
}

const ACTION_LABELS := {
	"move_forward": "Move forward",
	"move_back": "Move back",
	"move_left": "Move left",
	"move_right": "Move right",
	"jump": "Jump / swim up",
	"sprint": "Sprint",
	"fly_toggle": "Toggle fly",
	"fly_up": "Fly up",
	"fly_down": "Fly down",
	"flashlight": "Flashlight",
	"mine": "Mine block",
	"place": "Place block",
	"hotbar_next": "Hotbar next",
	"hotbar_prev": "Hotbar previous",
	"hotbar_1": "Hotbar slot 1",
	"hotbar_2": "Hotbar slot 2",
	"hotbar_3": "Hotbar slot 3",
	"hotbar_4": "Hotbar slot 4",
	"hotbar_5": "Hotbar slot 5",
	"hotbar_6": "Hotbar slot 6",
	"hotbar_7": "Hotbar slot 7",
	"hotbar_8": "Hotbar slot 8",
	"hotbar_9": "Hotbar slot 9",
	"hotbar_10": "Hotbar slot 10",
	"pause": "Pause menu",
}

var profiles: Array = []
var current_user: Dictionary = {}
var current_world: Dictionary = {}
var current_slot := ""
var settings: Dictionary = {}

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_streams: Dictionary = {}

const SFX_NAMES := ["dig", "place", "break", "step", "splash", "ui_click"]
const SYNC_PATH := "user://sync.json"


func _ready() -> void:
	_ensure_audio_buses()
	profiles = _load_json_array(PROFILES_PATH)
	_install_default_bindings()
	_apply_volumes()
	_setup_audio()


func _setup_audio() -> void:
	for sfx_name in SFX_NAMES:
		var path: String = "res://assets/audio/" + sfx_name + ".wav"
		if ResourceLoader.exists(path):
			_sfx_streams[sfx_name] = load(path)
	for i in 8:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	var music_path := "res://assets/audio/music_ambient.wav"
	if ResourceLoader.exists(music_path):
		var music_stream := load(music_path) as AudioStreamWAV
		if music_stream != null:
			# Loop the ambient track (set in code: the WAV importer's
			# loop setting does not survive headless reimports).
			music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			music_stream.loop_begin = 0
			music_stream.loop_end = int(music_stream.get_length() * music_stream.mix_rate)
		_music_player.stream = music_stream
		_music_player.play()


## Play a sound effect from the pool (used by gameplay and UI alike).
func play_sfx(sfx_name: String, pitch := 1.0) -> void:
	if not _sfx_streams.has(sfx_name):
		return
	for player in _sfx_players:
		if not player.playing:
			player.stream = _sfx_streams[sfx_name]
			player.pitch_scale = pitch
			player.play()
			return


# ---------------------------------------------------------------- profiles

func create_user(user_name: String) -> Dictionary:
	var user := {"id": _new_id("u"), "name": user_name}
	profiles.append(user)
	_save_json(PROFILES_PATH, profiles)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir(user["id"])))
	return user


func rename_user(user_id: String, new_name: String) -> void:
	for user in profiles:
		if user.get("id") == user_id:
			user["name"] = new_name
	_save_json(PROFILES_PATH, profiles)


func delete_user(user_id: String) -> void:
	profiles = profiles.filter(func(u: Dictionary) -> bool: return u.get("id") != user_id)
	_save_json(PROFILES_PATH, profiles)
	_delete_dir_recursive(user_dir(user_id))
	if current_user.get("id") == user_id:
		current_user = {}
		current_world = {}
		current_slot = ""


func user_dir(user_id: String) -> String:
	return "user://users/" + user_id


# ----------------------------------------------------------------- worlds

func list_worlds(user_id: String) -> Array:
	return _load_json_array(user_dir(user_id) + "/worlds.json")


func create_world(user_id: String, world_name: String, seed_value: int) -> Dictionary:
	var worlds := list_worlds(user_id)
	var world := {
		"id": _new_id("w"),
		"name": world_name,
		"seed": seed_value,
		"created": Time.get_datetime_string_from_system(),
	}
	worlds.append(world)
	_save_json(user_dir(user_id) + "/worlds.json", worlds)
	return world


func delete_world(user_id: String, world_id: String) -> void:
	var worlds := list_worlds(user_id).filter(
		func(w: Dictionary) -> bool: return w.get("id") != world_id)
	_save_json(user_dir(user_id) + "/worlds.json", worlds)
	_delete_dir_recursive(world_dir(user_id, world_id))


func world_dir(user_id: String, world_id: String) -> String:
	return user_dir(user_id) + "/worlds/" + world_id


# ------------------------------------------------------------------ slots

func list_slots(user_id: String, world_id: String) -> Array:
	var dir_path := world_dir(user_id, world_id) + "/slots"
	var names: Array = []
	var dir := DirAccess.open(dir_path)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				names.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	names.sort()
	return names


func slot_dir_path(user_id: String, world_id: String, slot: String) -> String:
	return world_dir(user_id, world_id) + "/slots/" + slot


func ensure_slot(user_id: String, world_id: String, slot: String) -> String:
	var path := slot_dir_path(user_id, world_id, slot)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	return path


func delete_slot(user_id: String, world_id: String, slot: String) -> void:
	_delete_dir_recursive(slot_dir_path(user_id, world_id, slot))


static func sanitize_slot_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "-" or c == "_":
			out += c
		elif c == " ":
			out += "_"
	return out if out != "" else "slot"


# ---------------------------------------------------------------- context

## Select a profile without a world yet (title screen): makes that
## user's settings the active ones so Settings edits apply to them.
func select_user(user: Dictionary) -> void:
	current_user = user
	current_world = {}
	current_slot = ""
	load_settings(user["id"])


func set_context(user: Dictionary, world: Dictionary, slot: String) -> void:
	current_user = user
	current_world = world
	current_slot = slot
	load_settings(user["id"])
	# A slot the player saves into must exist before the world streams.
	ensure_slot(user["id"], world["id"], slot)


func has_context() -> bool:
	return not current_user.is_empty() and not current_world.is_empty() and current_slot != ""


func active_slot_dir() -> String:
	if has_context():
		return slot_dir_path(current_user["id"], current_world["id"], current_slot)
	return DEV_SLOT_DIR


func active_player_path() -> String:
	return active_slot_dir() + "/player.json"


func active_seed() -> int:
	if has_context():
		return int(current_world.get("seed", 20261107))
	return 20261107


func stamp_manifest() -> void:
	var data := {
		"save_format_version": SAVE_FORMAT_VERSION,
		"game_version": GAME_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"user_name": current_user.get("name", "Dev"),
		"world_name": current_world.get("name", "Dev world"),
		"slot": current_slot,
	}
	_save_json(active_slot_dir() + "/manifest.json", data)


# --------------------------------------------------------------- settings

func default_settings() -> Dictionary:
	return {
		"music_volume": 0.7,
		"sfx_volume": 0.9,
		"sync_folder": "",
		"bindings": {},
	}


func load_settings(user_id: String) -> void:
	settings = default_settings()
	var loaded := _load_json(user_dir(user_id) + "/settings.json")
	for key in loaded.keys():
		settings[key] = loaded[key]
	_apply_settings()


func save_settings() -> void:
	if current_user.is_empty():
		return
	_save_json(user_dir(current_user["id"]) + "/settings.json", settings)


func _apply_settings() -> void:
	_apply_volumes()
	var bindings: Dictionary = settings.get("bindings", {})
	for action in DEFAULT_BINDINGS.keys():
		_erase_action(action)
		var specs: Array = bindings.get(action, DEFAULT_BINDINGS[action])
		for spec in specs:
			var event := _spec_to_event(spec)
			if event != null:
				InputMap.action_add_event(action, event)


func reset_bindings() -> void:
	settings["bindings"] = {}
	_apply_settings()
	save_settings()


## Rebind one action to a single captured event (settings UI capture).
func rebind_action(action: String, event: InputEvent) -> void:
	var spec := _event_to_spec(event)
	if spec.is_empty():
		return
	var bindings: Dictionary = settings.get("bindings", {}).duplicate()
	bindings[action] = [spec]
	settings["bindings"] = bindings
	_erase_action(action)
	InputMap.action_add_event(action, event)
	save_settings()


func binding_summary(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "(unbound)"
	var parts: Array[String] = []
	for event in events:
		parts.append(event.as_text())
	return ", ".join(parts)


func _install_default_bindings() -> void:
	for action in DEFAULT_BINDINGS.keys():
		_erase_action(action)
		for spec in DEFAULT_BINDINGS[action]:
			var event := _spec_to_event(spec)
			if event != null:
				InputMap.action_add_event(action, event)


func _erase_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_set_deadzone(action, 0.15)
	InputMap.action_erase_events(action)


func _spec_to_event(spec: Array) -> InputEvent:
	if spec.size() < 2:
		return null
	match spec[0]:
		"key":
			var event := InputEventKey.new()
			event.physical_keycode = int(spec[1])
			return event
		"mouse":
			var event := InputEventMouseButton.new()
			event.button_index = int(spec[1])
			return event
		"joybtn":
			var event := InputEventJoypadButton.new()
			event.button_index = int(spec[1])
			return event
		"joyaxis":
			var event := InputEventJoypadMotion.new()
			event.axis = int(spec[1])
			event.axis_value = float(spec[2]) if spec.size() > 2 else 1.0
			return event
	return null


func _event_to_spec(event: InputEvent) -> Array:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode
		if code == 0:
			code = key.keycode
		return ["key", code]
	if event is InputEventMouseButton:
		return ["mouse", (event as InputEventMouseButton).button_index]
	if event is InputEventJoypadButton:
		return ["joybtn", (event as InputEventJoypadButton).button_index]
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return ["joyaxis", motion.axis, signf(motion.axis_value) if motion.axis_value != 0.0 else 1.0]
	return []


# ------------------------------------------------------------------ audio

func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


func _apply_volumes() -> void:
	_set_bus_volume("Music", float(settings.get("music_volume", 0.7)))
	_set_bus_volume("SFX", float(settings.get("sfx_volume", 0.9)))


func _set_bus_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))


func set_volume(kind: String, value: float) -> void:
	settings[kind] = value
	_apply_volumes()
	save_settings()


# ------------------------------------------------------------------- misc

# ---------------------------------------------------------- export/import
## A profile export is a single .zip: a manifest.json at the root plus
## the profile's settings.json, worlds.json, and every world/slot file.
## It can live anywhere — USB stick, network share, a Drive/OneDrive/Git
## sync folder — and imports back into a fresh profile.

func find_user(user_id: String) -> Dictionary:
	for user in profiles:
		if user.get("id") == user_id:
			return user
	return {}


func export_profile(user_id: String, dest_path: String) -> bool:
	var user := find_user(user_id)
	if user.is_empty():
		return false
	var packer := ZIPPacker.new()
	if packer.open(dest_path) != OK:
		return false
	var manifest := {
		"format": "goodenoughcraft-profile",
		"version": SAVE_FORMAT_VERSION,
		"game_version": GAME_VERSION,
		"user_name": user.get("name", ""),
		"exported_at": Time.get_datetime_string_from_system(),
	}
	packer.start_file("manifest.json")
	packer.write_file(JSON.stringify(manifest, "\t").to_utf8_buffer())
	packer.close_file()
	_add_dir_to_zip(packer, user_dir(user_id), "")
	packer.close()
	return true


func _add_dir_to_zip(packer: ZIPPacker, base: String, rel: String) -> void:
	var dir := DirAccess.open(base + "/" + rel)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child_rel := entry if rel == "" else rel + "/" + entry
			if dir.current_is_dir():
				_add_dir_to_zip(packer, base, child_rel)
			else:
				var bytes := FileAccess.get_file_as_bytes(base + "/" + child_rel)
				packer.start_file(child_rel)
				packer.write_file(bytes)
				packer.close_file()
		entry = dir.get_next()
	dir.list_dir_end()


func import_profile(zip_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {}
	var files := reader.get_files()
	if not files.has("manifest.json"):
		reader.close()
		return {}
	var parsed: Variant = JSON.parse_string(
		reader.read_file("manifest.json").get_string_from_utf8())
	if parsed is not Dictionary or parsed.get("format") != "goodenoughcraft-profile":
		reader.close()
		return {}
	var user_name := str(parsed.get("user_name", "Imported profile"))
	for user in profiles:
		if user.get("name") == user_name:
			user_name += " (imported)"
			break
	var user := {"id": _new_id("u"), "name": user_name}
	for file_name in files:
		if file_name == "manifest.json" or file_name.ends_with("/"):
			continue
		var dest := user_dir(user["id"]) + "/" + file_name
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(dest.get_base_dir()))
		var out := FileAccess.open(dest, FileAccess.WRITE)
		if out != null:
			out.store_buffer(reader.read_file(file_name))
	reader.close()
	profiles.append(user)
	_save_json(PROFILES_PATH, profiles)
	return user


# ------------------------------------------------------------------- sync
## Optional per-user sync folder: after every world save the profile zip
## is refreshed there, ready to be picked up by whatever syncs that
## folder (or carried on USB). The folder path is also remembered
## globally so the title screen can offer sync import before any
## profile exists.

func global_sync_folder() -> String:
	return str(_load_json(SYNC_PATH).get("folder", ""))


func set_sync_folder(folder: String) -> void:
	settings["sync_folder"] = folder
	save_settings()
	_save_json(SYNC_PATH, {"folder": folder})


func sync_export() -> void:
	if current_user.is_empty():
		return
	var folder := str(settings.get("sync_folder", ""))
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		return
	var dest := folder + "/GoodEnoughCraft-" + str(
		current_user.get("name", "profile")).validate_filename() + ".zip"
	export_profile(current_user["id"], dest)


func _new_id(prefix: String) -> String:
	return prefix + str(Time.get_ticks_msec()) + str(randi() % 100000)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		return parsed
	return []


func _save_json(path: String, data: Variant) -> void:
	var dir_path := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


func _delete_dir_recursive(path: String) -> void:
	_delete_abs_dir(ProjectSettings.globalize_path(path))


func _delete_abs_dir(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := abs_path + "/" + entry
			if dir.current_is_dir():
				_delete_abs_dir(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_path)
