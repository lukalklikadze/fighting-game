extends Node2D
## Trash-talk intro sequence: fighters walk in, dramatic VS split, then dialog.
## Emit `intro_finished` when the sequence is done so the game can start.

signal intro_finished

const SW := 1280
const SH := 720

# Fighter accent colours (match juggling / beer colour scheme)
const PLAYER_COL := Color(0.28, 0.56, 1.00)
const OPP_COL    := Color(1.00, 0.36, 0.24)

# Placeholder rectangle fighters
const FIG_W : float = 88.0
const FIG_H : float = 168.0

# Stage layout
const GROUND_Y      : float = SH * 0.72          # 518 — feet / floor line
const PLAYER_STOP_X : float = SW * 0.5 - 128.0   # 512 — stops left of centre
const OPP_STOP_X    : float = SW * 0.5 + 40.0    # 680 — stops right of centre

# Camera zoom
const ZOOM_NORMAL := Vector2(1.0, 1.0)
const ZOOM_IN     := Vector2(1.5, 1.5)

# ─── Animation state ─────────────────────────────────────────────────────────
var player_x : float = -FIG_W - 40.0
var opp_x    : float = SW + 40.0
var _vs_alpha : float = 0.0
var _show_vs  : bool  = false

# ─── Dialog data ─────────────────────────────────────────────────────────────
# Fill each entry's `text` and `duration` with real trash-talk later.
# `side` is "player" or "opp".
var _dialogs : Array[Dictionary] = [
	{side = "player", text = "...", duration = 2.5},
	{side = "opp",    text = "...", duration = 2.5},
]

var _show_dialogs  : bool   = false
var _active_side   : String = ""
var _active_text   : String = ""

# ─── Node refs ───────────────────────────────────────────────────────────────
var _font         : Font
var _camera       : Camera2D
var _player_panel : PanelContainer
var _player_label : Label
var _opp_panel    : PanelContainer
var _opp_label    : Label


# ═══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	get_window().content_scale_size   = Vector2i(SW, SH)
	get_window().content_scale_mode   = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

	# Same handwritten font as typeracer / juggling
	var base := SystemFont.new()
	base.font_names = PackedStringArray([
		"Marker Felt", "Chalkboard SE", "Noteworthy", "Bradley Hand",
		"Segoe Script", "Comic Sans MS",
	])
	var chubby := FontVariation.new()
	chubby.base_font = base
	chubby.variation_embolden = 0.6
	_font = chubby

	# Camera centred on stage, initially at normal zoom
	_camera          = Camera2D.new()
	_camera.position = Vector2(SW * 0.5, SH * 0.5)
	_camera.zoom     = ZOOM_NORMAL
	add_child(_camera)

	_setup_dialog_ui()
	_run_intro()


