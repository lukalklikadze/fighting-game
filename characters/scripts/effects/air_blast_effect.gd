extends Node2D
class_name AirBlastEffect

## Short-lived gust from the Scottish fighter's bagpipe. Purely cosmetic (the
## knock-back is applied by TrumpetBlast on the authority) plus it owns the honk
## sound so every peer hears it. The visual is the hand-drawn "bagpipe smoke"
## sprite animation, blown out in front of the piper.

const LIFETIME := 0.6
const REACH := 340.0

# Hand-drawn smoke puff frames. The art faces LEFT by default, so we mirror it
# (flip_h) when the piper is facing right.
const SMOKE_FRAMES := [
	"res://assets/bagpipe smoke/Smoke VFX A1.png",
	"res://assets/bagpipe smoke/Smoke VFX A2.png",
	"res://assets/bagpipe smoke/Smoke VFX A3.png",
	"res://assets/bagpipe smoke/Smoke VFX A4.png",
	"res://assets/bagpipe smoke/Smoke VFX A5.png",
	"res://assets/bagpipe smoke/Smoke VFX A6.png",
	"res://assets/bagpipe smoke/Smoke VFX A7.png",
	"res://assets/bagpipe smoke/Smoke VFX A8.png",
	"res://assets/bagpipe smoke/Smoke VFX A9.png",
]
const SMOKE_SCALE := 6.0             # 48x32 source art -> ~288x192 gust
const SMOKE_FORWARD := 96.0          # initial offset in front of the pipe (starts further out)
const SMOKE_LIFT := 44.0             # raise the smoke a little so it leaves the pipe higher
# Travels outward to ~REACH over its lifetime so it reads as a gust blowing out.
const SMOKE_TRAVEL_SPEED := 480.0

# ── Swap this path to change the trumpet/bagpipe sound. ──
# If the file is absent the move simply stays silent (no crash), so the game
# runs before any audio asset exists.
const TRUMPET_SOUND := "res://assets/audio/trumpet.ogg"

var _dir := 1
var _age := 0.0
var _smoke: AnimatedSprite2D = null


func setup(origin: Vector2, dir: int) -> void:
	global_position = origin
	_dir = dir
	add_to_group("special_effects")
	z_index = 50
	_play_sound()
	_build_smoke()


func _build_smoke() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("smoke")
	frames.set_animation_loop("smoke", false)
	frames.set_animation_speed("smoke", float(SMOKE_FRAMES.size()) / LIFETIME)
	for path in SMOKE_FRAMES:
		frames.add_frame("smoke", load(path))

	_smoke = AnimatedSprite2D.new()
	_smoke.sprite_frames = frames
	_smoke.flip_h = _dir > 0          # art faces LEFT by default -> mirror when blowing right
	_smoke.scale = Vector2(SMOKE_SCALE, SMOKE_SCALE)
	_smoke.position = Vector2(float(_dir) * SMOKE_FORWARD, -SMOKE_LIFT)
	add_child(_smoke)
	_smoke.play("smoke")


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
	if _smoke != null:
		_smoke.position.x += float(_dir) * SMOKE_TRAVEL_SPEED * delta
	if _age >= LIFETIME:
		queue_free()
