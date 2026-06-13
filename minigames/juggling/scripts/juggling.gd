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
const EMBED_WIN_KICKS := 6   # reach this many clean kicks to "win" the embedded super
var embedded := false
var _result_emitted := false

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
	_run_countdown()


func _emit_embedded_result(result: int) -> void:
	if _result_emitted:
		return
	_result_emitted = true
	await get_tree().create_timer(1.1).timeout  # let the WINNER/LOSER banner show
	minigame_finished.emit(result)

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
		_emit_embedded_result(1 if winner == "you" else 0)
	if winner == "":
		_update(delta)
		if not solo and op_alive:
			var signed_kick := my_kick * (1.0 if my_kick_right else -1.0)
			_net_state.rpc(my_x, my_lean, my_ball.x, my_ball.y, signed_kick)
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
			if embedded and my_kick_count >= EMBED_WIN_KICKS:
				winner = "you"   # kept the ball up long enough — super lands
			var dir_x := (my_ball.x - my_x) * 1.3
			var rnd_x := randf_range(-KICK_RAND_X, KICK_RAND_X)
			my_bvel   = Vector2(dir_x + rnd_x, KICK_VEL_Y) * my_speed

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
func _net_state(x: float, lean: float, bx: float, by: float, kick: float) -> void:
	op_x = x;  op_lean = lean
	op_ball = Vector2(bx, by)
	op_kick_right = kick >= 0.0
	op_kick = absf(kick)

@rpc("any_peer", "call_remote", "reliable")
func _net_lost() -> void:
	winner = "you";  op_alive = false

# ══════════════════════════════════ DRAW ══════════════════════════════════════
func _draw() -> void:
	_draw_pitch()
	_draw_half(0.0,    my_x, my_lean, my_ball, my_kick, my_alive, true,  my_kick_right)
	_draw_half(HALF_W, op_x, op_lean, op_ball, op_kick, op_alive, false, op_kick_right)
	if game_on and winner == "":
		_lbl_outlined(Vector2(38.0, 130.0), str(my_kick_count), Color.WHITE, 52)
	if _countdown_text != "":
		_lbl(Vector2(SW / 2.0, SH / 2.0), _countdown_text, Color.WHITE, 96)
	elif winner != "":
		_draw_banner()

# ── Night stadium pitch (same style as typeracer) ────────────────────────────
func _draw_pitch() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var crowd := 68.0   # stand height top and bottom

	# Stadium base
	draw_rect(Rect2(0, 0, SW, SH), Color("#070b1f"))
	draw_rect(Rect2(0, 0, SW, SH * 0.5), Color(0.10, 0.14, 0.31, 0.22))

	# Stands
	draw_rect(Rect2(0, 0, SW, crowd), Color("#0b1230"))
	draw_rect(Rect2(0, SH - crowd, SW, crowd), Color("#0b1230"))
	_draw_crowd_dots(0.0, crowd)
	_draw_crowd_dots(SH - crowd, crowd)
	draw_rect(Rect2(0, crowd - 6, SW, 6), Color("#11183a"))
	draw_rect(Rect2(0, SH - crowd, SW, 6), Color("#11183a"))

	# Mown grass stripes
	var stripe_w := float(SW) / 16.0
	var py := crowd
	var ph := SH - 2.0 * crowd
	var sx := 0.0
	var si := 0
	while sx < SW:
		var sc := Color("#2e8f4e") if si % 2 == 0 else Color("#2a833f")
		draw_rect(Rect2(sx, py, minf(stripe_w, SW - sx), ph), sc)
		sx += stripe_w
		si += 1

	# Ground line
	draw_line(Vector2(0, GROUND_Y), Vector2(SW, GROUND_Y), Color(1, 1, 1, 0.45), 2.0)

	# Centre divider — pulsing glow like typeracer
	var pulse := 0.55 + 0.45 * sin(t * 1.6)
	var dy := py + ph * 0.03
	var dh := ph * 0.94
	draw_rect(Rect2(HALF_W - 7, dy, 14, dh), Color(0.6, 0.72, 1.0, 0.12 * pulse))
	draw_rect(Rect2(HALF_W - 3, dy, 6,  dh), Color(0.8, 0.86, 1.0, 0.30 * pulse))
	draw_rect(Rect2(HALF_W - 1.5, dy, 3, dh), Color(1, 1, 1, 0.92))
	# Floodlights
	for fx: float in [0.09, 0.5, 0.91]:
		_draw_floodlight(SW * fx, t, true)
		_draw_floodlight(SW * fx, t, false)

	# Edge vignette
	var vig := Color(0.016, 0.027, 0.07, 0.45)
	draw_rect(Rect2(0, 0, SW, 4), vig)
	draw_rect(Rect2(0, SH - 4, SW, 4), vig)
	draw_rect(Rect2(0, 0, 4, SH), vig)
	draw_rect(Rect2(SW - 4, 0, 4, SH), vig)


func _draw_crowd_dots(top: float, band_h: float) -> void:
	var step := 18.0
	var y := top + 5.0
	while y < top + band_h - 3.0:
		var x := 5.0
		while x < SW:
			draw_circle(Vector2(x, y), 1.0, Color(0.84, 0.88, 1.0, 0.5))
			x += step
		y += step