# ─── Main sequence ────────────────────────────────────────────────────────────
func _run_intro() -> void:
	# ── 1. Fighters walk in from opposite sides ────────────────────────────
	var tw1 := create_tween().set_parallel(true)
	tw1.tween_method(_set_px, player_x, PLAYER_STOP_X, 1.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw1.tween_method(_set_ox, opp_x, OPP_STOP_X, 1.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw1.finished

	await get_tree().create_timer(0.12).timeout

	# ── 2. Camera zooms in on the face-off ────────────────────────────────
	var tw2 := create_tween()
	tw2.tween_method(_set_zoom, 1.0, ZOOM_IN.x, 0.40) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await tw2.finished

	# ── 3. VS overlay fades in ────────────────────────────────────────────
	_show_vs = true
	var tw3 := create_tween()
	tw3.tween_method(_set_vs_alpha, 0.0, 1.0, 0.25)
	await tw3.finished

	await get_tree().create_timer(1.2).timeout

	# ── 4. Camera zooms back out ──────────────────────────────────────────
	var tw4 := create_tween()
	tw4.tween_method(_set_zoom, ZOOM_IN.x, 1.0, 0.40) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw4.finished

	_show_vs = false
	queue_redraw()

	await get_tree().create_timer(0.25).timeout

	# ── 5. Trash-talk dialog sequence ─────────────────────────────────────
	for d: Dictionary in _dialogs:
		_active_side  = d["side"]
		_active_text  = d["text"]
		_show_dialogs = true
		_refresh_dialog_ui()
		await get_tree().create_timer(float(d["duration"])).timeout

	_show_dialogs         = false
	_player_panel.visible = false
	_opp_panel.visible    = false

	await get_tree().create_timer(0.35).timeout
	intro_finished.emit()


# ─── Tween helpers ────────────────────────────────────────────────────────────
func _set_px(v: float) -> void:       player_x = v;                     queue_redraw()
func _set_ox(v: float) -> void:       opp_x    = v;                     queue_redraw()
func _set_zoom(v: float) -> void:     _camera.zoom = Vector2(v, v);     queue_redraw()
func _set_vs_alpha(v: float) -> void: _vs_alpha = v;                    queue_redraw()


# ─── Dialog UI ────────────────────────────────────────────────────────────────
func _setup_dialog_ui() -> void:
	# CanvasLayer keeps dialogs in screen-space so camera zoom doesn't affect them
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	var pp := _make_panel(layer, 55.0,          SH - 190.0, 420.0, PLAYER_COL)
	_player_panel = pp[0];  _player_label = pp[1]

	var op := _make_panel(layer, SW - 475.0, SH - 190.0, 420.0, OPP_COL)
	_opp_panel = op[0];  _opp_label = op[1]

	_player_panel.visible = false
	_opp_panel.visible    = false


func _make_panel(parent: Node, x: float, y: float, w: float,
		accent: Color) -> Array:
	var panel := PanelContainer.new()
	panel.position = Vector2(x, y)

	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.04, 0.04, 0.09, 0.93)
	style.border_color               = accent
	style.border_width_left          = 3
	style.border_width_right         = 3
	style.border_width_top           = 3
	style.border_width_bottom        = 3
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left        = 16
	style.content_margin_right       = 16
	style.content_margin_top         = 14
	style.content_margin_bottom      = 14
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.autowrap_mode           = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size     = Vector2(w, 0)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	lbl.add_theme_constant_override("outline_size", 4)
	panel.add_child(lbl)
	parent.add_child(panel)

	return [panel, lbl]


func _refresh_dialog_ui() -> void:
	_player_panel.visible = (_active_side == "player") and _show_dialogs
	_opp_panel.visible    = (_active_side == "opp")    and _show_dialogs
	if _active_side == "player":
		_player_label.text = _active_text
	elif _active_side == "opp":
		_opp_label.text = _active_text


# ═══════════════════════════════════════════════════════════════════════════════
#  Drawing
# ═══════════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	# Background gradient — dark blue-purple top, dark warm bottom
	draw_polygon(
		PackedVector2Array([
			Vector2(0, 0), Vector2(SW, 0), Vector2(SW, SH), Vector2(0, SH)]),
		PackedColorArray([
			Color(0.06, 0.05, 0.16), Color(0.06, 0.05, 0.16),
			Color(0.12, 0.07, 0.04), Color(0.12, 0.07, 0.04),
		])
	)

	# Subtle overhead glow (arena lighting atmosphere)
	for i in range(4):
		var fi := float(i)
		draw_circle(Vector2(SW * 0.5, -60.0),
				280.0 + fi * 110.0,
				Color(0.28, 0.20, 0.55, 0.055 - fi * 0.010))

	# Floor slab
	draw_rect(Rect2(0, GROUND_Y, SW, SH - GROUND_Y), Color(0.07, 0.05, 0.03))
	draw_line(Vector2(0, GROUND_Y), Vector2(SW, GROUND_Y),
			Color(0.65, 0.50, 0.28, 0.90), 3.0)
	draw_rect(Rect2(0, GROUND_Y + 3.0, SW, 6.0), Color(1, 1, 1, 0.05))

	# Fighter shadows (flat ellipses on the floor line)
	_draw_shadow(player_x)
	_draw_shadow(opp_x)

	# Fighter rectangles
	_draw_fighter(player_x, PLAYER_COL, false)
	_draw_fighter(opp_x,    OPP_COL,    true)

	# VS overlay (active only during the zoom-in phase)
	if _show_vs and _vs_alpha > 0.0:
		_draw_vs()


func _draw_shadow(rx: float) -> void:
	var cx  := rx + FIG_W * 0.5
	var pts := PackedVector2Array()
	for i in range(22):
		var a := float(i) / 22.0 * TAU
		pts.append(Vector2(cx + cos(a) * FIG_W * 0.60, GROUND_Y + sin(a) * 11.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.32))


func _draw_fighter(rx: float, col: Color, flip: bool) -> void:
	var ry := GROUND_Y - FIG_H

	# Body fill
	draw_rect(Rect2(rx, ry, FIG_W, FIG_H), col)

	# Shading — dark strip on the inward side (facing opponent)
	var shd_x := rx if not flip else rx + FIG_W - 20.0
	draw_rect(Rect2(shd_x, ry, 20.0, FIG_H), Color(0, 0, 0, 0.20))

	# Rim light — bright strip on the outer edge
	var rim_x := rx + FIG_W - 5.0 if not flip else rx
	draw_rect(Rect2(rim_x, ry, 5.0, FIG_H), Color(1, 1, 1, 0.14))

	# Top highlight
	draw_rect(Rect2(rx, ry, FIG_W, 7.0), Color(1, 1, 1, 0.22))

	# Outline
	draw_rect(Rect2(rx, ry, FIG_W, FIG_H), col.darkened(0.40), false, 2.5)

	# Eye — on the inward (facing) side
	var eye_xf := 0.70 if not flip else 0.30
	var eye_c  := Vector2(rx + FIG_W * eye_xf, ry + FIG_H * 0.11)
	draw_circle(eye_c, 8.0, Color.WHITE)
	draw_circle(eye_c, 4.0, Color(0.08, 0.08, 0.12))
	draw_circle(eye_c + Vector2(1.5, -1.5), 1.5, Color(1, 1, 1, 0.7))  # specular

	# Name tag
	var tag := "PLAYER 1" if not flip else "PLAYER 2"
	var sz  := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var tp  := Vector2(rx + FIG_W * 0.5 - sz.x * 0.5, ry - 12.0)
	# Outline
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			draw_string(_font, tp + Vector2(float(dx), float(dy)), tag,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.7))
	draw_string(_font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))


