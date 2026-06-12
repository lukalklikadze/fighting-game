extends Control
## Simple warm pub background: a dark gradient, a wooden bar counter along the
## bottom, and a soft glowing centre divider that splits the two players' sides.

const TOP := Color("#241a12")
const BOTTOM := Color("#3a2618")
const BAR := Color("#5a3b22")
const BAR_LIP := Color("#6e4a2c")

var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	# vertical gradient drawn as horizontal bands
	var bands := 24
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		draw_rect(Rect2(0, h * float(i) / bands, w, h / bands + 1.0), TOP.lerp(BOTTOM, t))

	# wooden bar counter along the bottom
	draw_rect(Rect2(0, h * 0.82, w, h * 0.18), BAR)
	draw_rect(Rect2(0, h * 0.82, w, 6), BAR_LIP)

	# soft glowing centre divider
	var pulse := 0.6 + 0.4 * sin(_t * 1.6)
	draw_rect(Rect2(w * 0.5 - 7.0, 0, 14.0, h), Color(1.0, 0.85, 0.5, 0.06 * pulse))
	draw_rect(Rect2(w * 0.5 - 1.5, 0, 3.0, h), Color(1.0, 0.9, 0.65, 0.55 * pulse))
