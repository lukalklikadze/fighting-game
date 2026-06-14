extends Node2D
## Move / animation test bench for the hand-drawn fighters.
##
## You control the left fighter against a stationary dummy so you can see every
## move and animation. Switch your character on the fly to test all three.
##
##   A / D  move        W  jump          J  hand kick (light)
##   K  leg kick        L  hard hit       O O  super (special)
##   I  block      (Mortal-Kombat feel: one committed move at a time, no combos)
##   1 / 2 / 3  English / Georgian / Scotsman      Q  cycle character
##   R  reset positions                            Esc  quit

const P1_START := Vector2(-150, 232)
const P2_START := Vector2(170, 232)
const CHARS := ["english", "georgian", "scotish"]
const CHAR_NAMES := {"english": "ENGLISHMAN", "georgian": "GEORGIAN", "scotish": "SCOTSMAN"}

const CAM_VIEW_W := 1280.0
const CAM_STAGE_HALF := 950.0
const CAM_MARGIN := 380.0
const CAM_MIN_ZOOM := 0.58
const CAM_MAX_ZOOM := 0.95
const CAM_LERP := 0.14
const CAM_Y := 10.0

@onready var p1: FightingPlayer = $Players/PlayerOne
@onready var p2: FightingPlayer = $Players/PlayerTwo
@onready var camera: Camera2D = $Camera2D

var _p1_index := 0
var _resetting := false
var _char_label: Label


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	RenderingServer.set_default_clear_color(Color.WHITE)
	p1.opponent_path = p1.get_path_to(p2)
	p2.opponent_path = p2.get_path_to(p1)
	p1.accept_local_input = true
	p1.bot_enabled = false
	# A stationary training dummy: no input, no AI -- it just stands and takes hits.
	p2.accept_local_input = false
	p2.bot_enabled = false
	_apply_character(p2, "english")
	p1.died.connect(_on_died)
	p2.died.connect(_on_died)
	_build_hud()
	_set_p1_character(0)


func _apply_character(player: FightingPlayer, key: String) -> void:
	player.set_meta("character_id", key)
	player.call("set_character", key)
	player.call("_resolve_special_ability")


func _set_p1_character(index: int) -> void:
	_p1_index = (index % CHARS.size() + CHARS.size()) % CHARS.size()
	var key: String = CHARS[_p1_index]
	_apply_character(p1, key)
	if _char_label != null:
		_char_label.text = "YOU: %s    [ 1 English   2 Georgian   3 Scotsman   Q cycle ]" % CHAR_NAMES[key]
	_reset()


func _reset() -> void:
	p1.reset_fighter(P1_START, true)
	p2.reset_fighter(P2_START, true)
	_resetting = false


func _on_died(_pid: int) -> void:
	# Pop both back up so practice never stops.
	if _resetting:
		return
	_resetting = true
	# Hold the death pose for a beat, then pop both back to their start positions.
	await get_tree().create_timer(1.5).timeout
	_reset()


func _process(delta: float) -> void:
	_update_camera()
	# Test bench: keep the special always ready (no cooldown) so you can spam it.
	p1.reset_special_cooldown()
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			_set_p1_character(0)
		KEY_2:
			_set_p1_character(1)
		KEY_3:
			_set_p1_character(2)
		KEY_Q:
			_set_p1_character(_p1_index + 1)
		KEY_R:
			_reset()


func _update_camera() -> void:
	var p1x := p1.global_position.x
	var p2x := p2.global_position.x
	var sep := absf(p2x - p1x)
	var target_zoom := clampf(CAM_VIEW_W / (sep + CAM_MARGIN), CAM_MIN_ZOOM, CAM_MAX_ZOOM)
	var z := lerpf(camera.zoom.x, target_zoom, CAM_LERP)
	camera.zoom = Vector2(z, z)
	var half_view := (CAM_VIEW_W / z) * 0.5
	var center_x := (p1x + p2x) * 0.5
	var min_x := -CAM_STAGE_HALF + half_view
	var max_x := CAM_STAGE_HALF - half_view
	var target_x := clampf(center_x, min_x, max_x) if min_x <= max_x else 0.0
	camera.global_position = Vector2(lerpf(camera.global_position.x, target_x, CAM_LERP), CAM_Y)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_char_label = _make_label(24, Color(0.05, 0.05, 0.05, 1.0))
	_char_label.position = Vector2(40, 28)
	_char_label.size = Vector2(1200, 32)
	layer.add_child(_char_label)

	var controls := _make_label(20, Color(0.12, 0.12, 0.12, 1.0))
	controls.position = Vector2(40, 70)
	controls.size = Vector2(1400, 30)
	controls.text = "A/D move    W jump    J hand kick    K leg kick    L hard hit    O O super    I block    R reset    Esc quit"
	layer.add_child(controls)

	var combos := _make_label(20, Color(0.55, 0.12, 0.10, 1.0))
	combos.position = Vector2(40, 100)
	combos.size = Vector2(1400, 30)
	combos.text = "Mortal-Kombat style: one move at a time (no combos). Brief invulnerability after each hit. ~10fps snappy poses."
	layer.add_child(combos)


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	return label
