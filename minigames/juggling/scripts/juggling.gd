extends Node2D

## Juggling — LAN multiplayer mini-game
## Keep the ball in the air. Ball touches the ground = you lose.
## Controls: A / D  or  ← / →  to move     SPACE or Left Click to kick

# ─── Layout ───────────────────────────────────────────────────────────────────
const SW     := 1280
const SH     := 720
const HALF_W := SW / 2   # 640 — each player owns one half

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
const RAMP_INTERVAL := 5.0     # seconds between speed increases
const RAMP_FACTOR   := 1.08    # multiplier per interval

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
var my_kick   := 0.0    # remaining kick animation time
var my_alive  := true
var my_ramp_t := 0.0
var my_speed  := 1.0    # kick velocity multiplier; grows over time

# ─── Opponent state (filled by RPC in multiplayer) ────────────────────────────
var op_x: float = HALF_W / 2.0
var op_lean   := 0.0
var op_ball   := Vector2.ZERO
var op_kick   := 0.0
var op_alive  := false   # true once opponent connects

var winner    := ""      # "" | "you" | "opponent"
var game_on   := false
var am_host   := false
var solo      := false

# ─── UI ───────────────────────────────────────────────────────────────────────
var _menu : Control
var _ip   : LineEdit
var _msg  : Label
var _font : Font

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	get_window().content_scale_size   = Vector2i(SW, SH)
	get_window().content_scale_mode   = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	_font = ThemeDB.fallback_font
	_build_menu()

# ══════════════════════════════════ MENU ══════════════════════════════════════
func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.18, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(380, 0)
	vb.position = Vector2(SW / 2.0 - 190, SH / 2.0 - 160)
	vb.add_theme_constant_override("separation", 10)
	_menu.add_child(vb)

	var title := Label.new()
	title.text = "JUGGLING BATTLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "Keep the ball in the air — don't let it touch the ground!"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)

	_gap(vb, 12)

	var hbtn := Button.new()
	hbtn.text = "HOST  (you = left side)"
	hbtn.pressed.connect(_do_host)
	vb.add_child(hbtn)

	_gap(vb, 4)

	var lbl := Label.new()
	lbl.text = "— or join with host's LAN IP —"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)

	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.x.x"
	_ip.text = "127.0.0.1"
	vb.add_child(_ip)

	var jbtn := Button.new()
	jbtn.text = "JOIN  (you = left side)"
	jbtn.pressed.connect(_do_join)
	vb.add_child(jbtn)

	_gap(vb, 6)

	var sbtn := Button.new()
	sbtn.text = "SOLO TEST"
	sbtn.pressed.connect(_do_solo)
	vb.add_child(sbtn)

	_gap(vb, 8)

	_msg = Label.new()
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_msg)

func _gap(p: Control, h: int) -> void:
	var s := Control.new(); s.custom_minimum_size = Vector2(0, h); p.add_child(s)

# ══════════════════════════════════ NETWORK ═══════════════════════════════════
func _do_host() -> void:
	am_host = true
	var enet := ENetMultiplayerPeer.new()
	if enet.create_server(PORT, 1) != OK:
		_msg.text = "Cannot open port %d." % PORT; return
	multiplayer.multiplayer_peer = enet
	multiplayer.peer_connected.connect(func(_id: int) -> void: _start(true))
	_msg.text = "Hosting on port %d…\nWaiting for opponent." % PORT

func _do_join() -> void:
	am_host = false
	var ip := _ip.text.strip_edges()
	var enet := ENetMultiplayerPeer.new()
	if enet.create_client(ip, PORT) != OK:
		_msg.text = "Could not connect."; return
	multiplayer.multiplayer_peer = enet
	multiplayer.connected_to_server.connect(func() -> void: _start(true))
	multiplayer.connection_failed.connect(func() -> void: _msg.text = "Connection failed.")
	_msg.text = "Connecting to %s…" % ip

func _do_solo() -> void:
	solo = true; am_host = true
	_start(false)

func _start(has_opponent: bool) -> void:
	game_on = true
	op_alive = has_opponent
	my_ball  = Vector2(HALF_W / 2.0, GROUND_Y - 160.0)
	my_bvel  = Vector2(randf_range(-80.0, 80.0), -380.0)
	if has_opponent:
		op_ball = Vector2(HALF_W / 2.0, 180.0)
	if is_instance_valid(_menu): _menu.queue_free(); _menu = null