func _draw_vs() -> void:
	var a  := _vs_alpha
	var cx := float(SW) * 0.5

	# Half-screen colour washes
	draw_rect(Rect2(0,  0, cx, SH),
			Color(PLAYER_COL.r, PLAYER_COL.g, PLAYER_COL.b, 0.20 * a))
	draw_rect(Rect2(cx, 0, cx, SH),
			Color(OPP_COL.r, OPP_COL.g, OPP_COL.b, 0.20 * a))

	# Lightning zigzag from top to bottom
	var pts := PackedVector2Array()
	var n   := 14
	var amp := 56.0
	for i in range(n + 1):
		var yy := float(i) / float(n) * float(SH)
		var xx := cx + (amp if i % 2 == 0 else -amp)
		pts.append(Vector2(xx, yy))

	# Layered glow — widest / faintest first, sharpest / brightest last
	draw_polyline(pts, Color(1.0, 0.88, 0.20, 0.10 * a), 54.0, true)
	draw_polyline(pts, Color(1.0, 0.92, 0.32, 0.28 * a), 26.0, true)
	draw_polyline(pts, Color(1.0, 0.98, 0.65, 0.60 * a),  9.0, true)
	draw_polyline(pts, Color(1.0, 1.00, 0.95,       a),   2.5, true)

	# VS text with dark outline
	var fs  := 108
	var sz  := _font.get_string_size("VS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var tp  := Vector2(cx - sz.x * 0.5, float(SH) * 0.5 + sz.y * 0.35)
	for dx: int in [-4, 0, 4]:
		for dy: int in [-4, 0, 4]:
			if dx == 0 and dy == 0: continue
			draw_string(_font, tp + Vector2(float(dx), float(dy)), "VS",
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.02, 0.0, a))
	draw_string(_font, tp, "VS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1.0, 0.94, 0.18, a))
