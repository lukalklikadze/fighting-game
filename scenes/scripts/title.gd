extends Node2D
## Title splash shown at game launch, before the online start screen (starter_2).
##
## Displays the game name art fullscreen. Press any key (or click) to continue
## to the lobby. Networking is NOT touched here -- the real session starts in
## starter_2.

const NEXT_SCENE := "res://starter_2.tscn"

var _advancing := false


func _ready() -> void:
	# Match the rest of the game: fullscreen 16:9 with the seats' navy clear color
	# so any letterbox sliver blends into the art.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	RenderingServer.set_default_clear_color(Color(0.05, 0.10, 0.25, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	var pressed_key: bool = event is InputEventKey and event.pressed and not event.echo
	var pressed_click: bool = event is InputEventMouseButton and event.pressed
	if pressed_key or pressed_click:
		_advance()


func _advance() -> void:
	if _advancing:
		return
	_advancing = true
	get_tree().change_scene_to_file(NEXT_SCENE)
