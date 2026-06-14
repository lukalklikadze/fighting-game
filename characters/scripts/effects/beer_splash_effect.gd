extends Node2D
class_name BeerSplashEffect

## The aftermath of the English fighter's thrown beer can: the hand-drawn beer
## puddle on the floor plus a quick burst of glass/beer specks. It grows in fast,
## sits for a moment, then fades out smoothly and removes itself. Cosmetic only —
## the hit is dealt by BeerSplash (this just lingers as the visible hazard).

const LIFETIME := 6.5
const FADE_TIME := 2.2               # smooth fade over the final stretch
const GROW_TIME := 0.28

# Hand-drawn puddle art (1000x1000 canvas). Scaled down to a floor-sized splat,
# and nudged so the drawn puddle's centre sits on the landing point.
const BEER_FLOOR_TEX := "res://assets/beer on floor.png"
const BEER_SCALE := 0.5
const BEER_OFFSET := Vector2(65.0, -10.0)

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
var _sprite: Sprite2D = null


func setup(user, authoritative: bool, land: Vector2, radius: float, payload: String) -> void:
	_user = user
	_authoritative = authoritative
	_land = land
	_radius = radius
	_payload = payload
	global_position = land
	add_to_group("special_effects")
	z_index = -1                      # sits on the floor, behind the fighters
	_build_puddle()
	_spawn_shards()


func _build_puddle() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(BEER_FLOOR_TEX)
	_sprite.position = BEER_OFFSET
	_sprite.scale = Vector2.ZERO       # grows in over GROW_TIME
	add_child(_sprite)


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
	# One-shot burst of glass/beer specks for the splash moment.
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
	if _sprite != null:
		var grow := clampf(_age / GROW_TIME, 0.0, 1.0)
		_sprite.scale = Vector2(BEER_SCALE, BEER_SCALE) * grow
		var fade := 1.0
		var remaining := LIFETIME - _age
		if remaining < FADE_TIME:
			fade = clampf(remaining / FADE_TIME, 0.0, 1.0)
		_sprite.modulate.a = fade
	if _age >= LIFETIME:
		queue_free()
