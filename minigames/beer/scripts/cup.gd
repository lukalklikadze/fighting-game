extends Control
## A glass cup that fills with beer. `fill` is 0..1 where 1.0 == the brim;
## values above 1.0 spill over the rim.

const AMBER := Color("#eba000")        # beer
const FOAM := Color("#fff6e0")         # head / foam
const GLASS_LINE := Color(0.88, 0.93, 1.0, 0.9)
const GLASS_TINT := Color(0.8, 0.9, 1.0, 0.07)
const BRIM := Color(1, 1, 1, 0.65)     # target line at the brim
const PUDDLE := Color(0.92, 0.63, 0.0, 0.85)

var fill := 0.0


func set_fill(v: float) -> void:
	fill = v
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return

	# A stout mug body, shifted slightly left to leave room for the handle.
	var cw: float = min(s.x * 0.5, 200.0)
	var ch: float = min(s.y * 0.55, 300.0)
	var x := (s.x - cw) * 0.5 - 18.0
	var y := (s.y - ch) * 0.5

	var m := 12.0
	var ix := x + m
	var iw := cw - 2.0 * m
	# fill==1.0 reaches the brim line, which sits right at the top rim.
	var brim_y := y + 5.0
	var base_y := y + ch - m
	var ih := base_y - brim_y

	# --- handle: a glass "C" attached to the right wall (drawn behind body) ---
	var hr := ch * 0.2
	var ang := PI / 3.0
	var hc := Vector2(x + cw - hr * 0.5, y + ch * 0.46)
	draw_arc(hc, hr, -ang, ang, 24, GLASS_LINE, 14.0)

	var f: float = clamp(fill, 0.0, 1.0)
	var beer_h := ih * f
	var beer_y := base_y - beer_h

	# beer
	if beer_h > 0.0:
		draw_rect(Rect2(ix, beer_y, iw, beer_h), AMBER)
	# foam at the surface
	if fill > 0.015:
		var foam_h: float = min(18.0, beer_h)
		draw_rect(Rect2(ix, beer_y, iw, foam_h), FOAM)

	# mug facets (subtle vertical glass lines)
	for k in range(1, 4):
		var lx := ix + iw * float(k) / 4.0
		draw_line(Vector2(lx, brim_y), Vector2(lx, base_y), Color(1, 1, 1, 0.06), 2.0)

	# brim target line (== fill 1.0, at the rim)
	_dashed_line(ix, brim_y, iw, BRIM)

	# spill: beer foaming over the rim + a puddle at the base
	if fill > 1.0:
		var over: float = min(fill - 1.0, 0.4)
		var oh := ih * over + 8.0
		draw_rect(Rect2(ix - 6.0, brim_y - oh, iw + 12.0, oh), FOAM)
		draw_rect(Rect2(x - 16.0, y + ch - 4.0, cw + 40.0, 10.0), PUDDLE)

	# mug walls + a base lip for a chunky look
	draw_rect(Rect2(x, y, cw, ch), GLASS_TINT)
	draw_rect(Rect2(x, y, cw, ch), GLASS_LINE, false, 5.0)
	draw_rect(Rect2(x - 4.0, y + ch - 10.0, cw + 8.0, 10.0), GLASS_LINE, false, 5.0)


func _dashed_line(x: float, y: float, w: float, col: Color) -> void:
	var seg := 11.0
	var xx := x
	while xx < x + w:
		draw_line(Vector2(xx, y), Vector2(min(xx + seg, x + w), y), col, 2.0)
		xx += seg * 1.8
