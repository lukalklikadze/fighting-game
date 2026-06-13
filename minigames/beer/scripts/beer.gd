extends Control
## Online 2-player Beer Pour minigame.
##
## Split screen: LEFT panel is the local player, RIGHT panel is the remote
## opponent. Beer pours into each cup over time; press SPACE to stop. Get as
## close to the brim (fill == 1.0) as possible WITHOUT spilling (fill > 1.0).
## The closer clean pour wins; any spill loses to any clean pour. WINNER / LOSER
## (or DRAW) is shown on each side — same interface as the typeracer minigame.

const PORT := 9999

const MAX_FLOW := 0.35     # max pour speed (fill per second) while holding
const POUR_ACCEL := 1.2    # how fast the flow ramps up while held
const POUR_DECEL := 0.9    # how fast the flow eases off after release (momentum)
const SPILL_LIMIT := 1.30  # the cup fully spills here
const FOAM_ZONE   := 0.02  # tiny grace margin above the brim before it counts as a spill

# Accent colors (panel headers, WINNER/LOSER/DRAW messages).
const COL_WIN := "#3ddc84"
const COL_LOSE := "#ff5555"
const COL_DRAW := "#ffd166"
const COL_HEADER_OPP := "#c2cad6"

# --- Game state -------------------------------------------------------------
var fill := 0.0          # local cup fill (1.0 == brim)
var velocity := 0.0      # current pour speed (eases up while held, down on release)
var started := false     # has the local player begun pouring?
var releasing := false   # has the player let go (pour now easing to a stop)?
var stopped := false     # has the local pour fully come to rest (locked)?
var finished := false    # is the match over?
var game_active := false

var opp_fill := 0.0      # opponent's fill (synced, or bot-driven)
var opp_velocity := 0.0  # bot pour speed (solo)
var opp_releasing := false
var opp_stopped := false

# --- Solo practice mode -----------------------------------------------------
var solo := false
var bot_target := 0.9    # the fill the bot tries to stop at

# Host-side bookkeeping for deciding the winner.
var _finals := {}

# Handwriting-style font (emboldened, chubby), shared with the theme.
var hand_font: Font

# --- Node references --------------------------------------------------------
var game_ui: Control
var you_cup: Control
var opp_cup: Control
var you_pct: Label
var opp_pct: Label
var result_label: Label
var you_result: Label
var opp_result: Label

const Cup := preload("res://minigames/beer/scripts/cup.gd")
const BarBackground := preload("res://minigames/beer/scripts/bar_background.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Handwritten, chubby font for all text.
	var base_font := SystemFont.new()
	base_font.font_names = PackedStringArray([
		"Marker Felt", "Chalkboard SE", "Noteworthy", "Bradley Hand",
		"Segoe Script", "Comic Sans MS", "Comic Sans MS",
	])
	var chubby := FontVariation.new()
	chubby.base_font = base_font
	chubby.variation_embolden = 0.6
	hand_font = chubby
	var hand_theme := Theme.new()
	hand_theme.default_font = hand_font
	theme = hand_theme

	# Pub background behind everything.
	add_child(BarBackground.new())

	_build_game_ui()
	result_label.visible = false

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# No menu — drop straight into a match (solo vs a bot).
	_on_solo_pressed()


# ===========================================================================
#  Connection (multiplayer entry points kept for real 2-player play)
# ===========================================================================

func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 1) != OK:
		return
	multiplayer.multiplayer_peer = peer


