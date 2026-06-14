extends AudioStreamPlayer
## Persistent bar ambience. Lives as an autoload so it keeps playing across scene
## changes — started when the bar cutscene begins and looped for the rest of the
## game (it sits quietly under the SFX / fight music).

const AMBIENCE: AudioStream = preload("res://sounds/background bar.wav")


func _ready() -> void:
	stream = AMBIENCE
	volume_db = -16.0   # background level, under the music and voices
	bus = "Master"
	finished.connect(_loop)


# Begin the ambience (no-op if it's already going), called from the bar scene.
func start() -> void:
	if not playing:
		play()


func _loop() -> void:
	play()   # restart on finish so it loops forever