# ══════════════════════════════════ GAME LOOP ══════════════════════════════════
func _process(delta: float) -> void:
	if not game_on: return
	if winner == "":
		_update(delta)
		if not solo and op_alive:
			_net_state.rpc(my_x, my_lean, my_ball.x, my_ball.y, my_kick)
	queue_redraw()

func _update(delta: float) -> void:
	if not my_alive: return

	# ── Figure movement ──────────────────────────────────────────────────────
	my_vx = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  my_vx = -MOVE_SPD
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): my_vx =  MOVE_SPD
	my_x    = clamp(my_x + my_vx * delta, FIG_MIN_X, FIG_MAX_X)
	my_lean = lerpf(my_lean, my_vx / MOVE_SPD * 0.38, delta * 9.0)
	my_kick = max(0.0, my_kick - delta)

	# ── Ball physics ─────────────────────────────────────────────────────────
	my_bvel.y += GRAVITY * delta
	my_ball   += my_bvel * delta

	if my_ball.x - BALL_R < WALL_L:
		my_ball.x = WALL_L + BALL_R;  my_bvel.x =  absf(my_bvel.x) * BOUNCE_DAMP
	elif my_ball.x + BALL_R > WALL_R:
		my_ball.x = WALL_R - BALL_R;  my_bvel.x = -absf(my_bvel.x) * BOUNCE_DAMP
	if my_ball.y - BALL_R < CEILING_Y:
		my_ball.y = CEILING_Y + BALL_R; my_bvel.y = absf(my_bvel.y) * BOUNCE_DAMP

	if my_ball.y + BALL_R >= GROUND_Y:
		my_alive = false
		winner   = "opponent"
		if not solo: _net_lost.rpc()
		return

	# ── Speed ramp ───────────────────────────────────────────────────────────
	my_ramp_t += delta
	if my_ramp_t >= RAMP_INTERVAL:
		my_ramp_t = 0.0
		my_speed  = min(my_speed * RAMP_FACTOR, 2.8)
		if my_bvel.length() < MAX_BSPEED:
			my_bvel *= 1.05   # gradually speed up ball in air too

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
	my_kick = KICK_DURATION
	var dx      := absf(my_ball.x - my_x)
	var ball_h  := GROUND_Y - my_ball.y   # distance above ground (positive = airborne)
	if dx < KICK_RANGE_X and ball_h >= 0.0 and ball_h < KICK_RANGE_Y:
		var dir_x := (my_ball.x - my_x) * 1.3              # kick away from body
		var rnd_x := randf_range(-KICK_RAND_X, KICK_RAND_X)
		my_bvel   = Vector2(dir_x + rnd_x, KICK_VEL_Y) * my_speed

# ══════════════════════════════════ RPCs ══════════════════════════════════════
@rpc("any_peer", "call_remote", "unreliable")
func _net_state(x: float, lean: float, bx: float, by: float, kick: float) -> void:
	op_x = x;  op_lean = lean
	op_ball = Vector2(bx, by);  op_kick = kick

@rpc("any_peer", "call_remote", "reliable")
func _net_lost() -> void:
	winner = "you";  op_alive = false

# ══════════════════════════════════ DRAW ══════════════════════════════════════
func _draw() -> void:
	if not game_on: return
	_draw_pitch()
	_draw_half(0.0,      my_x, my_lean, my_ball, my_kick, my_alive, true)
	_draw_half(HALF_W,   op_x, op_lean, op_ball, op_kick, op_alive, false)
	# Vertical divider — the centre line
	draw_line(Vector2(HALF_W, 0), Vector2(HALF_W, SH), Color.WHITE, 3.0)
	draw_circle(Vector2(HALF_W, SH / 2.0), 9.0, Color.WHITE)
	if winner != "": _draw_banner()

# ── Football pitch background ─────────────────────────────────────────────────
func _draw_pitch() -> void:
	# Alternating green stripes across full width
	var sw := float(SW) / 10.0
	for i in range(10):
		var c := Color(0.10, 0.40, 0.10) if i % 2 == 0 else Color(0.12, 0.46, 0.12)
		draw_rect(Rect2(i * sw, 0, sw, GROUND_Y), c)
	# Grass strip at bottom
	draw_rect(Rect2(0, GROUND_Y, SW, GRASS_H), Color(0.08, 0.30, 0.08))
	# Ground line
	draw_line(Vector2(0, GROUND_Y), Vector2(SW, GROUND_Y), Color(1, 1, 1, 0.5), 2.0)
	# Goal areas at base of each half
	var gw := 130.0;  var gh := 40.0
	for ox in [0.0, float(HALF_W)]:
		draw_rect(Rect2(ox + HALF_W / 2.0 - gw / 2.0, GROUND_Y, gw, gh),
				  Color(1, 1, 1, 0.25), false)

