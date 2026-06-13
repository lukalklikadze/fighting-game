extends SpecialAbility
class_name TrumpetBlast

## Scottish fighter — blows a trumpet/bagpipe, releasing a medium-range gust of
## air. Anyone the blue gust reaches (in front, within its visual reach) takes
## damage + knockback; the hit lands as the gust front sweeps onto them, not on
## direct contact. The honk is played by the AirBlastEffect.

const HIT_PAYLOAD := "special_trumpet"

func id() -> String:
	return "trumpet"

func display_name() -> String:
	return "BAGPIPE BLAST"

func cooldown() -> float:
	return 15.0

func windup_frames() -> int:
	return 20                          # punch wind-up (pipe animation comes later)

func total_frames() -> int:
	return 44

func user_animation() -> String:
	return "arm_attack"


func cast(user, authoritative: bool, origin: Vector2, dir: int) -> void:
	# Visual gust + sound on every peer.
	var blast := AirBlastEffect.new()
	blast.setup(origin, dir)
	user.spawn_world_effect(blast)

	# Knock-back + damage only on the casting authority.
	if not authoritative:
		return
	var target = user.opponent
	if target == null or not is_instance_valid(target):
		return
	var to_target: float = float(target.global_position.x) - float(user.global_position.x)
	if signf(to_target) != float(dir):
		return                          # opponent is behind — the gust misses
	var dist := absf(to_target)
	if dist > AirBlastEffect.REACH:
		return                          # beyond the gust's reach
	# The hit lands as the gust front sweeps onto them: closer = sooner.
	var travel := (dist / AirBlastEffect.REACH) * AirBlastEffect.LIFETIME
	user.deal_special_hit_after(target, HIT_PAYLOAD, travel)
