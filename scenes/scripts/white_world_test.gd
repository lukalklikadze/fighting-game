extends Node2D

const LAN_PORT := 7777
const DISCOVERY_PORT := 7778
const DISCOVERY_REQUEST := "FIGHTING_GAME_FIND_HOST"
const DISCOVERY_RESPONSE_PREFIX := "FIGHTING_GAME_HOST:"
const JOIN_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const JOIN_TIMEOUT_TIME := 8.0
const PLAYER_ONE_START := Vector2(-260, 232)
const PLAYER_TWO_START := Vector2(260, 232)
const TITLE_DURATION := 1.8
const VICTORY_DISPLAY_TIME := 2.6

# --- Lives + super-meter → minigame loop (host-authoritative, RPC-synced) ---
const TOTAL_BARS := 3
const TOTAL_SUPERS := 3
const BIG_SUPER_FRACTION := 0.30     # starter won the minigame
const SMALL_SUPER_FRACTION := 0.15   # starter lost the minigame
const KO_FREEZE_TIME := 1.4
const SUPER_FADE := 0.35

# --- Pause menu (each player may pause once per match; never during a minigame) ---
# A centred, hand-drawn card (assets/pause menu) with two READY buttons that
# light up per state. Local perspective: the LEFT button is always YOU, the
# right is the opponent. Pause with ESC, ready with ENTER.
const PAUSE_DURATION := 20.0
const PAUSE_PER_PLAYER := 2           # how many times each player may pause per match
const PAUSE_KEY := KEY_ESCAPE
const PAUSE_READY_KEY := KEY_ENTER
const PAUSE_MENU_HEIGHT := 580.0     # on-screen height of the centred card (kept off the edges)
const PAUSE_IMG_NONE := preload("res://assets/pause menu/pausNotReady.png")
const PAUSE_IMG_P1 := preload("res://assets/pause menu/pausePlayer1Ready.png")
const PAUSE_IMG_P2 := preload("res://assets/pause menu/pauseOpponentReady.png")
const PAUSE_IMG_BOTH := preload("res://assets/pause menu/pauseBothReady.png")

const MINIGAME_PATHS := {
	1: "res://minigames/typeracer/scenes/Typeracer.tscn",
	2: "res://minigames/beer/scenes/Beer.tscn",
	3: "res://minigames/juggling/scenes/Juggling.tscn",
}
# Shown over the frozen fight for a few seconds after a minigame, by winner.
const WIN_CARDS := {
	"english":  preload("res://assets/england_win.png"),
	"georgian": preload("res://assets/georgian_win.png"),
	"scotish":  preload("res://assets/scotish_win.png"),
	"scottish": preload("res://assets/scotish_win.png"),
}
const WIN_CARD_TIME := 3.0
enum MatchSub { FIGHT, SUPER, KO, PAUSE }

# Fighting-game camera: follow the midpoint, zoom out as the fighters separate,
# and clamp to the stage so it never scrolls past the walls (as in Sakuga-Engine
# / field_trip_fighters). VIEW_W is the logical viewport width.
const CAM_VIEW_W := 1280.0
const CAM_STAGE_HALF := 950.0   # camera edge limit (just past the ±900 walls)
const CAM_MARGIN := 380.0       # extra world width kept around the two fighters
const CAM_MIN_ZOOM := 0.58      # most zoomed out (fighters far apart)
const CAM_MAX_ZOOM := 0.95      # most zoomed in (fighters close)
const CAM_LERP := 0.14          # smoothing toward the target
const CAM_Y := 10.0
const RANDOM_SLOT := 3
const MENU_FONT: FontFile = preload("res://assets/fonts/NotoSansGeorgian-Black.ttf")
const FIGHTER_ICON: Texture2D = preload("res://assets/Fighter sprites/fighter_Idle_0001.png")

# Select-screen palette (matches the layout sketch: green cards, black code box, red buttons).
const SELECT_BG := Color(0.05, 0.06, 0.055, 1.0)
const CARD_FILL := Color(0.06, 0.13, 0.08, 1.0)
const CARD_FILL_IDLE := Color(0.07, 0.08, 0.075, 1.0)
const CARD_BORDER := Color(0.20, 0.82, 0.38, 1.0)
const CARD_BORDER_FOCUS := Color(1.0, 0.90, 0.32, 1.0)
const P1_COLOR := Color(0.22, 0.52, 1.0, 1.0)
const P2_COLOR := Color(1.0, 0.26, 0.20, 1.0)
const BOTH_COLOR := Color(0.82, 0.30, 0.96, 1.0)
const CARD_SIZE := Vector2(200, 238)
const ACCENT_GREEN := Color(0.32, 0.95, 0.46, 1.0)

const CHARACTERS := [
	{"id": "english", "key": "english", "name": "ENGLISHMAN", "icon": "res://assets/walk/english man0000.png"},
	{"id": "georgian", "key": "georgian", "name": "GEORGIAN", "icon": "res://assets/walk/georgian man0000.png"},
	{"id": "scotish", "key": "scotish", "name": "SCOTSMAN", "icon": "res://assets/walk/scotish man0000.png"},
	{"id": "random", "key": "", "name": "RANDOM", "icon": ""},
]

enum ScreenState {
	TITLE,
	SELECT,
	MATCH,
}

enum FocusTarget {
	START,
	JOIN,
	GRID,
}

@onready var player_one: Node2D = $Players/PlayerOne
@onready var player_two: Node2D = $Players/PlayerTwo
@onready var camera: Camera2D = $Camera2D
@onready var arena_visuals: Node2D = $ArenaVisuals
@onready var world_collision: StaticBody2D = $WorldCollision
@onready var players_root: Node2D = $Players

var _screen := ScreenState.TITLE
var _focus := FocusTarget.START
var _title_timer := TITLE_DURATION
var _match_end_sent := false
var _reset_down := false

var _ui_layer: CanvasLayer
var _fight_layer: CanvasLayer
var _title_root: Control
var _select_root: Control
var _grid: Control
var _start_button: Button
var _join_button: Button
var _code_edit: LineEdit
var _host_code_label: Label
var _status_label: Label
var _victory_label: Label
var _msub := MatchSub.FIGHT
var _bar := {1: 1, 2: 1}
var _super_connected := false
var _last_minigame := 0               # host-tracked: never run the same minigame twice in a row

# Pause state (host-authoritative, mirrored on both peers).
var _pause_active := false
var _pause_is_intro := false      # true while showing the pre-fight instructions
var _pauser_pid := 0
var _pause_time_left := 0.0
var _pause_down := false
var _super_down := false
var _pause_ready_down := false
var _pause_count := {1: 0, 2: 0}      # pauses each player has used this match
var _pause_ready := {1: false, 2: false}
var _pause_root: Control
var _pause_image: TextureRect
var _pause_timer_label: Label
var _quit_button: TextureButton
var _minigame: Node = null
var _mg_layer: CanvasLayer
var _fade_rect: ColorRect
var _p1_super_bar: ProgressBar
var _p2_super_bar: ProgressBar
var _p1_pips: Array = []
var _p2_pips: Array = []
var _card_panels: Array[PanelContainer] = []
var _card_name_labels: Array[Label] = []
var _card_p1_badges: Array[Label] = []
var _card_p2_badges: Array[Label] = []
var _p1_health_bar: ProgressBar
var _p2_health_bar: ProgressBar
var _p1_health_text: Label
var _p2_health_text: Label
var _p1_special_label: Label
var _p2_special_label: Label

var _hover_by_player := {1: 0, 2: 0}
var _locked_by_player := {1: false, 2: false}
var _selected_by_player := {1: -1, 2: -1}
var _resolved_character_by_player := {1: 0, 2: 0}

var _host_discovery_peer: PacketPeerUDP
var _join_discovery_peer: PacketPeerUDP
var _discovery_timer := 0.0
var _discovery_attempts_left := 0
var _join_timeout_timer := 0.0
var _pending_join_ip := ""
var _client_peer_id := 0
var _hosting_active := false
var _connected_as_client := false
var _rng := RandomNumberGenerator.new()

# Fight-mode: launched directly from the starter_2 select scene (skip title/select).
var _fight_mode := false
var _fight_started := false
var _fight_ready_timer := 0.0


func _ready() -> void:
	_rng.randomize()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	RenderingServer.set_default_clear_color(Color(0.015, 0.012, 0.012, 1.0))
	_build_interface()
	_connect_health_signals()
	_connect_death_signals()
	_connect_multiplayer_signals()
	_configure_players_for_selection()
	_reset_match()
	_set_match_enabled(false)
	if MatchSetup.active:
		_enter_fight_mode()
	else:
		_show_title_screen()


func _process(delta: float) -> void:
	_process_lan_discovery(delta)
	_process_join_timeout(delta)
	_update_quit_visibility()
	if _fight_mode and not _fight_started:
		_process_fight_handshake(delta)
		return
	match _screen:
		ScreenState.TITLE:
			_process_title(delta)
		ScreenState.SELECT:
			_process_select_input()
		ScreenState.MATCH:
			_update_camera()
			_refresh_special_hud()
			_refresh_lives_super_hud()
			if _pause_active:
				_process_pause(delta)
			else:
				if _msub == MatchSub.FIGHT:
					_process_match_end()
				_handle_debug_reset()
				_handle_pause_input()
				_handle_super_input()


