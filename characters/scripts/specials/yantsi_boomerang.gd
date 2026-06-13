extends SpecialAbility
class_name YantsiBoomerang

## Georgian fighter — throws a ყანწი (traditional drinking horn) that flies out
## like a boomerang and returns. The opponent must jump it on the way out AND
## again on the way back, or take a hit. All flight + damage logic lives in the
## spawned YantsiProjectile; this just launches it.

func id() -> String:
	return "yantsi"

func display_name() -> String:
	return "YANTSI"

func cooldown() -> float:
	return 15.0

func windup_frames() -> int:
	return 20                          # let the punch animation play first

func total_frames() -> int:
	return 38

func user_animation() -> String:
	return "arm_attack"                # regular J punch as the wind-up


func cast(user, authoritative: bool, origin: Vector2, dir: int) -> void:
	var yantsi := YantsiProjectile.new()
	yantsi.setup(user, authoritative, origin, dir)
	user.spawn_world_effect(yantsi)