func join(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		return
	multiplayer.multiplayer_peer = peer


func _on_peer_connected(_id: int) -> void:
	if multiplayer.is_server():
		start_game.rpc()


func _on_peer_disconnected(_id: int) -> void:
	game_active = false


# ===========================================================================
#  Match flow
# ===========================================================================

@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	_begin_match()


func _on_solo_pressed() -> void:
	solo = true
	_begin_match()


func _begin_match() -> void:
	fill = 0.0
	velocity = 0.0
	started = false
	releasing = false
	stopped = false
	finished = false
	opp_fill = 0.0
	opp_velocity = 0.0
	opp_releasing = false
	opp_stopped = false
	bot_target = randf_range(0.82, 0.99)
	_finals = {}
	game_active = false
	game_ui.visible = true
	you_result.get_parent().visible = false
	opp_result.get_parent().visible = false
	_render_you()
	_render_opponent()

	for n in [3, 2, 1]:
		result_label.text = str(n)
		result_label.add_theme_color_override("font_color", Color("#ffffff"))
		result_label.visible = true
		await get_tree().create_timer(1.0).timeout
	result_label.text = "POUR!"
	result_label.add_theme_color_override("font_color", Color(COL_WIN))
	await get_tree().create_timer(0.5).timeout
	result_label.visible = false
	game_active = true


func _process(delta: float) -> void:
	if not game_active or finished:
		return

	# Hold Space/Enter to pour; release to ease the flow smoothly to a stop.
	if not stopped:
		var holding := not releasing and (
			Input.is_key_pressed(KEY_SPACE)
			or Input.is_key_pressed(KEY_ENTER)
			or Input.is_key_pressed(KEY_KP_ENTER))
		if holding:
			started = true
			velocity = move_toward(velocity, MAX_FLOW, POUR_ACCEL * delta)
		else:
			if started:
				releasing = true # let go: pour now coasts to a stop
			velocity = move_toward(velocity, 0.0, POUR_DECEL * delta)

		fill += velocity * delta
		if fill >= SPILL_LIMIT:
			fill = SPILL_LIMIT
			_lock()
		elif releasing and velocity <= 0.0001:
			_lock()

		_render_you()
		if not solo:
			update_fill.rpc(fill, stopped)

	# Solo: drive the bot (it pours, then releases so its momentum lands near
	# its target), then resolve once both cups have come to rest.
	if solo:
		if not opp_stopped:
			var stop_dist := (opp_velocity * opp_velocity) / (2.0 * POUR_DECEL)
			if not opp_releasing and opp_fill + stop_dist >= bot_target:
				opp_releasing = true
			if opp_releasing:
				opp_velocity = move_toward(opp_velocity, 0.0, POUR_DECEL * delta)
			else:
				opp_velocity = move_toward(opp_velocity, MAX_FLOW, POUR_ACCEL * delta)
			opp_fill += opp_velocity * delta
			if opp_fill >= SPILL_LIMIT:
				opp_fill = SPILL_LIMIT
				opp_stopped = true
			elif opp_releasing and opp_velocity <= 0.0001:
				opp_stopped = true
			_render_opponent()
		if stopped and opp_stopped and not finished:
			_resolve_solo()


func _lock() -> void:
	if stopped:
		return
	stopped = true
	_render_you()
	if not solo:
		update_fill.rpc(fill, true)
		report_stopped.rpc(fill)
	# Solo resolution happens in _process once the bot has also stopped.


# Local player keeps the opponent's cup up to date.
@rpc("any_peer", "unreliable_ordered")
func update_fill(f: float, s: bool) -> void:
	opp_fill = f
	opp_stopped = s
	_render_opponent()


# Each player reports their final fill; the host decides the winner.
@rpc("any_peer", "call_local", "reliable")
func report_stopped(f: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_finals[sender] = f
	if _finals.size() >= 2:
		var ids := _finals.keys()
		var sa := _score(_finals[ids[0]])
		var sb := _score(_finals[ids[1]])
		var winner := 0 # 0 == draw
		if abs(sa - sb) >= 0.0005:
			winner = ids[0] if sa < sb else ids[1]
		set_result.rpc(winner)


@rpc("authority", "call_local", "reliable")
func set_result(winner_id: int) -> void:
	if winner_id == 0:
		_show_outcome("DRAW", "DRAW")
	else:
		var won := winner_id == multiplayer.get_unique_id()
		_show_outcome("WINNER" if won else "LOSER", "LOSER" if won else "WINNER")


func _resolve_solo() -> void:
	_show_outcome(_outcome(fill, opp_fill), _outcome(opp_fill, fill))


# ===========================================================================
#  Scoring / results
# ===========================================================================

# Distance from a perfect pour (lower is better). Any spill (>1.0) ranks below
# every clean pour; among spills, the smaller overflow is better.
func _score(f: float) -> float:
	if f <= 1.0 + FOAM_ZONE:
		return abs(1.0 - f)            # 0 = perfect brim; foam zone scores slightly worse but not a spill
	return 1.0 + FOAM_ZONE + (f - 1.0 - FOAM_ZONE)  # real spill — heavily penalised


func _outcome(mine: float, other: float) -> String:
	var sm := _score(mine)
	var so := _score(other)
	if abs(sm - so) < 0.0005:
		return "DRAW"
	return "WINNER" if sm < so else "LOSER"


func _show_outcome(you_text: String, opp_text: String) -> void:
	game_active = false
	finished = true
	result_label.visible = false
	_set_panel_result(you_result, you_text)
	_set_panel_result(opp_result, opp_text)
	if you_text == "DRAW":
		_restart_on_draw()


func _restart_on_draw() -> void:
	await get_tree().create_timer(2.0).timeout
	_begin_match()


func _set_panel_result(label: Label, text: String) -> void:
	label.text = text
	var col := COL_DRAW
	if text == "WINNER":
		col = COL_WIN
	elif text == "LOSER":
		col = COL_LOSE
	label.add_theme_color_override("font_color", Color(col))
	label.get_parent().visible = true # the transparent wrapper


# ===========================================================================
#  Rendering
# ===========================================================================

func _render_you() -> void:
	you_cup.set_fill(fill)
	you_pct.text = _fill_text(fill)


func _render_opponent() -> void:
	opp_cup.set_fill(opp_fill)
	opp_pct.text = _fill_text(opp_fill)


func _fill_text(f: float) -> String:
	if f > 1.0 + FOAM_ZONE:
		return "SPILLED!"
	return "%d%%" % roundi(minf(f, 1.0) * 100.0)


# ===========================================================================
#  UI construction
# ===========================================================================

func _build_game_ui() -> void:
	game_ui = Control.new()
	game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_ui)

	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 0)
	game_ui.add_child(split)

	var you_panel := _make_panel("YOU", true)
	split.add_child(you_panel[0])
	you_cup = you_panel[1]
	you_pct = you_panel[2]
	you_result = you_panel[3]

	var opp_panel := _make_panel("OPPONENT", false)
	split.add_child(opp_panel[0])
	opp_cup = opp_panel[1]
	opp_pct = opp_panel[2]
	opp_result = opp_panel[3]

	# Countdown overlay (3-2-1-POUR), centered across the whole screen.
	result_label = Label.new()
	result_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 96)
	game_ui.add_child(result_label)


# Returns [panel_root, cup, percent_label, result_label].
func _make_panel(header: String, is_you: bool) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Transparent panel so the bar background shows through.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)

	var inner := Control.new()
	panel.add_child(inner)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 14)
	inner.add_child(col)

	var head := Label.new()
	head.text = header
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 28)
	head.add_theme_color_override("font_color", Color(COL_WIN) if is_you else Color(COL_HEADER_OPP))
	head.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	head.add_theme_constant_override("outline_size", 5)
	col.add_child(head)

	var cup := Cup.new()
	cup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cup.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cup)

	var pct := Label.new()
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct.add_theme_font_size_override("font_size", 30)
	pct.add_theme_color_override("font_color", Color("#ffffff"))
	pct.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	pct.add_theme_constant_override("outline_size", 6)
	col.add_child(pct)

	# Per-panel WINNER/LOSER/DRAW overlay, centered over this side.
	var overlay := CenterContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(overlay)

	var result_box := PanelContainer.new()
	result_box.visible = false
	result_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	overlay.add_child(result_box)

	var result := Label.new()
	result.add_theme_font_size_override("font_size", 80)
	result.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	result.add_theme_constant_override("outline_size", 12)
	result_box.add_child(result)

	return [panel, cup, pct, result]
