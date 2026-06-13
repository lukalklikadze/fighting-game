extends Node2D

## Solo practice arena — fight a bot with no network peer so everything runs
## locally on one machine. Pick a fighter, then test movement, attacks and the
## special move without a second player.
##
## Controls (in the fight):
##   A / D move · W jump · S crouch · J/K/L light/medium/heavy · I guard
##   SPECIAL  = triple-tap L
##   1 / 2 / 3  switch YOUR fighter      B  cycle the BOT's fighter
##   C  instantly recharge your special  R  restart the round
##   TAB  back to the fighter-select screen

const PLAYER_ONE_START := Vector2(-260, 232)
const PLAYER_TWO_START := Vector2(260, 232)
const MENU_FONT: FontFile = preload("res://assets/fonts/NotoSansGeorgian-Black.ttf")

const FIGHTERS := [
	{"id": "georgian", "name": "GEORGIAN", "special": "Yantsi boomerang"},
	{"id": "scotish",  "name": "SCOTTISH", "special": "Bagpipe air blast"},
	{"id": "english",  "name": "ENGLISH",  "special": "Beer-can splash"},
]

@onready var player_one: Node2D = $Players/PlayerOne
@onready var player_two: Node2D = $Players/PlayerTwo
@onready var camera: Camera2D = $Camera2D

var _human_fighter := 0
var _bot_fighter := 1
var _selecting := true
var _round_over := false

var _select_root: Control
var _p1_bar: ProgressBar
var _p2_bar: ProgressBar
var _p1_sp_bar: ProgressBar
var _p2_sp_bar: ProgressBar
var _p1_sp_label: Label
var _p2_sp_label: Label
var _info_label: Label
var _banner: Label


func _ready() -> void:
	# No multiplayer peer: the whole match is simulated locally, so both fighters
	# process every frame and hits are applied with direct calls.
	multiplayer.multiplayer_peer = null
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	RenderingServer.set_default_clear_color(Color.WHITE)
	_build_hud()
	_configure_players()
	# Park the fighters at their start spots, then wait on the select screen.
	player_one.set_meta("character_id", str(FIGHTERS[_human_fighter]["id"]))
	player_two.set_meta("character_id", str(FIGHTERS[_bot_fighter]["id"]))
	player_one.call("reset_fighter", PLAYER_ONE_START)
	player_two.call("reset_fighter", PLAYER_TWO_START)
	_show_select()


func _configure_players() -> void:
	player_one.set("player_id", 1)
	player_one.set("accept_local_input", true)
	player_one.set("bot_enabled", false)
	player_one.set("opponent_path", player_one.get_path_to(player_two))

	player_two.set("player_id", 2)
	player_two.set("accept_local_input", false)
	player_two.set("bot_enabled", true)
	player_two.set("opponent_path", player_two.get_path_to(player_one))

	player_one.connect("died", Callable(self, "_on_fighter_died"))
	player_two.connect("died", Callable(self, "_on_fighter_died"))


# ── Flow ──────────────────────────────────────────────────────────────────────
func _show_select() -> void:
	_selecting = true
	_select_root.visible = true
	_banner.visible = false
	player_one.set_physics_process(false)
	player_two.set_physics_process(false)


func _start_fight() -> void:
	_selecting = false
	_round_over = false
	_select_root.visible = false
	_banner.visible = false
	for node in get_tree().get_nodes_in_group("special_effects"):
		node.queue_free()
	player_one.set_meta("character_id", str(FIGHTERS[_human_fighter]["id"]))
	player_two.set_meta("character_id", str(FIGHTERS[_bot_fighter]["id"]))
	player_one.call("reset_fighter", PLAYER_ONE_START)
	player_two.call("reset_fighter", PLAYER_TWO_START)
	player_one.set_physics_process(true)
	player_two.set_physics_process(true)
	_info_label.text = "YOU: %s  [1/2/3]      BOT: %s  [B]      recharge [C]   restart [R]   select [TAB]" % [
		str(FIGHTERS[_human_fighter]["name"]), str(FIGHTERS[_bot_fighter]["name"])]


func _on_fighter_died(dead_player_id: int) -> void:
	if _round_over or _selecting:
		return
	_round_over = true
	if dead_player_id == 2:
		_banner.text = "YOU WIN!     [R] fight again"
		_banner.add_theme_color_override("font_color", Color(0.10, 0.55, 0.18, 1.0))
	else:
		_banner.text = "BOT WINS     [R] fight again"
		_banner.add_theme_color_override("font_color", Color(0.70, 0.12, 0.10, 1.0))
	_banner.visible = true


