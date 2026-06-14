extends Control
## Online 2-player Typeracer minigame.
##
## Split screen: the LEFT panel is the local player, the RIGHT panel is the
## remote opponent. Each fighter types a random line from their OWN character's
## pool (in their own language); the host picks BOTH lines length-matched so the
## race is fair, then hands each side its line. First to finish their line wins.
## Georgian/English fighters type Georgian text (Latin keystrokes are remapped
## phonetically).

const PORT := 9999

# Each fighter types a random line from their own pool (in their own language).
const CHAR_SENTENCES := {
	"georgian": [
		"ცოტა სიჩუმეა და დინამოს ექიმი ბოოოოოსი",
		"არავარ არსად სიაში, დუბლებში მე არავარ, არსად არავარ",
		"ფეხბურთი მეტია...ვიდრე გაზაევი",
		"ჯოტია მუს გილამჯანუქ სი ჯოღორისკუა",
		"ფეხბურთი თურმე კუჭის აშლილობას გავს",
		"შენთვის, შენთვის ვმღერი ზღაპრის ბოლო კეთილია",
	],
	"scottish": [
		"Let's pretend, let's pretend we score a goal",
		"Yer stick's not even touchin the ground man",
		"Hocus pocus there's pizza on your focus",
		"It's shite being scottish, we're the lowest of the low",
		"What's heavier, a kilogramme of steel or feathers",
		"We've got McGinn, Super John McGinn",
	],
	"english": [
		"ქვეყნად ვერავინ შეძლებს, დედა შეაგინოს მგელს",
		"ე ზიდან, დედაშენს დაუსიგნალე საკუარში, ბიჭო",
		"თუ გინდა, დედა არ გაგინო, დროზე ინგლისის ჰიმნი იმღერე",
		"მოდი აქ, შენი ლიზარაზუ დედა მოვ***ნ",
		"აბა ვინა ვართ? დედის მ***ელები",
		"გადაა*ვით ბიჭო, რომელ მხარეს მოდიხართ",
		"მოიცა, ის ველოსიპედიანი კაცი სად არი",
	],
}
const FALLBACK_SENTENCES := [
	"the quick brown fox jumps over the lazy dog",
	"pack my box with five dozen liquor jugs",
]

# Phonetic Georgian input: when typing a Georgian line, Latin keystrokes map to
# Georgian letters (so any keyboard works; a real Georgian layout also works,
# since those keys pass through unchanged). The 7 aspirated/extra letters use
# Shift (uppercase Latin).
const GEO_PHONETIC := {
	"a": "ა", "b": "ბ", "g": "გ", "d": "დ", "e": "ე", "v": "ვ", "z": "ზ",
	"T": "თ", "i": "ი", "k": "კ", "l": "ლ", "m": "მ", "n": "ნ", "o": "ო",
	"p": "პ", "J": "ჟ", "r": "რ", "s": "ს", "t": "ტ", "u": "უ", "f": "ფ",
	"q": "ქ", "R": "ღ", "y": "ყ", "S": "შ", "C": "ჩ", "c": "ც", "Z": "ძ",
	"w": "წ", "W": "ჭ", "x": "ხ", "j": "ჯ", "h": "ჰ",
}

# Accent colors (headers, WINNER/LOSER messages) — readable on the white boards.
const COL_DONE := "#1f9d57"    # green accent (darker so it reads on white)
const COL_ERROR := "#d83232"   # red accent

# Typing text sits on the white boards: dark ink, faint until typed.
const TXT_TODO := "#1118278c"  # not yet typed -> faint dark ink
const TXT_DONE := "#111827"    # correctly typed -> solid dark ink
const TXT_ERROR := "#d83232"   # wrong key on the current char -> red
const COL_CURSOR_BG := "#11182722" # subtle dark highlight behind the current char

const COL_HEADER_OPP := "#3a4252"

# Georgian-capable font for the headers (the handwriting font has no Georgian glyphs).
const GEORGIAN_FONT: FontFile = preload("res://assets/fonts/NotoSansGeorgian-Black.ttf")

# White board geometry in the 720-tall canvas: the boards span ~17%–67% of the
# height. Header floats above the board; the sentence centers inside the band.
const BOARD_TOP_Y := 122.0
const BOARD_BOTTOM_Y := 486.0
const BOARD_INSET_X := 40.0
const HEADER_Y := 16.0
# Sentence column is inset further than the board so long lines wrap before they
# reach the white edges (per half-panel: 640 - 2*TEXT_INSET_X wide).
const TEXT_INSET_X := 95.0

