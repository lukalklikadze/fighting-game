extends Control
## Online 2-player Typeracer minigame.
##
## Split screen: the LEFT panel is the local player, the RIGHT panel is the
## remote opponent. Both peers load the same scene and connect over ENet.
## The host picks the sentence and hands it to the client, then both race to
## type it. Each correctly typed character turns green, a wrong key turns the
## current character red. First to finish wins.

const PORT := 9999

# Sentences the host can pick from. Kept short so a race resolves quickly.
const SENTENCES := [
	"the quick brown fox jumps over the lazy dog",
	"pack my box with five dozen liquor jugs",
	"sphinx of black quartz judge my vow",
	"how vexingly quick daft zebras jump",
	"the five boxing wizards jump quickly",
	"bright vixens jump dozy fowl quack",
]

# Accent colors (panel borders, headers, WINNER/LOSER messages).
const COL_DONE := "#3ddc84"    # green accent
const COL_ERROR := "#ff5555"   # red accent

# Typing text — referee white: faint while untyped, bold white once typed.
const TXT_TODO := "#ffffff70"  # not yet typed -> lighter (semi-transparent) white
const TXT_DONE := "#ffffff"    # correctly typed -> solid white (also bold)
const TXT_ERROR := "#ff5555"   # wrong key on the current char -> red
const COL_CURSOR_BG := "#ffffff33" # subtle highlight behind the current char

const COL_HEADER_OPP := "#c2cad6"

# --- Game state -------------------------------------------------------------
var target := ""        # the sentence both players type
var cursor := 0         # number of characters typed correctly so far (local)
var error := false      # is the current local character mis-keyed?
var finished := false   # has the local player completed the sentence?
var game_active := false

var opp_cursor := 0     # opponent's progress (synced, or driven by the bot)
var opp_error := false  # opponent's current-char error state (synced)
var opp_finished := false   # has the opponent finished?

# --- Solo practice mode -----------------------------------------------------
var solo := false           # playing alone vs a bot (no networking)
const BOT_SPEED := 3.5       # bot typing speed in characters per second
var bot_progress := 0.0      # fractional char count the bot has "typed"

# --- Embedded mode (launched as a "super" by the fight controller) ----------
signal minigame_finished(result: int)  # 1 = local won, 0 = local lost, -1 = draw
var embedded := false
var _result_emitted := false

# --- Multiplayer draw detection ---------------------------------------------
var _finishers: Array[int] = []  # peer IDs that have reported finished (host only)

# Handwriting-style font pulled from the OS (with fallbacks across platforms),
# emboldened for a chubby look.
var hand_font: Font

# --- Node references (built in code) ---------------------------------------
var connect_ui: Control
var status_label: Label
var ip_input: LineEdit
var game_ui: Control
var you_label: RichTextLabel
var opp_label: RichTextLabel
var you_progress: Label
var opp_progress: Label
var result_label: Label   # centered countdown (3-2-1-GO)
var you_result: Label     # WINNER/LOSER over the player's panel
var opp_result: Label     # WINNER/LOSER over the opponent's panel


