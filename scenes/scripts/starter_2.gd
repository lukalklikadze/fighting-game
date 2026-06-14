extends Node2D

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
const MENU_SELECTED := Color(0.45, 0.45, 0.45, 1.0)

const MENU_FONT: FontFile = preload("res://assets/fonts/NotoSansGeorgian-Black.ttf")

enum Menu { CHOICES, CODE_ENTRY, WAIT, SELECT }

@onready var _character_display: Sprite2D = $CharacterDisplay
@onready var _opponent_display: Sprite2D = $OpponentDisplay
@onready var _start_sprite: Sprite2D = $start
@onready var _join_sprite: Sprite2D = $join

var _balls: Dictionary = {}
var _base_scale: Dictionary = {}
var _selected := 0
var _chosen := -1
var _opp_chosen := -1
var _starting := false
var _selection_enabled := false

var _menu := Menu.CHOICES
var _menu_index := 0
var _test_mode := false

var _code_edit: LineEdit
var _code_label: Label
var _status_label: Label

var _hosting_active := false
var _connected_as_client := false
var _client_peer_id := 0
var _pending_join_ip := ""
var _join_timeout_timer := 0.0


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	RenderingServer.set_default_clear_color(Color(0.05, 0.10, 0.25, 1.0))
	randomize()
	for ball_name in BALL_ORDER:
		var ball := get_node(NodePath(ball_name)) as Sprite2D
		_balls[ball_name] = ball
		_base_scale[ball_name] = ball.scale
	_character_display.visible = false
	_opponent_display.visible = false
	_build_ui()
	_connect_multiplayer_signals()
	_update_highlight()
	_show_choices()


