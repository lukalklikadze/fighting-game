extends Node2D
## Bot-fight TEST scene for the super-attack minigame mechanic.
##
## You (PlayerOne, blue) fight a bot (PlayerTwo, red). A super meter fills from
## time + combat; when YOUR meter fills it auto-launches a minigame "super":
##   bar 1 -> Typeracer, bar 2 -> Beer, bar 3 -> Juggling (the attacker's bar).
## Win the minigame -> opponent takes BIG damage; lose -> SMALL damage.
## Each fighter has 3 health bars (lives); losing your current bar resurrects
## you at the start position with the next bar. Lose all 3 -> match over.
##
## This scene is single-process (no networking). Only the human triggers supers
## here; the bot's meter is intentionally inert. The damage mapping is written
## generally so it ports to real 2-player later.

const PLAYER_ONE_START := Vector2(-260, 232)
const PLAYER_TWO_START := Vector2(260, 232)
const MENU_FONT: FontFile = preload("res://assets/fonts/NotoSansGeorgian-Black.ttf")

const TOTAL_BARS := 3
const TOTAL_SUPERS := 3   # supers per player per match: 1st=Typeracer, 2nd=Beer, 3rd=Juggling
# Super damage as a fraction of the victim's full health bar: the super starter
# winning the minigame lands 30%; if the defender wins instead it's 15%.
const BIG_SUPER_FRACTION := 0.30    # starter (damager) won the minigame
const SMALL_SUPER_FRACTION := 0.15  # defender won the minigame
const KO_FREEZE_TIME := 1.4      # seconds the death animation plays before resurrect
const FADE_TIME := 0.35

const P1_COLOR := Color(0.22, 0.52, 1.0, 1.0)
const P2_COLOR := Color(1.0, 0.26, 0.20, 1.0)
const SUPER_COLOR := Color(1.0, 0.82, 0.26, 1.0)

# Keyed by the player's super number (not their health bar): 1st / 2nd / 3rd.
const MINIGAME_PATHS := {
	1: "res://minigames/typeracer/scenes/Typeracer.tscn",
	2: "res://minigames/beer/scenes/Beer.tscn",
	3: "res://minigames/juggling/scenes/Juggling.tscn",
}
const MINIGAME_NAMES := {1: "TYPERACER", 2: "BEER POUR", 3: "JUGGLING"}

enum MatchState { FIGHT, SUPER, KO, OVER }

@onready var player_one: Node2D = $Players/PlayerOne
@onready var player_two: Node2D = $Players/PlayerTwo
@onready var camera: Camera2D = $Camera2D
@onready var players_root: Node2D = $Players

var _state := MatchState.FIGHT
var _bar := {1: 1, 2: 1}          # current bar (1..TOTAL_BARS) per player — lives only
var _supers_used := {1: 0, 2: 0}  # how many supers each player has fired (picks the minigame)
var _last_super_opp_bar := {1: 0, 2: 0}  # opponent's bar when this player last fired a super

var _hud_layer: CanvasLayer
var _minigame_layer: CanvasLayer
var _overlay_layer: CanvasLayer
var _black: ColorRect
var _banner: Label
var _hint: Label
var _minigame: Node

var _health_bar := {1: null, 2: null}
var _super_bar := {1: null, 2: null}
var _pips := {1: [], 2: []}


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	RenderingServer.set_default_clear_color(Color.WHITE)
	_build_hud()
	_configure_players()
	_connect_signals()
	_start_fresh_match()


func _process(_delta: float) -> void:
	if _state == MatchState.FIGHT or _state == MatchState.KO or _state == MatchState.SUPER:
		var midpoint: Vector2 = (player_one.global_position + player_two.global_position) * 0.5
		camera.global_position = Vector2(midpoint.x, 10.0)
	if _state == MatchState.OVER and Input.is_action_just_pressed("ui_accept"):
		_start_fresh_match()


# ===========================================================================
#  Setup
# ===========================================================================

func _configure_players() -> void:
	player_one.set("opponent_path", player_one.get_path_to(player_two))
	player_two.set("opponent_path", player_two.get_path_to(player_one))
	player_one.set("player_id", 1)
	player_two.set("player_id", 2)


func _connect_signals() -> void:
	player_one.connect("health_changed", _on_health_changed.bind(1))
	player_two.connect("health_changed", _on_health_changed.bind(2))
	player_one.connect("super_meter_changed", _on_super_changed.bind(1))
	player_two.connect("super_meter_changed", _on_super_changed.bind(2))
	player_one.connect("died", _on_fighter_died)
	player_two.connect("died", _on_fighter_died)
	player_one.connect("super_full", _on_super_full)
	player_two.connect("super_full", _on_super_full)


func _fighter(pid: int) -> Node2D:
	return player_one if pid == 1 else player_two


func _other(pid: int) -> int:
	return 2 if pid == 1 else 1


# A player may build/fire a super only if (a) they have supers left, and (b) they
# haven't already spent one against the opponent's CURRENT health bar — so you
# must knock the opponent to their next bar before you can charge another super.
func _can_build_super(pid: int) -> bool:
	if int(_supers_used[pid]) >= TOTAL_SUPERS:
		return false
	return int(_bar[_other(pid)]) > int(_last_super_opp_bar[pid])


