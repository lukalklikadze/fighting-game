extends Node2D
## Minimal animation test world: the Englishman (you, left) vs the default
## placeholder fighter (bot, right). Pure movement/animation check — walk with
## A/D (backward walk plays the walk animation reversed), hand kick = J,
## leg kick = K. No jump (people have no jump animation yet). ESC quits.
## When either fighter is KO'd, both reset so you can keep testing.

const P1_START := Vector2(-220, 232)
const P2_START := Vector2(220, 232)

@onready var p1: Node2D = $Players/PlayerOne
@onready var p2: Node2D = $Players/PlayerTwo
@onready var camera: Camera2D = $Camera2D

var _resetting := false


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	RenderingServer.set_default_clear_color(Color.WHITE)
	p1.set("opponent_path", p1.get_path_to(p2))
	p2.set("opponent_path", p2.get_path_to(p1))
	p1.connect("died", _on_died)
	p2.connect("died", _on_died)
	_reset()


func _reset() -> void:
	p1.call("reset_fighter", P1_START, true)
	p2.call("reset_fighter", P2_START, true)
	_resetting = false


func _on_died(_pid: int) -> void:
	if _resetting:
		return
	_resetting = true
	await get_tree().create_timer(1.2).timeout
	_reset()


func _process(_delta: float) -> void:
	camera.global_position = Vector2((p1.global_position.x + p2.global_position.x) * 0.5, 10.0)
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