const PitchBackground := preload("res://minigames/typeracer/scripts/pitch_background.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Handwritten look: a casual/handwriting font from the OS, emboldened so the
	# strokes look thick and chubby.
	var base_font := SystemFont.new()
	base_font.font_names = PackedStringArray([
		"Marker Felt", "Chalkboard SE", "Noteworthy", "Bradley Hand",
		"Segoe Script", "Comic Sans MS", "Comic Sans MS",
	])
	var chubby := FontVariation.new()
	chubby.base_font = base_font
	chubby.variation_embolden = 0.6 # thicker strokes
	hand_font = chubby

	var hand_theme := Theme.new()
	hand_theme.default_font = hand_font
	theme = hand_theme

	# Football-pitch background, drawn behind everything else.
	add_child(PitchBackground.new())

	_build_game_ui()
	result_label.visible = false

	# No menu — drop straight into a match (unless the fight controller drives us).
	if not embedded:
		_on_solo_pressed()


# Public entry point used by the fight controller for an embedded super.
func begin_solo() -> void:
	_on_solo_pressed()


func _emit_embedded_result(result: int) -> void:
	if _result_emitted:
		return
	_result_emitted = true
	await get_tree().create_timer(1.1).timeout  # let WINNER/LOSER show briefly
	minigame_finished.emit(result)


# ===========================================================================
#  Connection
# ===========================================================================

func _on_host_pressed() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		status_label.text = "Could not host (error %d). Port in use?" % err
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Hosting on port %d — waiting for opponent..." % PORT


func _on_join_pressed() -> void:
	var ip := ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		status_label.text = "Could not connect (error %d)." % err
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to %s..." % ip


func _on_peer_connected(_id: int) -> void:
	# Only the host reacts: choose the sentence and start the match for both.
	if multiplayer.is_server():
		var text: String = SENTENCES[randi() % SENTENCES.size()]
		start_game.rpc(text)


func _on_peer_disconnected(_id: int) -> void:
	if not finished:
		status_label.text = "Opponent disconnected."
	game_active = false


func _on_connected_to_server() -> void:
	status_label.text = "Connected — waiting for the host to start..."


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the IP and that the host is running."
	multiplayer.multiplayer_peer = null


# ===========================================================================
#  Match flow (RPCs)
# ===========================================================================

# Host hands the sentence to everyone (including itself) and starts the match.
@rpc("authority", "call_local", "reliable")
func start_game(text: String) -> void:
	_begin_match(text)


# Start the solo practice match against the bot (no networking).
func _on_solo_pressed() -> void:
	solo = true
	_begin_match(SENTENCES[randi() % SENTENCES.size()])


# Shared match setup: reset state, run a synced 3-2-1-GO countdown, then race.
# Both peers run this locally at nearly the same time, so the countdown stays
# in sync without extra messages.
func _begin_match(text: String) -> void:
	target = text
	cursor = 0
	error = false
	finished = false
	opp_cursor = 0
	opp_error = false
	opp_finished = false
	bot_progress = 0.0
	_finishers = []
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
	result_label.text = "GO!"
	result_label.add_theme_color_override("font_color", Color(COL_DONE))
	await get_tree().create_timer(0.5).timeout
	result_label.visible = false
	game_active = true


# Drives the bot opponent in solo mode.
func _process(delta: float) -> void:
	if not solo or not game_active or opp_finished:
		return
	bot_progress += delta * BOT_SPEED
	opp_cursor = min(int(bot_progress), target.length())
	_render_opponent()
	if opp_cursor >= target.length():
		opp_finished = true
		if finished:
			_show_draw()  # both finished in the same frame
		else:
			_show_result(false)  # bot finished first


func _show_result(won: bool) -> void:
	game_active = false
	result_label.visible = false
	you_label.text = ""
	opp_label.text = ""
	you_progress.text = ""
	opp_progress.text = ""
	_set_panel_result(you_result, won)
	_set_panel_result(opp_result, not won)
	if embedded:
		_emit_embedded_result(1 if won else 0)


func _show_draw() -> void:
	game_active = false
	result_label.visible = false
	you_label.text = ""
	opp_label.text = ""
	you_progress.text = ""
	opp_progress.text = ""
	for lbl in [you_result, opp_result]:
		lbl.text = "DRAW"
		lbl.add_theme_color_override("font_color", Color("#ffd166"))
		lbl.get_parent().visible = true
	if embedded:
		_emit_embedded_result(-1)
	else:
		_restart_on_draw()


func _restart_on_draw() -> void:
	await get_tree().create_timer(2.0).timeout
	if solo:
		_begin_match(SENTENCES[randi() % SENTENCES.size()])
	elif multiplayer.is_server():
		start_game.rpc(SENTENCES[randi() % SENTENCES.size()])


func _set_panel_result(label: Label, is_winner: bool) -> void:
	label.text = "WINNER" if is_winner else "LOSER"
	label.add_theme_color_override("font_color", Color(COL_DONE) if is_winner else Color(COL_ERROR))
	label.get_parent().visible = true


# Local player keeps the opponent's panel up to date with their progress.
@rpc("any_peer", "unreliable_ordered")
func update_progress(c: int, e: bool) -> void:
	opp_cursor = c
	opp_error = e
	_render_opponent()


# A player tells the host they finished. Simultaneous finishes → draw.
@rpc("any_peer", "call_local", "reliable")
func report_finished() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender not in _finishers:
		_finishers.append(sender)
	if _finishers.size() == 1:
		# Wait one frame — if the other peer also finishes this frame it's a draw.
		_announce_winner.call_deferred()


func _announce_winner() -> void:
	if _finishers.size() >= 2:
		set_result.rpc(0)  # draw
	else:
		set_result.rpc(_finishers[0])


# Host announces the result to everyone (winner_id == 0 means draw).
@rpc("authority", "call_local", "reliable")
func set_result(winner_id: int) -> void:
	if winner_id == 0:
		_show_draw()
	else:
		_show_result(winner_id == multiplayer.get_unique_id())


# ===========================================================================
#  Typing input
# ===========================================================================

func _input(event: InputEvent) -> void:
	if not game_active or finished:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var key := event as InputEventKey

	# Backspace steps back over a correctly typed character.
	if key.keycode == KEY_BACKSPACE:
		if error:
			error = false
		elif cursor > 0:
			cursor -= 1
		_after_local_change()
		return

	var ch := char(key.unicode)
	if key.unicode == 0 or ch == "":
		return # not a printable character (shift, ctrl, arrows, etc.)

	var expected := target.substr(cursor, 1)
	if ch == expected:
		cursor += 1
		error = false
		if cursor >= target.length():
			finished = true
			_render_you()
			if solo:
				if opp_finished:
					_show_draw()  # bot already finished — same frame
				else:
					_show_result(true)  # beat the bot
			else:
				update_progress.rpc(cursor, error) # let the opponent see the full bar
				report_finished.rpc()
			return # don't re-render: _show_result/set_winner clears the text
	else:
		error = true

	_after_local_change()


func _after_local_change() -> void:
	_render_you()
	if not solo:
		update_progress.rpc(cursor, error)


# ===========================================================================
#  Rendering
# ===========================================================================

func _render_you() -> void:
	you_label.text = _build_bbcode(cursor, error, true)
	you_progress.text = "%d / %d" % [cursor, target.length()]


func _render_opponent() -> void:
	opp_label.text = _build_bbcode(opp_cursor, opp_error, false)
	opp_progress.text = "%d / %d" % [opp_cursor, target.length()]


# Builds the per-character text for one panel, centered. Same glyph size
# throughout — only the color/brightness changes.
#   [0, c)  -> solid white (typed)
#   c       -> red if error, else the current char (faint white, highlighted)
#   (c, n)  -> faint white (not yet typed)
func _build_bbcode(c: int, e: bool, show_cursor: bool) -> String:
	var out := ""
	for i in target.length():
		var ch := target.substr(i, 1)
		if i < c:
			out += "[color=%s]%s[/color]" % [TXT_DONE, ch]
		elif i == c:
			if e:
				out += "[color=%s]%s[/color]" % [TXT_ERROR, ch]
			elif show_cursor:
				out += "[bgcolor=%s][color=%s]%s[/color][/bgcolor]" % [COL_CURSOR_BG, TXT_TODO, ch]
			else:
				out += "[color=%s]%s[/color]" % [TXT_TODO, ch]
		else:
			out += "[color=%s]%s[/color]" % [TXT_TODO, ch]
	return "[center]%s[/center]" % out


# ===========================================================================
#  UI construction
# ===========================================================================

func _build_connect_ui() -> void:
	connect_ui = Control.new()
	connect_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connect_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(connect_ui)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connect_ui.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "TYPERACER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var solo_btn := Button.new()
	solo_btn.text = "Play solo (practice vs bot)"
	solo_btn.pressed.connect(_on_solo_pressed)
	box.add_child(solo_btn)

	var sep := HSeparator.new()
	box.add_child(sep)

	var host_btn := Button.new()
	host_btn.text = "Host a game"
	host_btn.pressed.connect(_on_host_pressed)
	box.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)

	ip_input = LineEdit.new()
	ip_input.placeholder_text = "Host IP (blank = 127.0.0.1)"
	ip_input.custom_minimum_size = Vector2(240, 0)
	join_row.add_child(ip_input)

	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)

	status_label = Label.new()
	status_label.text = "Host a game, or enter the host's IP and Join."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(360, 0)
	box.add_child(status_label)


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
	you_label = you_panel[1]
	you_progress = you_panel[2]
	you_result = you_panel[3]

	var opp_panel := _make_panel("OPPONENT", false)
	split.add_child(opp_panel[0])
	opp_label = opp_panel[1]
	opp_progress = opp_panel[2]
	opp_result = opp_panel[3]

	# Countdown overlay (3-2-1-GO), centered across the whole screen.
	result_label = Label.new()
	result_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 96)
	game_ui.add_child(result_label)


