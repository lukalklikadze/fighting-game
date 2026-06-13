extends Node2D
## Camera / superpower test arena.
##   You  = Scotsman (left)  — A/D move, J hand kick, K leg kick, L SUPERPOWER.
##   Dummy = Englishman bot (right) — approaches & pokes, and occasionally fires
##           its own super so you can see an enemy super land.
## Fighting-game camera: follows the midpoint, zooms out as you separate, and
## clamps to the stage walls so it pans to the edge instead of stopping dead.
## Esc quits. A KO resets both so you can keep testing.

const P1_START := Vector2(-300, 232)
const P2_START := Vector2(300, 232)

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

var _resetting := false
var _dummy_super_timer := 3.5


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	RenderingServer.set_default_clear_color(Color.WHITE)
	p1.opponent_path = p1.get_path_to(p2)
	p2.opponent_path = p2.get_path_to(p1)
	p1.set_meta("character_id", "scotish")
	p2.set_meta("character_id", "english")
	p1.accept_local_input = true
	p1.bot_enabled = false
	p2.accept_local_input = false
	p2.bot_enabled = true
	p1.died.connect(_on_died)
	p2.died.connect(_on_died)
	_reset()


func _reset() -> void:
	p1.reset_fighter(P1_START, true)
	p2.reset_fighter(P2_START, true)
	_resetting = false


func _on_died(_pid: int) -> void:
	if _resetting:
		return
	_resetting = true
	await get_tree().create_timer(1.4).timeout
	_reset()


func _process(delta: float) -> void:
	_update_camera()
	_dummy_super_timer -= delta
	if _dummy_super_timer <= 0.0:
		_dummy_super_timer = randf_range(3.5, 5.5)
		if p2.is_special_ready():
			p2._try_start_special()
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()


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
