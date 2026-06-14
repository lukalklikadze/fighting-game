extends Node
## Solo preview of the REAL fight. Picks two random fighters, fills MatchSetup
## exactly as the character-select would, then loads the actual Fight scene
## offline (Player 1 = you, Player 2 = a bot). What you see is precisely the real
## match: same arena/background, 3 health bars, super meter, minigames, specials,
## MK combat, block + death. Nothing here is a mock-up — it IS scenes/final/Fight.tscn.

const FIGHT_SCENE := "res://scenes/final/Fight.tscn"
const FIGHTERS := ["english", "georgian", "scottish"]


func _ready() -> void:
	randomize()
	# Offline solo preview: drop any editor/MCP multiplayer peer so the fight
	# controller takes its local path (Player 2 = bot) instead of waiting for a
	# remote client. (The real networked game sets up its own peer in Select.)
	multiplayer.multiplayer_peer = null
	var pool := FIGHTERS.duplicate()
	pool.shuffle()
	MatchSetup.active = true
	MatchSetup.p1_choice = pool[0]
	MatchSetup.p2_choice = pool[1]
	MatchSetup.client_peer_id = 0
	# Deferred: can't change scene while the tree is mid-add of this node.
	get_tree().change_scene_to_file.call_deferred(FIGHT_SCENE)
