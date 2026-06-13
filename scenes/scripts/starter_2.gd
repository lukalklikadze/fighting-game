extends Node2D
## Online start screen.
##
## Highlight one of four footballs with Left/Right arrows, then press Enter to
## CHOOSE it — only then does the matching fighter PNG appear on CharacterDisplay.
## Click START to host (a share code is shown) or type a friend's code and click
## JOIN. Once connected, each player's choice is sent to the other and shown on
## OpponentDisplay. Drag CharacterDisplay / OpponentDisplay in the editor to place
## where each fighter appears — the script only swaps their textures.

const LAN_PORT := 7777
const JOIN_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const JOIN_TIMEOUT_TIME := 8.0

const CHAR_TEXTURES := {
	"georgian": preload("res://assets/start sprites/Group 3.png"),
	"scottish": preload("res://assets/start sprites/Group 4.png"),
	"english":  preload("res://assets/start sprites/Group 2.png"),
	"random":   preload("res://assets/start sprites/random.png"),
}
const BALL_ORDER := ["georgian", "scottish", "english", "random"]
const SELECTED_SCALE := 1.18
const DIMMED := Color(0.65, 0.65, 0.65, 1.0)

const MENU_FONT: FontFile = preload("res://assets/fonts/NotoSansGeorgian-Black.ttf")

@onready var _character_display: Sprite2D = $CharacterDisplay
@onready var _opponent_display: Sprite2D = $OpponentDisplay

var _balls: Dictionary = {}
var _base_scale: Dictionary = {}
var _selected := 0
var _chosen := -1
var _selection_enabled := false

var _code_edit: LineEdit
var _code_label: Label
var _status_label: Label
var _start_button: Button
var _join_button: Button

var _hosting_active := false
var _connected_as_client := false
var _client_peer_id := 0
var _pending_join_ip := ""
var _join_timeout_timer := 0.0


func _ready() -> void:
	for ball_name in BALL_ORDER:
		var ball := get_node(NodePath(ball_name)) as Sprite2D
		_balls[ball_name] = ball
		_base_scale[ball_name] = ball.scale
	# Nothing is shown until both players are in and selection is enabled.
	_character_display.visible = false
	_opponent_display.visible = false
	_build_ui()
	_connect_multiplayer_signals()
	_update_highlight()
	_set_status("Click START to host, or type a code and click JOIN.")


func _process(delta: float) -> void:
	_process_join_timeout(delta)


# ── Ball selection ───────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# Selection is locked until both players are connected.
	if not _selection_enabled:
		return
	if _code_edit != null and _code_edit.has_focus():
		return
	if event.is_action_pressed("ui_right"):
		_selected = (_selected + 1) % BALL_ORDER.size()
		_update_highlight()
	elif event.is_action_pressed("ui_left"):
		_selected = (_selected - 1 + BALL_ORDER.size()) % BALL_ORDER.size()
		_update_highlight()
	elif event.is_action_pressed("ui_accept"):
		_choose(_selected)


func _set_selection_enabled(enabled: bool) -> void:
	_selection_enabled = enabled
	_update_highlight()


func _update_highlight() -> void:
	# Before both players are in, the balls sit neutral and no fighter is shown.
	if not _selection_enabled:
		for ball_name in BALL_ORDER:
			_balls[ball_name].scale = _base_scale[ball_name]
			_balls[ball_name].modulate = Color.WHITE
		_character_display.visible = false
		return
	# Moving the cursor grows/dims the balls and previews the highlighted fighter.
	for i in range(BALL_ORDER.size()):
		var ball_name: String = BALL_ORDER[i]
		var ball: Sprite2D = _balls[ball_name]
		if i == _selected:
			ball.scale = _base_scale[ball_name] * SELECTED_SCALE
			ball.modulate = Color.WHITE
		else:
			ball.scale = _base_scale[ball_name]
			ball.modulate = DIMMED
	_character_display.texture = CHAR_TEXTURES[BALL_ORDER[_selected]]
	_character_display.visible = true