# Returns [panel_root, text_label, progress_label, result_label].
func _make_panel(header: String, is_you: bool) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Transparent panel — the pitch shows through undimmed.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)

	# Inner Control so we can overlay the result message on top of the content.
	var inner := Control.new()
	panel.add_child(inner)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 18)
	inner.add_child(col)

	var head := Label.new()
	head.text = header
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 28)
	head.add_theme_color_override("font_color", Color(COL_DONE) if is_you else Color(COL_HEADER_OPP))
	col.add_child(head)

	# Expanding spacers above/below center the sentence vertically in the panel.
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer_top)

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_font_override("normal_font", hand_font)
	text.add_theme_font_size_override("normal_font_size", 32)
	# Dark outline keeps the white text legible over the bright grass.
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	text.add_theme_constant_override("outline_size", 6)
	col.add_child(text)

	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer_bottom)

	var progress := Label.new()
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.add_theme_font_size_override("font_size", 22)
	progress.add_theme_color_override("font_color", Color(COL_HEADER_OPP))
	col.add_child(progress)

	# Per-panel WINNER/LOSER overlay, centered over this side of the screen.
	var overlay := CenterContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(overlay)

	# Transparent wrapper (no background) used only to toggle the message.
	var result_box := PanelContainer.new()
	result_box.visible = false
	result_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	overlay.add_child(result_box)

	var result := Label.new()
	result.add_theme_font_size_override("font_size", 80)
	# Dark outline keeps the message readable over the grass (no solid box).
	result.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	result.add_theme_constant_override("outline_size", 12)
	result_box.add_child(result)

	return [panel, text, progress, result]
