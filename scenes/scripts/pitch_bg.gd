extends Control
## Football night-stadium pitch drawn as a UI-layer background.
## Add to any CanvasLayer or Control and it fills to PRESET_FULL_RECT.

const SW := 1280.0
const SH := 720.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t     := Time.get_ticks_msec() * 0.001
	var crowd := 68.0

	draw_rect(Rect2(0, 0, SW, SH), Color("#070b1f"))
	draw_rect(Rect2(0, 0, SW, SH * 0.5), Color(0.10, 0.14, 0.31, 0.22))

	draw_rect(Rect2(0, 0, SW, crowd), Color("#0b1230"))
	draw_rect(Rect2(0, SH - crowd, SW, crowd), Color("#0b1230"))
	_draw_crowd_dots(0.0, crowd)
	_draw_crowd_dots(SH - crowd, crowd)
	draw_rect(Rect2(0, crowd - 6, SW, 6), Color("#11183a"))
	draw_rect(Rect2(0, SH - crowd, SW, 6), Color("#11183a"))

	var stripe_w := SW / 16.0
	var py := crowd
	var ph := SH - 2.0 * crowd
	var sx := 0.0
	var si := 0
	while sx < SW:
		var sc := Color("#2e8f4e") if si % 2 == 0 else Color("#2a833f")
		draw_rect(Rect2(sx, py, minf(stripe_w, SW - sx), ph), sc)
		sx += stripe_w
		si += 1

	for fx: float in [0.09, 0.5, 0.91]:
		_draw_floodlight(SW * fx, t, true)
		_draw_floodlight(SW * fx, t, false)

	var vig := Color(0.016, 0.027, 0.07, 0.45)
	draw_rect(Rect2(0, 0, SW, 4), vig)
	draw_rect(Rect2(0, SH - 4, SW, 4), vig)
	draw_rect(Rect2(0, 0, 4, SH), vig)
	draw_rect(Rect2(SW - 4, 0, 4, SH), vig)


func _draw_crowd_dots(top: float, band_h: float) -> void:
	var step := 18.0
	var y    := top + 5.0
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