# Flip to true to outline each text region (header / sentence / progress) so the
# exact bounds are visible in a screenshot for tuning. Leave false for play.
const DEBUG_TEXT_BORDERS := false

# Instruction card shown (over the frozen game) for a few seconds before each round.
const INSTRUCTION_TEX: Texture2D = preload("res://assets/mini_game_instruction_1.png")
const INSTRUCTION_W := 500.0
const INSTRUCTION_TIME := 3.0

# --- Character names (resolved from MatchSetup: which fighter each side picked) ---
var local_char := ""    # character id of the local player
var opp_char := ""      # character id of the opponent

const CHAR_NAMES := {
	"georgian": "ჯოტია ცაავა",
	"english":  "ლოთი ინგლისელი",
	"scotish":  "კაბიანი შოტლანდიელი",
	"scottish": "კაბიანი შოტლანდიელი",
}

# --- Game state -------------------------------------------------------------
var target := ""        # the local player's own sentence (their character)
var opp_target := ""    # the opponent's sentence (their character)
var _georgian_input := false  # remap Latin keys to Georgian while typing a Georgian line
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
var networked := false
var _result_emitted := false
var _net_elapsed := 0.0
const MAX_ROUND_TIME := 25.0   # safety timeout so a networked round always resolves

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
var _instruction: TextureRect   # instruction card shown before the round
var you_result: Label     # WINNER/LOSER over the player's panel
var opp_result: Label     # WINNER/LOSER over the opponent's panel


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

	# Stadium background art (two white boards for the two players), behind all.
	var bg := TextureRect.new()
	bg.texture = preload("res://assets/type_background.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_game_ui()
	result_label.visible = false

	# No menu — drop straight into a match (unless the fight controller drives us).
	if not embedded:
		_on_solo_pressed()


# Public entry point used by the fight controller for an embedded super.
func begin_solo() -> void:
	_on_solo_pressed()


# Networked embedded entry: runs over the fight's existing peer (no own peer).
# The host picks BOTH lines (length-matched) and starts both via the authority
# RPC; the client just waits for it. First to finish wins; timeout forces a result.
func begin_networked(is_host: bool) -> void:
	solo = false
	networked = true
	_net_elapsed = 0.0
	if is_host:
		_host_start()


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
	# Only the host reacts: pick both lines and start the match for both.
	if multiplayer.is_server():
		_host_start()


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

# Host picks both fighters' lines (length-matched) and starts the match for all.
# On the host local_char is Player 1, opp_char is Player 2.
func _host_start() -> void:
	var pair := _matched_pair(local_char, opp_char)
	start_game.rpc(pair[0], pair[1])


# Host hands everyone both lines (p1 = host, p2 = client) and starts the round.
@rpc("authority", "call_local", "reliable")
func start_game(p1_text: String, p2_text: String) -> void:
	var is_host := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_host:
		_begin_match(p1_text, p2_text)
	else:
		_begin_match(p2_text, p1_text)


# Start the solo practice match against the bot (no networking).
func _on_solo_pressed() -> void:
	solo = true
	var pair := _matched_pair(local_char, opp_char)
	_begin_match(pair[0], pair[1])


func _pool_for(char_id: String) -> Array:
	var key := "scottish" if char_id == "scotish" else char_id
	return CHAR_SENTENCES.get(key, FALLBACK_SENTENCES)


func _pick_sentence(char_id: String) -> String:
	var pool := _pool_for(char_id)
	return String(pool[randi() % pool.size()])


# Pick a random line for a_char, then the closest-length line(s) from b_char's
# pool (randomised among the nearest few) so both sides type similar lengths.
func _matched_pair(a_char: String, b_char: String) -> Array:
	var a := _pick_sentence(a_char)
	var b_pool := _pool_for(b_char).duplicate()
	var target_len := a.length()
	b_pool.sort_custom(func(x, y):
		return absi(String(x).length() - target_len) < absi(String(y).length() - target_len))
	var n: int = mini(3, b_pool.size())
	return [a, String(b_pool[randi() % n])]


# Match setup with both lines already decided (my_text local, opp_text opponent).
func _begin_match(my_text: String, opp_text: String) -> void:
	target = my_text
	opp_target = opp_text
	_georgian_input = _is_georgian(local_char)
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

	# Instruction card over the frozen game for a few seconds, then the countdown.
	_instruction.visible = true
	await get_tree().create_timer(INSTRUCTION_TIME).timeout
	_instruction.visible = false

	for n in [3, 2, 1]:
		result_label.text = str(n)
		result_label.add_theme_color_override("font_color", Color.BLACK)
		result_label.visible = true
		await get_tree().create_timer(1.0).timeout
	result_label.text = "GO!"
	result_label.add_theme_color_override("font_color", Color.BLACK)
	await get_tree().create_timer(0.5).timeout
	result_label.visible = false
	game_active = true


# Drives the bot opponent in solo mode.
func _process(delta: float) -> void:
	if networked:
		_process_net_timeout(delta)
		return
	if not solo or not game_active or opp_finished:
		return
	bot_progress += delta * BOT_SPEED
	opp_cursor = min(int(bot_progress), opp_target.length())
	_render_opponent()
	if opp_cursor >= opp_target.length():
		opp_finished = true
		if finished:
			_show_draw()  # both finished in the same frame
		else:
			_show_result(false)  # bot finished first


# Host-only safety net: if nobody has finished by MAX_ROUND_TIME, the player who
# typed the most wins (draw if tied), so a networked round can never hang.
func _process_net_timeout(delta: float) -> void:
	if not game_active or finished or _result_emitted:
		return
	_net_elapsed += delta
	if not multiplayer.is_server() or _net_elapsed < MAX_ROUND_TIME:
		return
	# Sentences differ in length, so compare fraction completed, not raw chars.
	var mine := float(cursor) / maxf(1.0, float(target.length()))
	var theirs := float(opp_cursor) / maxf(1.0, float(opp_target.length()))
	if abs(mine - theirs) < 0.001:
		set_result.rpc(0)
	elif mine > theirs:
		set_result.rpc(multiplayer.get_unique_id())
	else:
		var peers := multiplayer.get_peers()
		set_result.rpc(peers[0] if peers.size() > 0 else 0)


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
		var pair := _matched_pair(local_char, opp_char)
		_begin_match(pair[0], pair[1])
	elif multiplayer.is_server():
		_host_start()


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
	# Georgian line: translate Latin keystrokes to Georgian letters.
	if _georgian_input and GEO_PHONETIC.has(ch):
		ch = GEO_PHONETIC[ch]

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
	you_label.text = _build_bbcode(target, cursor, error, true)
	you_progress.text = "%d / %d" % [cursor, target.length()]


func _render_opponent() -> void:
	opp_label.text = _build_bbcode(opp_target, opp_cursor, opp_error, false)
	opp_progress.text = "%d / %d" % [opp_cursor, opp_target.length()]


# Builds the per-character text for one panel, centered. Same glyph size
# throughout — only the color/brightness changes.
#   [0, c)  -> solid white (typed)
#   c       -> red if error, else the current char (faint white, highlighted)
#   (c, n)  -> faint white (not yet typed)
func _build_bbcode(text: String, c: int, e: bool, show_cursor: bool) -> String:
	var out := ""
	for i in text.length():
		var ch := text.substr(i, 1)
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


# Work out which fighter is on each side (host = Player 1 = p1_choice).
func _resolve_chars() -> void:
	var is_host := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	local_char = String(MatchSetup.p1_choice if is_host else MatchSetup.p2_choice)
	opp_char = String(MatchSetup.p2_choice if is_host else MatchSetup.p1_choice)


func _char_name(id: String) -> String:
	return CHAR_NAMES.get(id, id)


func _is_georgian(id: String) -> bool:
	return id == "georgian" or id == "english"


func _build_game_ui() -> void:
	_resolve_chars()
	game_ui = Control.new()
	game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_ui)

	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 0)
	game_ui.add_child(split)

	var you_panel := _make_panel(_char_name(local_char), true)
	split.add_child(you_panel[0])
	you_label = you_panel[1]
	you_progress = you_panel[2]
	you_result = you_panel[3]

	var opp_panel := _make_panel(_char_name(opp_char), false)
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

	_instruction = _make_instruction(INSTRUCTION_TEX)
	game_ui.add_child(_instruction)


