extends Control
## Top-down, night-floodlit football pitch drawn natively in Godot.
##
## A re-creation of pitch-background.html: a dark stadium with crowd stands top
## and bottom, a green striped pitch, a glowing centre line that splits the field
## into a LEFT and RIGHT half (one typing lane each), and floodlight halos.
## Add this as the bottom-most child of the Typeracer scene so the race UI sits
## on top of it.

const BASE := Color("#070b1f")        # deep night sky / stadium base
const STADIUM_GLOW := Color("#1a2350") # faint glow toward the top
const CROWD := Color("#0b1230")        # the stands
const CROWD_LIP := Color("#11183a")    # bright lip where stands meet the pitch
const CROWD_DOT := Color(0.84, 0.88, 1.0, 0.5) # crowd speckle
const STRIPE_A := Color("#2e8f4e")     # mown grass stripe
const STRIPE_B := Color("#2a833f")     # alternate stripe
const LINE := Color(1, 1, 1, 0.92)     # centre line
const LIGHT := Color(1.0, 0.97, 0.88)  # floodlight warmth

var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw() # gentle pulse on the centre line and floodlights


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var crowd: float = clamp(h * 0.09, 44.0, 84.0)

	# --- stadium base + soft top glow ---
	draw_rect(Rect2(0, 0, w, h), BASE)
	draw_rect(Rect2(0, 0, w, h * 0.5), Color(STADIUM_GLOW.r, STADIUM_GLOW.g, STADIUM_GLOW.b, 0.22))

	# --- crowd / stands ---
	draw_rect(Rect2(0, 0, w, crowd), CROWD)
	draw_rect(Rect2(0, h - crowd, w, crowd), CROWD)
	_draw_crowd_dots(0.0, crowd, w)
	_draw_crowd_dots(h - crowd, crowd, w)
	draw_rect(Rect2(0, crowd - 6, w, 6), CROWD_LIP)
	draw_rect(Rect2(0, h - crowd, w, 6), CROWD_LIP)

	# --- the pitch: vertical mown stripes ---
	var py := crowd
	var ph := h - 2.0 * crowd
	var stripe_w: float = max(8.0, w * 0.05)
	var x := 0.0
	var i := 0
	while x < w:
		draw_rect(Rect2(x, py, min(stripe_w, w - x), ph), STRIPE_A if i % 2 == 0 else STRIPE_B)
		x += stripe_w
		i += 1

	# --- centre line (the divider) with a soft glow, pulsing ---
	var pulse := 0.55 + 0.45 * sin(_t * 1.6)
	var cx := w * 0.5
	var dy := py + ph * 0.03
	var dh := ph * 0.94
	draw_rect(Rect2(cx - 7, dy, 14, dh), Color(0.6, 0.72, 1.0, 0.12 * pulse))
	draw_rect(Rect2(cx - 3, dy, 6, dh), Color(0.8, 0.86, 1.0, 0.30 * pulse))
	draw_rect(Rect2(cx - 1.5, dy, 3, dh), LINE)

	# --- floodlights: lamps on poles, 3 along the top stand, 3 along the bottom ---
	for fx in [0.09, 0.5, 0.91]:
		_draw_floodlight(w * fx, h, true)
		_draw_floodlight(w * fx, h, false)

	# --- edge vignette ---
	var vig := Color(0.016, 0.027, 0.07, 0.45)
	draw_rect(Rect2(0, 0, w, 4), vig)
	draw_rect(Rect2(0, h - 4, w, 4), vig)
	draw_rect(Rect2(0, 0, 4, h), vig)
	draw_rect(Rect2(w - 4, 0, 4, h), vig)


func _draw_crowd_dots(top: float, band_h: float, w: float) -> void:
	var step := 18.0
	var y := top + 5.0
	while y < top + band_h - 3.0:
		var x := 5.0
		while x < w:
			draw_circle(Vector2(x, y), 1.0, CROWD_DOT)
			x += step
		y += step


# A floodlight: a lit lamp head on a pole, with a warm halo. `top` puts the
# lamp at the top edge with its pole hanging down; otherwise it is mirrored.
func _draw_floodlight(x: float, h: float, top: bool) -> void:
	var bank_w := 34.0
	var bank_h := 15.0
	var pole_w := 4.0
	var pole_h := 38.0
	var bank_y: float
	var pole_y: float
	if top:
		bank_y = 8.0
		pole_y = bank_y + bank_h
	else:
		bank_y = h - 8.0 - bank_h
		pole_y = bank_y - pole_h

	var center := Vector2(x, bank_y + bank_h * 0.5)

	# warm glow emanating from the lamp (gentle pulse)
	var glow := 0.85 + 0.15 * sin(_t * 1.1)
	_draw_halo(center, 62.0 * glow)

	# pole
	draw_rect(Rect2(x - pole_w * 0.5, pole_y, pole_w, pole_h), Color("#283154"))

	# housing + lit lamp face
	draw_rect(Rect2(x - bank_w * 0.5, bank_y, bank_w, bank_h), Color("#0c1228"))
	var face := Rect2(x - bank_w * 0.5 + 2.0, bank_y + 2.0, bank_w - 4.0, bank_h - 4.0)
	draw_rect(face, Color(1.0, 0.97, 0.85, 0.95 * glow))
	# dark separators to suggest individual bulbs
	for k in range(1, 4):
		var lx := face.position.x + face.size.x * float(k) / 4.0
		draw_rect(Rect2(lx, face.position.y, 1.0, face.size.y), Color("#0c1228"))


# Warm floodlight glow (layered circles, brighter toward the centre).
func _draw_halo(center: Vector2, radius: float) -> void:
	for k in range(4):
		var f := float(k) / 4.0
		draw_circle(center, radius * (1.0 - f * 0.55), Color(LIGHT.r, LIGHT.g, LIGHT.b, 0.10))
