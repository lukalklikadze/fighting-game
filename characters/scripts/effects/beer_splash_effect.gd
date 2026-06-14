extends Node2D
class_name BeerSplashEffect

## The aftermath of the English fighter's thrown beer can: a spreading puddle of
## beer plus a burst of broken-glass shards on the floor. It grows in fast, sits
## for a moment, then fades out smoothly and removes itself. Cosmetic only — the
## hit is dealt by BeerSplash at spawn time.

const LIFETIME := 6.5
const FADE_TIME := 2.2               # smooth fade over the final stretch
const GROW_TIME := 0.28
const PUDDLE_RX := 132.0              # large enough to read clearly (≈ the hit zone)
const PUDDLE_RY := 30.0

# Hazard: anyone standing in the spill keeps taking damage on this interval.
const HIT_INTERVAL := 0.7            # seconds between damage ticks
const GROUND_TOLERANCE := 40.0       # how close to the floor the victim must be (jumping over it is safe)

var _age := 0.0
var _user                            # casting FightingPlayer (untyped)
var _authoritative := false
var _land := Vector2.ZERO
var _radius := 135.0
var _payload := ""
var _hit_cd := 0.0


func setup(user, authoritative: bool, land: Vector2, radius: float, payload: String) -> void:
	_user = user
	_authoritative = authoritative
	_land = land
	_radius = radius
	_payload = payload
	global_position = land
	add_to_group("special_effects")
	z_index = -1                      # sits on the floor, behind the fighters
	_spawn_shards()


func _physics_process(delta: float) -> void:
	# Continuous hazard — only the casting authority deals damage, ticking it on
	# HIT_INTERVAL while the opponent stands in the spill (and isn't jumping over).
	if not _authoritative:
		return
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	if _hit_cd > 0.0:
		return
	if _user == null or not is_instance_valid(_user):
		return
	var target = _user.opponent
	if target == null or not is_instance_valid(target):
		return
	var in_zone := absf(float(target.global_position.x) - _land.x) <= _radius
	var on_floor := absf(float(target.global_position.y) - _land.y) <= GROUND_TOLERANCE
	if in_zone and on_floor:
		_user.deal_special_hit(target, _payload)
		_hit_cd = HIT_INTERVAL


func _spawn_shards() -> void:
	# One-shot burst of glass/beer specks. Swap for a sprite-based particle
	# texture later; the lifecycle here is independent of the look.
	var shards := CPUParticles2D.new()
	shards.emitting = true
	shards.one_shot = true
	shards.explosiveness = 0.95
	shards.amount = 24
	shards.lifetime = 0.8
	shards.direction = Vector2(0, -1)
	shards.spread = 72.0
	shards.gravity = Vector2(0, 980)
	shards.initial_velocity_min = 180.0
	shards.initial_velocity_max = 380.0
	shards.scale_amount_min = 2.0
	shards.scale_amount_max = 5.0
	shards.color = Color(0.82, 0.66, 0.24, 0.95)
	add_child(shards)


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= LIFETIME:
		queue_free()


func _draw() -> void:
	var fade := 1.0
	var remaining := LIFETIME - _age
	if remaining < FADE_TIME:
		fade = clampf(remaining / FADE_TIME, 0.0, 1.0)
	var grow := clampf(_age / GROW_TIME, 0.0, 1.0)
	var rx := PUDDLE_RX * grow
	var ry := PUDDLE_RY * grow

	# Beer puddle — layered DARK amber ellipses (high alpha so it reads clearly).
	_draw_ellipse(Vector2.ZERO, rx, ry, Color(0.34, 0.21, 0.04, 0.92 * fade))
	_draw_ellipse(Vector2.ZERO, rx * 0.78, ry * 0.82, Color(0.46, 0.29, 0.07, 0.9 * fade))
	_draw_ellipse(Vector2.ZERO, rx * 0.5, ry * 0.6, Color(0.60, 0.40, 0.11, 0.85 * fade))

	# Foam — a frothy cream cap with scattered bubbles, the signature of beer.
	_draw_ellipse(Vector2(0.0, -ry * 0.18), rx * 0.66, ry * 0.62, Color(0.90, 0.83, 0.62, 0.6 * fade))
	var foam := Color(0.99, 0.97, 0.88, 0.85 * fade)
	for i in range(12):
		var ang := float(i) / 12.0 * TAU + 0.5
		var ring := rx * (0.32 + 0.46 * float((i * 7) % 5) / 5.0)
		var bubble := Vector2(cos(ang) * ring, sin(ang) * ry * 0.66 - ry * 0.1)
		var br := 2.5 + float((i * 3) % 4)
		draw_circle(bubble, br, foam)
		draw_circle(bubble + Vector2(-br * 0.3, -br * 0.3), br * 0.4, Color(1.0, 1.0, 0.96, 0.7 * fade))

	# Broken-glass shards resting in the puddle.
	var glass := Color(0.86, 0.90, 0.82, 0.85 * fade)
	for i in range(6):
		var a := float(i) / 6.0 * TAU + 0.4
		var c := Vector2(cos(a), sin(a) * 0.4) * rx * 0.72
		var s := 5.0 + float(i % 3) * 2.0
		var tri := PackedVector2Array([c + Vector2(-s, s * 0.5), c + Vector2(s, 0.0), c + Vector2(0.0, -s)])
		draw_colored_polygon(tri, glass)


func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 22
	for i in range(n):
		var a := float(i) / float(n) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