func _process(_delta: float) -> void:
	_update_camera()
	_update_hud()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _selecting:
		match key.keycode:
			KEY_1:
				_pick_and_fight(0)
			KEY_2:
				_pick_and_fight(1)
			KEY_3:
				_pick_and_fight(2)
		return
	match key.keycode:
		KEY_1:
			_human_fighter = 0
			_start_fight()
		KEY_2:
			_human_fighter = 1
			_start_fight()
		KEY_3:
			_human_fighter = 2
			_start_fight()
		KEY_B:
			_bot_fighter = (_bot_fighter + 1) % FIGHTERS.size()
			_start_fight()
		KEY_C:
			player_one.call("reset_special_cooldown")
		KEY_R:
			_start_fight()
		KEY_TAB:
			_show_select()


func _pick_and_fight(index: int) -> void:
	_human_fighter = index
	_bot_fighter = (index + 1) % FIGHTERS.size()
	_start_fight()


func _update_camera() -> void:
	var mid: Vector2 = (player_one.global_position + player_two.global_position) * 0.5
	camera.global_position = Vector2(mid.x, 10.0)


# ── HUD ───────────────────────────────────────────────────────────────────────
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Top row: health bars + special cooldown bars for each side.
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 28.0
	top.offset_right = -28.0
	top.offset_top = 16.0
	top.add_theme_constant_override("separation", 60)
	layer.add_child(top)

	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 4)
	top.add_child(left_box)
	_p1_bar = _make_bar(Color(0.20, 0.50, 1.0, 1.0), 30)
	left_box.add_child(_p1_bar)
	_p1_sp_label = _make_label("", 15)
	left_box.add_child(_p1_sp_label)
	_p1_sp_bar = _make_bar(Color(1.0, 0.78, 0.20, 1.0), 14)
	left_box.add_child(_p1_sp_bar)

	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 4)
	top.add_child(right_box)
	_p2_bar = _make_bar(Color(1.0, 0.30, 0.25, 1.0), 30)
	right_box.add_child(_p2_bar)
	_p2_sp_label = _make_label("", 15)
	_p2_sp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_box.add_child(_p2_sp_label)
	_p2_sp_bar = _make_bar(Color(1.0, 0.78, 0.20, 1.0), 14)
	right_box.add_child(_p2_sp_bar)

	_info_label = _make_label("", 18)
	_info_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_info_label.offset_top = 96.0
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_info_label)

	_banner = _make_label("", 60)
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color.WHITE)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.visible = false
	layer.add_child(_banner)

	_build_select_screen(layer)


func _build_select_screen(layer: CanvasLayer) -> void:
	_select_root = Control.new()
	_select_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_select_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(1.0, 1.0, 1.0, 0.86)
	_select_root.add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	column.offset_left = -360.0
	column.offset_right = 360.0
	column.offset_top = -220.0
	column.offset_bottom = 220.0
	_select_root.add_child(column)

	var title := _make_label("CHOOSE YOUR FIGHTER", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.10, 0.10, 0.10, 1.0))
	column.add_child(title)

	for i in range(FIGHTERS.size()):
		var line := _make_label("[%d]  %s  —  %s" % [
			i + 1, str(FIGHTERS[i]["name"]), str(FIGHTERS[i]["special"])], 26)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(line)

	var hint := _make_label("Press 1 / 2 / 3 to start.   Special move = triple-tap L.", 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.30, 0.30, 0.30, 1.0))
	column.add_child(hint)


func _make_bar(fill: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill
	fill_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill_style)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.85, 0.85, 0.85, 1.0)
	bg_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_style)
	return bar


func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1.0))
	return label


func _update_hud() -> void:
	_set_health(_p1_bar, player_one)
	_set_health(_p2_bar, player_two)
	_set_special(_p1_sp_label, _p1_sp_bar, player_one, true)
	_set_special(_p2_sp_label, _p2_sp_bar, player_two, false)


func _set_health(bar: ProgressBar, player: Node2D) -> void:
	if bar == null or player == null:
		return
	var hp := int(player.get("health"))
	var maxhp := maxi(int(player.get("max_health")), 1)
	bar.max_value = float(maxhp)
	bar.value = float(clampi(hp, 0, maxhp))


func _set_special(label: Label, bar: ProgressBar, player: Node2D, is_human: bool) -> void:
	if label == null or bar == null or player == null:
		return
	if not bool(player.call("has_special")):
		label.text = "No special"
		bar.value = 0.0
		return
	var sp_name := str(player.call("get_special_name"))
	var remaining: float = float(player.call("get_special_cooldown_remaining"))
	var total: float = maxf(float(player.call("get_special_cooldown_total")), 0.001)
	bar.value = clampf((total - remaining) / total * 100.0, 0.0, 100.0)
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if remaining <= 0.0:
		var hint := "   (triple-tap L)" if is_human else ""
		label.text = "%s — READY%s" % [sp_name, hint]
		label.add_theme_color_override("font_color", Color(0.10, 0.55, 0.18, 1.0))
		if fill != null:
			fill.bg_color = Color(0.16, 0.70, 0.26, 1.0)
	else:
		label.text = "%s — %ds" % [sp_name, int(ceil(remaining))]
		label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35, 1.0))
		if fill != null:
			fill.bg_color = Color(1.0, 0.78, 0.20, 1.0)
