extends CanvasLayer
## Touch controls for tablets (Fire OS / Android), built in code like
## the HUD. The layout mirrors Minecraft Bedrock's "Joystick & tap to
## interact" mode (Fire build issue #3):
##
## - One thumb: a virtual joystick that appears where the thumb lands
##   and steers with full analog strength. Pushing it fully forward to
##   its rim sprints.
## - The other side: gestures — drag to look, tap to place a block at
##   the tap point, hold to mine the block under the finger (the mining
##   target follows the finger while held).
## - Buttons on the look side: JUMP (doubles as fly-up while flying; a
##   DOWN button appears next to it in fly mode), FLY and LAMP
##   (flashlight) above it, and II at the top corner to pause.
## - A Settings toggle (issue #6) mirrors the whole layout for
##   left-handed players.
## - The hotbar stays tappable for block selection (see hud.gd).
##
## The layer activates automatically on Android; on any other platform
## it activates on the first touch input, so desktop play with keyboard,
## mouse, or gamepad is completely unaffected.

const JOY_RADIUS := 62.0
const TAP_MAX_MS := 300
const TAP_MAX_MOVE := 18.0
const HOLD_MS := 320
const MINE_INTERVAL := 0.30

var _player = null
var _hud = null
var _active := false
var _was_paused := false
var _left_handed := false

var _joy_base: Panel
var _joy_knob: Panel
var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _look_zone: Control

var _down_btn: Button

# Gesture state for the look zone.
var _look_id := -1
var _press_pos := Vector2.ZERO
var _press_msec := 0
var _press_dragging := false
var _mining := false
var _mine_pos := Vector2.ZERO
var _mine_timer := 0.0


func _ready() -> void:
	layer = 2
	# Keep _process running while the tree is paused so the layer can
	# hide itself under the pause menu and release held actions.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_left_handed = Game.left_handed()
	Game.settings_changed.connect(_on_settings_changed)
	_build_all()


func setup(player, hud) -> void:
	_player = player
	_hud = hud
	# Rebuild now that the HUD is known (its scaled height sets how
	# much of the bottom the zones must keep clear).
	_build_all()
	if OS.has_feature("android"):
		_activate()


func _on_settings_changed() -> void:
	# Settings only change from the title or pause menus, never
	# mid-gesture; rebuilding there keeps handedness and the hotbar
	# clearance live.
	if _active and not get_tree().paused:
		return
	_left_handed = Game.left_handed()
	_build_all()
	if _active and _hud != null and _hud.has_method("set_touch_hint"):
		_hud.set_touch_hint()


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


func _process(delta: float) -> void:
	if not _active:
		return
	var paused_now := get_tree().paused
	if paused_now and not _was_paused:
		_release_all()
	_was_paused = paused_now
	visible = not paused_now
	if _down_btn != null:
		_down_btn.visible = _player != null and _player.flying
	if paused_now:
		return
	# Hold-to-mine: a press that stays put past the threshold becomes
	# mining; a drag that starts moving first becomes look instead.
	if _look_id != -1 and not _mining and not _press_dragging \
			and Time.get_ticks_msec() - _press_msec >= HOLD_MS:
		_mining = true
		_mine_pos = _to_viewport(_press_pos)
		_mine_timer = MINE_INTERVAL
		if _player != null:
			_player.touch_action_at(true, _mine_pos)
	if _mining and _player != null:
		_mine_timer -= delta
		if _mine_timer <= 0.0:
			_player.touch_action_at(true, _mine_pos)
			_mine_timer = MINE_INTERVAL


func _release_all() -> void:
	for action in ["mine", "place", "jump", "sprint", "fly_up", "fly_down"]:
		Input.action_release(action)
	if _player != null:
		_player.touch_move = Vector2.ZERO
	_joy_id = -1
	_look_id = -1
	_mining = false
	_press_dragging = false
	if _joy_base != null:
		_joy_base.visible = false
	if _joy_knob != null:
		_joy_knob.visible = false


# --- Construction ---

func _build_all() -> void:
	for child in get_children():
		child.queue_free()
	_down_btn = null
	_build_zones()
	_build_buttons()


func _circle_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(200)
	return style


