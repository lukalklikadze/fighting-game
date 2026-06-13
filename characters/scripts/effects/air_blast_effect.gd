extends Node2D
class_name AirBlastEffect

## Short-lived gust of air from the Scottish fighter's trumpet/bagpipe. Purely
## cosmetic (the knock-back is applied by TrumpetBlast on the authority) plus it
## owns the honk sound so every peer hears it.

const LIFETIME := 0.45
const REACH := 250.0

# ── Swap this path to change the trumpet/bagpipe sound. ──
# If the file is absent the move simply stays silent (no crash), so the game
# runs before any audio asset exists.
const TRUMPET_SOUND := "res://assets/audio/trumpet.ogg"

var _dir := 1
var _age := 0.0


func setup(origin: Vector2, dir: int) -> void:
	global_position = origin
	_dir = dir
	add_to_group("special_effects")
	z_index = 50
	_play_sound()


func _play_sound() -> void:
	if not ResourceLoader.exists(TRUMPET_SOUND):
		return
	var stream := load(TRUMPET_SOUND)
	if stream == null:
		return
	var audio := AudioStreamPlayer2D.new()
	audio.stream = stream
	add_child(audio)
	audio.play()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= LIFETIME:
		queue_free()


func _draw() -> void:
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	var alpha := (1.0 - t) * 0.9
	var col := Color(0.90, 0.97, 1.0, alpha)
	var base_angle := 0.0 if _dir > 0 else PI

	# Expanding concentric gust arcs, fanning out in the facing direction.
	for i in range(4):
		var radius := lerpf(24.0, REACH, t) - float(i) * 30.0
		if radius <= 6.0:
			continue
		draw_arc(Vector2.ZERO, radius, base_angle - 0.7, base_angle + 0.7, 18, col, 4.0)

	# A few wind speed-lines.
	for j in range(5):
		var yy := lerpf(-36.0, 36.0, float(j) / 4.0)
		var x_far := float(_dir) * lerpf(30.0, REACH, t)
		draw_line(Vector2(float(_dir) * 18.0, yy), Vector2(x_far, yy * 0.5), Color(1, 1, 1, alpha * 0.6), 2.0)
