extends Node2D

## Juggling — LAN multiplayer mini-game
## Keep the ball in the air. Ball touches the ground = you lose.
## Controls: A / D  or  ← / →  to move     SPACE or Left Click to kick

# ─── Layout ───────────────────────────────────────────────────────────────────
const SW     := 1280
const SH     := 720
const HALF_W := SW / 2   # 640 — each player owns one half

# Player sprites: idle, right-leg kick, left-leg kick. (Background is a scene node.)
const FIG_IDLE:   Texture2D = preload("res://assets/juggle0000.png")
const FIG_KICK_R: Texture2D = preload("res://assets/juggle0002.png")
const FIG_KICK_L: Texture2D = preload("res://assets/juggle0003.png")

# Georgian-capable font for the player labels (the handwriting font lacks glyphs).
const GEORGIAN_FONT: FontFile = preload("res://assets/fonts/NotoSansGeorgian-Black.ttf")
const FIG_HEIGHT   := 230.0   # on-screen sprite height
const FIG_FOOT_PAD := 14.0    # nudge so the drawn feet rest on the ground line
# Head centre within the sprite (measured from juggle0000.png) for headers.
const HEAD_CX_FRAC := 0.456   # head centre X as a fraction of sprite width
const HEAD_CY_FRAC := 0.203   # head centre Y as a fraction of sprite height (0 = top)
const HEAD_HIT_R   := 26.0    # header contact radius

const GRASS_H   := 70.0
const GROUND_Y:  float = SH - GRASS_H   # 650 — feet rest here; ball here = lose
const CEILING_Y := 36.0
const WALL_L    := 14.0
const WALL_R:    float = HALF_W - 14.0   # 626

# ─── Ball ─────────────────────────────────────────────────────────────────────
const BALL_R      := 16.0
const GRAVITY     := 640.0
const BOUNCE_DAMP := 0.80   # energy kept on wall/ceiling bounce
const MAX_BSPEED  := 900.0  # cap so ball never becomes unplayable

# ─── Kick ─────────────────────────────────────────────────────────────────────
const KICK_VEL_Y   := -510.0   # upward impulse base (scaled by speed multiplier)
const KICK_RAND_X  := 210.0    # ± random horizontal spread
const KICK_DURATION:= 0.20     # leg swing duration in seconds
const KICK_RANGE_X := 68.0     # max horizontal distance player–ball for kick to connect
const KICK_RANGE_Y := 95.0     # max height above ground for kick to connect

# ─── Speed ramp ───────────────────────────────────────────────────────────────
const RAMP_PER_SEC  := 0.034   # kick multiplier gained per second (1.0 → 2.8 in ~53 s)
const BVEL_PER_SEC  := 0.006   # fractional in-air speed gain per second

# ─── Stick figure ─────────────────────────────────────────────────────────────
const HEAD_R    := 15.0
const BODY_LEN  := 58.0
const LEG_LEN   := 58.0
const ARM_LEN   := 38.0
const FIG_MIN_X := 56.0
const FIG_MAX_X: float = HALF_W - 56.0
const MOVE_SPD  := 270.0

# ─── Network ──────────────────────────────────────────────────────────────────
const PORT := 7778

# ─── My state ─────────────────────────────────────────────────────────────────
var my_x: float = HALF_W / 2.0
var my_vx     := 0.0
var my_lean   := 0.0
var my_ball   := Vector2.ZERO
var my_bvel   := Vector2.ZERO
var my_kick       := 0.0    # remaining kick animation time
var my_kick_right := true   # which leg is swinging
var my_kick_hit   := false  # impulse already applied this swing
var my_rand_bounce := false # after a kick, the next wall/ceiling bounce goes a random way
var my_kick_count := 0
var my_alive  := true
var my_ramp_t := 0.0
var my_speed  := 1.0    # kick velocity multiplier; grows over time

