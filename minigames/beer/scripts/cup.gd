extends Control
## A glass beer mug (sprite) that fills with beer. `fill` is 0..1 (brim); >1 spills.
## The beer is drawn behind the translucent glass image so it shows through; on a
## real spill the empty mug swaps to the overflowing one.

const CUP_TEX:       Texture2D = preload("res://assets/beer_cup.png")
const CUP_SPILL_TEX: Texture2D = preload("res://assets/beer_cup_filled.png")

# Beer interior within the (square) cup image, as fractions of the drawn size.
const INT_L   := 0.31   # interior left edge
const INT_R   := 0.66   # interior right edge (excludes the handle)
const INT_TOP := 0.15   # brim — beer top when fill == 1 (finish line)
const INT_BOT := 0.727  # base — beer bottom (the inner base surface / red line)

const FOAM_ZONE := 0.10   # grace above the brim before the mug visibly overflows

const AMBER_TOP  := Color(0.95, 0.72, 0.12, 1.0)
const AMBER_BOT  := Color(0.68, 0.40, 0.02, 1.0)
const FOAM_WHITE := Color(0.97, 0.95, 0.88, 1.0)
const FOAM_CREAM := Color(0.88, 0.83, 0.72, 1.0)
const BRIM       := Color(1, 1, 1, 0.5)

var fill := 0.0


func set_fill(v: float) -> void:
	fill = v
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return

	# Square cup image, centred in the control.
	var side: float = minf(s.x, s.y)
	var rx := (s.x - side) * 0.5
	var ry := (s.y - side) * 0.5
	var spilled := fill > 1.0 + FOAM_ZONE

	# Interior rect (screen space) where the beer sits.
	var ix     := rx + side * INT_L
	var iright := rx + side * INT_R
	var iw     := iright - ix
	var brim_y := ry + side * INT_TOP
	var base_y := ry + side * INT_BOT
	var ih     := base_y - brim_y

	var f: float = clampf(fill, 0.0, 1.0)
	var beer_h := ih * f
	var beer_y := base_y - beer_h

	# Beer fill (behind the glass) — gradient top to bottom.
	if beer_h > 0.0:
		draw_polygon(
			PackedVector2Array([
				Vector2(ix,     beer_y),
				Vector2(iright, beer_y),
				Vector2(iright, base_y),
				Vector2(ix,     base_y),
			]),
			PackedColorArray([AMBER_TOP, AMBER_TOP, AMBER_BOT, AMBER_BOT]))

	# Foam head — also behind the glass.
	if fill > 0.015:
		_draw_foam(ix, iw, beer_y, brim_y)

	# Glass mug sprite on top — swaps to the overflowing mug on a real spill.
	var tex := CUP_SPILL_TEX if spilled else CUP_TEX
	draw_texture_rect(tex, Rect2(rx, ry, side, side), false)

	# Brim target line (aim here) — subtle, over the glass.
	_dashed_line(ix, brim_y, iw, BRIM)


func _draw_foam(ix: float, iw: float, beer_y: float, brim_y: float) -> void:
	var foam_h   := minf(24.0, (beer_y - brim_y) + 16.0)
	foam_h       = maxf(foam_h, 10.0)
	# Never draw foam above the brim — that only happens during a real spill.
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