# ── One player's half ─────────────────────────────────────────────────────────
func _draw_half(ox: float, fig_x: float, lean: float, ball: Vector2,
		kick_t: float, alive: bool, is_mine: bool) -> void:

	var fig_col  := Color(0.30, 0.62, 1.00) if is_mine else Color(1.00, 0.38, 0.28)
	var ball_col := Color.WHITE

	if alive:
		var hip := Vector2(ox + fig_x, GROUND_Y - LEG_LEN)
		_draw_figure(hip, lean, kick_t, fig_col)
		_draw_ball(Vector2(ox + ball.x, ball.y), ball_col)
	elif solo and not is_mine:
		# Solo mode: show idle grey placeholder on opponent side
		var hip := Vector2(ox + HALF_W / 2.0, GROUND_Y - LEG_LEN)
		_draw_figure(hip, 0.0, 0.0, Color(0.55, 0.55, 0.55))
	else:
		_draw_fallen(Vector2(ox + fig_x, GROUND_Y), fig_col)

	var label := "YOU  [A / D + SPACE]" if is_mine else ("OPPONENT" if op_alive else ("—" if solo else "WAITING…"))
	_lbl(Vector2(ox + HALF_W / 2.0, 20.0), label, Color.WHITE, 14)

# ── Stick figure ──────────────────────────────────────────────────────────────
func _draw_figure(hip: Vector2, lean: float, kick_t: float, col: Color) -> void:
	var lw  := 4.0
	var lw2 := 3.0

	# ── Upper body ───────────────────────────────────────────────────────────
	var neck := hip + Vector2(lean * 16.0, -BODY_LEN)
	var head := neck + Vector2(lean * 5.0, -HEAD_R * 1.6)

	# Shoulders — small horizontal bar at neck
	var ls := neck + Vector2(-14.0 - lean * 4.0, 4.0)
	var rs := neck + Vector2( 14.0 + lean * 4.0, 4.0)

	# ── Legs ─────────────────────────────────────────────────────────────────
	var thigh := LEG_LEN * 0.50
	# Natural slight outward bend at knees, feet wider than knees
	var lk := hip + Vector2(-13.0 + lean * 3.0, thigh)
	var rk := hip + Vector2( 13.0 + lean * 3.0, thigh)
	var lf := Vector2(hip.x - 17.0 + lean * 2.0, GROUND_Y)
	var rf  := Vector2(hip.x + 17.0 + lean * 2.0, GROUND_Y)

	if kick_t > 0.0:
		var p := sin((1.0 - kick_t / KICK_DURATION) * PI)
		rk = hip + Vector2(14.0 + p * 26.0, thigh * (1.0 - p * 0.5))
		rf = Vector2(hip.x + 16.0 + p * 56.0, hip.y + LEG_LEN * 0.78 - p * 42.0)

	# Thighs & shins
	draw_line(hip, lk, col, lw,  true)
	draw_line(lk, lf,  col, lw2, true)
	draw_line(hip, rk, col, lw,  true)
	draw_line(rk, rf,  col, lw2, true)

	# Knee dots
	draw_circle(lk, 3.5, col)
	draw_circle(rk, 3.5, col)

	# Feet — short horizontal lines
	draw_line(lf + Vector2(-8.0, 0), lf + Vector2(5.0, 0), col, lw2, true)
	if kick_t > 0.0:
		var p := sin((1.0 - kick_t / KICK_DURATION) * PI)
		draw_line(rf + Vector2(-4.0, p * -3.0), rf + Vector2(9.0, p * 3.0), col, lw2, true)
	else:
		draw_line(rf + Vector2(-5.0, 0), rf + Vector2(8.0, 0), col, lw2, true)

	# ── Torso ────────────────────────────────────────────────────────────────
	# Hip-width bar
	draw_line(hip + Vector2(-10.0, 0), hip + Vector2(10.0, 0), col, lw2, true)
	draw_line(hip, neck, col, lw, true)

	# ── Arms ─────────────────────────────────────────────────────────────────
	var la := ls + Vector2(-ARM_LEN * 0.72 - lean * 10.0, ARM_LEN * 0.78)
	var ra := rs + Vector2( ARM_LEN * 0.72 + lean * 10.0, ARM_LEN * 0.78)
	if kick_t > 0.0:
		var p := sin((1.0 - kick_t / KICK_DURATION) * PI)
		la = ls + Vector2(-ARM_LEN * 1.2, -ARM_LEN * 0.30 + p * ARM_LEN * 0.55)
		ra = rs + Vector2( ARM_LEN * 0.55, -ARM_LEN * 0.18)

	draw_line(ls, la, col, lw2, true)
	draw_line(rs, ra, col, lw2, true)
	# Hand dots
	draw_circle(la, 3.0, col)
	draw_circle(ra, 3.0, col)

	# ── Head ─────────────────────────────────────────────────────────────────
	draw_circle(head, HEAD_R, col)
	var dark := Color(col.r * 0.25, col.g * 0.25, col.b * 0.25)
	draw_arc(head, HEAD_R, 0.0, TAU, 20, dark, 1.8)
	draw_circle(head + Vector2(HEAD_R * 0.36 + lean * 3.5, -HEAD_R * 0.12), 3.0, dark)