# ===========================================================================
#  Match / round flow
# ===========================================================================

func _start_fresh_match() -> void:
	_bar = {1: 1, 2: 1}
	_supers_used = {1: 0, 2: 0}
	_last_super_opp_bar = {1: 0, 2: 0}
	player_one.call("reset_super")
	player_two.call("reset_super")
	_banner.visible = false
	_hint.visible = false
	_black.color.a = 0.0
	_black.visible = false
	_reset_round()
	_state = MatchState.FIGHT
	_set_fight_running(true)
	_refresh_hud()


# Reposition + heal both fighters to start a (re)round. Super meters persist.
func _reset_round() -> void:
	player_one.call("reset_fighter", PLAYER_ONE_START, true)
	player_two.call("reset_fighter", PLAYER_TWO_START, true)
	_refresh_hud()


# Toggle live combat: human input, bot AI and the human's meter fill.
func _set_fight_running(running: bool) -> void:
	player_one.set("accept_local_input", running)
	player_one.set("bot_enabled", false)
	player_two.set("accept_local_input", false)
	player_two.set("bot_enabled", running)
	# Only the human builds meter, and only while a super is available to charge.
	player_one.set("super_fill_enabled", running and _can_build_super(1))
	player_two.set("super_fill_enabled", false)


func _on_fighter_died(pid: int) -> void:
	# Deaths during normal combat run the KO flow; super-induced deaths are
	# handled inline inside _run_super (which guards on state).
	if _state != MatchState.FIGHT:
		return
	_handle_ko(pid)


# Lose-a-bar transition: play the death anim, then resurrect or end the match.
func _handle_ko(dead_id: int) -> void:
	_state = MatchState.KO
	_set_fight_running(false)
	await get_tree().create_timer(KO_FREEZE_TIME).timeout
	if _bar[dead_id] < TOTAL_BARS:
		_bar[dead_id] += 1
		_reset_round()
		_state = MatchState.FIGHT
		_set_fight_running(true)
		_refresh_hud()
	else:
		_match_over(_other(dead_id))


func _match_over(winner_id: int) -> void:
	_state = MatchState.OVER
	_set_fight_running(false)
	_banner.text = "PLAYER %d WINS!" % winner_id
	_banner.add_theme_color_override("font_color", P1_COLOR if winner_id == 1 else P2_COLOR)
	_banner.visible = true
	_hint.text = "Press SPACE / ENTER for a rematch"
	_hint.visible = true
	_refresh_hud()


# ===========================================================================
#  Super attack -> minigame
# ===========================================================================

func _on_super_full(pid: int) -> void:
	# Only the human triggers supers in this test scene; bot meter is inert.
	# Each player gets TOTAL_SUPERS supers total (1st=Typeracer, 2nd=Beer, 3rd=Juggling),
	# and at most one per opponent health bar.
	if _state != MatchState.FIGHT or pid != 1 or not _can_build_super(pid):
		return
	_run_super(pid)


func _run_super(attacker_id: int) -> void:
	_state = MatchState.SUPER
	# Nth super -> Nth minigame, per player, regardless of health bar.
	var which := clampi(int(_supers_used[attacker_id]) + 1, 1, TOTAL_SUPERS)
	_supers_used[attacker_id] += 1
	_last_super_opp_bar[attacker_id] = int(_bar[_other(attacker_id)])  # one super per opp bar
	_set_fight_running(false)

	await _fade(1.0)                       # black out the arena
	_hud_layer.visible = false
	_start_minigame(which)                 # spin it up while the screen is black
	await _fade(0.0)                       # reveal the minigame
	var result: int = await _minigame.minigame_finished   # 1 win / 0 lose / -1 draw
	await _fade(1.0)                       # cover the minigame before tearing it down
	_clear_minigame()
	_hud_layer.visible = true

	# Starter-won decides damage magnitude; opponent always takes the hit.
	var human_is_attacker := attacker_id == 1
	var starter_won := (result == 1) if human_is_attacker else (result == 0)
	if result != -1:
		var victim_node := _fighter(_other(attacker_id))
		var frac := BIG_SUPER_FRACTION if starter_won else SMALL_SUPER_FRACTION
		var dmg := int(round(frac * float(victim_node.get("max_health"))))
		victim_node.call("apply_super_damage", dmg)
	_fighter(attacker_id).call("reset_super")
	_refresh_hud()

	# apply_super_damage emits `died` but _on_fighter_died ignores non-FIGHT
	# states, so resolve a super KO here, still under the black overlay.
	var victim := _fighter(_other(attacker_id))
	if int(victim.get("health")) <= 0:
		await _handle_ko(_other(attacker_id))

	await _fade(0.0)                       # reveal the arena / fresh round / banner
	if _state == MatchState.SUPER:
		_state = MatchState.FIGHT
		_set_fight_running(true)


