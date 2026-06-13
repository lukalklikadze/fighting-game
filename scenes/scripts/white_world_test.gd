extends Node2D

const LAN_PORT := 7777
const DISCOVERY_PORT := 7778
const DISCOVERY_REQUEST := "FIGHTING_GAME_FIND_HOST"
const DISCOVERY_RESPONSE_PREFIX := "FIGHTING_GAME_HOST:"
const JOIN_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const JOIN_TIMEOUT_TIME := 8.0
const PLAYER_ONE_START := Vector2(-260, 232)
const PLAYER_TWO_START := Vector2(260, 232)

@onready var player_one: Node2D = $Players/PlayerOne
@onready var player_two: Node2D = $Players/PlayerTwo
@onready var camera: Camera2D = $Camera2D

var _reset_down := false
var _ip_edit: LineEdit
var _status_label: Label
var _p1_health_bar: ProgressBar
var _p2_health_bar: ProgressBar
var _p1_health_text: Label
var _p2_health_text: Label
var _host_discovery_peer: PacketPeerUDP
var _join_discovery_peer: PacketPeerUDP
var _discovery_timer := 0.0
var _discovery_attempts_left := 0
var _join_timeout_timer := 0.0
var _pending_join_ip := ""
var _client_peer_id := 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.WHITE)
	_build_lan_ui()
	_connect_health_signals()
	_connect_multiplayer_signals()
	_configure_players_for_local_bot()
	_reset_match()
	_set_status("Local bot test. Host to play over WiFi on port %d." % LAN_PORT)


func _process(_delta: float) -> void:
	_process_lan_discovery(_delta)
	_process_join_timeout(_delta)
	_update_camera()
	_handle_debug_reset()


func _build_lan_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_build_health_hud(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 64)
	panel.custom_minimum_size = Vector2(420, 104)
	layer.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	layout.add_child(row)

	var host_button := Button.new()
	host_button.text = "Host"
	host_button.pressed.connect(_host_lan_game)
	row.add_child(host_button)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "Code, IP, or Find Host"
	_ip_edit.text = ""
	_ip_edit.custom_minimum_size = Vector2(170, 32)
	row.add_child(_ip_edit)

	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_join_lan_game)
	row.add_child(join_button)

	var find_button := Button.new()
	find_button.text = "Find Host"
	find_button.pressed.connect(_find_lan_host)
	row.add_child(find_button)

	var local_button := Button.new()
	local_button.text = "Local Bot"
	local_button.pressed.connect(_return_to_local_bot)
	row.add_child(local_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status_label)


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

	var p1_label := Label.new()
	p1_label.text = "P1"
	p1_label.custom_minimum_size = Vector2(28, 28)
	p1_box.add_child(p1_label)

	_p1_health_bar = _make_health_bar(Color(0.95, 0.18, 0.12, 1.0))
	p1_box.add_child(_p1_health_bar)

	_p1_health_text = Label.new()
	_p1_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_p1_health_text.custom_minimum_size = Vector2(72, 28)
	p1_box.add_child(_p1_health_text)

	var center_label := Label.new()
	center_label.text = "VS"
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.custom_minimum_size = Vector2(42, 28)
	row.add_child(center_label)

	var p2_box := HBoxContainer.new()
	p2_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2_box.add_theme_constant_override("separation", 8)
	row.add_child(p2_box)

	var p2_label := Label.new()
	p2_label.text = "P2"
	p2_label.custom_minimum_size = Vector2(28, 28)
	p2_box.add_child(p2_label)

	_p2_health_bar = _make_health_bar(Color(0.10, 0.34, 0.95, 1.0))
	p2_box.add_child(_p2_health_bar)

	_p2_health_text = Label.new()
	_p2_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_p2_health_text.custom_minimum_size = Vector2(72, 28)
	p2_box.add_child(_p2_health_text)


func _make_health_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(260, 28)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.02, 0.02, 0.02, 1.0)
	background.border_color = Color.BLACK
	background.set_border_width_all(2)
	bar.add_theme_stylebox_override("background", background)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("fill", fill)

	return bar


func _connect_health_signals() -> void:
	var p1_callable := Callable(self, "_on_player_one_health_changed")
	var p2_callable := Callable(self, "_on_player_two_health_changed")
	if not player_one.is_connected("health_changed", p1_callable):
		player_one.connect("health_changed", p1_callable)
	if not player_two.is_connected("health_changed", p2_callable):
		player_two.connect("health_changed", p2_callable)
	_refresh_health_hud()


func _on_player_one_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(_p1_health_bar, _p1_health_text, current_health, max_health)


func _on_player_two_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(_p2_health_bar, _p2_health_text, current_health, max_health)


func _refresh_health_hud() -> void:
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


func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _host_lan_game() -> void:
	_close_multiplayer_peer()
	_client_peer_id = 0
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(LAN_PORT, 1)
	if error != OK:
		_set_status("Host failed: %s" % error_string(error))
		return

	multiplayer.multiplayer_peer = peer
	_configure_players_for_lan()
	_reset_match()
	_start_host_discovery()
	var host_ip := _guess_lan_ip()
	_set_status("Hosting. Code: %s  IP: %s:%d. Allow UDP %d/%d if friend cannot join." % [_ip_to_join_code(host_ip), host_ip, LAN_PORT, LAN_PORT, DISCOVERY_PORT])