func _draw_fallen(base: Vector2, col: Color) -> void:
	var lw   := 3.5
	var dark := Color(col.r * 0.22, col.g * 0.22, col.b * 0.22)

	# Anchor points — figure lying on back, body goes left from feet
	var hips  := base + Vector2(-8.0,  -3.0)
	var shldr := base + Vector2(-62.0, -9.0)
	var head  := shldr + Vector2(-HEAD_R * 1.1, -HEAD_R * 0.4)

	# Torso flat on ground
	draw_line(hips, shldr, col, 4.5, true)

	# Legs — lying along the ground (knees slightly bent, natural)
	var lk := base + Vector2(20.0, -14.0)   # left knee raised a little
	var rk := base + Vector2(36.0,  -3.0)   # right knee nearly flat
	var lf := base + Vector2(38.0,   0.0)   # left foot on ground
	var rf  := base + Vector2(54.0,  -1.0)  # right foot on ground
	draw_line(hips, lk, col, lw,        true)
	draw_line(lk,   lf, col, lw * 0.8,  true)
	draw_line(hips, rk, col, lw,        true)
	draw_line(rk,   rf, col, lw * 0.8,  true)
	# Knee dots
	draw_circle(lk, 3.0, col)
	draw_circle(rk, 3.0, col)
	# Feet flat on ground
	draw_line(lf + Vector2(-3.0, 0), lf + Vector2(9.0, 0), col, lw * 0.8, true)
	draw_line(rf + Vector2(-3.0, 0), rf + Vector2(9.0, 0), col, lw * 0.8, true)

	# Left arm — resting on the ground above the head
	var la := shldr + Vector2(-22.0, 18.0)
	draw_line(shldr, la, col, lw * 0.85, true)
	draw_circle(la, 3.0, col)

	# Right arm — resting on ground beside body
	var ra := shldr + Vector2(16.0, 14.0)
	draw_line(shldr, ra, col, lw * 0.85, true)
	draw_circle(ra, 3.0, col)

	# Head lying sideways, slightly off the ground
	draw_circle(head, HEAD_R, col)
	draw_arc(head, HEAD_R, 0.0, TAU, 20, dark, 1.8)
	# Closed eyes (two short X lines)
	draw_line(head + Vector2(-4.5, -2.5), head + Vector2(-1.5,  0.5), dark, 1.8)
	draw_line(head + Vector2(-1.5, -2.5), head + Vector2(-4.5,  0.5), dark, 1.8)
	draw_line(head + Vector2( 0.5, -2.5), head + Vector2( 3.5,  0.5), dark, 1.8)
	draw_line(head + Vector2( 3.5, -2.5), head + Vector2( 0.5,  0.5), dark, 1.8)

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
	var win := winner == "you"
	var text := "YOU WIN!" if win else "YOU LOSE…"
	var col  := Color(0.25, 1.0, 0.3) if win else Color(1.0, 0.3, 0.25)
	draw_rect(Rect2(SW / 2.0 - 220, SH / 2.0 - 44, 440, 88), Color(0, 0, 0, 0.82))
	_lbl(Vector2(SW / 2.0, SH / 2.0 + 10.0), text, col, 42)

func _lbl(centre: Vector2, text: String, col: Color, fs: int) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, centre + Vector2(-sz.x / 2.0, sz.y * 0.35),
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