# ─── Opponent state (filled by RPC in multiplayer) ────────────────────────────
var op_x: float = HALF_W / 2.0
var op_lean   := 0.0
var op_ball   := Vector2.ZERO
var op_kick       := 0.0
var op_kick_right := true
var op_alive  := false   # true once opponent connects

var winner    := ""      # "" | "you" | "opponent"
var game_on   := false
var am_host   := false
var solo      := false

# Embedded mode (launched as a "super" by the fight controller)
signal minigame_finished(result: int)  # 1 = local won, 0 = local lost, -1 = draw
const Voices := preload("res://minigames/character_voices.gd")
var win_sound: AudioStream = null   # clip played over the win card (random from winner)
var win_sound_seed := -1   # shared seed so both peers pick the same clip
const EMBED_WIN_KICKS := 6   # solo only: reach this many clean kicks to "win"
const MAX_DURATION := 30.0   # networked round cap; most kicks wins at timeout
var embedded := false
var networked := false
var _result_emitted := false
var _net_elapsed := 0.0
var op_kick_count := 0
# Start handshake: host waits for the client's node before sending the start, so
# the RPC isn't dropped on a freshly-instantiated round.
var _host_ready_to_start := false
var _client_ready_for_start := false
var _start_sent := false
var _net_resolved := false   # host: winner decided

# ─── Character names (resolved from MatchSetup: which fighter each side picked) ──
var local_char := ""
var opp_char := ""
const CHAR_NAMES := {
	"georgian": "ჯოტია ცაავა",
	"english":  "ლოთი ინგლისელი",
	"scotish":  "კაბიანი შოტლანდიელი",
	"scottish": "კაბიანი შოტლანდიელი",
}

# ─── Instruction card (shown over the frozen game before each round) ───────────
const INSTRUCTION_TEX: Texture2D = preload("res://assets/mini_game_instruction_2.png")
const INSTRUCTION_W := 500.0
const INSTRUCTION_TIME := 3.0
var _showing_instruction := false

# ─── Audio ────────────────────────────────────────────────────────────────────
const BALL_SFX: AudioStream = preload("res://sounds/SFX/ball.wav")
var _ball_sfx: AudioStreamPlayer

# ─── UI ───────────────────────────────────────────────────────────────────────
var _font           : Font
var _countdown_text := ""   # drawn over the pitch before game_on

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Skip the global window resize when embedded — we render as an overlay.
	if not embedded:
		get_window().content_scale_size   = Vector2i(SW, SH)
		get_window().content_scale_mode   = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	var base_font := SystemFont.new()
	base_font.font_names = PackedStringArray([
		"Marker Felt", "Chalkboard SE", "Noteworthy", "Bradley Hand",
		"Segoe Script", "Comic Sans MS", "Comic Sans MS",
	])
	var chubby := FontVariation.new()
	chubby.base_font = base_font
	chubby.variation_embolden = 0.6
	_font = chubby
	_ball_sfx = AudioStreamPlayer.new()
	_ball_sfx.stream = BALL_SFX
	add_child(_ball_sfx)
	_resolve_chars()
	if not embedded:
		begin_solo()


# Public entry point used by the fight controller for an embedded super.
func begin_solo() -> void:
	solo    = true
	am_host = true
	winner  = ""
	my_alive = true
	my_kick_count = 0
	my_ball = Vector2(HALF_W / 2.0, SH / 2.0)
	my_bvel = Vector2(randf_range(-80.0, 80.0), -380.0)
	_start_round()


# Networked embedded entry: runs over the fight's peer. Host starts both via the
# authority RPC; survival game — first to drop loses, most kicks wins at timeout.
func begin_networked(is_host: bool) -> void:
	solo = false
	networked = true
	am_host = is_host
	if is_host:
		_host_ready_to_start = true
		if _client_ready_for_start:
			_send_start()
	else:
		_rpc_request_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_start() -> void:
	if not multiplayer.is_server():
		return
	_client_ready_for_start = true
	if _host_ready_to_start:
		_send_start()


func _send_start() -> void:
	if _start_sent:
		return
	_start_sent = true
	_net_start.rpc()


