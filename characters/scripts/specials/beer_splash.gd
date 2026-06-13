extends SpecialAbility
class_name BeerSplash

## English fighter — hurls a beer can a set distance in front (the throw is just
## the body animation, there is no flying can object). Where it lands, beer
## spills across the floor and broken-glass shards scatter, then fade away. The
## opponent is hit if they are standing in the landing zone.

const THROW_RANGE := 190.0            # how far in front the can lands
const SPLASH_RADIUS := 135.0          # horizontal reach of the splash hit
const HIT_PAYLOAD := "special_beer"

func id() -> String:
	return "beer"

func display_name() -> String:
	return "PINT SMASH"

func cooldown() -> float:
	return 15.0

func windup_frames() -> int:
	return 14

func total_frames() -> int:
	return 32

func user_animation() -> String:
	return "heavy_attack"


func cast(user, authoritative: bool, _origin: Vector2, dir: int) -> void:
	# Landing spot: a set range in front of the thrower, on the floor line.
	var land := Vector2(float(user.global_position.x) + THROW_RANGE * float(dir), float(user.global_position.y))

	# The puddle itself is a lingering hazard: it keeps damaging whoever stands in
	# the spilled beer + broken glass for as long as it is on the floor.
	var splash := BeerSplashEffect.new()
	splash.setup(user, authoritative, land, SPLASH_RADIUS, HIT_PAYLOAD)
	user.spawn_world_effect(splash)