func _make_instruction(tex: Texture2D) -> TextureRect:
	var card := TextureRect.new()
	card.texture = tex
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := INSTRUCTION_W
	var h := w * float(tex.get_height()) / float(tex.get_width())
	card.position = Vector2((1280.0 - w) * 0.5, (720.0 - h) * 0.5)
	card.size = Vector2(w, h)
	card.visible = false
	return card


# Returns [panel_root, text_label, progress_label, result_label].
func _make_panel(header: String, is_you: bool) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Transparent panel — the background art shows through undimmed.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	panel.add_theme_stylebox_override("panel", style)

	# Inner Control fills this half of the screen; children are placed by anchor
	# so the header floats up top while the sentence centers inside the board.
	var inner := Control.new()
	panel.add_child(inner)

	var head := Label.new()
	head.text = header
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = HEADER_Y
	head.offset_bottom = HEADER_Y + 60
	head.add_theme_font_override("font", GEORGIAN_FONT)
	head.add_theme_font_size_override("font_size", 36)
	head.add_theme_color_override("font_color", Color.BLACK)
	inner.add_child(head)
	_add_debug_border(inner, head, Color(0, 0.6, 1))

	# Band = the white board's interior. Expanding spacers center the sentence
	# vertically inside the band; the text fills the band width so it wraps.
	var band := VBoxContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_top = 0.0
	band.anchor_right = 1.0
	band.anchor_bottom = 0.0
	band.offset_left = TEXT_INSET_X
	band.offset_right = -TEXT_INSET_X
	band.offset_top = BOARD_TOP_Y
	band.offset_bottom = BOARD_BOTTOM_Y
	inner.add_child(band)
	_add_debug_border(inner, band, Color(1, 0, 0))

	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.add_child(spacer_top)

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Georgian lines need the Georgian font; Latin (scottish) keeps the handwriting look.
	var side_char: String = local_char if is_you else opp_char
	text.add_theme_font_override("normal_font", GEORGIAN_FONT if _is_georgian(side_char) else hand_font)
	text.add_theme_font_size_override("normal_font_size", 32)
	# Light outline keeps the dark ink crisp on the white board.
	text.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	text.add_theme_constant_override("outline_size", 4)
	band.add_child(text)

	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.add_child(spacer_bottom)

	var progress := Label.new()
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.set_anchors_preset(Control.PRESET_TOP_WIDE)
	progress.offset_top = BOARD_BOTTOM_Y - 46
	progress.offset_bottom = BOARD_BOTTOM_Y - 6
	progress.add_theme_font_size_override("font_size", 22)
	progress.add_theme_color_override("font_color", Color(COL_HEADER_OPP))
	inner.add_child(progress)
	_add_debug_border(inner, progress, Color(1, 0.8, 0))

	# Per-panel WINNER/LOSER overlay, centered over the white board.
	var overlay := CenterContainer.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 0.0
	overlay.offset_left = BOARD_INSET_X
	overlay.offset_right = -BOARD_INSET_X
	overlay.offset_top = BOARD_TOP_Y
	overlay.offset_bottom = BOARD_BOTTOM_Y
	inner.add_child(overlay)

	# Transparent wrapper (no background) used only to toggle the message.
	var result_box := PanelContainer.new()
	result_box.visible = false
	result_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	overlay.add_child(result_box)

	var result := Label.new()
	result.add_theme_font_size_override("font_size", 80)
	# Light outline keeps the WINNER/LOSER message readable on the white board.
	result.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	result.add_theme_constant_override("outline_size", 10)
	result_box.add_child(result)

	return [panel, text, progress, result]


# Draws a thin colored outline matching another Control's rect, for visually
# tuning where each text region sits. No-op unless DEBUG_TEXT_BORDERS is true.
func _add_debug_border(parent: Control, target: Control, color: Color) -> void:
	if not DEBUG_TEXT_BORDERS:
		return
	var border := Panel.new()
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.anchor_left = target.anchor_left
	border.anchor_top = target.anchor_top
	border.anchor_right = target.anchor_right
	border.anchor_bottom = target.anchor_bottom
	border.offset_left = target.offset_left
	border.offset_top = target.offset_top
	border.offset_right = target.offset_right
	border.offset_bottom = target.offset_bottom
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = color
	s.set_border_width_all(2)
	border.add_theme_stylebox_override("panel", s)
	parent.add_child(border)
