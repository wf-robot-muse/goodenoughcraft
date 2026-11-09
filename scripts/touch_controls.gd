extends CanvasLayer
## Touch controls for tablets (Fire OS / Android), built in code like
## the HUD. Layout follows the usual mobile-sandbox pattern:
##
## - Left thumb: a virtual joystick that appears where the thumb lands
##   (left 42% of the screen) and steers with full analog strength.
## - Right side: drag anywhere to look around.
## - Buttons (bottom right): MINE and PLACE (tap = one block, hold =
##   repeat), JUMP (doubles as fly-up while flying; a DOWN button
##   appears next to it in fly mode), and a small row with FLY, LAMP
##   (flashlight) and RUN (sprint toggle). II at the top right pauses.
## - The hotbar stays tappable for block selection (see hud.gd).
##
## The layer activates automatically on Android; on any other platform
## it activates on the first touch input, so desktop play with keyboard,
## mouse, or gamepad is completely unaffected.

const JOY_RADIUS := 62.0

var _player = null
var _hud = null
var _active := false
var _was_paused := false

var _joy_base: Panel
var _joy_knob: Panel
var _joy_id := -1
var _joy_origin := Vector2.ZERO

var _down_btn: Button
var _jump_fly := false


func _ready() -> void:
	layer = 2
	# Keep _process running while the tree is paused so the layer can
	# hide itself under the pause menu and release held actions.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_zones()
	_build_buttons()


func setup(player, hud) -> void:
	_player = player
	_hud = hud
	if OS.has_feature("android"):
		_activate()


func _activate() -> void:
	if _active:
		return
	_active = true
	visible = not get_tree().paused
	if _player != null:
		_player.set_touch_mode(true)
	if _hud != null and _hud.has_method("set_touch_hint"):
		_hud.set_touch_hint()


func _input(event: InputEvent) -> void:
	if not _active and event is InputEventScreenTouch and event.pressed:
		_activate()


func _process(_delta: float) -> void:
	if not _active:
		return
	var paused_now := get_tree().paused
	if paused_now and not _was_paused:
		_release_all()
	_was_paused = paused_now
	visible = not paused_now
	if _down_btn != null:
		_down_btn.visible = _player != null and _player.flying


func _release_all() -> void:
	for action in ["mine", "place", "jump", "sprint", "fly_up", "fly_down"]:
		Input.action_release(action)
	if _player != null:
		_player.touch_move = Vector2.ZERO
	_joy_id = -1
	if _joy_base != null:
		_joy_base.visible = false
	if _joy_knob != null:
		_joy_knob.visible = false


# --- Construction ---

func _circle_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(200)
	return style


func _build_zones() -> void:
	var move_zone := Control.new()
	move_zone.anchor_top = 0.30
	move_zone.anchor_right = 0.42
	move_zone.anchor_bottom = 1.0
	move_zone.offset_bottom = -128 # keep the hotbar strip tappable
	move_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	move_zone.gui_input.connect(_on_move_zone_input)
	add_child(move_zone)

	_joy_base = Panel.new()
	_joy_base.custom_minimum_size = Vector2(190, 190)
	_joy_base.size = Vector2(190, 190)
	_joy_base.add_theme_stylebox_override("panel",
		_circle_style(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.30)))
	_joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_base.visible = false
	move_zone.add_child(_joy_base)

	_joy_knob = Panel.new()
	_joy_knob.custom_minimum_size = Vector2(80, 80)
	_joy_knob.size = Vector2(80, 80)
	_joy_knob.add_theme_stylebox_override("panel",
		_circle_style(Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.55)))
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_knob.visible = false
	move_zone.add_child(_joy_knob)

	var look_zone := Control.new()
	look_zone.anchor_left = 0.42
	look_zone.anchor_right = 1.0
	look_zone.anchor_bottom = 1.0
	look_zone.offset_bottom = -128
	look_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	look_zone.gui_input.connect(_on_look_zone_input)
	add_child(look_zone)