@rpc("authority", "call_local", "reliable")
func _net_start() -> void:
	winner = ""
	my_alive = true
	op_alive = true
	my_kick_count = 0
	op_kick_count = 0
	_net_elapsed = 0.0
	_net_resolved = false
	my_ball = Vector2(HALF_W / 2.0, SH / 2.0)
	my_bvel = Vector2(randf_range(-80.0, 80.0), -380.0)
	_start_round()


# A ball hit the ground. The host serializes drops so the first one always loses
# (no both-drop race), then broadcasts the authoritative result.
func _report_drop() -> void:
	if multiplayer.is_server():
		_register_drop(multiplayer.get_unique_id())
	else:
		_net_report_drop.rpc_id(1, multiplayer.get_unique_id())


@rpc("any_peer", "call_remote", "reliable")
func _net_report_drop(dropper_id: int) -> void:
	if multiplayer.is_server():
		_register_drop(dropper_id)


func _register_drop(dropper_id: int) -> void:
	if _net_resolved:
		return
	_net_resolved = true
	_net_result.rpc(dropper_id)   # the player who dropped loses


func _resolve_timeout() -> void:
	_net_resolved = true
	if my_kick_count == op_kick_count:
		_net_result.rpc(0)                      # draw
	elif my_kick_count > op_kick_count:
		var peers := multiplayer.get_peers()
		_net_result.rpc(peers[0] if peers.size() > 0 else 0)  # opponent loses
	else:
		_net_result.rpc(multiplayer.get_unique_id())          # host loses


@rpc("authority", "call_local", "reliable")
func _net_result(loser_id: int) -> void:
	if loser_id == 0:
		winner = "draw"
	elif loser_id == multiplayer.get_unique_id():
		winner = "opponent"   # I lost
	else:
		winner = "you"        # I won
	op_alive = false


func _emit_embedded_result(result: int) -> void:
	if _result_emitted:
		return
	_result_emitted = true
	# The win-card clip is a random line from the winning fighter (seed-synced).
	if result == 1:
		win_sound = Voices.random_sound(local_char, win_sound_seed)
	elif result == 0:
		win_sound = Voices.random_sound(opp_char, win_sound_seed)
	await get_tree().create_timer(1.1).timeout  # let the WINNER/LOSER banner show
	minigame_finished.emit(result)

# Show the instruction card over the frozen game, then run the countdown.
func _start_round() -> void:
	_showing_instruction = true
	queue_redraw()
	await get_tree().create_timer(INSTRUCTION_TIME).timeout
	_showing_instruction = false
	_run_countdown()


func _run_countdown() -> void:
	for n in [3, 2, 1]:
		_countdown_text = str(n)
		queue_redraw()
		await get_tree().create_timer(1.0).timeout
	_countdown_text = "GO!"
	queue_redraw()
	await get_tree().create_timer(0.6).timeout
	_countdown_text = ""
	game_on = true

# ══════════════════════════════════ GAME LOOP ══════════════════════════════════
func _process(delta: float) -> void:
	if not game_on: return
	if embedded and winner != "" and not _result_emitted:
		_emit_embedded_result(1 if winner == "you" else (-1 if winner == "draw" else 0))
	if winner == "":
		_update(delta)
		if not solo and op_alive:
			var signed_kick := my_kick * (1.0 if my_kick_right else -1.0)
			_net_state.rpc(my_x, my_lean, my_ball.x, my_ball.y, signed_kick, my_kick_count)
		if networked and multiplayer.is_server() and not _net_resolved:
			_net_elapsed += delta
			if _net_elapsed >= MAX_DURATION:
				_resolve_timeout()
	queue_redraw()

