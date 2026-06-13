extends Node
## Tiny autoload that carries the lobby result (who picked what + the peer id)
## from the starter_2 select scene into the fight scene. The ENet peer itself
## persists across change_scene_to_file; this just carries the choices.

var active := false
var p1_choice := "english"   # host's ball key  (english/georgian/scottish/random)
var p2_choice := "georgian"  # client's ball key
var client_peer_id := 0


func clear() -> void:
	active = false
