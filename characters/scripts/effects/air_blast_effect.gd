extends Node2D
class_name AirBlastEffect

## Short-lived gust of air from the Scottish fighter's trumpet/bagpipe. Purely
## cosmetic (the knock-back is applied by TrumpetBlast on the authority) plus it
## owns the honk sound so every peer hears it.

const LIFETIME := 0.6
const REACH := 340.0

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
	var alpha := (1.0 - t)
	# Bold colors so the gust reads clearly against the white arena.
	var deep := Color(0.10, 0.40, 0.85, alpha)        # strong blue
	var mid := Color(0.35, 0.65, 1.0, alpha * 0.95)   # lighter inner
	var base_angle := 0.0 if _dir > 0 else PI

	# Expanding concentric gust arcs (circular wave lines), fanning out in the
	# facing direction — the only element of the blast.
	for i in range(6):
		var radius := lerpf(34.0, REACH, t) - float(i) * 38.0
		if radius <= 8.0:
			continue
		draw_arc(Vector2.ZERO, radius, base_angle - 0.9, base_angle + 0.9, 28, deep if i % 2 == 0 else mid, 8.0)