func _update(delta: float) -> void:
	if not my_alive: return

	# ── Figure movement ──────────────────────────────────────────────────────
	my_vx = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  my_vx = -MOVE_SPD
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): my_vx =  MOVE_SPD
	my_x    = clamp(my_x + my_vx * delta, FIG_MIN_X, FIG_MAX_X)
	my_lean = lerpf(my_lean, my_vx / MOVE_SPD * 0.38, delta * 9.0)
	my_kick = maxf(0.0, my_kick - delta)

	# ── Foot-contact kick detection (applied mid-swing when foot meets ball) ──
	if my_kick > 0.0 and not my_kick_hit:
		var p      := sin((1.0 - my_kick / KICK_DURATION) * PI)
		var hip_x  := my_x
		var hip_y  := GROUND_Y - LEG_LEN
		var foot_x := hip_x + (16.0 + p * 56.0) * (1.0 if my_kick_right else -1.0)
		var foot_y := hip_y + LEG_LEN * 0.78 - p * 42.0
		if absf(my_ball.x - foot_x) < BALL_R + 20.0 and absf(my_ball.y - foot_y) < BALL_R + 26.0:
			my_kick_hit = true
			my_kick_count += 1
			_ball_sfx.play()
			if embedded and not networked and my_kick_count >= EMBED_WIN_KICKS:
				winner = "you"   # solo only: kept the ball up long enough
			var dir_x := (my_ball.x - my_x) * 1.3
			var rnd_x := randf_range(-KICK_RAND_X, KICK_RAND_X)
			my_bvel   = Vector2(dir_x + rnd_x, KICK_VEL_Y) * my_speed
			my_rand_bounce = true   # next bounce sends it a random direction

	# ── Ball physics ─────────────────────────────────────────────────────────
	my_bvel.y += GRAVITY * delta
	my_ball   += my_bvel * delta

	if my_ball.x - BALL_R < WALL_L:
		my_ball.x = WALL_L + BALL_R
		if my_rand_bounce:
			my_bvel.x = randf_range(60.0, 320.0); my_rand_bounce = false   # kicked: random rightward
		else:
			my_bvel.x = absf(my_bvel.x) * BOUNCE_DAMP
	elif my_ball.x + BALL_R > WALL_R:
		my_ball.x = WALL_R - BALL_R
		if my_rand_bounce:
			my_bvel.x = -randf_range(60.0, 320.0); my_rand_bounce = false  # kicked: random leftward
		else:
			my_bvel.x = -absf(my_bvel.x) * BOUNCE_DAMP
	if my_ball.y - BALL_R < CEILING_Y:
		my_ball.y = CEILING_Y + BALL_R; my_bvel.y = absf(my_bvel.y) * BOUNCE_DAMP
		if my_rand_bounce:
			my_bvel.x = randf_range(-320.0, 320.0); my_rand_bounce = false  # kicked: random sideways

	if my_ball.y + BALL_R >= GROUND_Y:
		my_alive = false
		if networked:
			_report_drop()        # host decides the winner; don't set it locally
		else:
			winner = "opponent"   # solo: dropping = you lose
		return

	# ── Continuous speed ramp ────────────────────────────────────────────────
	my_ramp_t += delta
	my_speed   = minf(1.0 + my_ramp_t * RAMP_PER_SEC, 2.8)
	if my_bvel.length() < MAX_BSPEED:
		my_bvel *= 1.0 + BVEL_PER_SEC * delta

# ══════════════════════════════════ INPUT ══════════════════════════════════════
func _input(event: InputEvent) -> void:
	if not game_on or not my_alive or winner != "": return
	var do_kick := false
	if event is InputEventKey and event.pressed and not event.echo:
		do_kick = event.keycode == KEY_SPACE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		do_kick = event.position.x < HALF_W   # click must be in own half
	if do_kick: _kick()

func _kick() -> void:
	my_kick_right = my_ball.x >= my_x
	my_kick       = KICK_DURATION
	my_kick_hit   = false

# ══════════════════════════════════ RPCs ══════════════════════════════════════
@rpc("any_peer", "call_remote", "unreliable")
func _net_state(x: float, lean: float, bx: float, by: float, kick: float, kicks: int) -> void:
	op_x = x;  op_lean = lean
	op_ball = Vector2(bx, by)
	op_kick_right = kick >= 0.0
	op_kick = absf(kick)
	op_kick_count = kicks

