extends Node2D
## Bar cutscene: hold the wide shot of the whole bar for a few seconds, then
## smoothly zoom in to the two figures, then a lightning/thunder transition into
## the TrashTalk scene. Frame the close-up by moving/zooming the Camera2D in the
## editor — wherever you park it is the shot we zoom into.

const WIDE_POS := Vector2(640, 360)   # full 1280x720 bar view
const WIDE_ZOOM := Vector2(1, 1)
const HOLD_TIME := 1.5                # seconds on the wide shot
const ZOOM_TIME := 1.4                # seconds for the zoom-in
const SHAKE_AMPLITUDE := 7.0          # camera shake during the thunder
const NEXT_SCENE := "res://scenes/TrashTalk.tscn"
const THUNDER_SFX: AudioStream = preload("res://sounds/thunder.mp3")

@onready var _camera: Camera2D = $Camera2D

var _flash: ColorRect
var _shake := 0.0
var _shake_total := 0.0
var _thunder: AudioStreamPlayer


func _ready() -> void:
	randomize()
	BarAmbience.start()   # bar ambience, looped for the rest of the game
	_thunder = AudioStreamPlayer.new()
	_thunder.stream = THUNDER_SFX
	add_child(_thunder)
	_build_flash_overlay()
	# The camera's authored transform IS the close-up target.
	var target_pos := _camera.position
	var target_zoom := _camera.zoom
	# Start on the wide shot.
	_camera.position = WIDE_POS
	_camera.zoom = WIDE_ZOOM
	_camera.make_current()
	# Hold, ease into the close-up, then crack the thunder.
	var tween := create_tween()
	tween.tween_interval(HOLD_TIME)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "position", target_pos, ZOOM_TIME)
	tween.parallel().tween_property(_camera, "zoom", target_zoom, ZOOM_TIME)
	tween.tween_callback(_start_thunder)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake -= delta
		var strength := SHAKE_AMPLITUDE * maxf(_shake / _shake_total, 0.0)
		_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength
		if _shake <= 0.0:
			_camera.offset = Vector2.ZERO


func _build_flash_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)


func _start_thunder() -> void:
	_thunder.play()   # thunder crack as the lightning flashes begin
	var tween := create_tween()
	# A few lightning stabs with beats between them...
	tween.tween_property(_flash, "color:a", 0.9, 0.04)
	tween.tween_callback(func(): _kick_shake(0.18))
	tween.tween_property(_flash, "color:a", 0.0, 0.12)
	tween.tween_interval(0.22)
	tween.tween_property(_flash, "color:a", 0.65, 0.03)
	tween.tween_callback(func(): _kick_shake(0.30))
	tween.tween_property(_flash, "color:a", 0.05, 0.14)
	tween.tween_interval(0.26)
	tween.tween_property(_flash, "color:a", 0.85, 0.04)
	tween.tween_callback(func(): _kick_shake(0.34))
	tween.tween_property(_flash, "color:a", 0.08, 0.16)
	tween.tween_interval(0.24)
	# ...then the blinding strike that whites out into TrashTalk.
	tween.tween_property(_flash, "color:a", 1.0, 0.32)
	tween.tween_interval(0.12)
	tween.tween_callback(func(): get_tree().change_scene_to_file(NEXT_SCENE))


func _kick_shake(duration: float) -> void:
	_shake = duration
	_shake_total = duration
