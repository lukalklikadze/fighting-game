class_name MatchState
extends RefCounted
## Selection carried between scenes (starter_2 → bar → TrashTalk → fight).
## Static so it survives scene changes for the lifetime of the process.

static var player_icon: Texture2D = null
static var opponent_icon: Texture2D = null
static var player_key := ""
static var opponent_key := ""