@rpc("any_peer", "call_remote", "reliable")
func _net_lost() -> void:
	winner = "you";  op_alive = false

# ══════════════════════════════════ DRAW ══════════════════════════════════════
func _draw() -> void:
	_draw_half(0.0,    my_x, my_lean, my_ball, my_kick, my_alive, true,  my_kick_right)
	_draw_half(HALF_W, op_x, op_lean, op_ball, op_kick, op_alive, false, op_kick_right)
	if game_on and winner == "":
		_lbl_outlined(Vector2(38.0, 130.0), str(my_kick_count), Color.WHITE, 52)
	if _showing_instruction:
		var iw := INSTRUCTION_W
		var ih := iw * float(INSTRUCTION_TEX.get_height()) / float(INSTRUCTION_TEX.get_width())
		draw_texture_rect(INSTRUCTION_TEX, Rect2((SW - iw) * 0.5, (SH - ih) * 0.5, iw, ih), false)
	elif _countdown_text != "":
		_lbl(Vector2(SW / 2.0, SH / 2.0), _countdown_text, Color("#1f7a3d"), 96)
	elif winner != "":
		_draw_banner()

# ── One player's half ─────────────────────────────────────────────────────────
func _draw_half(ox: float, fig_x: float, lean: float, ball: Vector2,
		kick_t: float, alive: bool, is_mine: bool, kick_right: bool) -> void:

	var fig_col  := Color(0.30, 0.62, 1.00) if is_mine else Color(1.00, 0.38, 0.28)
	var ball_col := Color.WHITE

	if alive:
		var hip := Vector2(ox + fig_x, GROUND_Y - LEG_LEN)
		_draw_figure(hip, lean, kick_t, fig_col, kick_right)
		_draw_ball(Vector2(ox + ball.x, ball.y), ball_col)
	elif solo and not is_mine:
		# Solo mode: show idle grey placeholder on opponent side
		var hip := Vector2(ox + HALF_W / 2.0, GROUND_Y - LEG_LEN)
		_draw_figure(hip, 0.0, 0.0, Color(0.55, 0.55, 0.55), true)
	else:
		_draw_fallen(Vector2(ox + fig_x, GROUND_Y), fig_col)

	var label := _char_name(local_char) if is_mine else _char_name(opp_char)
	_lbl_georgian(Vector2(ox + HALF_W / 2.0, 64.0), label, Color.WHITE, 34)

# ── Stick figure ──────────────────────────────────────────────────────────────
func _draw_figure(hip: Vector2, _lean: float, kick_t: float, _col: Color, kick_right: bool) -> void:
	# Pick the pose: idle, or right/left kick while a swing is active.
	var tex := FIG_IDLE
	if kick_t > 0.0:
		tex = FIG_KICK_R if kick_right else FIG_KICK_L
	var h := FIG_HEIGHT
	var w := h   # source sprites are square
	# hip.x is the figure centre; align the sprite's feet to the ground line.
	var top := GROUND_Y + FIG_FOOT_PAD - h
	draw_texture_rect(tex, Rect2(hip.x - w * 0.5, top, w, h), false)