func _make_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	var normal := _circle_style(Color(0, 0, 0, 0.38), Color(1, 1, 1, 0.55))
	var pressed := _circle_style(Color(1, 1, 1, 0.32), Color(1, 1, 1, 0.85))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _place_bottom_right(button: Button, left: float, top: float, right: float, bottom: float) -> void:
	button.anchor_left = 1.0
	button.anchor_top = 1.0
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = left
	button.offset_top = top
	button.offset_right = right
	button.offset_bottom = bottom
	add_child(button)


func _build_buttons() -> void:
	var jump_btn := _make_button("JUMP", 19)
	_place_bottom_right(jump_btn, -120, -248, -24, -152)
	jump_btn.button_down.connect(_on_jump_down)
	jump_btn.button_up.connect(_on_jump_up)

	var mine_btn := _make_button("MINE", 16)
	_place_bottom_right(mine_btn, -216, -240, -136, -160)
	mine_btn.button_down.connect(_on_mine_down)
	mine_btn.button_up.connect(func() -> void: Input.action_release("mine"))

	var place_btn := _make_button("PLACE", 15)
	_place_bottom_right(place_btn, -216, -336, -136, -256)
	place_btn.button_down.connect(_on_place_down)
	place_btn.button_up.connect(func() -> void: Input.action_release("place"))

	_down_btn = _make_button("DOWN", 13)
	_place_bottom_right(_down_btn, -304, -236, -232, -164)
	_down_btn.button_down.connect(func() -> void: Input.action_press("fly_down"))
	_down_btn.button_up.connect(func() -> void: Input.action_release("fly_down"))
	_down_btn.visible = false

	var fly_btn := _make_button("FLY", 13)
	_place_bottom_right(fly_btn, -88, -420, -28, -360)
	fly_btn.pressed.connect(func() -> void:
		if _player != null:
			_player.toggle_fly())

	var lamp_btn := _make_button("LAMP", 13)
	_place_bottom_right(lamp_btn, -156, -420, -96, -360)
	lamp_btn.pressed.connect(func() -> void:
		if _player != null:
			_player.set_flashlight(not _player.flashlight_on))

	var run_btn := _make_button("RUN", 13)
	_place_bottom_right(run_btn, -224, -420, -164, -360)
	run_btn.toggle_mode = true
	run_btn.toggled.connect(func(on: bool) -> void:
		if on:
			Input.action_press("sprint")
		else:
			Input.action_release("sprint"))

	var pause_btn := _make_button("II", 16)
	pause_btn.anchor_left = 1.0
	pause_btn.anchor_right = 1.0
	pause_btn.offset_left = -72
	pause_btn.offset_top = 14
	pause_btn.offset_right = -16
	pause_btn.offset_bottom = 70
	add_child(pause_btn)
	pause_btn.pressed.connect(func() -> void:
		if _player != null:
			_player.pause_requested.emit())


# --- Input handling ---

func _on_move_zone_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _joy_id == -1:
			_joy_id = event.index
			_joy_origin = event.position
			_joy_base.position = _joy_origin - Vector2(95, 95)
			_joy_base.visible = true
			_joy_knob.visible = true
			_update_joystick(event.position)
		elif not event.pressed and event.index == _joy_id:
			_joy_id = -1
			if _player != null:
				_player.touch_move = Vector2.ZERO
			_joy_base.visible = false
			_joy_knob.visible = false
	elif event is InputEventScreenDrag and event.index == _joy_id:
		_update_joystick(event.position)


func _update_joystick(pos: Vector2) -> void:
	var offset := pos - _joy_origin
	if offset.length() > JOY_RADIUS:
		offset = offset.normalized() * JOY_RADIUS
	_joy_knob.position = _joy_origin + offset - Vector2(40, 40)
	if _player != null:
		_player.touch_move = offset / JOY_RADIUS


func _on_look_zone_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag and _player != null:
		_player.touch_look(event.relative)


func _on_jump_down() -> void:
	_jump_fly = _player != null and _player.flying
	Input.action_press("fly_up" if _jump_fly else "jump")


func _on_jump_up() -> void:
	Input.action_release("fly_up")
	Input.action_release("jump")


func _on_mine_down() -> void:
	if _player != null:
		_player.touch_action(true)
	Input.action_press("mine")


func _on_place_down() -> void:
	if _player != null:
		_player.touch_action(false)
	Input.action_press("place")