func _draw_floodlight(x: float, t: float, top: bool) -> void:
	var bank_w := 34.0
	var bank_h := 15.0
	var pole_h := 38.0
	var bank_y := 8.0 if top else SH - 8.0 - bank_h
	var pole_y := bank_y + bank_h if top else bank_y - pole_h
	var center := Vector2(x, bank_y + bank_h * 0.5)
	var glow   := 0.85 + 0.15 * sin(t * 1.1)
	for k in range(4):
		draw_circle(center, 62.0 * glow * (1.0 - float(k) / 4.0 * 0.55),
				Color(1.0, 0.97, 0.88, 0.10))
	draw_rect(Rect2(x - 2.0, pole_y, 4.0, pole_h), Color("#283154"))
	draw_rect(Rect2(x - bank_w * 0.5, bank_y, bank_w, bank_h), Color("#0c1228"))
	var face := Rect2(x - bank_w * 0.5 + 2.0, bank_y + 2.0, bank_w - 4.0, bank_h - 4.0)
	draw_rect(face, Color(1.0, 0.97, 0.85, 0.95 * glow))
	for k in range(1, 4):
		var lx := face.position.x + face.size.x * float(k) / 4.0
		draw_rect(Rect2(lx, face.position.y, 1.0, face.size.y), Color("#0c1228"))

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

	var label := "YOU  [A / D + SPACE]" if is_mine else ("OPPONENT" if op_alive else ("—" if solo else "WAITING…"))
	_lbl(Vector2(ox + HALF_W / 2.0, 86.0), label, Color.WHITE, 14)

# ── Stick figure ──────────────────────────────────────────────────────────────
func _draw_figure(hip: Vector2, lean: float, kick_t: float, col: Color, kick_right: bool) -> void:
	var lw  := 4.0
	var lw2 := 3.0
	var p   := 0.0
	if kick_t > 0.0:
		p = sin((1.0 - kick_t / KICK_DURATION) * PI)

	# ── Upper body ───────────────────────────────────────────────────────────
	var neck := hip + Vector2(lean * 16.0, -BODY_LEN)
	var head := neck + Vector2(lean * 5.0, -HEAD_R * 1.6)

	var ls := neck + Vector2(-14.0 - lean * 4.0, 4.0)
	var rs := neck + Vector2( 14.0 + lean * 4.0, 4.0)

	# ── Legs ─────────────────────────────────────────────────────────────────
	var thigh := LEG_LEN * 0.50
	var lk := hip + Vector2(-13.0 + lean * 3.0, thigh)
	var rk := hip + Vector2( 13.0 + lean * 3.0, thigh)
	var lf := Vector2(hip.x - 17.0 + lean * 2.0, GROUND_Y)
	var rf  := Vector2(hip.x + 17.0 + lean * 2.0, GROUND_Y)

	if kick_t > 0.0:
		if kick_right:
			rk = hip + Vector2(14.0 + p * 26.0,  thigh * (1.0 - p * 0.5))
			rf = Vector2(hip.x + 16.0 + p * 56.0, hip.y + LEG_LEN * 0.78 - p * 42.0)
		else:
			lk = hip + Vector2(-14.0 - p * 26.0,  thigh * (1.0 - p * 0.5))
			lf = Vector2(hip.x - 16.0 - p * 56.0, hip.y + LEG_LEN * 0.78 - p * 42.0)

	# Thighs & shins
	draw_line(hip, lk, col, lw,  true)
	draw_line(lk, lf,  col, lw2, true)
	draw_line(hip, rk, col, lw,  true)
	draw_line(rk, rf,  col, lw2, true)

	# Knee dots
	draw_circle(lk, 3.5, col)
	draw_circle(rk, 3.5, col)

	# Feet
	if kick_t > 0.0 and not kick_right:
		draw_line(lf + Vector2(-9.0, p * 3.0), lf + Vector2(4.0, p * -3.0), col, lw2, true)
	else:
		draw_line(lf + Vector2(-8.0, 0), lf + Vector2(5.0, 0), col, lw2, true)

	if kick_t > 0.0 and kick_right:
		draw_line(rf + Vector2(-4.0, p * -3.0), rf + Vector2(9.0, p * 3.0), col, lw2, true)
	else:
		draw_line(rf + Vector2(-5.0, 0), rf + Vector2(8.0, 0), col, lw2, true)

	# ── Torso ────────────────────────────────────────────────────────────────
	draw_line(hip + Vector2(-10.0, 0), hip + Vector2(10.0, 0), col, lw2, true)
	draw_line(hip, neck, col, lw, true)

	# ── Arms — opposite arm swings back during kick for balance ──────────────
	var la := ls + Vector2(-ARM_LEN * 0.72 - lean * 10.0, ARM_LEN * 0.78)
	var ra := rs + Vector2( ARM_LEN * 0.72 + lean * 10.0, ARM_LEN * 0.78)
	if kick_t > 0.0:
		if kick_right:
			la = ls + Vector2(-ARM_LEN * 1.2, -ARM_LEN * 0.30 + p * ARM_LEN * 0.55)
			ra = rs + Vector2( ARM_LEN * 0.55, -ARM_LEN * 0.18)
		else:
			ra = rs + Vector2( ARM_LEN * 1.2, -ARM_LEN * 0.30 + p * ARM_LEN * 0.55)
			la = ls + Vector2(-ARM_LEN * 0.55, -ARM_LEN * 0.18)

	draw_line(ls, la, col, lw2, true)
	draw_line(rs, ra, col, lw2, true)
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
