extends RefCounted
class_name SpecialRegistry

## Single source of truth that maps fighters to their signature specials.
##
## CHARACTER_ABILITY links a select-screen character_id to an ability id; make()
## turns an ability id into a fresh ability instance (also used to rebuild the
## move on the remote peer from an RPC). Add new fighters / moves here only.

const CHARACTER_ABILITY := {
	"fighter_alpha": "yantsi",   # Georgian — ყანწი drinking-horn boomerang
	"fighter_beta":  "trumpet",  # Scottish — bagpipe/trumpet air blast
	"fighter_gamma": "beer",     # English  — beer-can splash
}


static func for_character(character_id: String) -> SpecialAbility:
	return make(str(CHARACTER_ABILITY.get(character_id, "")))


static func make(ability_id: String) -> SpecialAbility:
	match ability_id:
		"yantsi":
			return YantsiBoomerang.new()
		"trumpet":
			return TrumpetBlast.new()
		"beer":
			return BeerSplash.new()
		_:
			return null
