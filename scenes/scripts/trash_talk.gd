extends Node2D
## Trash-talk screen: shows the two matchup dialog boxes over the bar background.
## The monologue appears immediately at the top; the answer drops in at the
## bottom after a few seconds. Emits `intro_finished` once both are shown.

signal intro_finished

const SW := 1280
const SH := 720
const DIALOG_W := 600.0
const DIALOG_H := 300.0
const MONOLOGUE_TIME := 2.5   # seconds before the answer appears

const BAR_BG: Texture2D = preload("res://scenes/scripts/bar_background.png")
const DIALOG_DIR := "res://assets/dialogs/"
const FIGHT_SCENE := "res://scenes/WhiteWorldTest.tscn"

# Fighter key (as chosen in starter_2) -> dialog-file token spelling.
const KEY_TOKEN := {
	"english": "english",
	"scottish": "scotish",
	"scotish": "scotish",
	"georgian": "georgian",
}

# Per-matchup speaking order. Key is the two tokens sorted and joined with "|".
# Value is [first_speaker_file, second_speaker_file] (no extension).
const MATCHUP_DIALOGS := {
	"english|scotish": ["scotish_to_english", "english_to_scotish"],
	"english|georgian": ["english_to_georgian", "georgian_to_english"],
	"georgian|scotish": ["scotish_to_georgian", "georgian_to_scotish"],
}

# Voice clip played when a given dialog image appears; the scene then holds for
# the clip's length so the line can finish before the fight starts.
const DIALOG_SFX := {
	"georgian_to_scotish": preload("res://sounds/Shit Talk/jotia vs scot.wav"),
	"georgian_to_english": preload("res://sounds/Shit Talk/jotia vs eng.wav"),
}
const ANSWER_TAIL := 1.0   # hold after the answer when there's no clip

var _monologue: TextureRect
var _answer: TextureRect
var _answer_token := ""
var _sfx: AudioStreamPlayer


func _ready() -> void:
	_build_scene()
	_reveal()


func _build_scene() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Same bar background as the bar scene, so the colours carry over.
	var bg := TextureRect.new()
	bg.texture = BAR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.28)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)

	var files := _matchup_dialog_files()

	# First line (monologue) up top, the answer down at the bottom.
	_monologue = _make_dialog(layer, files[0] if files.size() > 0 else "")
	_monologue.position = Vector2(110, 70)

	_answer_token = files[1] if files.size() > 1 else ""
	_answer = _make_dialog(layer, _answer_token)
	_answer.position = Vector2(SW - DIALOG_W - 110, SH - DIALOG_H - 70)

	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)


func _matchup_dialog_files() -> Array:
	var a: String = KEY_TOKEN.get(MatchSetup.p1_choice, "")
	var b: String = KEY_TOKEN.get(MatchSetup.p2_choice, "")
	if a == "" or b == "":
		return []  # e.g. a "random" pick — no fixed matchup dialog
	var pair := [a, b]
	pair.sort()
	var key := "%s|%s" % [pair[0], pair[1]]
	if MATCHUP_DIALOGS.has(key):
		return MATCHUP_DIALOGS[key]
	# Fallback until the order is specified: alphabetical speaks first.
	return ["%s_to_%s" % [pair[0], pair[1]], "%s_to_%s" % [pair[1], pair[0]]]


func _make_dialog(parent: Node, file_token: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.size = Vector2(DIALOG_W, DIALOG_H)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if file_token != "":
		rect.texture = load(DIALOG_DIR + file_token + ".png")
	rect.visible = rect.texture != null
	parent.add_child(rect)
	return rect


func _reveal() -> void:
	# Monologue is on screen from the start; the answer appears after a beat.
	_monologue.modulate.a = 1.0
	_answer.modulate.a = 0.0
	# If the answer has a voice clip, hold the scene for its full length.
	var clip: AudioStream = DIALOG_SFX.get(_answer_token, null)
	var tail: float = clip.get_length() if clip != null else ANSWER_TAIL
	var tween := create_tween()
	tween.tween_interval(MONOLOGUE_TIME)
	tween.tween_property(_answer, "modulate:a", 1.0, 0.4)
	tween.tween_callback(_play_answer_clip)
	tween.tween_interval(tail)
	tween.tween_callback(_go_to_fight)


func _play_answer_clip() -> void:
	var clip: AudioStream = DIALOG_SFX.get(_answer_token, null)
	if clip != null:
		_sfx.stream = clip
		_sfx.play()


# Host drives the hand-off into the fight so both players leave together; the
# client waits for the RPC. (MatchSetup + the live ENet peer carry over.)
func _go_to_fight() -> void:
	intro_finished.emit()
	if not multiplayer.has_multiplayer_peer():
		get_tree().change_scene_to_file(FIGHT_SCENE)
		return
	if multiplayer.is_server():
		_rpc_start_fight.rpc()
		get_tree().change_scene_to_file(FIGHT_SCENE)


@rpc("authority", "call_remote", "reliable")
func _rpc_start_fight() -> void:
	get_tree().change_scene_to_file(FIGHT_SCENE)
