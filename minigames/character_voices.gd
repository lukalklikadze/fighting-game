extends RefCounted
## Per-character voice lines.
##   TEXT_SOUND  — maps each typeracer line to the clip the speaker recorded
##                 (used to play exactly what the winner typed).
##   CHAR_SOUNDS — every clip per character, for a random pick (beer / juggling).
## Texts here must match the typeracer CHAR_SENTENCES strings exactly.

const TEXT_SOUND := {
	# English fighter (Georgian taunts)
	"ქვეყნად ვერავინ შეძლებს, დედა შეაგინოს მგელს": preload("res://sounds/English/qveynad veravin.wav"),
	"ე ზიდან, დედაშენს დაუსიგნალე საკუარში, ბიჭო": preload("res://sounds/English/dedashens dausignale.wav"),
	"თუ გინდა, დედა არ გაგინო, დროზე ინგლისის ჰიმნი იმღერე": preload("res://sounds/English/tu ginda deda ar gaginot.wav"),
	"მოდი აქ, შენი ლიზარაზუ დედა მოვ***ნ": preload("res://sounds/English/modi aq sheni.wav"),
	"აბა ვინა ვართ? დედის მ***ელები": preload("res://sounds/English/aba vina vart.wav"),
	"გადაა*ვით ბიჭო, რომელ მხარეს მოდიხართ": preload("res://sounds/English/gadaavit bicho.wav"),
	"მოიცა, ის ველოსიპედიანი კაცი სად არი": preload("res://sounds/English/velosipediani kaci.wav"),
	# Scottish fighter
	"Let's pretend, let's pretend we score a goal": preload("res://sounds/Scottish/lets pretend.wav"),
	"Yer stick's not even touchin the ground man": preload("res://sounds/Scottish/yer stick.wav"),
	"Hocus pocus there's pizza on your focus": preload("res://sounds/Scottish/hocuspocus.wav"),
	"It's shite being scottish, we're the lowest of the low": preload("res://sounds/Scottish/its shite.wav"),
	"What's heavier, a kilogramme of steel or feathers": preload("res://sounds/Scottish/kilogramme.wav"),
	"We've got McGinn, Super John McGinn": preload("res://sounds/Scottish/mcginn.wav"),
	# Georgian fighter
	"ცოტა სიჩუმეა და დინამოს ექიმი ბოოოოოსი": preload("res://sounds/Georgian/dinamos eqimi.wav"),
	"არავარ არსად სიაში, დუბლებში მე არავარ, არსად არავარ": preload("res://sounds/Georgian/aravar siashi.wav"),
	"ფეხბურთი მეტია...ვიდრე გაზაევი": preload("res://sounds/Georgian/gazaevi.wav"),
	"ჯოტია მუს გილამჯანუქ სი ჯოღორისკუა": preload("res://sounds/Georgian/ade imushave.wav"),
	"ფეხბურთი თურმე კუჭის აშლილობას გავს": preload("res://sounds/Georgian/fexburti kuchis.wav"),
	"შენთვის, შენთვის ვმღერი ზღაპრის ბოლო კეთილია": preload("res://sounds/Georgian/zgapris bolo.wav"),
}

const CHAR_SOUNDS := {
	"english": [
		preload("res://sounds/English/qveynad veravin.wav"),
		preload("res://sounds/English/dedashens dausignale.wav"),
		preload("res://sounds/English/tu ginda deda ar gaginot.wav"),
		preload("res://sounds/English/modi aq sheni.wav"),
		preload("res://sounds/English/aba vina vart.wav"),
		preload("res://sounds/English/gadaavit bicho.wav"),
		preload("res://sounds/English/velosipediani kaci.wav"),
	],
	"scottish": [
		preload("res://sounds/Scottish/lets pretend.wav"),
		preload("res://sounds/Scottish/yer stick.wav"),
		preload("res://sounds/Scottish/hocuspocus.wav"),
		preload("res://sounds/Scottish/its shite.wav"),
		preload("res://sounds/Scottish/kilogramme.wav"),
		preload("res://sounds/Scottish/mcginn.wav"),
	],
	"georgian": [
		preload("res://sounds/Georgian/dinamos eqimi.wav"),
		preload("res://sounds/Georgian/aravar siashi.wav"),
		preload("res://sounds/Georgian/gazaevi.wav"),
		preload("res://sounds/Georgian/ade imushave.wav"),
		preload("res://sounds/Georgian/fexburti kuchis.wav"),
		preload("res://sounds/Georgian/zgapris bolo.wav"),
	],
}


static func sound_for_text(text: String) -> AudioStream:
	return TEXT_SOUND.get(text, null)


static func random_sound(char_id: String, seed: int = -1) -> AudioStream:
	var key := "scottish" if char_id == "scotish" else char_id
	var pool: Array = CHAR_SOUNDS.get(key, [])
	if pool.is_empty():
		return null
	# A shared seed (>= 0) makes both peers pick the same clip for the same
	# winner; otherwise it's a local random pick.
	var i := (seed % pool.size()) if seed >= 0 else (randi() % pool.size())
	return pool[i]