func _process(delta: float) -> void:
	_process_join_timeout(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _code_edit != null and _code_edit.has_focus():
		if event.is_action_pressed("ui_cancel"):
			_code_edit.release_focus()
			_show_choices()
		return
	match _menu:
		Menu.CHOICES:
			_menu_input(event)
		Menu.SELECT:
			_select_input(event)
		_:
			pass


func _menu_input(event: InputEvent) -> void:
	if _key_left(event):
		_menu_index = 0
		_update_menu_highlight()
	elif _key_right(event):
		_menu_index = 1
		_update_menu_highlight()
	elif event.is_action_pressed("ui_accept"):
		_activate_menu()
	elif _key_pressed(event, KEY_T):
		_enter_test_mode()


func _select_input(event: InputEvent) -> void:
	if not _selection_enabled:
		return
	if _key_right(event):
		_selected = (_selected + 1) % BALL_ORDER.size()
		_update_highlight()
	elif _key_left(event):
		_selected = (_selected - 1 + BALL_ORDER.size()) % BALL_ORDER.size()
		_update_highlight()
	elif event.is_action_pressed("ui_accept"):
		_choose(_selected)


func _activate_menu() -> void:
	if _menu_index == 0:
		_activate_start()
	else:
		_activate_join()


func _key_left(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_left") or _key_pressed(event, KEY_A)


func _key_right(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_right") or _key_pressed(event, KEY_D)


func _key_pressed(event: InputEvent, code: int) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == code


func _activate_start() -> void:
	_host_game()


func _activate_join() -> void:
	_menu = Menu.CODE_ENTRY
	_apply_menu_visibility()
	_code_label.text = "ENTER A CODE TO JOIN"
	_code_edit.editable = true
	_code_edit.text = ""
	_code_edit.grab_focus()
	_set_status("Type your friend's code and press ENTER. (ESC to go back.)")


func _enter_test_mode() -> void:
	_test_mode = true
	_menu = Menu.SELECT
	_apply_menu_visibility()
	_opp_chosen = 1
	_opponent_display.texture = CHAR_TEXTURES[BALL_ORDER[_opp_chosen]]
	_opponent_display.visible = true
	_set_selection_enabled(true)
	_set_status("")


func _set_selection_enabled(enabled: bool) -> void:
	_selection_enabled = enabled
	_update_highlight()


func _update_highlight() -> void:
	if not _selection_enabled:
		for ball_name in BALL_ORDER:
			_balls[ball_name].scale = _base_scale[ball_name]
			_balls[ball_name].modulate = Color.WHITE
		_character_display.visible = false
		return
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
	if BALL_ORDER[index] == "random":
		index = _resolve_random()
	_chosen = index
	_character_display.texture = CHAR_TEXTURES[BALL_ORDER[index]]
	_character_display.visible = true
	if _hosting_active or _connected_as_client:
		_rpc_set_opponent_choice.rpc(index)
	if _test_mode:
		return
	_set_status("Waiting for both to choose...")
	_maybe_start()


func _resolve_random() -> int:
	var pool := [0, 1, 2]
	if _opp_chosen in pool:
		pool.erase(_opp_chosen)
	return pool[randi() % pool.size()]


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_opponent_choice(index: int) -> void:
	index = clampi(index, 0, BALL_ORDER.size() - 1)
	_opp_chosen = index
	_opponent_display.texture = CHAR_TEXTURES[BALL_ORDER[index]]
	_opponent_display.visible = true
	_maybe_start()


func _maybe_start() -> void:
	if _starting or _test_mode or not _hosting_active:
		return
	if _chosen < 0 or _opp_chosen < 0:
		return
	_starting = true
	_set_status("Starting fight...")
	var host_key: String = BALL_ORDER[_chosen]
	var client_key: String = BALL_ORDER[_opp_chosen]
	_rpc_goto_fight.rpc(host_key, client_key, _client_peer_id)
	_goto_fight(host_key, client_key, _client_peer_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_goto_fight(p1_key: String, p2_key: String, cpid: int) -> void:
	_goto_fight(p1_key, p2_key, cpid)


func _goto_fight(p1_key: String, p2_key: String, cpid: int) -> void:
	MatchSetup.active = true
	MatchSetup.p1_choice = p1_key
	MatchSetup.p2_choice = p2_key
	MatchSetup.client_peer_id = cpid
	get_tree().change_scene_to_file("res://bar.tscn")


func _send_choice_to(peer_id: int) -> void:
	if _chosen >= 0:
		_rpc_set_opponent_choice.rpc_id(peer_id, _chosen)


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

	_status_label = _make_label("", 15, Color(0.85, 0.92, 0.88, 1.0))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.position = Vector2(90, 696)
	_status_label.size = Vector2(1100, 22)
	layer.add_child(_status_label)


func _show_choices() -> void:
	_menu = Menu.CHOICES
	_menu_index = 0
	_apply_menu_visibility()
	_update_menu_highlight()
	_set_status("")


func _apply_menu_visibility() -> void:
	var entering_code := _menu == Menu.CODE_ENTRY
	var hosting_wait := _menu == Menu.WAIT
	if _code_label != null:
		_code_label.visible = entering_code or hosting_wait
	if _code_edit != null:
		_code_edit.visible = entering_code or hosting_wait
	_update_menu_highlight()


func _update_menu_highlight() -> void:
	if _start_sprite == null or _join_sprite == null:
		return
	var in_choices := _menu == Menu.CHOICES
	_start_sprite.modulate = MENU_SELECTED if (in_choices and _menu_index == 0) else Color.WHITE
	_join_sprite.modulate = MENU_SELECTED if (in_choices and _menu_index == 1) else Color.WHITE


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


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _refresh_lobby_controls() -> void:
	var locked := _hosting_active or _connected_as_client
	if _code_edit != null:
		_code_edit.editable = not locked


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
	_menu = Menu.WAIT
	_apply_menu_visibility()
	var code := _ip_to_join_code(_guess_lan_ip())
	_code_edit.editable = false
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
	_code_edit.release_focus()
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
		_show_choices()
		_set_status("Join timed out to %s. Check the code, WiFi and firewall (UDP %d)." % [failed_ip, LAN_PORT])


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_client_peer_id = peer_id
		_menu = Menu.SELECT
		_apply_menu_visibility()
		_code_label.text = "PLAYER 2 CONNECTED"
		_set_status("Both players in — pick your fighter!")
		_set_selection_enabled(true)
		_send_choice_to(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id == _client_peer_id:
		_client_peer_id = 0
		_opponent_display.visible = false
		_set_selection_enabled(false)
		_menu = Menu.WAIT
		_apply_menu_visibility()
		_set_status("Player 2 disconnected. Waiting for another player.")


func _on_connected_to_server() -> void:
	_connected_as_client = true
	_hosting_active = false
	_join_timeout_timer = 0.0
	_pending_join_ip = ""
	_menu = Menu.SELECT
	_apply_menu_visibility()
	_code_label.text = "CONNECTED AS PLAYER 2"
	_set_status("Both players in — pick your fighter!")
	_refresh_lobby_controls()
	_set_selection_enabled(true)
	_send_choice_to(1)


func _on_connection_failed() -> void:
	_close_multiplayer_peer()
	_show_choices()
	_set_status("Connection failed. Check the code, WiFi and firewall (UDP %d)." % LAN_PORT)


func _on_server_disconnected() -> void:
	_close_multiplayer_peer()
	_opponent_display.visible = false
	_set_selection_enabled(false)
	_show_choices()
	_set_status("Disconnected from host.")


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