func _build_zones() -> void:
	var clearance := 128.0
	if _hud != null and _hud.has_method("bottom_clearance"):
		clearance = _hud.bottom_clearance()

	var move_zone := Control.new()
	if _left_handed:
		move_zone.anchor_left = 0.58
		move_zone.anchor_right = 1.0
	else:
		move_zone.anchor_left = 0.0
		move_zone.anchor_right = 0.42
	move_zone.anchor_top = 0.30
	move_zone.anchor_bottom = 1.0
	move_zone.offset_bottom = -clearance # keep the hotbar strip tappable
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
	if _left_handed:
		look_zone.anchor_left = 0.0
		look_zone.anchor_right = 0.58
	else:
		look_zone.anchor_left = 0.42
		look_zone.anchor_right = 1.0
	look_zone.anchor_bottom = 1.0
	look_zone.offset_bottom = -clearance
	look_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	look_zone.gui_input.connect(_on_look_zone_input)
	add_child(look_zone)
	_look_zone = look_zone


## gui_input delivers positions in the zone's LOCAL coordinates; the
## player's screen-point actions need viewport coordinates.
func _to_viewport(local_pos: Vector2) -> Vector2:
	if _look_zone == null:
		return local_pos
	return _look_zone.get_global_transform() * local_pos


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


## Place a button by its distance from the look-side bottom corner, so
## the cluster mirrors with the handedness setting.
func _place_corner(button: Button, from_side: float, from_bottom: float,
		width: float, height: float) -> void:
	if _left_handed:
		button.anchor_left = 0.0
		button.anchor_right = 0.0
		button.offset_left = from_side
		button.offset_right = from_side + width
	else:
		button.anchor_left = 1.0
		button.anchor_right = 1.0
		button.offset_left = -(from_side + width)
		button.offset_right = -from_side
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_top = -(from_bottom + height)
	button.offset_bottom = -from_bottom
	add_child(button)


func _build_buttons() -> void:
	var jump_btn := _make_button("JUMP", 19)
	_place_corner(jump_btn, 24, 152, 96, 96)
	jump_btn.button_down.connect(_on_jump_down)
	jump_btn.button_up.connect(_on_jump_up)

	_down_btn = _make_button("DOWN", 13)
	_place_corner(_down_btn, 232, 164, 72, 72)
	_down_btn.button_down.connect(func() -> void: Input.action_press("fly_down"))
	_down_btn.button_up.connect(func() -> void: Input.action_release("fly_down"))
	_down_btn.visible = false

	var fly_btn := _make_button("FLY", 13)
	_place_corner(fly_btn, 28, 360, 60, 60)
	fly_btn.pressed.connect(func() -> void:
		if _player != null:
			_player.toggle_fly())

	var lamp_btn := _make_button("LAMP", 13)
	_place_corner(lamp_btn, 96, 360, 60, 60)
	lamp_btn.pressed.connect(func() -> void:
		if _player != null:
			_player.set_flashlight(not _player.flashlight_on))

	var pause_btn := _make_button("II", 16)
	if _left_handed:
		pause_btn.anchor_left = 0.0
		pause_btn.anchor_right = 0.0
		pause_btn.offset_left = 16
		pause_btn.offset_right = 72
	else:
		pause_btn.anchor_left = 1.0
		pause_btn.anchor_right = 1.0
		pause_btn.offset_left = -72
		pause_btn.offset_right = -16
	pause_btn.offset_top = 14
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


## Look-zone gestures (issue #3): a quick, still tap places a block at
## the tap point; holding still starts mining the block under the
## finger, and the target follows the finger while held; moving early
## makes it a look-drag instead. Only the first finger is tracked —
## extra fingers are ignored.
func _on_look_zone_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _look_id == -1:
				_look_id = event.index
				_press_pos = event.position
				_press_msec = Time.get_ticks_msec()
				_press_dragging = false
				_mining = false
		elif event.index == _look_id:
			if _mining:
				_mining = false
			elif not _press_dragging \
					and Time.get_ticks_msec() - _press_msec <= TAP_MAX_MS:
				if _player != null:
					_player.touch_action_at(false, _to_viewport(event.position))
			_look_id = -1
	elif event is InputEventScreenDrag and event.index == _look_id:
		if _mining:
			_mine_pos = _to_viewport(event.position)
		elif _press_dragging:
			if _player != null:
				_player.touch_look(event.relative)
		elif event.position.distance_to(_press_pos) > TAP_MAX_MOVE:
			_press_dragging = true
			if _player != null:
				_player.touch_look(event.relative)


func _on_jump_down() -> void:
	Input.action_press("fly_up" if _player != null and _player.flying else "jump")


func _on_jump_up() -> void:
	Input.action_release("fly_up")
	Input.action_release("jump")
