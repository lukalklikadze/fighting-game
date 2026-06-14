extends Control
## Draws selection highlight rings over the footballs baked into the
## select-screen background. `rings[i]` is null (no highlight) or a
## dictionary {"color": Color, "width": int} for football `positions[i]`.

var positions: PackedVector2Array = PackedVector2Array()
var radius := 80.0
var rings: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for i in range(positions.size()):
		if i >= rings.size() or rings[i] == null:
			continue
		var spec: Dictionary = rings[i]
		var color: Color = spec.get("color", Color.WHITE)
		var width: int = int(spec.get("width", 6))
		var center := positions[i]
		# Soft outer glow.
		var glow := Color(color.r, color.g, color.b, 0.18)
		draw_arc(center, radius + 6.0, 0.0, TAU, 64, glow, float(width) + 10.0, true)
		# Crisp selection ring.
		draw_arc(center, radius, 0.0, TAU, 64, color, float(width), true)