func _build_interface() -> void:
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)

	_fight_layer = CanvasLayer.new()
	add_child(_fight_layer)
	_build_health_hud(_fight_layer)
	_build_lives_super_hud(_fight_layer)
	_build_victory_banner(_fight_layer)

	# Minigame renders above the fight; the fade sits above the minigame.
	# Explicit names so the NodePath is identical on both peers (minigame RPCs).
	_mg_layer = CanvasLayer.new()
	_mg_layer.name = "MinigameLayer"
	_mg_layer.layer = 50
	add_child(_mg_layer)

	var fade_layer := CanvasLayer.new()
	fade_layer.name = "FadeLayer"
	fade_layer.layer = 60
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.visible = false
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)

	# Pause overlay sits above the fight/fade, below the always-on QUIT button.
	var pause_layer := CanvasLayer.new()
	pause_layer.name = "PauseLayer"
	pause_layer.layer = 80
	add_child(pause_layer)
	_build_pause_menu(pause_layer)

	_build_title_screen(_ui_layer)
	_build_select_screen(_ui_layer)
	_build_quit_button()


# A thin row under the health bars: 3 life pips + a gold super-meter bar per side.
func _build_lives_super_hud(layer: CanvasLayer) -> void:
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_top = 0.0
	row.anchor_right = 1.0
	row.offset_left = 16.0
	row.offset_top = 50.0
	row.offset_right = -16.0
	row.offset_bottom = 74.0
	row.add_theme_constant_override("separation", 24)
	layer.add_child(row)

	var p1_box := HBoxContainer.new()
	p1_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_box.add_theme_constant_override("separation", 6)
	row.add_child(p1_box)
	for i in range(TOTAL_BARS):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(22, 12)
		p1_box.add_child(pip)
		_p1_pips.append(pip)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(46, 0)
	row.add_child(spacer)

	var p2_box := HBoxContainer.new()
	p2_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2_box.alignment = BoxContainer.ALIGNMENT_END
	p2_box.add_theme_constant_override("separation", 6)
	row.add_child(p2_box)
	for i in range(TOTAL_BARS):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(22, 12)
		p2_box.add_child(pip)
		_p2_pips.append(pip)

	# Slim vertical super meters at each player's screen edge (P1 left, P2 right),
	# filling bottom-to-top. Clean and compact instead of the wide horizontal bars.
	_p1_super_bar = _make_super_bar()
	_anchor_super_meter(_p1_super_bar, true)
	layer.add_child(_p1_super_bar)
	_p2_super_bar = _make_super_bar()
	_anchor_super_meter(_p2_super_bar, false)
	layer.add_child(_p2_super_bar)


func _make_super_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(26, 150)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	# Vertical fill, growing upward as the meter charges.
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.add_theme_stylebox_override("background", _panel_style(Color(0.06, 0.06, 0.05, 0.92), Color(0.86, 0.70, 0.26, 1.0), 2, 7))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.82, 0.26, 1.0)
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _anchor_super_meter(bar: ProgressBar, on_left: bool) -> void:
	var bar_w := 26.0
	var bar_h := 150.0
	# Vertically centred on the screen edge (well below the top health HUD).
	bar.anchor_top = 0.5
	bar.anchor_bottom = 0.5
	bar.offset_top = -bar_h * 0.5
	bar.offset_bottom = bar_h * 0.5
	if on_left:
		bar.anchor_left = 0.0
		bar.anchor_right = 0.0
		bar.offset_left = 16.0
		bar.offset_right = 16.0 + bar_w
	else:
		bar.anchor_left = 1.0
		bar.anchor_right = 1.0
		bar.offset_left = -16.0 - bar_w
		bar.offset_right = -16.0


func _build_quit_button() -> void:
	# Top-most layer. Hidden during the live fight (it overlapped the lives) and
	# only shown while paused / on the menus — see _update_quit_visibility().
	# Bottom-right so it never covers the top health/lives HUD.
	var quit_layer := CanvasLayer.new()
	quit_layer.layer = 100
	add_child(quit_layer)

	# Hand-drawn QUIT image, matching the pause menu art.
	var quit := TextureButton.new()
	_quit_button = quit
	quit.texture_normal = preload("res://assets/pause menu/quit.png")
	quit.ignore_texture_size = true
	quit.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	quit.focus_mode = Control.FOCUS_NONE
	var quit_w := 180.0
	var quit_h := quit_w * 481.0 / 1000.0     # keep the image's aspect ratio
	quit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quit.offset_left = -quit_w - 18.0
	quit.offset_top = -quit_h - 18.0
	quit.offset_right = -18.0
	quit.offset_bottom = -18.0
	quit.pressed.connect(_on_quit_pressed)
	quit_layer.add_child(quit)


func _on_quit_pressed() -> void:
	_close_multiplayer_peer()
	get_tree().quit()


func _update_quit_visibility() -> void:
	# Hide QUIT during a live fight (it covered the lives); show it on the menus
	# and while the game is paused.
	if _quit_button != null:
		_quit_button.visible = _screen != ScreenState.MATCH or _pause_active


func _build_victory_banner(layer: CanvasLayer) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	_victory_label = Label.new()
	_victory_label.add_theme_font_override("font", MENU_FONT)
	_victory_label.add_theme_font_size_override("font_size", 88)
	_victory_label.add_theme_color_override("font_color", Color.WHITE)
	_victory_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_victory_label.add_theme_constant_override("outline_size", 14)
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_victory_label.visible = false
	center.add_child(_victory_label)


func _build_pause_menu(layer: CanvasLayer) -> void:
	_pause_root = Control.new()
	_pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.visible = false
	layer.add_child(_pause_root)

	# Light dim so the frozen fight stays visible behind the centred card.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.32)
	_pause_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.add_child(center)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	center.add_child(col)

	# Countdown above the card (the card art has no timer slot of its own).
	_pause_timer_label = _make_menu_label("", 34, Color(1.0, 0.95, 0.5, 1.0))
	_pause_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_pause_timer_label)

	# The hand-drawn menu card, scaled to a fixed height (keeps its aspect ratio).
	_pause_image = TextureRect.new()
	_pause_image.texture = PAUSE_IMG_NONE
	_pause_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pause_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var card_w := PAUSE_MENU_HEIGHT * 1000.0 / 1294.0
	_pause_image.custom_minimum_size = Vector2(card_w, PAUSE_MENU_HEIGHT)
	col.add_child(_pause_image)


func _build_title_screen(layer: CanvasLayer) -> void:
	_title_root = Control.new()
	_title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_title_root)

	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.015, 0.012, 0.012, 1.0)
	_title_root.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.add_child(center)

	var title_box := VBoxContainer.new()
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 18)
	center.add_child(title_box)

	var title := Label.new()
	title.text = "ქვეყნად ვერავინ შეძლებს"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.80, 0.28, 1.0))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "VERSUS TEST BUILD"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", MENU_FONT)
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.90, 0.08, 0.06, 1.0))
	subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle.add_theme_constant_override("outline_size", 5)
	title_box.add_child(subtitle)


func _build_select_screen(layer: CanvasLayer) -> void:
	_select_root = Control.new()
	_select_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_select_root)

	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = SELECT_BG
	_select_root.add_child(background)

	# Single vertical column, centered in the screen, holds every section in order:
	# title -> character cards -> player status -> code box -> action buttons -> hint.
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 48)
	root_margin.add_theme_constant_override("margin_right", 48)
	root_margin.add_theme_constant_override("margin_top", 28)
	root_margin.add_theme_constant_override("margin_bottom", 28)
	_select_root.add_child(root_margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 20)
	root_margin.add_child(column)

	var title := _make_menu_label("აირჩიე მებრძოლი", 46, ACCENT_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 8)
	column.add_child(title)

	# --- Character cards (green squares) ---
	var cards_center := CenterContainer.new()
	column.add_child(cards_center)

	_grid = HBoxContainer.new()
	_grid.add_theme_constant_override("separation", 22)
	cards_center.add_child(_grid)

	for index in range(CHARACTERS.size()):
		_add_character_card(index)

	# --- Code box (black) ---
	var code_center := CenterContainer.new()
	column.add_child(code_center)

	var code_box := PanelContainer.new()
	code_box.custom_minimum_size = Vector2(380, 96)
	code_box.add_theme_stylebox_override("panel", _panel_style(Color(0.0, 0.0, 0.0, 1.0), CARD_BORDER, 3, 10))
	code_center.add_child(code_box)

	var code_inner := VBoxContainer.new()
	code_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	code_inner.add_theme_constant_override("separation", 6)
	code_box.add_child(code_inner)

	_host_code_label = _make_menu_label("ENTER CODE", 15, Color(0.62, 0.86, 0.68, 1.0))
	_host_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_inner.add_child(_host_code_label)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "CODE"
	_code_edit.custom_minimum_size = Vector2(300, 44)
	_code_edit.max_length = 15
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.caret_blink = true
	_code_edit.add_theme_font_override("font", MENU_FONT)
	_code_edit.add_theme_font_size_override("font_size", 24)
	_code_edit.add_theme_color_override("font_color", ACCENT_GREEN)
	_code_edit.add_theme_color_override("font_placeholder_color", Color(0.35, 0.45, 0.38, 1.0))
	_code_edit.add_theme_stylebox_override("normal", _panel_style(Color(0.02, 0.03, 0.025, 1.0), Color(0.10, 0.30, 0.16, 1.0), 1, 6))
	_code_edit.add_theme_stylebox_override("focus", _panel_style(Color(0.03, 0.05, 0.04, 1.0), ACCENT_GREEN, 2, 6))
	_code_edit.text_submitted.connect(_on_join_code_submitted)
	code_inner.add_child(_code_edit)

	# --- Action buttons (red squares) ---
	var controls_center := CenterContainer.new()
	column.add_child(controls_center)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 40)
	controls_center.add_child(action_row)

	_start_button = _make_menu_button("START")
	_start_button.pressed.connect(_on_start_pressed)
	action_row.add_child(_start_button)

	_join_button = _make_menu_button("JOIN")
	_join_button.pressed.connect(_on_join_pressed)
	action_row.add_child(_join_button)

	# --- Status hint line ---
	_status_label = _make_menu_label("", 16, Color(0.78, 0.86, 0.80, 1.0))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 54)
	column.add_child(_status_label)

	_select_root.visible = false