func _join_lan_game() -> void:
	_stop_host_discovery()
	_stop_join_discovery()
	var host_ip := _parse_join_address(_ip_edit.text)
	if host_ip == "":
		_set_status("Enter host code, host IP, or click Find Host.")
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


func _return_to_local_bot() -> void:
	_close_multiplayer_peer()
	_stop_host_discovery()
	_stop_join_discovery()
	_configure_players_for_local_bot()
	_reset_match()
	_set_status("Local bot test. Host to play over WiFi on port %d." % LAN_PORT)


func _close_multiplayer_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_join_timeout_timer = 0.0
	_pending_join_ip = ""
	_client_peer_id = 0


func _find_lan_host() -> void:
	_stop_join_discovery()
	_join_discovery_peer = PacketPeerUDP.new()
	var error := _join_discovery_peer.bind(0)
	if error != OK:
		_set_status("Find Host failed: %s" % error_string(error))
		_stop_join_discovery()
		return

	_join_discovery_peer.set_broadcast_enabled(true)
	_discovery_attempts_left = 8
	_discovery_timer = 0.0
	_send_discovery_request()
	_set_status("Searching WiFi for a host...")


func _start_host_discovery() -> void:
	_stop_host_discovery()
	_host_discovery_peer = PacketPeerUDP.new()
	var error := _host_discovery_peer.bind(DISCOVERY_PORT)
	if error != OK:
		_set_status("Hosting, but discovery failed: %s. Friend can still type %s." % [error_string(error), _guess_lan_ip()])
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
	_configure_players_for_local_bot()
	_reset_match()
	_set_status("Join timed out to %s. Use latest zip, same WiFi, no guest/client-isolation network, and allow UDP %d/%d in firewall." % [failed_ip, LAN_PORT, DISCOVERY_PORT])


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
		_ip_edit.text = host_ip
		_stop_join_discovery()
		_set_status("Found host at %s. Joining..." % host_ip)
		_join_lan_game()
		return

	if _discovery_attempts_left <= 0:
		_stop_join_discovery()
		_set_status("No host found. Make sure host clicked Host, both computers are on same WiFi, and firewall allows UDP %d/%d." % [LAN_PORT, DISCOVERY_PORT])
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


func _configure_players_for_local_bot() -> void:
	_configure_common_player_settings(2)
	player_one.set("accept_local_input", true)
	player_two.set("accept_local_input", false)
	player_one.set("bot_enabled", false)
	player_two.set("bot_enabled", true)


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
	player_one.call("reset_fighter", PLAYER_ONE_START)
	player_two.call("reset_fighter", PLAYER_TWO_START)


@rpc("authority", "call_local", "reliable")
func _rpc_reset_lan_match(client_peer_id: int) -> void:
	_configure_players_for_lan(client_peer_id)
	_reset_match()
	_set_status("LAN match running. You control Player %d." % _local_player_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_reset_lan_match() -> void:
	if multiplayer.is_server():
		var requester_id := multiplayer.get_remote_sender_id()
		var client_peer_id := _client_peer_id if _client_peer_id > 0 else requester_id
		_rpc_reset_lan_match.rpc(client_peer_id)


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_client_peer_id = peer_id
		_set_status("Peer %d connected. Starting LAN match." % peer_id)
		_rpc_reset_lan_match.rpc(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		if peer_id == _client_peer_id:
			_client_peer_id = 0
		_set_status("Peer %d disconnected. Waiting for another player." % peer_id)


func _on_connected_to_server() -> void:
	_stop_host_discovery()
	_stop_join_discovery()
	_client_peer_id = multiplayer.get_unique_id()
	_configure_players_for_lan(_client_peer_id)
	_set_status("Connected. You control Player 2.")


func _on_connection_failed() -> void:
	_close_multiplayer_peer()
	_stop_host_discovery()
	_stop_join_discovery()
	_configure_players_for_local_bot()
	_reset_match()
	_set_status("Connection failed. Check both computers are on same WiFi and firewall allows UDP %d." % LAN_PORT)


func _on_server_disconnected() -> void:
	_close_multiplayer_peer()
	_stop_host_discovery()
	_stop_join_discovery()
	_configure_players_for_local_bot()
	_reset_match()
	_set_status("Disconnected from host. Back to local bot test.")


func _update_camera() -> void:
	var midpoint: Vector2 = (player_one.global_position + player_two.global_position) * 0.5
	camera.global_position = Vector2(midpoint.x, 10.0)


func _handle_debug_reset() -> void:
	var reset_pressed := Input.is_physical_key_pressed(KEY_R)
	if reset_pressed and not _reset_down:
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				_rpc_reset_lan_match.rpc(_client_peer_id)
			else:
				_rpc_request_reset_lan_match.rpc_id(1)
		else:
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
