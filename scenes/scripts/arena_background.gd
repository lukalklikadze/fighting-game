extends Node2D
## Static reference marks across the arena. Without something fixed in the
## world, panning the camera over a blank white void makes the stationary
## fighter look like it is sliding — these give the eye a clear cue that it is
## the camera moving, not the characters.

const GROUND_Y := 232.0
const TOP_Y := -340.0
const HALF := 1000.0
const PILLAR_STEP := 180.0
const TICK_STEP := 90.0

const PILLAR_COL := Color(0.86, 0.89, 0.94, 1.0)   # faint grey — subtle back reference
const TICK_COL := Color(0.0, 0.0, 0.0, 1.0)        # bold floor markers


func _draw() -> void:
	# Faint tall pillars across the back wall.
	var x := -HALF
	while x <= HALF:
		draw_line(Vector2(x, TOP_Y), Vector2(x, GROUND_Y), PILLAR_COL, 3.0)
		x += PILLAR_STEP
	# Bold ticks along the ground line (clear horizontal reference).
	x = -HALF
	while x <= HALF:
		draw_rect(Rect2(x - 3.0, GROUND_Y - 18.0, 6.0, 18.0), TICK_COL)
		x += TICK_STEP