func _add_character_card(index: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	panel.add_theme_stylebox_override("panel", _card_style(CARD_FILL, CARD_BORDER, 3))
	_grid.add_child(panel)
	_card_panels.append(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	var badge_row := HBoxContainer.new()
	stack.add_child(badge_row)

	var p1_badge := _make_badge("P1", P1_COLOR)
	badge_row.add_child(p1_badge)
	_card_p1_badges.append(p1_badge)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_row.add_child(spacer)

	var p2_badge := _make_badge("P2", P2_COLOR)
	badge_row.add_child(p2_badge)
	_card_p2_badges.append(p2_badge)

	if index == RANDOM_SLOT:
		var question := Label.new()
		question.text = "?"
		question.custom_minimum_size = Vector2(0, 150)
		question.size_flags_vertical = Control.SIZE_EXPAND_FILL
		question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		question.add_theme_font_override("font", MENU_FONT)
		question.add_theme_font_size_override("font_size", 92)
		question.add_theme_color_override("font_color", ACCENT_GREEN)
		question.add_theme_color_override("font_outline_color", Color.BLACK)
		question.add_theme_constant_override("outline_size", 7)
		stack.add_child(question)
	else:
		var icon := TextureRect.new()
		var icon_path := str(CHARACTERS[index].get("icon", ""))
		icon.texture = load(icon_path) if icon_path != "" else FIGHTER_ICON
		icon.custom_minimum_size = Vector2(0, 150)
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stack.add_child(icon)

	var name_label := _make_menu_label(str(CHARACTERS[index]["name"]), 16, Color(0.88, 0.98, 0.90, 1.0))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(name_label)
	_card_name_labels.append(name_label)


func _build_health_hud(layer: CanvasLayer) -> void:
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_top = 0.0
	row.anchor_right = 1.0
	row.anchor_bottom = 0.0
	row.offset_left = 16.0
	row.offset_top = 12.0
	row.offset_right = -16.0
	row.offset_bottom = 48.0
	row.add_theme_constant_override("separation", 24)
	layer.add_child(row)

	var p1_box := HBoxContainer.new()
	p1_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_box.add_theme_constant_override("separation", 8)
	row.add_child(p1_box)

	var p1_label := _make_fight_label("P1", 18)
	p1_label.custom_minimum_size = Vector2(34, 28)
	p1_box.add_child(p1_label)

	_p1_health_bar = _make_health_bar(Color(0.95, 0.18, 0.12, 1.0))
	p1_box.add_child(_p1_health_bar)

	_p1_health_text = _make_fight_label("", 15)
	_p1_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_p1_health_text.custom_minimum_size = Vector2(78, 28)
	p1_box.add_child(_p1_health_text)

	_p1_special_label = _make_fight_label("", 14)
	_p1_special_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_p1_special_label.custom_minimum_size = Vector2(104, 28)
	p1_box.add_child(_p1_special_label)

	var center_label := _make_fight_label("VS", 18)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.custom_minimum_size = Vector2(46, 28)
	row.add_child(center_label)

	var p2_box := HBoxContainer.new()
	p2_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2_box.add_theme_constant_override("separation", 8)
	row.add_child(p2_box)

	var p2_label := _make_fight_label("P2", 18)
	p2_label.custom_minimum_size = Vector2(34, 28)
	p2_box.add_child(p2_label)

	_p2_health_bar = _make_health_bar(Color(0.10, 0.34, 0.95, 1.0))
	p2_box.add_child(_p2_health_bar)

	_p2_health_text = _make_fight_label("", 15)
	_p2_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_p2_health_text.custom_minimum_size = Vector2(78, 28)
	p2_box.add_child(_p2_health_text)

	_p2_special_label = _make_fight_label("", 14)
	_p2_special_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_p2_special_label.custom_minimum_size = Vector2(104, 28)
	p2_box.add_child(_p2_special_label)


func _make_menu_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


func _make_fight_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	return label


func _make_menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(250, 86)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", MENU_FONT)
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_color_override("font_color", Color(1.0, 0.92, 0.90, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.70, 0.46, 0.44, 1.0))
	button.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_theme_constant_override("outline_size", 5)
	return button


func _make_badge(text: String, color: Color) -> Label:
	var badge := _make_menu_label(text, 14, Color.WHITE)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(40, 26)
	badge.add_theme_stylebox_override("normal", _panel_style(color, Color.WHITE, 2, 6))
	return badge


func _make_health_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(260, 28)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _panel_style(Color(0.02, 0.02, 0.02, 1.0), Color.BLACK, 2, 3))

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _panel_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _card_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	return _panel_style(fill, border, border_width, 8)


func _connect_health_signals() -> void:
	var p1_callable := Callable(self, "_on_player_one_health_changed")
	var p2_callable := Callable(self, "_on_player_two_health_changed")
	if not player_one.is_connected("health_changed", p1_callable):
		player_one.connect("health_changed", p1_callable)
	if not player_two.is_connected("health_changed", p2_callable):
		player_two.connect("health_changed", p2_callable)
	_refresh_health_hud()


func _connect_death_signals() -> void:
	var callable := Callable(self, "_on_fighter_died")
	if not player_one.is_connected("died", callable):
		player_one.connect("died", callable)
	if not player_two.is_connected("died", callable):
		player_two.connect("died", callable)


func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _show_title_screen() -> void:
	_screen = ScreenState.TITLE
	_title_timer = TITLE_DURATION
	_clear_pause_state()
	_title_root.visible = true
	_select_root.visible = false
	_fight_layer.visible = false
	_set_match_enabled(false)


func _show_select_screen(message := "") -> void:
	_screen = ScreenState.SELECT
	_msub = MatchSub.FIGHT
	_clear_pause_state()
	_clear_minigame()
	if _fade_rect != null:
		_fade_rect.color.a = 0.0
		_fade_rect.visible = false
	RenderingServer.set_default_clear_color(Color(0.015, 0.012, 0.012, 1.0))
	_title_root.visible = false
	_select_root.visible = true
	_fight_layer.visible = false
	_set_match_enabled(false)
	if not _is_selection_open() and _focus == FocusTarget.GRID:
		_focus = FocusTarget.START
	if message != "":
		_set_status(message)
	_refresh_select_ui()


func _hide_title_and_select() -> void:
	_title_root.visible = false
	_select_root.visible = false
	_fight_layer.visible = false
	_set_match_enabled(false)


func _show_match_screen() -> void:
	_screen = ScreenState.MATCH
	RenderingServer.set_default_clear_color(Color.WHITE)
	_title_root.visible = false
	_select_root.visible = false
	_fight_layer.visible = true
	if _victory_label != null:
		_victory_label.visible = false
	_set_match_enabled(true)
	_refresh_health_hud()
	_refresh_special_hud()


func _set_match_enabled(enabled: bool) -> void:
	arena_visuals.visible = enabled
	world_collision.visible = enabled
	players_root.visible = enabled
	player_one.set_physics_process(enabled)
	player_two.set_physics_process(enabled)


func _process_title(delta: float) -> void:
	_title_timer -= delta
	if _title_timer <= 0.0 or Input.is_action_just_pressed("ui_accept"):
		_show_select_screen("Choose START to host or JOIN with your friend's code.")


func _process_select_input() -> void:
	if _code_edit.has_focus():
		if Input.is_action_just_pressed("ui_cancel"):
			_code_edit.release_focus()
			_focus = FocusTarget.JOIN
			_refresh_select_ui()
		return

	var grid_enabled := _is_selection_open()
	if Input.is_action_just_pressed("ui_left"):
		_move_select_focus(Vector2i.LEFT, grid_enabled)
	elif Input.is_action_just_pressed("ui_right"):
		_move_select_focus(Vector2i.RIGHT, grid_enabled)
	elif Input.is_action_just_pressed("ui_up"):
		_move_select_focus(Vector2i.UP, grid_enabled)
	elif Input.is_action_just_pressed("ui_down"):
		_move_select_focus(Vector2i.DOWN, grid_enabled)
	elif Input.is_action_just_pressed("ui_accept"):
		_accept_select_focus(grid_enabled)


func _move_select_focus(direction: Vector2i, grid_enabled: bool) -> void:
	if grid_enabled:
		# Inside an active lobby the character grid is the only focusable element;
		# START / JOIN are locked, so navigation never returns to them.
		_focus = FocusTarget.GRID
		var player_id := _local_player_id()
		if bool(_locked_by_player[player_id]):
			return
		var index := int(_hover_by_player[player_id])
		var col := index % CHARACTERS.size()
		col = clampi(col + direction.x, 0, CHARACTERS.size() - 1)
		_hover_by_player[player_id] = col
		_submit_local_selection(false)
		_refresh_select_ui()
		return

	# Before a lobby exists, only the START / JOIN buttons can be focused.
	if direction.x < 0:
		_focus = FocusTarget.START
	elif direction.x > 0:
		_focus = FocusTarget.JOIN
	_refresh_select_ui()


func _accept_select_focus(grid_enabled: bool) -> void:
	match _focus:
		FocusTarget.START:
			_on_start_pressed()
		FocusTarget.JOIN:
			_on_join_pressed()
		FocusTarget.GRID:
			if grid_enabled:
				_submit_local_selection(true)


func _on_start_pressed() -> void:
	if _is_selection_open():
		_focus = FocusTarget.GRID
		_refresh_select_ui()
		return
	_host_lan_game()


func _on_join_pressed() -> void:
	if _is_selection_open():
		_focus = FocusTarget.GRID
		_refresh_select_ui()
		return
	if _code_edit.text.strip_edges() == "":
		_code_edit.grab_focus()
		_set_status("Enter host code, then press JOIN.")
		return
	_join_lan_game()


func _on_join_code_submitted(_text: String) -> void:
	_join_lan_game()


func _submit_local_selection(lock_selection: bool) -> void:
	if not _is_selection_open():
		return
	var player_id := _local_player_id()
	var hover := clampi(int(_hover_by_player[player_id]), 0, CHARACTERS.size() - 1)
	_hover_by_player[player_id] = hover
	if lock_selection:
		if _is_slot_taken_by_opponent(player_id, hover):
			_set_status("%s is taken — pick another fighter." % str(CHARACTERS[hover]["name"]))
		else:
			_locked_by_player[player_id] = true
			_selected_by_player[player_id] = hover

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_submit_selection.rpc_id(1, hover, bool(_locked_by_player[player_id]), int(_selected_by_player[player_id]))
	else:
		_broadcast_lobby_state()
		_try_start_match_if_ready()

	_refresh_select_ui()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_selection(hover: int, locked: bool, selected: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _client_peer_id > 0 and sender != _client_peer_id:
		return
	_hover_by_player[2] = clampi(hover, 0, CHARACTERS.size() - 1)
	var clamped_selected := clampi(selected, -1, CHARACTERS.size() - 1)
	# Host is authoritative: the client cannot lock a fighter Player 1 already owns.
	if locked and _is_slot_taken_by_opponent(2, clamped_selected):
		locked = false
		clamped_selected = -1
	_locked_by_player[2] = locked
	_selected_by_player[2] = clamped_selected
	_broadcast_lobby_state()
	_try_start_match_if_ready()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_lobby_state() -> void:
	if multiplayer.is_server():
		_send_lobby_state_to_peer(multiplayer.get_remote_sender_id())


func _broadcast_lobby_state(message := "") -> void:
	var state := _lobby_state_payload(message)
	_apply_lobby_state(state)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_apply_lobby_state.rpc(state)


func _send_lobby_state_to_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	_rpc_apply_lobby_state.rpc_id(peer_id, _lobby_state_payload())


func _lobby_state_payload(message := "") -> Dictionary:
	return {
		"p1_hover": int(_hover_by_player[1]),
		"p2_hover": int(_hover_by_player[2]),
		"p1_locked": bool(_locked_by_player[1]),
		"p2_locked": bool(_locked_by_player[2]),
		"p1_selected": int(_selected_by_player[1]),
		"p2_selected": int(_selected_by_player[2]),
		"client_peer_id": _client_peer_id,
		"message": message,
	}


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_lobby_state(state: Dictionary) -> void:
	_apply_lobby_state(state)


func _apply_lobby_state(state: Dictionary) -> void:
	_hover_by_player[1] = clampi(int(state.get("p1_hover", 0)), 0, CHARACTERS.size() - 1)
	_hover_by_player[2] = clampi(int(state.get("p2_hover", 0)), 0, CHARACTERS.size() - 1)
	_locked_by_player[1] = bool(state.get("p1_locked", false))
	_locked_by_player[2] = bool(state.get("p2_locked", false))
	_selected_by_player[1] = clampi(int(state.get("p1_selected", -1)), -1, CHARACTERS.size() - 1)
	_selected_by_player[2] = clampi(int(state.get("p2_selected", -1)), -1, CHARACTERS.size() - 1)
	_client_peer_id = int(state.get("client_peer_id", _client_peer_id))
	if _screen != ScreenState.MATCH:
		_show_select_screen()
	var message := str(state.get("message", ""))
	if message != "":
		_set_status(message)
	_refresh_select_ui()


# --- Fight-mode entry (launched from the starter_2 select scene) ---------------

# Map a starter_2 ball key to our CHARACTERS index.
# starter_2 uses "scottish" (two t's); our gameplay uses "scotish".
func _ball_key_to_index(key: String) -> int:
	match key:
		"english":
			return 0
		"georgian":
			return 1
		"scottish", "scotish":
			return 2
		_:
			return RANDOM_SLOT


func _enter_fight_mode() -> void:
	_fight_mode = true
	_fight_started = false
	_hide_title_and_select()
	if multiplayer.is_server():
		_hosting_active = true
		_connected_as_client = false
		_client_peer_id = int(MatchSetup.client_peer_id)
		_set_status("Starting fight...")
		# Host waits for the client to signal it's loaded (_rpc_fight_ready).
	else:
		_hosting_active = false
		_connected_as_client = true
		_client_peer_id = multiplayer.get_unique_id()
		_fight_ready_timer = 0.0  # start pinging the host immediately


func _process_fight_handshake(delta: float) -> void:
	# Client repeatedly tells the host it's in the fight scene until the match
	# actually starts (covers any scene-load ordering between the two peers).
	if not _connected_as_client:
		return
	_fight_ready_timer -= delta
	if _fight_ready_timer <= 0.0:
		_fight_ready_timer = 0.3
		if multiplayer.has_multiplayer_peer():
			_rpc_fight_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_fight_ready() -> void:
	if not (multiplayer.is_server() and _fight_mode) or _fight_started:
		return
	_begin_fight_from_setup()


func _begin_fight_from_setup() -> void:
	if _fight_started:
		return
	_fight_started = true
	_selected_by_player[1] = _ball_key_to_index(String(MatchSetup.p1_choice))
	_selected_by_player[2] = _ball_key_to_index(String(MatchSetup.p2_choice))
	var resolved := _resolve_match_characters()
	var p1_character := int(resolved[0])
	var p2_character := int(resolved[1])
	_rpc_start_match.rpc(_client_peer_id, p1_character, p2_character)
	_start_match(_client_peer_id, p1_character, p2_character)


func _return_to_lobby_scene() -> void:
	MatchSetup.clear()
	get_tree().change_scene_to_file("res://starter_2.tscn")


func _try_start_match_if_ready() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if _client_peer_id <= 0:
		_set_status("Waiting for Player 2 to join.")
		return
	if not bool(_locked_by_player[1]) or not bool(_locked_by_player[2]):
		return
	var resolved := _resolve_match_characters()
	var p1_character := int(resolved[0])
	var p2_character := int(resolved[1])
	_rpc_start_match.rpc(_client_peer_id, p1_character, p2_character)
	_start_match(_client_peer_id, p1_character, p2_character)


@rpc("authority", "call_remote", "reliable")
func _rpc_start_match(client_peer_id: int, p1_character: int, p2_character: int) -> void:
	_start_match(client_peer_id, p1_character, p2_character)


func _start_match(client_peer_id: int, p1_character: int, p2_character: int) -> void:
	_client_peer_id = _resolve_client_peer_id(client_peer_id)
	_resolved_character_by_player[1] = p1_character
	_resolved_character_by_player[2] = p2_character
	_stop_join_discovery()
	if not multiplayer.is_server():
		_stop_host_discovery()
	_configure_players_for_lan(_client_peer_id)
	_apply_character_to_player(player_one, p1_character)
	_apply_character_to_player(player_two, p2_character)
	_reset_match()
	_match_end_sent = false
	# Start the lives + super-meter loop.
	_bar = {1: 1, 2: 1}
	_pause_count = {1: 0, 2: 0}
	_last_minigame = 0
	_clear_pause_state()
	_msub = MatchSub.FIGHT
	player_one.set("super_fill_enabled", true)
	player_two.set("super_fill_enabled", true)
	player_one.call("reset_super")
	player_two.call("reset_super")
	_connect_super_signals()
	if _fight_mode:
		_fight_started = true
		MatchSetup.clear()
	_show_match_screen()
	# Pre-fight instructions: same card + ready logic, shown on both peers. The
	# fight is frozen until both ready or the 20s runs out. Doesn't use a pause.
	_begin_intro()


func _connect_super_signals() -> void:
	if _super_connected:
		return
	_super_connected = true
	player_one.connect("super_full", _on_super_full)
	player_two.connect("super_full", _on_super_full)


func _refresh_lives_super_hud() -> void:
	if _p1_super_bar != null:
		_p1_super_bar.max_value = float(player_one.get("super_max"))
		_p1_super_bar.value = float(player_one.get("super_meter"))
	if _p2_super_bar != null:
		_p2_super_bar.max_value = float(player_two.get("super_max"))
		_p2_super_bar.value = float(player_two.get("super_meter"))
	_refresh_pips(_p1_pips, 1, P1_COLOR)
	_refresh_pips(_p2_pips, 2, P2_COLOR)


func _refresh_pips(pips: Array, pid: int, col: Color) -> void:
	var lit := clampi(TOTAL_BARS - (int(_bar[pid]) - 1), 0, TOTAL_BARS)
	for i in range(pips.size()):
		pips[i].color = col if i < lit else Color(0.18, 0.18, 0.18, 1.0)


func _set_match_frozen(frozen: bool) -> void:
	player_one.set("accept_local_input", not frozen)
	player_two.set("accept_local_input", not frozen)
	player_one.set("super_fill_enabled", not frozen)
	player_two.set("super_fill_enabled", not frozen)


func _other_player(player_id: int) -> int:
	return 2 if player_id == 1 else 1


func _is_slot_taken_by_opponent(player_id: int, slot: int) -> bool:
	# RANDOM is shareable (it is not a concrete fighter); the match-start resolver
	# guarantees the two random picks land on different fighters.
	if slot == RANDOM_SLOT or slot < 0:
		return false
	var other := _other_player(player_id)
	return bool(_locked_by_player[other]) and int(_selected_by_player[other]) == slot


func _explicit_choice(selection_index: int) -> int:
	# Concrete fighter index for an explicit pick, or -1 for RANDOM / nothing.
	if selection_index < 0 or selection_index == RANDOM_SLOT:
		return -1
	return clampi(selection_index, 0, RANDOM_SLOT - 1)


func _resolve_match_characters() -> Array:
	# Returns [p1_fighter, p2_fighter], always two distinct fighters. Explicit
	# picks are already unique (locking blocks duplicates); RANDOM picks are
	# resolved from the remaining pool so they never collide.
	var taken: Array[int] = []
	var c1 := _explicit_choice(int(_selected_by_player[1]))
	if c1 >= 0:
		taken.append(c1)
	var c2 := _explicit_choice(int(_selected_by_player[2]))
	if c2 >= 0 and not taken.has(c2):
		taken.append(c2)
	if c1 < 0:
		c1 = _pick_random_fighter(taken)
		taken.append(c1)
	if c2 < 0:
		c2 = _pick_random_fighter(taken)
		taken.append(c2)
	return [c1, c2]


func _pick_random_fighter(taken: Array) -> int:
	var pool: Array[int] = []
	for i in range(RANDOM_SLOT):
		if not taken.has(i):
			pool.append(i)
	if pool.is_empty():
		return _rng.randi_range(0, RANDOM_SLOT - 1)
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _apply_character_to_player(player: Node2D, character_index: int) -> void:
	player.set_meta("character_id", str(CHARACTERS[character_index]["id"]))
	player.set_meta("character_name", str(CHARACTERS[character_index]["name"]))
	player.call("set_character", str(CHARACTERS[character_index].get("key", "placeholder")))


func _return_to_selection_after_match(message: String) -> void:
	_locked_by_player[1] = false
	_locked_by_player[2] = false
	_selected_by_player[1] = -1
	_selected_by_player[2] = -1
	_match_end_sent = false
	# Tear down the lives/super loop.
	_clear_pause_state()
	_msub = MatchSub.FIGHT
	_bar = {1: 1, 2: 1}
	_clear_minigame()
	if _fade_rect != null:
		_fade_rect.color.a = 0.0
		_fade_rect.visible = false
	player_one.set("super_fill_enabled", false)
	player_two.set("super_fill_enabled", false)
	# Both players are still connected, so drop them straight back onto the
	# character grid -- they can only pick again, never touch START/JOIN.
	_focus = FocusTarget.GRID
	_configure_players_for_selection()
	_reset_match()
	_show_select_screen(message)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_broadcast_lobby_state(message)


@rpc("authority", "call_remote", "reliable")
func _rpc_return_to_selection_after_match(message: String) -> void:
	_return_to_selection_after_match(message)


func _process_match_end() -> void:
	if _match_end_sent or _msub != MatchSub.FIGHT:
		return   # a super KO is resolved once the sequence returns to FIGHT
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var p1_dead := int(player_one.get("health")) <= 0
	var p2_dead := int(player_two.get("health")) <= 0
	if not p1_dead and not p2_dead:
		return
	_match_end_sent = true
	_run_ko(1 if p1_dead else 2)


# Host-authoritative: a fighter lost its current bar — death anim, then either
# resurrect onto the next bar (both reset to start) or end the match.
func _run_ko(loser: int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_begin_ko.rpc(loser)
	_begin_ko(loser)
	await get_tree().create_timer(KO_FREEZE_TIME).timeout
	if _screen != ScreenState.MATCH or _msub != MatchSub.KO:
		return
	if int(_bar[loser]) < TOTAL_BARS:
		_bar[loser] += 1
		if multiplayer.has_multiplayer_peer():
			_rpc_resume_round.rpc(int(_bar[1]), int(_bar[2]))
		_resume_round(int(_bar[1]), int(_bar[2]))
	else:
		var winner := _other_player(loser)
		if multiplayer.has_multiplayer_peer():
			_rpc_play_victory.rpc(winner)
		_play_victory(winner)


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_ko(loser: int) -> void:
	_begin_ko(loser)


func _begin_ko(_loser: int) -> void:
	_msub = MatchSub.KO
	_set_match_frozen(true)


@rpc("authority", "call_remote", "reliable")
func _rpc_resume_round(b1: int, b2: int) -> void:
	_resume_round(b1, b2)


func _resume_round(b1: int, b2: int) -> void:
	_bar[1] = b1
	_bar[2] = b2
	_match_end_sent = false
	player_one.call("reset_fighter", PLAYER_ONE_START, true)
	player_two.call("reset_fighter", PLAYER_TWO_START, true)
	_msub = MatchSub.FIGHT
	_set_match_frozen(false)
	_refresh_health_hud()
	_refresh_lives_super_hud()


# ===========================================================================
#  Super meter -> networked minigame
# ===========================================================================

func _on_super_full(_pid: int) -> void:
	# The minigame is now OPTIONAL: a full meter does nothing on its own — the
	# player launches the contest by pressing SPACE (see _handle_super_input).
	pass


func _handle_super_input() -> void:
	# Edge-detected SPACE launches the contest, but only if your meter is full.
	var pressed := Input.is_physical_key_pressed(KEY_SPACE)
	if pressed and not _super_down and _msub == MatchSub.FIGHT and not _pause_active:
		_try_use_super()
	_super_down = pressed


func _try_use_super() -> void:
	var pid := _local_player_id()
	var fighter: Node2D = player_one if pid == 1 else player_two
	# Checked on the local (authoritative) fighter, so the value is exact.
	if float(fighter.get("super_meter")) < float(fighter.get("super_max")):
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_request_super.rpc_id(1, pid)
	else:
		_host_begin_super(pid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_super(pid: int) -> void:
	if multiplayer.is_server():
		_host_begin_super(pid)


func _host_begin_super(attacker: int) -> void:
	# Simple rule: a full meter fires a RANDOM minigame, any time, as often as it
	# refills. One super at a time (host gates on FIGHT). The host picks the
	# random minigame and broadcasts it so both peers run the same one.
	if _screen != ScreenState.MATCH or _msub != MatchSub.FIGHT:
		return
	var which := _pick_minigame()
	if multiplayer.has_multiplayer_peer():
		_rpc_begin_super.rpc(which, attacker)
	_run_super(which, attacker)


func _pick_minigame() -> int:
	# Random, but never the same minigame type twice in a row.
	var pool: Array[int] = []
	for i in range(1, TOTAL_SUPERS + 1):
		if i != _last_minigame:
			pool.append(i)
	if pool.is_empty():
		pool.append(_rng.randi_range(1, TOTAL_SUPERS))
	_last_minigame = pool[_rng.randi_range(0, pool.size() - 1)]
	return _last_minigame


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_super(which: int, attacker: int) -> void:
	_run_super(which, attacker)


func _run_super(which: int, attacker: int) -> void:
	_msub = MatchSub.SUPER
	_set_match_frozen(true)
	var atk: Node2D = player_one if attacker == 1 else player_two
	if atk.is_multiplayer_authority():
		atk.call("reset_super")
	await _super_fade(1.0)
	_fight_layer.visible = false
	_start_minigame(which)
	await _super_fade(0.0)
	var result: int = await _minigame.minigame_finished
	# A draw doesn't resolve the super — replay the minigame until someone wins.
	while result == -1:
		_clear_minigame()
		_start_minigame(which)
		result = await _minigame.minigame_finished
	await _super_fade(1.0)
	_clear_minigame()
	_fight_layer.visible = true
	# Host alone resolves damage from its own minigame result.
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_apply_super_outcome(attacker, result)
	await _super_fade(0.0)
	# Show the winner's card over the frozen fight for a few seconds.
	await _show_win_card(result)
	if _msub == MatchSub.SUPER:
		_msub = MatchSub.FIGHT
		_set_match_frozen(false)


# Overlays the winning fighter's card over the (still frozen) fight. `result` is
# from the local perspective: 1 = local won, 0 = local lost, -1 = draw.
func _show_win_card(result: int) -> void:
	if result != 1 and result != 0:
		return  # draw — no winner card
	var local_id := _local_player_id()
	var winner_node: Node2D
	if result == 1:
		winner_node = player_one if local_id == 1 else player_two
	else:
		winner_node = player_two if local_id == 1 else player_one
	var winner_char := String(winner_node.get_meta("character_id", ""))
	var tex: Texture2D = WIN_CARDS.get(winner_char, null)
	if tex == null:
		return
	var card := TextureRect.new()
	card.texture = tex
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mg_layer.add_child(card)
	await get_tree().create_timer(WIN_CARD_TIME).timeout
	card.queue_free()


func _start_minigame(which: int) -> void:
	var packed: PackedScene = load(MINIGAME_PATHS[clampi(which, 1, TOTAL_SUPERS)])
	_minigame = packed.instantiate()
	_minigame.name = "ActiveMinigame"   # identical NodePath on both peers for RPCs
	_minigame.set("embedded", true)
	_mg_layer.add_child(_minigame)
	if multiplayer.has_multiplayer_peer() and (_hosting_active or _connected_as_client):
		_minigame.call("begin_networked", multiplayer.is_server())
	else:
		_minigame.call("begin_solo")


func _clear_minigame() -> void:
	if _minigame != null and is_instance_valid(_minigame):
		_minigame.queue_free()
	_minigame = null


func _apply_super_outcome(attacker: int, host_result: int) -> void:
	if host_result == -1:
		return   # draw — no damage
	# host_result is player_one's (host's) perspective of the minigame.
	var starter_won := (host_result == 1) if attacker == 1 else (host_result == 0)
	var loser := _other_player(attacker)
	var f: Node2D = player_one if loser == 1 else player_two
	var frac := BIG_SUPER_FRACTION if starter_won else SMALL_SUPER_FRACTION
	var dmg := int(round(frac * float(f.get("max_health"))))
	if multiplayer.has_multiplayer_peer():
		_rpc_super_damage.rpc(loser, dmg)
	else:
		f.call("apply_super_damage", dmg)


@rpc("authority", "call_local", "reliable")
func _rpc_super_damage(loser_pid: int, amount: int) -> void:
	var f: Node2D = player_one if loser_pid == 1 else player_two
	if f.is_multiplayer_authority():
		f.call("apply_super_damage", amount)


func _super_fade(to_alpha: float) -> void:
	_fade_rect.visible = true
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", to_alpha, SUPER_FADE)
	await tw.finished
	if to_alpha <= 0.0:
		_fade_rect.visible = false


# ===========================================================================
#  Pause menu (host-authoritative; one pause per player per match)
# ===========================================================================

func _handle_pause_input() -> void:
	# Edge-detected pause key. Only from a live fight (never a minigame / KO).
	var pressed := Input.is_physical_key_pressed(PAUSE_KEY)
	if pressed and not _pause_down and _msub == MatchSub.FIGHT and not _pause_active:
		_request_pause()
	_pause_down = pressed


func _request_pause() -> void:
	var pid := _local_player_id()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_request_pause.rpc_id(1, pid)
	else:
		_host_begin_pause(pid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pause(pid: int) -> void:
	if not multiplayer.is_server():
		return
	# The only remote peer is the client = Player 2; trust nothing else.
	var who := 2 if multiplayer.get_remote_sender_id() == _client_peer_id else pid
	_host_begin_pause(who)


func _host_begin_pause(pid: int) -> void:
	if _screen != ScreenState.MATCH or _msub != MatchSub.FIGHT or _pause_active:
		return
	if int(_pause_count.get(pid, PAUSE_PER_PLAYER)) >= PAUSE_PER_PLAYER:
		return   # this player has used up their pauses
	_pause_count[pid] = int(_pause_count[pid]) + 1
	if multiplayer.has_multiplayer_peer():
		_rpc_begin_pause.rpc(pid)
	_begin_pause(pid)


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_pause(pid: int) -> void:
	_pause_count[pid] = int(_pause_count[pid]) + 1
	_begin_pause(pid)


# Shared by the ESC pause and the pre-fight instructions intro (same card, same
# ready/timeout logic). The intro just doesn't consume a player's one pause.
func _enter_pause_overlay(pauser_pid: int, is_intro: bool) -> void:
	_pause_active = true
	_pause_is_intro = is_intro
	_pauser_pid = pauser_pid
	_pause_time_left = PAUSE_DURATION
	_pause_ready = {1: false, 2: false}
	# Require a fresh ENTER press (don't auto-ready if it's already held).
	_pause_ready_down = Input.is_physical_key_pressed(PAUSE_READY_KEY)
	_msub = MatchSub.PAUSE
	_set_match_frozen(true)
	# Fully halt the fighters so no in-progress attack/animation resolves.
	player_one.set_physics_process(false)
	player_two.set_physics_process(false)
	if _pause_root != null:
		_pause_root.visible = true
	_update_pause_ui()


func _begin_pause(pauser_pid: int) -> void:
	_enter_pause_overlay(pauser_pid, false)


# Pre-fight instructions: shown automatically at match start on both peers. Both
# call this from _start_match, so no begin RPC is needed; the host ends it (20s
# or both ready) via the same path as a pause.
func _begin_intro() -> void:
	_enter_pause_overlay(0, true)


func _process_pause(delta: float) -> void:
	_pause_time_left = maxf(_pause_time_left - delta, 0.0)
	# Local player readies with ENTER (edge-detected).
	var ready_pressed := Input.is_physical_key_pressed(PAUSE_READY_KEY)
	if ready_pressed and not _pause_ready_down:
		_ready_up_local()
	_pause_ready_down = ready_pressed
	_update_pause_ui()
	_maybe_host_end_pause()


func _ready_up_local() -> void:
	if not _pause_active:
		return
	var pid := _local_player_id()
	if bool(_pause_ready.get(pid, false)):
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_set_pause_ready(pid, true)         # optimistic local feedback
		_rpc_pause_ready.rpc_id(1, pid)
	else:
		_host_set_ready(pid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pause_ready(pid: int) -> void:
	if not multiplayer.is_server():
		return
	var who := 2 if multiplayer.get_remote_sender_id() == _client_peer_id else pid
	_host_set_ready(who)


func _host_set_ready(pid: int) -> void:
	if not _pause_active:
		return
	_set_pause_ready(pid, true)
	if multiplayer.has_multiplayer_peer():
		_rpc_pause_ready_state.rpc(bool(_pause_ready[1]), bool(_pause_ready[2]))
	_maybe_host_end_pause()


@rpc("authority", "call_remote", "reliable")
func _rpc_pause_ready_state(r1: bool, r2: bool) -> void:
	_pause_ready[1] = r1
	_pause_ready[2] = r2
	_update_pause_ui()


func _set_pause_ready(pid: int, ready: bool) -> void:
	_pause_ready[pid] = ready
	_update_pause_ui()


func _is_pause_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _maybe_host_end_pause() -> void:
	if not _is_pause_host() or not _pause_active:
		return
	var both_ready := bool(_pause_ready[1]) and bool(_pause_ready[2])
	if not multiplayer.has_multiplayer_peer():
		both_ready = bool(_pause_ready[_local_player_id()])
	if both_ready or _pause_time_left <= 0.0:
		if multiplayer.has_multiplayer_peer():
			_rpc_end_pause.rpc()
		_end_pause()


@rpc("authority", "call_remote", "reliable")
func _rpc_end_pause() -> void:
	_end_pause()


func _end_pause() -> void:
	if not _pause_active:
		return
	_pause_active = false
	_pause_is_intro = false
	_pause_ready = {1: false, 2: false}
	if _pause_root != null:
		_pause_root.visible = false
	if _msub == MatchSub.PAUSE:
		_msub = MatchSub.FIGHT
	player_one.set_physics_process(true)
	player_two.set_physics_process(true)
	_set_match_frozen(false)


func _clear_pause_state() -> void:
	# Force pause off (used when a match starts/ends or a peer drops mid-pause).
	_pause_active = false
	_pause_is_intro = false
	_pause_time_left = 0.0
	_pause_ready = {1: false, 2: false}
	if _pause_root != null:
		_pause_root.visible = false
	if _msub == MatchSub.PAUSE:
		_msub = MatchSub.FIGHT


func _update_pause_ui() -> void:
	if not _pause_active or _pause_image == null:
		return
	_pause_image.texture = _pause_texture_for_state()
	if _pause_is_intro:
		_pause_timer_label.text = "FIGHT STARTS IN   %ds" % int(ceil(_pause_time_left))
	else:
		_pause_timer_label.text = "PAUSED   %ds" % int(ceil(_pause_time_left))


func _pause_texture_for_state() -> Texture2D:
	# Local perspective: the LEFT button is always YOU, the right is the opponent.
	# So the same ready state shows mirrored on the two machines (you ready ->
	# you see the left light up, the opponent sees the right light up).
	var me := _local_player_id()
	var me_ready := bool(_pause_ready[me])
	var opp_ready := bool(_pause_ready[_other_player(me)])
	if me_ready and opp_ready:
		return PAUSE_IMG_BOTH
	if me_ready:
		return PAUSE_IMG_P1     # left red = you
	if opp_ready:
		return PAUSE_IMG_P2     # right red = opponent
	return PAUSE_IMG_NONE


@rpc("authority", "call_remote", "reliable")
func _rpc_play_victory(winner: int) -> void:
	_play_victory(winner)


func _play_victory(winner: int) -> void:
	# The loser is already in its DEAD state playing the death animation. Freeze
	# both fighters' input so the winner just stands while the banner is shown.
	player_one.set("accept_local_input", false)
	player_two.set("accept_local_input", false)
	_show_victory_banner(winner)
	# Only the host counts down, then sends everyone back to character select.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	await get_tree().create_timer(VICTORY_DISPLAY_TIME).timeout
	if not _match_end_sent or _screen != ScreenState.MATCH:
		return
	var message := "Player %d wins. Choose again." % winner
	if multiplayer.has_multiplayer_peer():
		_rpc_return_to_selection_after_match.rpc(message)
	_return_to_selection_after_match(message)


func _show_victory_banner(winner: int) -> void:
	if _victory_label == null:
		return
	_victory_label.text = "PLAYER %d WINS!" % winner
	_victory_label.add_theme_color_override("font_color", P1_COLOR if winner == 1 else P2_COLOR)
	_victory_label.visible = true


func _on_fighter_died(_player_id: int) -> void:
	_process_match_end()


func _is_selection_open() -> bool:
	# Godot 4 assigns a default OfflineMultiplayerPeer, so has_multiplayer_peer()/is_server()
	# are true even before hosting. Rely on our own host/client flags instead.
	return _hosting_active or _connected_as_client


func _refresh_select_ui() -> void:
	var grid_enabled := _is_selection_open()
	var p1_active := grid_enabled
	var p2_active := _client_peer_id > 0 or _connected_as_client
	var local_player := _local_player_id()
	var p1_hover_visible := p1_active and (bool(_locked_by_player[1]) or (_focus == FocusTarget.GRID and local_player == 1) or (multiplayer.has_multiplayer_peer() and local_player == 2))
	var p2_hover_visible := p2_active and (bool(_locked_by_player[2]) or (_focus == FocusTarget.GRID and local_player == 2) or (multiplayer.has_multiplayer_peer() and local_player == 1))
	for index in range(_card_panels.size()):
		var panel := _card_panels[index]
		var p1_here := p1_active and (int(_selected_by_player[1]) == index or (p1_hover_visible and int(_hover_by_player[1]) == index))
		var p2_here := p2_active and (int(_selected_by_player[2]) == index or (p2_hover_visible and int(_hover_by_player[2]) == index))
		var border := CARD_BORDER
		var width := 3
		if _focus == FocusTarget.GRID and grid_enabled and int(_hover_by_player[_local_player_id()]) == index:
			border = CARD_BORDER_FOCUS
			width = 6
		elif p1_here and p2_here:
			border = BOTH_COLOR
			width = 6
		elif p1_here:
			border = P1_COLOR
			width = 6
		elif p2_here:
			border = P2_COLOR
			width = 6
		var fill := CARD_FILL if grid_enabled else CARD_FILL_IDLE
		panel.add_theme_stylebox_override("panel", _card_style(fill, border, width))

		_card_p1_badges[index].visible = p1_here
		_card_p2_badges[index].visible = p2_here
		_card_p1_badges[index].text = "P1✓" if bool(_locked_by_player[1]) and int(_selected_by_player[1]) == index else "P1"
		_card_p2_badges[index].text = "P2✓" if bool(_locked_by_player[2]) and int(_selected_by_player[2]) == index else "P2"

	var controls_locked := _hosting_active or _connected_as_client
	_start_button.disabled = controls_locked
	_join_button.disabled = controls_locked
	_code_edit.editable = not controls_locked
	if not _code_edit.editable and _code_edit.has_focus():
		_code_edit.release_focus()
	_start_button.add_theme_stylebox_override("normal", _button_style(_focus == FocusTarget.START and not _start_button.disabled))
	_start_button.add_theme_stylebox_override("hover", _button_style(true))
	_start_button.add_theme_stylebox_override("pressed", _button_style(true))
	_start_button.add_theme_stylebox_override("disabled", _button_style(_focus == FocusTarget.START, true))
	_join_button.add_theme_stylebox_override("normal", _button_style(_focus == FocusTarget.JOIN and not _join_button.disabled))
	_join_button.add_theme_stylebox_override("hover", _button_style(true))
	_join_button.add_theme_stylebox_override("pressed", _button_style(true))
	_join_button.add_theme_stylebox_override("disabled", _button_style(_focus == FocusTarget.JOIN, true))

	if not grid_enabled:
		_host_code_label.text = "ENTER CODE TO JOIN"
	elif grid_enabled and _client_peer_id <= 0 and multiplayer.is_server():
		var host_code := _ip_to_join_code(_guess_lan_ip())
		if _code_edit.text != host_code:
			_code_edit.text = host_code
		_host_code_label.text = "SHARE THIS CODE"
	elif grid_enabled and multiplayer.is_server():
		_host_code_label.text = "PLAYER 2 CONNECTED"
	elif _connected_as_client:
		_host_code_label.text = "CONNECTED AS PLAYER 2"


func _button_style(selected: bool, disabled := false) -> StyleBoxFlat:
	if disabled:
		if selected:
			return _panel_style(Color(0.30, 0.07, 0.06, 1.0), Color(1.0, 0.88, 0.40, 1.0), 4, 10)
		return _panel_style(Color(0.16, 0.05, 0.05, 1.0), Color(0.45, 0.18, 0.16, 1.0), 2, 10)
	if selected:
		return _panel_style(Color(0.86, 0.20, 0.16, 1.0), Color(1.0, 0.90, 0.45, 1.0), 5, 10)
	return _panel_style(Color(0.58, 0.14, 0.12, 1.0), Color(0.92, 0.34, 0.28, 1.0), 3, 10)


func _host_lan_game() -> void:
	_close_multiplayer_peer()
	_client_peer_id = 0
	_hosting_active = false
	_connected_as_client = false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(LAN_PORT, 1)
	if error != OK:
		_set_status("Host failed: %s" % error_string(error))
		return

	multiplayer.multiplayer_peer = peer
	_hosting_active = true
	_connected_as_client = false
	_reset_lobby_state()
	_configure_players_for_selection()
	_start_host_discovery()
	var host_ip := _guess_lan_ip()
	_focus = FocusTarget.GRID
	_code_edit.text = _ip_to_join_code(host_ip)
	_host_code_label.text = "GIVE THIS CODE TO PLAYER 2"
	_set_status("Waiting for Player 2. You can choose now.")
	_broadcast_lobby_state("Waiting for Player 2. You can choose now.")


func _join_lan_game() -> void:
	_stop_host_discovery()
	_stop_join_discovery()
	var host_ip := _parse_join_address(_code_edit.text)
	if host_ip == "":
		_code_edit.grab_focus()
		_set_status("Enter host code.")
		return

	_close_multiplayer_peer()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_ip, LAN_PORT)
	if error != OK:
		_set_status("Join failed: %s" % error_string(error))
		return

	multiplayer.multiplayer_peer = peer
	_pending_join_ip = host_ip
	_join_timeout_timer = JOIN_TIMEOUT_TIME
	_set_status("Joining %s:%d..." % [host_ip, LAN_PORT])


func _close_multiplayer_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_join_timeout_timer = 0.0
	_pending_join_ip = ""
	_client_peer_id = 0
	_hosting_active = false
	_connected_as_client = false


func _reset_lobby_state() -> void:
	_hover_by_player[1] = 0
	_hover_by_player[2] = 0
	_locked_by_player[1] = false
	_locked_by_player[2] = false
	_selected_by_player[1] = -1
	_selected_by_player[2] = -1


func _start_host_discovery() -> void:
	_stop_host_discovery()
	_host_discovery_peer = PacketPeerUDP.new()
	var error := _host_discovery_peer.bind(DISCOVERY_PORT)
	if error != OK:
		_set_status("Hosting, but discovery failed: %s. Friend can still type %s." % [error_string(error), _ip_to_join_code(_guess_lan_ip())])
		_stop_host_discovery()
		return
	_host_discovery_peer.set_broadcast_enabled(true)


func _stop_host_discovery() -> void:
	if _host_discovery_peer != null:
		_host_discovery_peer.close()
		_host_discovery_peer = null


func _stop_join_discovery() -> void:
	if _join_discovery_peer != null:
		_join_discovery_peer.close()
		_join_discovery_peer = null
	_discovery_attempts_left = 0
	_discovery_timer = 0.0


func _process_lan_discovery(delta: float) -> void:
	_process_host_discovery()
	_process_join_discovery(delta)


func _process_join_timeout(delta: float) -> void:
	if _join_timeout_timer <= 0.0:
		return
	if multiplayer.multiplayer_peer == null:
		_join_timeout_timer = 0.0
		_pending_join_ip = ""
		return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_join_timeout_timer = 0.0
		_pending_join_ip = ""
		return

	_join_timeout_timer -= delta
	if _join_timeout_timer > 0.0:
		return

	var failed_ip := _pending_join_ip
	_close_multiplayer_peer()
	_configure_players_for_selection()
	_reset_match()
	_show_select_screen("Join timed out to %s. Check code, WiFi, and firewall UDP %d." % [failed_ip, LAN_PORT])


func _process_host_discovery() -> void:
	if _host_discovery_peer == null:
		return

	while _host_discovery_peer.get_available_packet_count() > 0:
		var packet_text := _host_discovery_peer.get_packet().get_string_from_utf8()
		if packet_text != DISCOVERY_REQUEST:
			continue
		var requester_ip := _host_discovery_peer.get_packet_ip()
		var requester_port := _host_discovery_peer.get_packet_port()
		_host_discovery_peer.set_dest_address(requester_ip, requester_port)
		_host_discovery_peer.put_packet(("%s%d" % [DISCOVERY_RESPONSE_PREFIX, LAN_PORT]).to_utf8_buffer())


func _process_join_discovery(delta: float) -> void:
	if _join_discovery_peer == null:
		return

	while _join_discovery_peer.get_available_packet_count() > 0:
		var packet_text := _join_discovery_peer.get_packet().get_string_from_utf8()
		if not packet_text.begins_with(DISCOVERY_RESPONSE_PREFIX):
			continue
		var host_ip := _join_discovery_peer.get_packet_ip()
		_code_edit.text = host_ip
		_stop_join_discovery()
		_set_status("Found host at %s. Joining..." % host_ip)
		_join_lan_game()
		return

	if _discovery_attempts_left <= 0:
		_stop_join_discovery()
		_set_status("No host found.")
		return

	_discovery_timer -= delta
	if _discovery_timer <= 0.0:
		_send_discovery_request()


func _send_discovery_request() -> void:
	if _join_discovery_peer == null or _discovery_attempts_left <= 0:
		return

	_discovery_attempts_left -= 1
	_discovery_timer = 0.45
	for address in _broadcast_addresses():
		_join_discovery_peer.set_dest_address(address, DISCOVERY_PORT)
		_join_discovery_peer.put_packet(DISCOVERY_REQUEST.to_utf8_buffer())


func _broadcast_addresses() -> Array[String]:
	var addresses: Array[String] = ["255.255.255.255"]
	for address in IP.get_local_addresses():
		if not _is_private_ipv4(address):
			continue
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		var broadcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not addresses.has(broadcast):
			addresses.append(broadcast)
	return addresses


func _parse_join_address(raw_text: String) -> String:
	var address := raw_text.strip_edges()
	if address == "":
		return ""

	var code_ip := _join_code_to_ip(address)
	if code_ip != "":
		return code_ip

	if address.begins_with("http://") or address.begins_with("https://"):
		address = address.get_slice("://", 1)

	address = address.strip_edges()
	if address.contains("/"):
		address = address.get_slice("/", 0)
	if address.contains(":"):
		address = address.get_slice(":", 0)

	return address.strip_edges()


func _ip_to_join_code(address: String) -> String:
	var parts := address.split(".")
	if parts.size() != 4:
		return "NO-CODE"

	var value := 0
	for part in parts:
		var octet := int(part)
		if octet < 0 or octet > 255:
			return "NO-CODE"
		value = value * 256 + octet

	var code := ""
	for index in range(7):
		var alphabet_index := value % JOIN_CODE_ALPHABET.length()
		code = JOIN_CODE_ALPHABET[alphabet_index] + code
		value = int(value / JOIN_CODE_ALPHABET.length())

	return "%s-%s" % [code.substr(0, 3), code.substr(3, 4)]


func _join_code_to_ip(raw_code: String) -> String:
	var code := raw_code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	code = code.replace("0", "O").replace("1", "I")
	if code.length() != 7:
		return ""

	var value := 0
	for index in range(code.length()):
		var alphabet_index := JOIN_CODE_ALPHABET.find(code[index])
		if alphabet_index < 0:
			return ""
		value = value * JOIN_CODE_ALPHABET.length() + alphabet_index

	var octets: Array[int] = []
	for index in range(4):
		octets.push_front(value % 256)
		value = int(value / 256)

	if value != 0:
		return ""

	var address := "%d.%d.%d.%d" % [octets[0], octets[1], octets[2], octets[3]]
	return address if _is_private_ipv4(address) else ""


func _configure_players_for_lan(client_peer_id := 0) -> void:
	_client_peer_id = _resolve_client_peer_id(client_peer_id)
	_configure_common_player_settings(_client_peer_id)
	player_one.set("accept_local_input", true)
	player_two.set("accept_local_input", true)
	player_one.set("bot_enabled", false)
	player_two.set("bot_enabled", false)


func _configure_players_for_selection() -> void:
	_configure_common_player_settings(_resolve_client_peer_id(_client_peer_id))
	player_one.set("accept_local_input", false)
	player_two.set("accept_local_input", false)
	player_one.set("bot_enabled", false)
	player_two.set("bot_enabled", false)


func _configure_common_player_settings(client_peer_id: int) -> void:
	player_one.set("opponent_path", player_one.get_path_to(player_two))
	player_two.set("opponent_path", player_two.get_path_to(player_one))
	player_one.set_multiplayer_authority(1)
	player_two.set_multiplayer_authority(client_peer_id)


func _resolve_client_peer_id(client_peer_id: int) -> int:
	if client_peer_id > 0:
		return client_peer_id
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return multiplayer.get_unique_id()
	if _client_peer_id > 0:
		return _client_peer_id
	return 2


func _reset_match() -> void:
	_clear_special_effects()
	player_one.call("reset_fighter", PLAYER_ONE_START)
	player_two.call("reset_fighter", PLAYER_TWO_START)
	_refresh_health_hud()


func _clear_special_effects() -> void:
	# Remove any in-flight horns / splashes / gusts left over from the last round.
	for node in get_tree().get_nodes_in_group("special_effects"):
		node.queue_free()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_client_peer_id = peer_id
		_configure_players_for_selection()
		_locked_by_player[2] = false
		_selected_by_player[2] = -1
		_set_status("Player 2 joined. Waiting for selections.")
		_broadcast_lobby_state("Player 2 joined. Waiting for selections.")


func _on_peer_disconnected(peer_id: int) -> void:
	if _fight_mode:
		_return_to_lobby_scene()
		return
	if multiplayer.is_server():
		if peer_id == _client_peer_id:
			_client_peer_id = 0
			_locked_by_player[2] = false
			_selected_by_player[2] = -1
		_show_select_screen("Player %d disconnected. Waiting for another player." % peer_id)
		_broadcast_lobby_state("Player %d disconnected. Waiting for another player." % peer_id)


func _on_connected_to_server() -> void:
	_stop_host_discovery()
	_stop_join_discovery()
	_join_timeout_timer = 0.0
	_pending_join_ip = ""
	_connected_as_client = true
	_hosting_active = false
	_client_peer_id = multiplayer.get_unique_id()
	_configure_players_for_selection()
	_focus = FocusTarget.GRID
	_show_select_screen("Connected. Choose Player 2.")
	_rpc_request_lobby_state.rpc_id(1)
	_submit_local_selection(false)


func _on_connection_failed() -> void:
	_close_multiplayer_peer()
	_stop_host_discovery()
	_stop_join_discovery()
	_configure_players_for_selection()
	_reset_match()
	_show_select_screen("Connection failed. Check code, WiFi, and firewall UDP %d." % LAN_PORT)


func _on_server_disconnected() -> void:
	if _fight_mode:
		_return_to_lobby_scene()
		return
	_close_multiplayer_peer()
	_stop_host_discovery()
	_stop_join_discovery()
	_configure_players_for_selection()
	_reset_match()
	_show_select_screen("Disconnected from host.")


func _on_player_one_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(_p1_health_bar, _p1_health_text, current_health, max_health)


func _on_player_two_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(_p2_health_bar, _p2_health_text, current_health, max_health)


func _refresh_health_hud() -> void:
	if _p1_health_bar == null or _p2_health_bar == null:
		return
	_on_player_one_health_changed(int(player_one.get("health")), int(player_one.get("max_health")))
	_on_player_two_health_changed(int(player_two.get("health")), int(player_two.get("max_health")))


func _update_health_bar(bar: ProgressBar, text_label: Label, current_health: int, max_health: int) -> void:
	if bar == null or text_label == null:
		return
	var safe_max := maxi(max_health, 1)
	var safe_current := clampi(current_health, 0, safe_max)
	bar.max_value = float(safe_max)
	bar.value = float(safe_current)
	text_label.text = "%d/%d" % [safe_current, safe_max]


func _update_camera() -> void:
	_update_fighting_camera(camera, player_one.global_position.x, player_two.global_position.x)


# Shared fighting-game camera: zoom to keep both fighters framed, follow their
# midpoint, and clamp the view to the stage walls so it can't scroll past them.
static func _update_fighting_camera(cam: Camera2D, p1x: float, p2x: float) -> void:
	var sep := absf(p2x - p1x)
	var target_zoom := clampf(CAM_VIEW_W / (sep + CAM_MARGIN), CAM_MIN_ZOOM, CAM_MAX_ZOOM)
	var z := lerpf(cam.zoom.x, target_zoom, CAM_LERP)
	cam.zoom = Vector2(z, z)
	var half_view := (CAM_VIEW_W / z) * 0.5
	var center_x := (p1x + p2x) * 0.5
	var min_x := -CAM_STAGE_HALF + half_view
	var max_x := CAM_STAGE_HALF - half_view
	var target_x := clampf(center_x, min_x, max_x) if min_x <= max_x else 0.0
	cam.global_position = Vector2(lerpf(cam.global_position.x, target_x, CAM_LERP), CAM_Y)


func _refresh_special_hud() -> void:
	_update_special_label(_p1_special_label, player_one)
	_update_special_label(_p2_special_label, player_two)


func _update_special_label(label: Label, player: Node2D) -> void:
	if label == null or player == null:
		return
	if not bool(player.call("has_special")):
		label.text = ""
		return
	var remaining: float = float(player.call("get_special_cooldown_remaining"))
	if remaining <= 0.0:
		label.text = "SP: READY"
		label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.30, 1.0))
	else:
		label.text = "SP: %ds" % int(ceil(remaining))
		label.add_theme_color_override("font_color", Color(0.66, 0.68, 0.72, 1.0))


func _handle_debug_reset() -> void:
	var reset_pressed := Input.is_physical_key_pressed(KEY_R)
	if reset_pressed and not _reset_down and _screen == ScreenState.MATCH:
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_rpc_start_match.rpc(_client_peer_id, int(_resolved_character_by_player[1]), int(_resolved_character_by_player[2]))
			_start_match(_client_peer_id, int(_resolved_character_by_player[1]), int(_resolved_character_by_player[2]))
		elif not multiplayer.has_multiplayer_peer():
			_reset_match()
	_reset_down = reset_pressed


func _local_player_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 1
	return 1 if multiplayer.get_unique_id() == 1 else 2


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _guess_lan_ip() -> String:
	for address in IP.get_local_addresses():
		if _is_private_ipv4(address):
			return address
	return "127.0.0.1"


func _is_private_ipv4(address: String) -> bool:
	if address.begins_with("192.168.") or address.begins_with("10.") or _is_private_172_address(address):
		return true
	return false


func _is_private_172_address(address: String) -> bool:
	if not address.begins_with("172."):
		return false
	var parts := address.split(".")
	if parts.size() < 2:
		return false
	var second_part := int(parts[1])
	return second_part >= 16 and second_part <= 31
