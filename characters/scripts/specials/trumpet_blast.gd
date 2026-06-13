extends SpecialAbility
class_name TrumpetBlast

## Scottish fighter — blows a trumpet/bagpipe, releasing a gust of air that
## knocks the opponent back if they are close and in front. The honking sound is
## played by the AirBlastEffect (swap its TRUMPET_SOUND constant to change it).

const RANGE := 250.0                  # only blows opponents within this distance
const HIT_PAYLOAD := "special_trumpet"

func id() -> String:
	return "trumpet"

func display_name() -> String:
	return "BAGPIPE BLAST"

func cooldown() -> float:
	return 15.0

func windup_frames() -> int:
	return 16                          # raise the trumpet, then blow

func total_frames() -> int:
	return 40

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
	if absf(to_target) > RANGE:
		return
	user.deal_special_hit(target, HIT_PAYLOAD)
