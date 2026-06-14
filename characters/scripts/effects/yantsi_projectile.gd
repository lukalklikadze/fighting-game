extends Node2D
class_name YantsiProjectile

## The flying ყანწי (drinking horn). It spins, sweeps out to MAX_RANGE and
## returns to the thrower along a smooth out-and-back arc — a boomerang. It flies
## at roughly chest height, so the opponent dodges by JUMPING (their hurtbox
## lifts above the horn). It can connect once on the way out and once on the way
## back (REHIT_COOLDOWN gates the two passes).
##
## Visuals are drawn placeholders — replace _draw() with a spinning sprite when
## the art is ready; the flight / hit logic stays untouched.

const OUTWARD_TIME := 0.85            # seconds to sweep out to peak range
const RETURN_SPEED := 1050.0         # px/s homing back to the thrower
const CATCH_RADIUS := 46.0           # "caught" (picked up) when this close to the hand
const MAX_LIFETIME := 6.0            # safety so it can never live forever
const MAX_RANGE := 780.0             # peak distance from the thrower (flies farther now)
const ARC_HEIGHT := 30.0             # slight vertical bow on the way out
const SPIN_SPEED := 17.0             # radians / second
const HIT_RADIUS := 38.0
const REHIT_COOLDOWN := 0.6          # gap so out + back are two separate hits
const HIT_PAYLOAD := "special_yantsi"

var _user                            # casting FightingPlayer (untyped)
var _authoritative := false
var _dir := 1
var _origin := Vector2.ZERO
var _age := 0.0
var _hit_cd := 0.0
var _returning := false              # false = flying out, true = homing back to the thrower


func setup(user, authoritative: bool, origin: Vector2, dir: int) -> void:
	_user = user
	_authoritative = authoritative
	_origin = origin
	_dir = dir
	global_position = origin
	add_to_group("special_effects")
	z_index = 50


func _physics_process(delta: float) -> void:
	_age += delta
	_hit_cd = maxf(_hit_cd - delta, 0.0)

	if not _returning:
		# Sweep outward to peak range, bowing up slightly, then start coming back.
		var phase: float = clampf(_age / OUTWARD_TIME, 0.0, 1.0)
		global_position = Vector2(
			_origin.x + float(_dir) * phase * MAX_RANGE,
			_origin.y - sin(phase * PI) * ARC_HEIGHT)
		if phase >= 1.0:
			_returning = true
	else:
		# Home back to the thrower's CURRENT hand (so it returns to the fighter even
		# if they moved) and vanish only once it reaches them — they "catch" it.
		var target := _catch_point()
		global_position = global_position.move_toward(target, RETURN_SPEED * delta)
		if global_position.distance_to(target) <= CATCH_RADIUS:
			queue_free()
			return

	rotation += SPIN_SPEED * delta * float(_dir)

	if _authoritative and _hit_cd <= 0.0:
		_check_hit()

	queue_redraw()
	if _age >= MAX_LIFETIME:
		queue_free()


# Where the horn returns to: the thrower's live hand position (fallback: origin).
func _catch_point() -> Vector2:
	if _user != null and is_instance_valid(_user) and _user.has_method("special_hand_position"):
		return _user.call("special_hand_position")
	return _origin


func _check_hit() -> void:
	if _user == null or not is_instance_valid(_user):
		return
	var target = _user.opponent
	if target == null or not is_instance_valid(target):
		return
	var rect: Rect2 = target.call("get_pushbox_rect")
	# Closest point on the opponent's body box to the horn's centre.
	var closest := Vector2(
		clampf(global_position.x, rect.position.x, rect.end.x),
		clampf(global_position.y, rect.position.y, rect.end.y))
	if global_position.distance_to(closest) <= HIT_RADIUS:
		_user.deal_special_hit(target, HIT_PAYLOAD)
		_hit_cd = REHIT_COOLDOWN


func _draw() -> void:
	# ── Placeholder ყანწი: a curved, tapering horn with a gold rim. ──
	var horn_col := Color(0.30, 0.19, 0.10)
	var horn_dark := Color(0.20, 0.12, 0.06)
	var rim_col := Color(0.86, 0.72, 0.34)

	var pts := PackedVector2Array()
	var segments := 12
	for i in range(segments + 1):
		pts.append(_horn_edge(float(i) / float(segments), -1.0))
	for i in range(segments + 1):
		pts.append(_horn_edge(float(segments - i) / float(segments), 1.0))
	draw_colored_polygon(pts, horn_col)

	# Spine shading + gold drinking rim at the wide mouth.
	draw_line(_horn_edge(0.05, 0.0), _horn_edge(0.95, 0.0), horn_dark, 2.5)
	draw_circle(_horn_edge(0.0, 0.0), 8.0, rim_col)
	draw_arc(_horn_edge(0.0, 0.0), 8.0, 0.0, TAU, 16, Color(0.55, 0.43, 0.20), 2.0)


func _horn_edge(t: float, side: float) -> Vector2:
	# t: 0 = wide mouth (left), 1 = pointed tip (right). side: -1 / +1 / 0 spine.
	var x := lerpf(-32.0, 35.0, t)
	var bow := sin(t * PI) * 13.0
	var half_width := lerpf(15.0, 1.0, t)
	return Vector2(x, -bow + side * half_width)