func _draw_fallen(base: Vector2, _col: Color) -> void:
	# Lying down = the idle sprite rotated onto its back.
	var h := FIG_HEIGHT
	var w := h
	draw_set_transform(Vector2(base.x, GROUND_Y - h * 0.28), -PI / 2.0, Vector2.ONE)
	draw_texture_rect(FIG_IDLE, Rect2(-w * 0.5, -h * 0.5, w, h), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── Football ──────────────────────────────────────────────────────────────────
func _draw_ball(pos: Vector2, _col: Color) -> void:
	var r  := BALL_R
	var bk := Color(0.06, 0.06, 0.06)

	# Drop shadow
	draw_circle(pos + Vector2(3.0, 4.0), r, Color(0.0, 0.0, 0.0, 0.22))

	# White base
	draw_circle(pos, r, Color.WHITE)

	# Central black pentagon
	var cp := PackedVector2Array()
	for i in range(5):
		var a := float(i) / 5.0 * TAU - PI * 0.5
		cp.append(pos + Vector2(cos(a), sin(a)) * r * 0.40)
	var cp_col := PackedColorArray(); for _i in range(5): cp_col.append(bk)
	draw_polygon(cp, cp_col)

	# 5 outer black patches
	for i in range(5):
		var a0 := float(i) / 5.0 * TAU - PI * 0.5
		var hw := TAU / 5.0 * 0.38
		var patch := PackedVector2Array([
			pos + Vector2(cos(a0 - hw * 0.55), sin(a0 - hw * 0.55)) * r * 0.50,
			pos + Vector2(cos(a0 + hw * 0.55), sin(a0 + hw * 0.55)) * r * 0.50,
			pos + Vector2(cos(a0 + hw),         sin(a0 + hw))         * r * 0.93,
			pos + Vector2(cos(a0),              sin(a0))              * r * 1.00,
			pos + Vector2(cos(a0 - hw),         sin(a0 - hw))         * r * 0.93,
		])
		var pc := PackedColorArray(); for _j in range(5): pc.append(bk)
		draw_polygon(patch, pc)

	# Outline
	draw_arc(pos, r, 0.0, TAU, 40, bk, 2.0)

	# Specular highlight (top-left)
	draw_circle(pos + Vector2(-r * 0.30, -r * 0.32), r * 0.22, Color(1.0, 1.0, 1.0, 0.72))

# ── HUD ───────────────────────────────────────────────────────────────────────
func _draw_banner() -> void:
	var you_win  := winner == "you"
	var you_text := "WINNER" if you_win else "LOSER"
	var opp_text := "LOSER"  if you_win else "WINNER"
	var you_col  := Color("#3ddc84") if you_win else Color("#ff5555")
	var opp_col  := Color("#ff5555") if you_win else Color("#3ddc84")
	var fs  := 80
	var lc  := Vector2(float(HALF_W) * 0.5, float(SH) * 0.5)
	var rc  := Vector2(float(HALF_W) * 1.5, float(SH) * 0.5)
	_lbl_outlined(lc, you_text, you_col, fs)
	_lbl_outlined(rc, opp_text, opp_col, fs)


func _lbl_outlined(centre: Vector2, text: String, col: Color, fs: int) -> void:
	var sz  := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := centre + Vector2(-sz.x * 0.5, sz.y * 0.35)
	var dark := Color(0.0, 0.0, 0.0, 0.85)
	for dx: int in [-2, 0, 2]:
		for dy: int in [-2, 0, 2]:
			if dx == 0 and dy == 0: continue
			draw_string(_font, pos + Vector2(float(dx), float(dy)), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dark)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _lbl(centre: Vector2, text: String, col: Color, fs: int) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, centre + Vector2(-sz.x / 2.0, sz.y * 0.35),
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# Work out which fighter is on each side (host = Player 1 = p1_choice).
func _resolve_chars() -> void:
	var is_host := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	local_char = String(MatchSetup.p1_choice if is_host else MatchSetup.p2_choice)
	opp_char = String(MatchSetup.p2_choice if is_host else MatchSetup.p1_choice)


func _char_name(id: String) -> String:
	return CHAR_NAMES.get(id, id)


# Centred label using the Georgian font, with a dark outline for legibility.
func _lbl_georgian(centre: Vector2, text: String, col: Color, fs: int) -> void:
	var sz  := GEORGIAN_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := centre + Vector2(-sz.x * 0.5, sz.y * 0.35)
	var dark := Color(0.0, 0.0, 0.0, 0.85)
	for dx: int in [-2, 0, 2]:
		for dy: int in [-2, 0, 2]:
			if dx == 0 and dy == 0:
				continue
			draw_string(GEORGIAN_FONT, pos + Vector2(float(dx), float(dy)), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dark)
	draw_string(GEORGIAN_FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
