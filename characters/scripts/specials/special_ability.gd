extends RefCounted
class_name SpecialAbility

## Abstract base for a fighter's signature special move.
##
## A special is fired from the SPECIAL fighter state after a short wind-up. The
## SAME move is built on every peer, but only the instance running on the
## casting player's authority machine is allowed to deal damage. Everything else
## is purely cosmetic so both screens show an identical effect.
##
## To add a new special:
##   1. Subclass this and override the tuning getters + cast().
##   2. Register it in SpecialRegistry (id -> class, character_id -> id).
## Nothing else in the fighter has to change.

# Stable id. Also used to rebuild the move on the remote peer over RPC.
func id() -> String:
	return "none"

# Shown on the HUD cooldown pip.
func display_name() -> String:
	return "SPECIAL"

# Seconds before the move can be used again.
func cooldown() -> float:
	return 30.0

# Wind-up: the user is locked, then the effect fires on this state frame (60fps).
func windup_frames() -> int:
	return 12

# Total frames the user stays rooted in the SPECIAL state.
func total_frames() -> int:
	return 34

# Placeholder body animation played during the cast. Swap this for a bespoke
# special animation once the art for the move is painted.
func user_animation() -> String:
	return "heavy_attack"

# Fire the move. Called on every peer on the same logical frame.
#   user          -> the casting FightingPlayer (untyped for duck-typing).
#   authoritative -> true only on the caster's own machine; the only instance
#                    permitted to deal damage / knockback.
#   origin / dir  -> identical on every peer so the visuals line up exactly.
func cast(_user, _authoritative: bool, _origin: Vector2, _dir: int) -> void:
	pass