func _choose(index: int) -> void:
	_chosen = index
	_set_status("You picked %s." % BALL_ORDER[index])
	# Tell the other player which fighter we picked.
	if multiplayer.has_multiplayer_peer():
		_rpc_set_opponent_choice.rpc(index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_opponent_choice(index: int) -> void:
	index = clampi(index, 0, BALL_ORDER.size() - 1)
	_opponent_display.texture = CHAR_TEXTURES[BALL_ORDER[index]]
	_opponent_display.visible = true


func _send_choice_to(peer_id: int) -> void:
	if _chosen >= 0:
		_rpc_set_opponent_choice.rpc_id(peer_id, _chosen)


# ── Lobby UI ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_code_label = _make_label("ENTER A CODE TO JOIN", 16, Color(0.88, 0.94, 1.0, 1.0))
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.position = Vector2(440, 408)
	_code_label.size = Vector2(400, 24)
	layer.add_child(_code_label)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "CODE"
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.max_length = 15
	_code_edit.position = Vector2(465, 436)
	_code_edit.size = Vector2(350, 46)
	_code_edit.add_theme_font_override("font", MENU_FONT)
	_code_edit.add_theme_font_size_override("font_size", 24)
	_code_edit.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	_code_edit.add_theme_color_override("font_placeholder_color", Color(0.50, 0.62, 0.78))
	_code_edit.add_theme_color_override("caret_color", Color(1.0, 0.88, 0.40))
	_code_edit.add_theme_stylebox_override("normal", _field_style(false))
	_code_edit.add_theme_stylebox_override("focus", _field_style(true))
	_code_edit.text_submitted.connect(func(_t): _join_game())
	layer.add_child(_code_edit)

	# Invisible hit areas over the baked-in START / JOIN words.
	_start_button = _make_overlay_button(Rect2(317, 556, 160, 96))
	_start_button.pressed.connect(_host_game)
	layer.add_child(_start_button)

	_join_button = _make_overlay_button(Rect2(750, 561, 120, 80))
	_join_button.pressed.connect(_join_game)
	layer.add_child(_join_button)

	_status_label = _make_label("", 15, Color(0.85, 0.92, 0.88, 1.0))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.position = Vector2(90, 696)
	_status_label.size = Vector2(1100, 22)
	layer.add_child(_status_label)


func _field_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.14, 0.88)
	style.border_color = Color(1.0, 0.88, 0.40, 0.95) if focused else Color(0.42, 0.66, 1.0, 0.85)
	style.set_border_width_all(3 if focused else 2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	return style


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


func _make_overlay_button(rect: Rect2) -> Button:
	# Completely invisible click area — the highlight is on the baked word itself.
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return button


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _refresh_lobby_controls() -> void:
	var locked := _hosting_active or _connected_as_client
	if _start_button != null:
		_start_button.disabled = locked
	if _join_button != null:
		_join_button.disabled = locked
	if _code_edit != null:
		_code_edit.editable = not locked


# ── Networking ───────────────────────────────────────────────────────────────

func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _host_game() -> void:
	_close_multiplayer_peer()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(LAN_PORT, 1)
	if error != OK:
		_set_status("Host failed: %s" % error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	_hosting_active = true
	_connected_as_client = false
	var code := _ip_to_join_code(_guess_lan_ip())
	_code_edit.text = code
	_code_label.text = "გააზიარე კოდი"
	_set_status("")
	_refresh_lobby_controls()


func _join_game() -> void:
	var host_ip := _parse_join_address(_code_edit.text)
	if host_ip == "":
		_code_edit.grab_focus()
		_set_status("Enter a valid host code.")
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
	_set_status("Joining %s..." % host_ip)


func _close_multiplayer_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_hosting_active = false
	_connected_as_client = false
	_client_peer_id = 0
	_pending_join_ip = ""
	_join_timeout_timer = 0.0
	_set_selection_enabled(false)
	_refresh_lobby_controls()


func _process_join_timeout(delta: float) -> void:
	if _join_timeout_timer <= 0.0:
		return
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		_join_timeout_timer = 0.0
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_join_timeout_timer = 0.0
		return
	_join_timeout_timer -= delta
	if _join_timeout_timer <= 0.0:
		var failed_ip := _pending_join_ip
		_close_multiplayer_peer()
		_set_status("Join timed out to %s. Check the code, WiFi and firewall (UDP %d)." % [failed_ip, LAN_PORT])


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_client_peer_id = peer_id
		_code_label.text = "PLAYER 2 CONNECTED"
		_set_status("Both players in — pick your fighter!")
		_set_selection_enabled(true)
		_send_choice_to(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id == _client_peer_id:
		_client_peer_id = 0
		_opponent_display.visible = false
		_set_selection_enabled(false)
		_set_status("Player 2 disconnected. Waiting for another player.")


func _on_connected_to_server() -> void:
	_connected_as_client = true
	_hosting_active = false
	_join_timeout_timer = 0.0
	_pending_join_ip = ""
	_code_label.text = "CONNECTED AS PLAYER 2"
	_set_status("Both players in — pick your fighter!")
	_refresh_lobby_controls()
	_set_selection_enabled(true)
	_send_choice_to(1)


func _on_connection_failed() -> void:
	_close_multiplayer_peer()
	_set_status("Connection failed. Check the code, WiFi and firewall (UDP %d)." % LAN_PORT)


func _on_server_disconnected() -> void:
	_close_multiplayer_peer()
	_opponent_display.visible = false
	_set_selection_enabled(false)
	_set_status("Disconnected from host.")


# ── Join-code helpers (port of WhiteWorldTest) ──────────────────────────────

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


func _guess_lan_ip() -> String:
	for address in IP.get_local_addresses():
		if _is_private_ipv4(address):
			return address
	return "127.0.0.1"


func _is_private_ipv4(address: String) -> bool:
	return address.begins_with("192.168.") or address.begins_with("10.") or _is_private_172_address(address)


func _is_private_172_address(address: String) -> bool:
	if not address.begins_with("172."):
		return false
	var parts := address.split(".")
	if parts.size() < 2:
		return false
	var second_part := int(parts[1])
	return second_part >= 16 and second_part <= 31