func _start_minigame(which: int) -> void:
	var path: String = MINIGAME_PATHS[clampi(which, 1, TOTAL_SUPERS)]
	var packed: PackedScene = load(path)
	_minigame = packed.instantiate()
	_minigame.set("embedded", true)
	_minigame_layer.add_child(_minigame)
	_minigame.call("begin_solo")


func _clear_minigame() -> void:
	if _minigame != null and is_instance_valid(_minigame):
		_minigame.queue_free()
	_minigame = null


func _fade(to_alpha: float) -> void:
	_black.visible = true
	var tw := create_tween()
	tw.tween_property(_black, "color:a", to_alpha, FADE_TIME)
	await tw.finished
	if to_alpha <= 0.0:
		_black.visible = false


# ===========================================================================
#  HUD
# ===========================================================================

func _on_health_changed(_cur: int, _max: int, pid: int) -> void:
	_refresh_hud_player(pid)


func _on_super_changed(_cur: float, _max: float, pid: int) -> void:
	_refresh_hud_player(pid)


func _refresh_hud() -> void:
	_refresh_hud_player(1)
	_refresh_hud_player(2)


func _refresh_hud_player(pid: int) -> void:
	var f := _fighter(pid)
	var hb: ProgressBar = _health_bar[pid]
	if hb != null:
		hb.max_value = float(f.get("max_health"))
		hb.value = float(f.get("health"))
	var sb: ProgressBar = _super_bar[pid]
	if sb != null:
		sb.max_value = float(f.get("super_max"))
		sb.value = float(f.get("super_meter"))
	var lit := clampi(TOTAL_BARS - (int(_bar[pid]) - 1), 0, TOTAL_BARS)
	for i in range(_pips[pid].size()):
		var pip: ColorRect = _pips[pid][i]
		pip.color = (P1_COLOR if pid == 1 else P2_COLOR) if i < lit else Color(0.18, 0.18, 0.18, 1.0)


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 40
	add_child(_hud_layer)

	_minigame_layer = CanvasLayer.new()
	_minigame_layer.layer = 50
	add_child(_minigame_layer)

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 60
	add_child(_overlay_layer)

	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0, 0, 0, 0)
	_black.visible = false
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_black)

	# Top status row: P1 stack | VS | P2 stack.
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_top = 0.0
	row.anchor_right = 1.0
	row.offset_left = 24.0
	row.offset_top = 14.0
	row.offset_right = -24.0
	row.add_theme_constant_override("separation", 20)
	_hud_layer.add_child(row)

	row.add_child(_build_player_hud(1))

	var vs := _make_label("VS", 24, Color.WHITE)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.custom_minimum_size = Vector2(60, 0)
	row.add_child(vs)

	row.add_child(_build_player_hud(2))

	# Centered banner + hint (match over).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)
	_banner = _make_label("", 84, Color.WHITE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.visible = false
	col.add_child(_banner)
	_hint = _make_label("", 24, Color(0.9, 0.9, 0.9, 1.0))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = false
	col.add_child(_hint)

	_build_quit_button()


func _build_player_hud(pid: int) -> Control:
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 4)

	# Life pips + label row (pips on the player's outer edge).
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	stack.add_child(top)
	var label := _make_label("P%d" % pid, 18, P1_COLOR if pid == 1 else P2_COLOR)
	if pid == 2:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer)
	for i in range(TOTAL_BARS):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(26, 12)
		top.add_child(pip)
		_pips[pid].append(pip)
	if pid == 1:
		var spacer2 := Control.new()
		spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer2)
	top.add_child(label)

	var hb := ProgressBar.new()
	hb.custom_minimum_size = Vector2(0, 26)
	hb.show_percentage = false
	hb.max_value = 100.0
	hb.value = 100.0
	hb.add_theme_stylebox_override("background", _bar_bg())
	hb.add_theme_stylebox_override("fill", _bar_fill(P1_COLOR if pid == 1 else P2_COLOR))
	if pid == 2:
		hb.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	_health_bar[pid] = hb
	stack.add_child(hb)

	var sb := ProgressBar.new()
	sb.custom_minimum_size = Vector2(0, 12)
	sb.show_percentage = false
	sb.max_value = 100.0
	sb.value = 0.0
	sb.add_theme_stylebox_override("background", _bar_bg())
	sb.add_theme_stylebox_override("fill", _bar_fill(SUPER_COLOR))
	if pid == 2:
		sb.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	_super_bar[pid] = sb
	stack.add_child(sb)

	return stack


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MENU_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _bar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.03, 0.03, 0.92)
	s.border_color = Color.BLACK
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	return s


func _bar_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	return s


func _build_quit_button() -> void:
	var quit := Button.new()
	quit.text = "QUIT"
	quit.focus_mode = Control.FOCUS_NONE
	quit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quit.offset_left = -120.0
	quit.offset_top = 60.0
	quit.offset_right = -18.0
	quit.offset_bottom = 100.0
	quit.add_theme_font_override("font", MENU_FONT)
	quit.add_theme_font_size_override("font_size", 18)
	quit.add_theme_color_override("font_color", Color(1.0, 0.92, 0.90, 1.0))
	quit.pressed.connect(func(): get_tree().quit())
	_hud_layer.add_child(quit)
