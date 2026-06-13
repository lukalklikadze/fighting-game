extends Control
## A glass beer mug that fills with beer. `fill` is 0..1 (brim); >1 spills.

const AMBER_TOP  := Color(0.95, 0.72, 0.12, 1.0)
const AMBER_BOT  := Color(0.68, 0.40, 0.02, 1.0)
const FOAM_WHITE := Color(0.97, 0.95, 0.88, 1.0)
const FOAM_CREAM := Color(0.88, 0.83, 0.72, 1.0)
const GLASS_LINE := Color(0.88, 0.93, 1.0, 0.9)
const GLASS_TINT := Color(0.8, 0.9, 1.0, 0.07)
const GLASS_HI   := Color(1.00, 1.00, 1.00, 0.55)
const BRIM       := Color(1, 1, 1, 0.65)

var fill := 0.0


func set_fill(v: float) -> void:
	fill = v
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return

	var cw: float = minf(s.x * 0.5, 200.0)
	var ch: float = minf(s.y * 0.55, 300.0)
	var x  := (s.x - cw) * 0.5 - 18.0
	var y  := (s.y - ch) * 0.5
	var m  := 12.0
	var ix := x + m
	var iw := cw - 2.0 * m
	var brim_y := y + 5.0
	var base_y := y + ch - m
	var ih     := base_y - brim_y

	var f: float = clampf(fill, 0.0, 1.0)
	var beer_h  := ih * f
	var beer_y  := base_y - beer_h

	# Handle (drawn behind the body)
	var hr  := ch * 0.2
	var ang := PI / 3.0
	var hc  := Vector2(x + cw - hr * 0.5, y + ch * 0.46)
	draw_arc(hc, hr, -ang, ang, 24, GLASS_LINE, 14.0)

	# Body tint
	draw_rect(Rect2(x, y, cw, ch), GLASS_TINT)

	# Beer fill — gradient top to bottom
	if beer_h > 0.0:
		draw_polygon(
			PackedVector2Array([
				Vector2(ix,      beer_y),
				Vector2(ix + iw, beer_y),
				Vector2(ix + iw, base_y),
				Vector2(ix,      base_y),
			]),
			PackedColorArray([AMBER_TOP, AMBER_TOP, AMBER_BOT, AMBER_BOT]))

	# Foam head
	if fill > 0.015:
		_draw_foam(ix, iw, beer_y, brim_y)

	# Mug facets
	for k in range(1, 4):
		var lx := ix + iw * float(k) / 4.0
		draw_line(Vector2(lx, brim_y), Vector2(lx, base_y), Color(1, 1, 1, 0.06), 2.0)

	# Brim target line
	_dashed_line(ix, brim_y, iw, BRIM)

	# Spill (only beyond the natural foam zone)
	const FOAM_ZONE := 0.10
	if fill > 1.0 + FOAM_ZONE:
		var over: float = minf(fill - 1.0 - FOAM_ZONE, 0.4)
		var oh := ih * over + 8.0
		draw_rect(Rect2(ix - 6.0, brim_y - oh, iw + 12.0, oh),
				Color(FOAM_WHITE.r, FOAM_WHITE.g, FOAM_WHITE.b, 0.92))

	# Glass walls + base lip
	draw_rect(Rect2(x, y, cw, ch), GLASS_LINE, false, 5.0)
	draw_rect(Rect2(x - 4.0, y + ch - 10.0, cw + 8.0, 10.0), GLASS_LINE, false, 5.0)

	# Glass left-edge highlight
	draw_line(Vector2(x + 6.0, y + 8.0), Vector2(x + 6.0, y + ch - 12.0), GLASS_HI, 5.0)


func _draw_foam(ix: float, iw: float, beer_y: float, brim_y: float) -> void:
	var foam_h   := minf(24.0, (beer_y - brim_y) + 16.0)
	foam_h       = maxf(foam_h, 10.0)
	# Never draw foam above the brim — that only happens during a real spill
	var foam_top := maxf(beer_y - foam_h, brim_y)

	draw_rect(Rect2(ix, foam_top + foam_h * 0.38, iw, foam_h * 0.62), FOAM_CREAM)

	var n: int = maxi(5, int(iw / 20.0))
	var step   := iw / float(n)
	for i in range(n):
		var bx := ix + step * (float(i) + 0.5)
		draw_circle(Vector2(bx, foam_top + foam_h * 0.42), step * 0.56, FOAM_WHITE)
	for i in range(n - 1):
		var bx := ix + step * (float(i) + 1.0)
		draw_circle(Vector2(bx, foam_top + foam_h * 0.22), step * 0.36, FOAM_WHITE)

	draw_line(Vector2(ix + 8.0, foam_top + foam_h * 0.38),
			Vector2(ix + iw - 8.0, foam_top + foam_h * 0.38),
			Color(1.0, 1.0, 1.0, 0.35), 3.0)


func _dashed_line(x: float, y: float, w: float, col: Color) -> void:
	var seg := 11.0
	var xx  := x
	while xx < x + w:
		draw_line(Vector2(xx, y), Vector2(minf(xx + seg, x + w), y), col, 2.0)
		xx += seg * 1.8
