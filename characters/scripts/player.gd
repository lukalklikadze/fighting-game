extends CharacterBody2D
class_name FightingPlayer

signal health_changed(current_health: int, max_health: int)
signal died(player_id: int)
signal attack_started(attack_name: String)
signal took_hit(amount: int, from_player_id: int)
signal blocked_hit(amount: int, from_player_id: int)
signal super_meter_changed(current: float, maximum: float)
signal super_full(player_id: int)

@export var player_id := 1
@export var accept_local_input := true
@export var bot_enabled := false
@export var max_health := 100
@export var opponent_path: NodePath
## Which sprite set / character this fighter uses. "placeholder" keeps the old
## stick-figure fighter with the full moveset; the hand-drawn people
## ("english"/"georgian"/"scotish") have walk + jump + hand kick + leg kick +
## hard hit (heavy), with double-tap-O for the special. They still have no
## crouch/dash/slide (no art); blocking is allowed (hold I, blue tint).
@export var character_key := "placeholder"
@export var bot_preferred_range := 145.0
@export var bot_attack_range := 190.0

const SPRITE_DIR := "res://assets/Fighter sprites/"
const FRAME_TIME := 1.0 / 60.0
const NETWORK_SYNC_INTERVAL := 1.0 / 30.0

# Hand-drawn "people" characters. Each has only walk / hand kick / leg kick.
# Value = filename base + frame count per animation folder.
const PERSON_WALK_DIR := "res://assets/walk/"
const PERSON_HAND_DIR := "res://assets/hand kick/"
const PERSON_LEG_DIR := "res://assets/leg kick/"
const PERSON_JUMP_DIR := "res://assets/jump/"
const PERSON_HARD_DIR := "res://assets/hard hit/"
const PERSON_IDLE_DIR := "res://assets/idle/"
const PERSON_BLOCK_DIR := "res://assets/block/"
const PERSON_DEATH_DIR := "res://assets/death/"
const SCOTISH_PIPE_IMG := "res://assets/bagpipe.png"
# Single drawn block pose per fighter (filename index in assets/block/).
const PERSON_BLOCK_FRAME := {"english": 20, "georgian": 20, "scotish": 3}
# walk/hand/leg/hard = frame counts; jump = explicit (sparse) frame numbers;
# dash = a single hard-hit frame reused as the dash pose; fig_h/feet =
# drawn-figure height and feet offset below the 1000px canvas center (from
# frame 0) used to scale + ground the art.
const PERSON_TARGET_HEIGHT := 340.0
const PERSON_SETS := {
	"english":  {"base": "english man",  "walk": 12, "idle": 12, "hand": 6, "leg": 8,  "hard": 16, "jump": [0, 6, 9],  "dash": 3, "fig_h": 905, "feet": 455},
	"georgian": {"base": "georgian man", "walk": 12, "idle": 12, "hand": 5, "leg": 10, "hard": 27, "jump": [4, 14],    "dash": 3, "fig_h": 958, "feet": 466},
	"scotish":  {"base": "scotish man",  "walk": 12, "idle": 12, "hand": 6, "leg": 10, "hard": 14, "jump": [0, 6, 17],  "dash": 3, "fig_h": 922, "feet": 449, "pipe": true},
}

# ── Mortal-Kombat-faithful animation + combat tuning ──────────────────────────
# Investigated against the MrezaDorudian/Mortal-Kombat Godot project. MK's "fast
# arcade" feel comes from FEW frames played at a LOW framerate: a punch is 3
# frames over 0.3s, a kick 5-8 frames, and EVERYTHING plays at ~10fps. Distinct,
# readable poses snap (windup -> impact -> recoil) instead of a smooth blur.
const PERSON_ANIM_FPS := 10.0   # MK plays every animation at ~10 frames/second.

# Which sub-frames of each (over-detailed) hand-drawn swing we keep, per fighter.
# Evenly sampled across the full range so windup / impact / recoil all survive.
# light(hand)=3 frames, medium(leg)=5, heavy(hard)=6 -- matching MK move lengths.
const PERSON_CUT_FRAMES := {
	"english":  {"hand": [0, 3, 5],   "leg": [0, 2, 4, 6, 7], "hard": [0, 3, 6, 9, 12, 15]},
	"georgian": {"hand": [0, 2, 4],   "leg": [0, 2, 5, 7, 9], "hard": [0, 5, 10, 15, 21, 26]},
	"scotish":  {"hand": [0, 3, 5],   "leg": [0, 2, 5, 7, 9], "hard": [0, 3, 6, 9, 11, 13]},
}
const PERSON_WALK_FRAMES := [0, 2, 3, 5, 6, 8, 9, 11]   # 8 of 12, MK walk = 9 frames.

# MK-style frame data in 60fps physics frames: startup / active / recovery, sized
# so the move ENDS exactly when its ~10fps animation ends (N frames / 10fps).
#   light : 3 frames @10fps = 18f = 0.30s   (MK punch = 0.3s)
#   medium: 5 frames @10fps = 30f = 0.50s   (MK light kick = 0.5s)
#   heavy : 6 frames @10fps = 36f = 0.60s   (MK roundhouse = 0.8s)
#   air   : 5 frames @10fps = 30f = 0.50s
const PERSON_ATK_TIMING := {
	"light":  {"startup": 7,  "active": 5,  "recovery": 6},
	"medium": {"startup": 12, "active": 6,  "recovery": 12},
	"heavy":  {"startup": 16, "active": 7,  "recovery": 13},
	"air":    {"startup": 6,  "active": 16, "recovery": 8},
}
# MK anti-spam: after taking a hit you are briefly invulnerable so a fast attack
# can't mash-lock you (MK's `time_flag`; MK uses 2.0s but that makes the match
# turn-based, so we use a snappier arcade window). This is the ONLY anti-spam --
# no combo proration, because MK has no combos: one move at a time until it ends.
const HIT_INVULN_TIME := 1.0
# MK deals a FLAT amount per clean hit regardless of which strike (its code does
# `health -= 15` for every hit). We mirror that: all normals do the same damage.
const PERSON_HIT_DAMAGE := 15
const PERSON_HIT_KNOCKBACK := 360.0   # uniform modest stagger, MK-style
const PERSON_HIT_STUN := 20           # uniform short hitstun (~0.33s)
# Real-arcade hitstop: a small, UNIFORM impact freeze on contact (~0.05s) so hits
# feel solid like a real fighting game -- but equal across every strike, so no
# move stalls mid-swing or "feels slower" up close (that was the old 6/8/12 bug).
const PERSON_HITSTOP := 3

# Arcade (Mortal-Kombat-style) feel: fast crisp walks, big snappy jumps, quick
# dashes. Movement is set directly each frame (no momentum drift), so releasing
# a direction stops you instantly -- the hallmark of an arcade fighter.
const WALK_SPEED := 700.0
const BACKWARD_SPEED := 540.0
const AIR_SPEED := 660.0
const JUMP_VELOCITY := -1320.0
const GRAVITY := 3050.0
const MAX_FALL_SPEED := 1750.0
const DASH_SPEED := 1520.0
const DASH_FRAMES := 8
const DASH_COOLDOWN := 0.42
const SLIDE_SPEED := 1040.0
const SLIDE_FRAMES := 12
const SLIDE_COOLDOWN := 0.55
const DOUBLE_TAP_TIME := 0.22
const GUARD_KEY := KEY_I
const GUARD_MAX := 100.0
const GUARD_MIN_TO_BLOCK := 8.0
const GUARD_REGEN_DELAY := 0.85
const GUARD_REGEN_RATE := 32.0
const GUARD_HOLD_DRAIN := 13.0
const GUARD_BREAK_STUN_FRAMES := 38
const PUSHBOX_WIDTH := 58.0
const PUSHBOX_HEIGHT := 140.0
const PUSHBOX_Y_OFFSET := -70.0
const SPAM_WINDOW_SIZE := 6
const SPAM_DAMAGE_SCALES := [1.0, 0.82, 0.65, 0.48, 0.36, 0.28]
const SPAM_HITSTUN_FRAME_PENALTIES := [0, 2, 5, 8, 12, 16]
const SPAM_WINDOW_TIME := 1.05
const FULL_COMBO_INPUT_WINDOW := 0.85

# --- Super meter (drives the minigame "super attacks"; see super_fight_test.gd) ---
# Like real fighters, the meter builds from COMBAT only (never from a timer):
# proportional to the damage you deal AND the damage you take, with the
# defender gaining a little more so a losing player can fight back to a super
# (a comeback mechanic, as in Street Fighter / KOF).
const SUPER_METER_PER_DMG_DEALT := 1.0    # meter per point of damage dealt
const SUPER_METER_PER_DMG_TAKEN := 1.4    # meter per point of damage taken

# ── Special move ──────────────────────────────────────────────────────────────
# Every fighter has one signature special (see characters/scripts/specials/).
# It is triggered by a quick DOUBLE-TAP of the dedicated special key O ("OO").
# A dedicated key (separate from the attack buttons) keeps the input clean and
# reliable on any keyboard. Re-bind below.
const SPECIAL_KEY := KEY_O                  # dedicated special button
const SPECIAL_TAP_COUNT := 2                # taps of SPECIAL_KEY that fire the special ("OO")
const SPECIAL_TAP_INTERVAL := 0.30          # max seconds between consecutive taps
const SPECIAL_CANCEL_FRAMES := 72           # the special can interrupt a normal attack in progress

enum FighterState {
	IDLE,
	WALK,
	CROUCH,
	JUMP,
	DASH,
	SLIDE,
	ATTACK,
	SPECIAL,
	BLOCK,
	BLOCKSTUN,
	HITSTUN,
	DEAD,
}

@onready var sprite: AnimatedSprite2D = $Visual/AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_hitbox_shape: CollisionShape2D = $AttackHitbox/AttackHitboxShape
@onready var hurtbox_shape: CollisionShape2D = $Hurtbox/HurtboxShape

var state: FighterState = FighterState.IDLE
var health := max_health
var super_meter := 0.0
var super_max := 100.0
var super_fill_enabled := false   # off by default; the super-fight controller turns it on
var _super_full_sent := false
var guard_meter := GUARD_MAX
var facing_dir := 1
var opponent: Node2D

var _state_frame := 0
var _frame_accum := 0.0
var _state_timer := 0.0
var _hitstop_timer := 0.0
var _dash_cooldown := 0.0
var _slide_cooldown := 0.0
var _guard_regen_delay := 0.0
var _last_left_tap := -10.0
var _last_right_tap := -10.0
var _dash_dir := 1
var _slide_dir := 1
var _slide_lockout := false

var _active_attack := ""
var _queued_attack := ""
var _attack_landed := false
var _attack_blocked := false
var _hit_targets := {}
var _combo_input_buffer: Array[Dictionary] = []
# Combo input buffering: a chain follow-up pressed mid-attack is remembered and
# fires the instant the cancel window opens (the hit lands), so MK-style strings
# flow even if you mash the next button a little early.
var _buffered_followup := ""

var _special_ability: SpecialAbility = null
var _special_cooldown := 0.0
var _special_fired := false
var _special_requested := false
var _special_tap_count := 0
var _last_special_tap := -10.0

var _move_dir := 0
var _down_held := false
var _down_pressed := false
var _guard_held := false
var _jump_pressed := false
var _left_pressed := false
var _right_pressed := false
var _attack_requests: Array[String] = []
var _key_down := {}
var _just_pressed := {}

var _bot_mode := "wait"
var _bot_mode_timer := 0.0
var _bot_attack_cooldown := 0.0
var _bot_rng := RandomNumberGenerator.new()

var _recent_received_attacks: Array[String] = []
var _last_received_attacker_id := 0
var _repeat_hit_timer := 0.0
var _network_sync_timer := 0.0
var _hit_invuln_timer := 0.0   # MK post-hit invulnerability window (anti-spam)

var _attack_defs := {
	"light": {
		"animation": "arm_attack",
		"damage": 7,
		"chip_damage": 1,
		"guard_damage": 13.0,
		"startup": 4,
		"active": 3,
		"recovery": 10,
		"hitstun": 14,
		"blockstun": 10,
		"hitstop": 6,
		"hit_knockback": 270.0,
		"block_knockback": 320.0,
		"self_block_recoil": 370.0,
		"cancel_frame": 7,
		"chains": ["light", "medium", "heavy"],
		"frames": [64, 65, 66, 67, 68],
		"anim_speed": 34.0,
		"hitbox_offset": Vector2(76.0, -86.0),
		"hitbox_size": Vector2(88.0, 62.0),
		"move_startup": 0.92,
		"move_active": 0.52,
		"move_recovery": 0.28,
	},
	"medium": {
		"animation": "leg_attack",
		"damage": 9,
		"chip_damage": 1,
		"guard_damage": 22.0,
		"startup": 7,
		"active": 4,
		"recovery": 14,
		"hitstun": 20,
		"blockstun": 13,
		"hitstop": 8,
		"hit_knockback": 380.0,
		"block_knockback": 430.0,
		"self_block_recoil": 500.0,
		"cancel_frame": 12,
		"chains": ["heavy"],
		"frames": [69, 70, 71, 72, 73, 74],
		"anim_speed": 28.0,
		"hitbox_offset": Vector2(90.0, -76.0),
		"hitbox_size": Vector2(112.0, 58.0),
		"move_startup": 0.78,
		"move_active": 0.42,
		"move_recovery": 0.18,
	},
	"heavy": {
		"animation": "heavy_attack",
		"damage": 18,
		"chip_damage": 2,
		"guard_damage": 48.0,
		"startup": 14,
		"active": 5,
		"recovery": 24,
		"hitstun": 34,
		"blockstun": 18,
		"hitstop": 12,
		"hit_knockback": 720.0,
		"block_knockback": 690.0,
		"self_block_recoil": 820.0,
		"cancel_frame": 999,
		"chains": [],
		"frames": [75, 76, 77, 78, 79, 80, 81, 82],
		"anim_speed": 18.0,
		"hitbox_offset": Vector2(108.0, -82.0),
		"hitbox_size": Vector2(132.0, 82.0),
		"move_startup": 0.58,
		"move_active": 0.22,
		"move_recovery": 0.08,
	},
	"full_combo": {
		"animation": "full_combo",
		"damage": 4,
		"chip_damage": 1,
		"guard_damage": 16.0,
		"startup": 4,
		"active": 32,
		"recovery": 16,
		"hitstun": 18,
		"blockstun": 11,
		"hitstop": 5,
		"hit_knockback": 300.0,
		"block_knockback": 350.0,
		"self_block_recoil": 410.0,
		"cancel_frame": 999,
		"chains": [],
		"frames": [64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82],
		"anim_speed": 25.0,
		"hitbox_offset": Vector2(86.0, -82.0),
		"hitbox_size": Vector2(104.0, 70.0),
		"move_startup": 0.86,
		"move_active": 0.34,
		"move_recovery": 0.10,
		"hit_segments": [
			{
				"hit_id": "arm",
				"start": 4,
				"end": 9,
				"damage": 3,
				"chip_damage": 1,
				"guard_damage": 12.0,
				"hitstun": 13,
				"blockstun": 9,
				"hitstop": 4,
				"hit_knockback": 250.0,
				"block_knockback": 300.0,
				"self_block_recoil": 340.0,
				"hitbox_offset": Vector2(76.0, -86.0),
				"hitbox_size": Vector2(88.0, 62.0),
			},
			{
				"hit_id": "leg",
				"start": 13,
				"end": 19,
				"damage": 4,
				"chip_damage": 1,
				"guard_damage": 18.0,
				"hitstun": 17,
				"blockstun": 11,
				"hitstop": 5,
				"hit_knockback": 340.0,
				"block_knockback": 390.0,
				"self_block_recoil": 460.0,
				"hitbox_offset": Vector2(92.0, -76.0),
				"hitbox_size": Vector2(112.0, 58.0),
			},
			{
				"hit_id": "heavy_leg",
				"start": 25,
				"end": 34,
				"damage": 7,
				"chip_damage": 2,
				"guard_damage": 34.0,
				"hitstun": 28,
				"blockstun": 16,
				"hitstop": 8,
				"hit_knockback": 560.0,
				"block_knockback": 620.0,
				"self_block_recoil": 720.0,
				"hitbox_offset": Vector2(108.0, -82.0),
				"hitbox_size": Vector2(132.0, 82.0),
			},
		],
	},
	"air": {
		"animation": "air_attack",
		"damage": 11,
		"chip_damage": 1,
		"guard_damage": 18.0,
		"startup": 5,
		"active": 9,
		"recovery": 18,
		"hitstun": 22,
		"blockstun": 12,
		"hitstop": 6,
		"hit_knockback": 350.0,
		"block_knockback": 360.0,
		"self_block_recoil": 420.0,
		"cancel_frame": 999,
		"chains": [],
		"frames": [62, 63],
		"anim_speed": 8.0,
		"hitbox_offset": Vector2(82.0, -94.0),
		"hitbox_size": Vector2(104.0, 76.0),
		"move_startup": 0.94,
		"move_active": 0.68,
		"move_recovery": 0.45,
	},
}

# Hit payloads for the special moves. These are never started as normal attacks;
# they are only looked up by receive_hit() (via get_attack_payload) when a
# special's effect lands, so they reuse the exact same damage / block / knockback
# pipeline as ordinary attacks.
var _special_hit_defs := {
	"special_yantsi": {
		"damage": 12,
		"chip_damage": 2,
		"guard_damage": 30.0,
		"hit_knockback": 430.0,
		"block_knockback": 360.0,
		"self_block_recoil": 0.0,
		"hitstun": 26,
		"blockstun": 14,
		"hitstop": 8,
	},
	"special_trumpet": {
		"damage": 12,
		"chip_damage": 2,
		"guard_damage": 26.0,
		"hit_knockback": 760.0,
		"block_knockback": 620.0,
		"self_block_recoil": 0.0,
		"hitstun": 24,
		"blockstun": 12,
		"hitstop": 7,
	},
	"special_beer": {
		# A repeating hazard tick (the puddle damages while you stand in it), so
		# per-hit values are modest; the anti-spam proration tapers repeats.
		"damage": 6,
		"chip_damage": 1,
		"guard_damage": 20.0,
		"hit_knockback": 200.0,
		"block_knockback": 180.0,
		"self_block_recoil": 0.0,
		"hitstun": 12,
		"blockstun": 8,
		"hitstop": 4,
	},
}


func _ready() -> void:
	_bot_rng.randomize()
	health = max_health
	if attack_hitbox_shape.shape != null:
		attack_hitbox_shape.shape = attack_hitbox_shape.shape.duplicate()
	if hurtbox_shape.shape != null:
		hurtbox_shape.shape = hurtbox_shape.shape.duplicate()
	_build_sprite_frames()
	attack_hitbox.area_entered.connect(_on_attack_hitbox_area_entered)
	_set_attack_hitbox_active(false)
	_resolve_opponent()
	_resolve_special_ability()
	_enter_state(FighterState.IDLE)
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	_resolve_opponent()
	_poll_key_edges()

	if _is_remote_network_player():
		return

	if bot_enabled:
		_update_bot_ai(delta)
	elif _has_local_input():
		_read_local_inputs()

	_update_facing()
	_update_global_timers(delta)

	if _hitstop_timer > 0.0:
		_hitstop_timer = maxf(_hitstop_timer - delta, 0.0)
		if _hitstop_timer <= 0.0:
			sprite.speed_scale = 1.0
		_sync_network_state(delta)
		return

	if state != FighterState.DEAD and not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	match state:
		FighterState.IDLE, FighterState.WALK, FighterState.CROUCH:
			_process_neutral(delta)
		FighterState.JUMP:
			_process_jump(delta)
		FighterState.DASH:
			_process_dash(delta)
		FighterState.SLIDE:
			_process_slide(delta)
		FighterState.ATTACK:
			_process_attack(delta)
		FighterState.SPECIAL:
			_process_special(delta)
		FighterState.BLOCK:
			_process_block(delta)
		FighterState.BLOCKSTUN, FighterState.HITSTUN:
			_process_stun(delta)
		FighterState.DEAD:
			_process_dead(delta)

	move_and_slide()
	_resolve_pushbox_overlap()
	_sync_network_state(delta)


func _build_sprite_frames() -> void:
	if PERSON_SETS.has(character_key):
		_build_person_frames(PERSON_SETS[character_key])
	else:
		_build_placeholder_frames()


func _build_placeholder_frames() -> void:
	sprite.scale = Vector2.ONE
	sprite.position = Vector2.ZERO
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_numbered_animation(frames, "idle", "fighter_Idle_", 1, 8, 12.0, true)
	_add_numbered_animation(frames, "walk", "fighter_walk_", 9, 16, 22.0, true)
	_add_numbered_animation(frames, "walk_back", "fighter_walk_", 9, 16, 22.0, true, true)
	_add_numbered_animation(frames, "slide", "fighter_slide_", 25, 32, 28.0, false)
	_add_numbered_animation(frames, "dash", "fighter_dash_", 33, 38, 32.0, false)
	_add_numbered_animation(frames, "jump_start", "fighter_jump_", 43, 47, 34.0, false)
	_add_numbered_animation(frames, "hit", "fighter_hit_", 48, 51, 22.0, false)
	_add_numbered_animation(frames, "death", "fighter_death_", 52, 61, 18.0, false)
	for attack_name in ["light", "medium", "heavy", "full_combo"]:
		var data: Dictionary = _attack_defs[attack_name]
		_add_combo_animation(frames, data["animation"], data["frames"], float(data["anim_speed"]))
	_add_numbered_animation(frames, "air_attack", "fighter_air_attack_", 62, 63, float(_attack_defs["air"]["anim_speed"]), false)
	sprite.sprite_frames = frames


# A hand-drawn person has walk / jump / hand kick / leg kick / hard hit. The
# state machine's other animations are mapped onto those: idle = first walk
# frame, backward walk = walk reversed, hand kick = light (J), leg kick =
# medium (K) + air fallback, hard hit = heavy (L), dash = one hard-hit pose,
# full_combo = leg, hit/death = a still frame. Attack timing is retuned to the
# art afterwards (see _retune_person_attacks).
func _build_person_frames(info: Dictionary) -> void:
	var base := str(info["base"])
	var walk_n := int(info["walk"])
	var hand_n := int(info["hand"])
	var leg_n := int(info["leg"])
	var hard_n := int(info["hard"])
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	# MK feel: few frames at ~10fps. Walk uses a trimmed 8-frame loop, and each
	# attack keeps only a handful of distinct poses (see PERSON_CUT_FRAMES).
	var cut: Dictionary = PERSON_CUT_FRAMES.get(character_key, {})
	var hand_frames: Array = cut.get("hand", range(0, hand_n))
	var leg_frames: Array = cut.get("leg", range(0, leg_n))
	var hard_frames: Array = cut.get("hard", range(0, hard_n))
	_add_person_anim_list(frames, "walk", PERSON_WALK_DIR, base, PERSON_WALK_FRAMES, PERSON_ANIM_FPS, true, false)
	_add_person_anim_list(frames, "walk_back", PERSON_WALK_DIR, base, PERSON_WALK_FRAMES, PERSON_ANIM_FPS, true, true)
	# Attack playback speeds are confirmed in _retune_person_attacks (fixed ~10fps).
	_add_person_anim_list(frames, "arm_attack", PERSON_HAND_DIR, base, hand_frames, PERSON_ANIM_FPS, false, false)
	_add_person_anim_list(frames, "leg_attack", PERSON_LEG_DIR, base, leg_frames, PERSON_ANIM_FPS, false, false)
	_add_person_anim_list(frames, "heavy_attack", PERSON_HARD_DIR, base, hard_frames, PERSON_ANIM_FPS, false, false)
	_add_person_anim_list(frames, "air_attack", PERSON_LEG_DIR, base, leg_frames, PERSON_ANIM_FPS, false, false)
	_add_person_anim_list(frames, "jump_start", PERSON_JUMP_DIR, base, info["jump"], 10.0, false, false)
	_add_person_anim_list(frames, "dash", PERSON_WALK_DIR, base, [info["dash"]], 6.0, false, false)
	_add_person_anim(frames, "idle", PERSON_IDLE_DIR, base, 0, int(info["idle"]) - 1, 9.0, true, false)
	for still in ["slide", "hit"]:
		_add_person_anim(frames, still, PERSON_IDLE_DIR, base, 0, 0, 6.0, false, false)
	# Block: hold the drawn block pose (replaces the old blue tint).
	var block_idx: int = int(PERSON_BLOCK_FRAME.get(character_key, 0))
	_add_person_anim_list(frames, "block", PERSON_BLOCK_DIR, base, [block_idx], 6.0, false, false)
	# Death: hold the drawn death pose (single un-numbered file: "<base>.png").
	frames.add_animation("death")
	frames.set_animation_speed("death", 1.0)
	frames.set_animation_loop("death", false)
	frames.add_frame("death", load("%s%s.png" % [PERSON_DEATH_DIR, base]))
	_add_person_anim(frames, "full_combo", PERSON_LEG_DIR, base, 0, leg_n - 1, 16.0, false, false)
	# Scotsman holds the bagpipe ("windpipe") pose while the air is blown out --
	# the trumpet special plays this during its wind-up (see TrumpetBlast).
	if bool(info.get("pipe", false)):
		frames.add_animation("bagpipe")
		frames.set_animation_speed("bagpipe", 6.0)
		frames.set_animation_loop("bagpipe", true)
		frames.add_frame("bagpipe", load(SCOTISH_PIPE_IMG))

	sprite.sprite_frames = frames
	_retune_person_attacks(info)

	# The hand-drawn art is 1000px tall; scale it to fighter size and drop the
	# feet onto the same ground line the placeholder uses. (facing uses flip_h,
	# so it's safe to drive sprite.scale here.)
	var s := PERSON_TARGET_HEIGHT / float(info["fig_h"])
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2(0.0, 124.0 - float(info["feet"]) * s)


# MK-faithful timing: each normal is a SHORT, fixed move whose length matches
# its trimmed ~10fps animation, the hit lands mid-swing, and -- crucially -- the
# move is NOT cancelable (MK has no combos: one strike at a time, committed until
# it finishes). Damage is chunky and knockback modest; the air kick gets a roomy,
# downward-reaching hitbox so a jump-in connects.
func _retune_person_attacks(_info: Dictionary) -> void:
	for atk in PERSON_ATK_TIMING.keys():
		var t: Dictionary = PERSON_ATK_TIMING[atk]
		var def: Dictionary = _attack_defs[atk]
		def["startup"] = int(t["startup"])
		def["active"] = int(t["active"])
		def["recovery"] = int(t["recovery"])
		def["cancel_frame"] = 999   # MK: no cancels.
		def["chains"] = []          # MK: no chained combos.
		# Every drawn swing plays at MK's fixed ~10fps (frame count = duration).
		if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(str(def["animation"])):
			sprite.sprite_frames.set_animation_speed(str(def["animation"]), PERSON_ANIM_FPS)
	# Literal MK: every clean hit does the same flat damage / stagger, regardless
	# of which strike. The post-hit invuln window (HIT_INVULN_TIME) -- not
	# proration -- is what stops spamming.
	for atk in ["light", "medium", "heavy", "air"]:
		_attack_defs[atk]["damage"] = PERSON_HIT_DAMAGE
		_attack_defs[atk]["hit_knockback"] = PERSON_HIT_KNOCKBACK
		_attack_defs[atk]["hitstun"] = PERSON_HIT_STUN
		_attack_defs[atk]["hitstop"] = PERSON_HITSTOP   # MK: no big impact freeze
	# A grounded foe's hurtbox spans y -144..0. Tall, downward-reaching air box
	# so a descending kick connects across a wide height band.
	var air: Dictionary = _attack_defs["air"]
	air["hitbox_offset"] = Vector2(76.0, -50.0)
	air["hitbox_size"] = Vector2(128.0, 174.0)


func _add_person_anim(frames: SpriteFrames, anim: String, dir: String, base: String, first: int, last: int, speed: float, loops: bool, reverse: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, speed)
	frames.set_animation_loop(anim, loops)
	var seq := range(first, last + 1)
	if reverse:
		seq = range(last, first - 1, -1)
	for n in seq:
		frames.add_frame(anim, load("%s%s%04d.png" % [dir, base, n]))


# Like _add_person_anim but takes an explicit list of (possibly non-contiguous)
# frame numbers -- the jump art only exists for a few sampled poses.
func _add_person_anim_list(frames: SpriteFrames, anim: String, dir: String, base: String, frame_list: Array, speed: float, loops: bool, reverse: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, speed)
	frames.set_animation_loop(anim, loops)
	var seq := frame_list.duplicate()
	if reverse:
		seq.reverse()
	for n in seq:
		frames.add_frame(anim, load("%s%s%04d.png" % [dir, base, int(n)]))


func _is_simple() -> bool:
	return PERSON_SETS.has(character_key)


# Swap the character at runtime (used by the character-select flow).
func set_character(key: String) -> void:
	character_key = key
	if sprite != null:
		_build_sprite_frames()
		_play_anim("idle", true)


func _add_numbered_animation(frames: SpriteFrames, animation_name: String, prefix: String, first_frame: int, last_frame: int, speed: float, loops: bool, reverse := false) -> void:
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, speed)
	frames.set_animation_loop(animation_name, loops)
	var seq := range(first_frame, last_frame + 1)
	if reverse:
		seq = range(last_frame, first_frame - 1, -1)
	for frame_number in seq:
		frames.add_frame(animation_name, load("%s%s%04d.png" % [SPRITE_DIR, prefix, frame_number]))


func _add_combo_animation(frames: SpriteFrames, animation_name: String, frame_numbers: Array, speed: float) -> void:
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, speed)
	frames.set_animation_loop(animation_name, false)
	for frame_number in frame_numbers:
		frames.add_frame(animation_name, load("%sfighter_combo_%04d.png" % [SPRITE_DIR, frame_number]))


func _process_neutral(_delta: float) -> void:
	if _guard_held and _can_guard():
		_enter_state(FighterState.BLOCK)
		return

	if _special_requested and _try_start_special():
		return

	if _try_start_attack_from_input():
		return

	if _jump_pressed and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_enter_state(FighterState.JUMP)
		_play_anim("jump_start", true)
		return

	if is_on_floor() and _try_start_slide():
		return

	if is_on_floor() and _try_start_dash():
		return

	if _down_held and is_on_floor():
		velocity.x = 0.0
		_enter_state(FighterState.CROUCH)
		_play_anim("idle")
		return

	var speed := _ground_speed_for_input(_move_dir)
	velocity.x = speed
	if _move_dir == 0:
		_enter_state(FighterState.IDLE)
		_play_anim("idle")
	elif _is_forward_input(_move_dir):
		_enter_state(FighterState.WALK)
		_play_anim("walk")
	else:
		_enter_state(FighterState.WALK)
		_play_anim("walk_back")   # backward walk = walk animation in reverse


func _process_jump(_delta: float) -> void:
	if _try_start_attack_from_input():
		return

	if _move_dir != 0:
		velocity.x = float(_move_dir) * AIR_SPEED

	if is_on_floor() and velocity.y >= 0.0:
		velocity.y = 0.0
		_enter_state(FighterState.IDLE)
		_play_anim("idle")
	else:
		_play_anim("jump_start")


func _process_dash(delta: float) -> void:
	_advance_state_frames(delta)
	velocity.x = float(_dash_dir) * DASH_SPEED
	if _state_frame >= DASH_FRAMES:
		velocity.x = 0.0
		_enter_state(FighterState.IDLE)
		_play_anim("idle")


func _process_slide(delta: float) -> void:
	_advance_state_frames(delta)
	velocity.x = float(_slide_dir) * SLIDE_SPEED
	if _state_frame >= SLIDE_FRAMES:
		velocity.x = 0.0
		if _down_held:
			_enter_state(FighterState.CROUCH)
			_play_anim("idle")
		else:
			_enter_state(FighterState.IDLE)
			_play_anim("idle")


func _process_attack(delta: float) -> void:
	_advance_state_frames(delta)
	# The very start of a normal attack can convert into the special (so the
	# chord still fires even though one of its keys briefly began an attack).
	if _special_requested and _state_frame <= SPECIAL_CANCEL_FRAMES and _try_start_special():
		return
	var data := _attack_data()
	if _is_simple():
		# MK roots you for grounded normals (committed strike); air kicks keep
		# their arc. No queue/cancel -- one move at a time, locked until it ends.
		if is_on_floor():
			velocity.x = 0.0
	else:
		var scale := _attack_movement_scale(data)
		if is_on_floor():
			velocity.x = _ground_speed_for_input(_move_dir) * scale
		elif _move_dir != 0:
			velocity.x = float(_move_dir) * AIR_SPEED * scale

		_try_queue_attack()
		# A queued follow-up means the move already landed and is cancelable, so
		# chain into it NOW -- cancel the recovery (placeholder fighter only).
		if _queued_attack != "" and _state_frame < _attack_total_frames(data):
			var chained := _queued_attack
			_queued_attack = ""
			_start_attack(chained)
			return

	_update_attack_hitbox_for_frame()

	if _state_frame >= _attack_total_frames(data):
		if not _is_simple() and _queued_attack != "":
			var next_attack := _queued_attack
			_queued_attack = ""
			_start_attack(next_attack)
			return
		_finish_attack()


func _process_block(delta: float) -> void:
	guard_meter = maxf(guard_meter - GUARD_HOLD_DRAIN * delta, 0.0)
	_guard_regen_delay = GUARD_REGEN_DELAY
	velocity.x = 0.0
	_apply_block_visual()

	if guard_meter <= 0.0 or not _guard_held:
		_enter_state(FighterState.IDLE)
		_reset_visual_tint()
		_play_anim("idle")


func _process_stun(delta: float) -> void:
	_advance_state_frames(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1150.0 * delta)
	if _state_frame >= int(_state_timer):
		_enter_state(FighterState.IDLE)
		_reset_visual_tint()
		_play_anim("idle")


func _process_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * delta)
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)


func _advance_state_frames(delta: float) -> void:
	_frame_accum += delta
	while _frame_accum >= FRAME_TIME:
		_frame_accum -= FRAME_TIME
		_state_frame += 1


func _update_global_timers(delta: float) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)
	_special_cooldown = maxf(_special_cooldown - delta, 0.0)
	_hit_invuln_timer = maxf(_hit_invuln_timer - delta, 0.0)
	_repeat_hit_timer = maxf(_repeat_hit_timer - delta, 0.0)
	if _repeat_hit_timer <= 0.0:
		_recent_received_attacks.clear()
		_last_received_attacker_id = 0

	if _guard_regen_delay > 0.0:
		_guard_regen_delay = maxf(_guard_regen_delay - delta, 0.0)
	elif state != FighterState.BLOCK and state != FighterState.BLOCKSTUN and state != FighterState.HITSTUN and state != FighterState.DEAD and not _guard_held:
		guard_meter = minf(guard_meter + GUARD_REGEN_RATE * delta, GUARD_MAX)


func _try_start_attack_from_input() -> bool:
	if _attack_requests.is_empty():
		return false
	if state == FighterState.JUMP or not is_on_floor():
		_start_attack("air")
		return true
	_start_attack(_attack_requests[0])
	return true


func _try_queue_attack() -> void:
	# Remember a chainable follow-up even if pressed before the cancel window.
	if not _attack_requests.is_empty():
		var requested := _attack_requests[0]
		if requested == "full_combo":
			if _active_attack == "light" or _active_attack == "medium":
				_start_full_combo_continuation(_active_attack, _state_frame)
			return
		if _is_chain_target(requested):
			_buffered_followup = requested
	# Fire the buffered follow-up the moment the move is cancelable (hit landed).
	if _queued_attack == "" and _buffered_followup != "" and _can_cancel_into(_buffered_followup):
		_queued_attack = _buffered_followup
		_buffered_followup = ""


func _is_chain_target(attack_name: String) -> bool:
	if _active_attack == "" or not _attack_defs.has(_active_attack):
		return false
	return (_attack_defs[_active_attack]["chains"] as Array).has(attack_name)


func _can_cancel_into(attack_name: String) -> bool:
	if _active_attack == "" or _active_attack == "air":
		return false
	var data := _attack_data()
	if _state_frame < int(data["cancel_frame"]):
		return false
	if attack_name == "full_combo":
		return _active_attack == "light" or _active_attack == "medium"
	var chains: Array = data["chains"]
	if not (_attack_landed or _attack_blocked):
		return false
	return chains.has(attack_name)


func _start_attack(attack_name: String) -> void:
	if not _attack_defs.has(attack_name) or state == FighterState.DEAD or state == FighterState.HITSTUN:
		return
	_active_attack = attack_name
	_queued_attack = ""
	_buffered_followup = ""
	_attack_landed = false
	_attack_blocked = false
	_hit_targets.clear()
	_enter_state(FighterState.ATTACK)
	var data := _attack_data()
	_play_anim(data["animation"], true)
	_update_attack_hitbox_shape()
	_update_attack_hitbox_for_frame()
	attack_started.emit(attack_name)


func _start_full_combo_continuation(previous_attack: String, previous_state_frame: int) -> void:
	_start_attack("full_combo")
	if previous_attack == "light" and previous_state_frame >= 2:
		_seek_attack_to_frame(9, 5)
	elif previous_attack == "medium" and previous_state_frame >= 3:
		_seek_attack_to_frame(19, 11)


func _seek_attack_to_frame(attack_frame: int, visual_frame: int) -> void:
	_state_frame = attack_frame
	_frame_accum = 0.0
	if sprite.sprite_frames == null or _active_attack == "" or not _attack_defs.has(_active_attack):
		return
	var data := _attack_data()
	var animation_name := str(data["animation"])
	if not sprite.sprite_frames.has_animation(animation_name):
		return
	var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
	if frame_count > 0:
		sprite.frame = clampi(visual_frame, 0, frame_count - 1)
	_update_attack_hitbox_shape()
	_update_attack_hitbox_for_frame()


func _finish_attack() -> void:
	_set_attack_hitbox_active(false)
	_active_attack = ""
	_queued_attack = ""
	_buffered_followup = ""
	_hit_targets.clear()
	if is_on_floor():
		_enter_state(FighterState.IDLE)
		_play_anim("idle")
	else:
		_enter_state(FighterState.JUMP)
		_play_anim("idle")


# ══════════════════════════════════ SPECIAL ════════════════════════════════════
func _resolve_special_ability() -> void:
	var character_id := str(get_meta("character_id", ""))
	_special_ability = SpecialRegistry.for_character(character_id)


func is_special_ready() -> bool:
	return _special_ability != null \
		and _special_cooldown <= 0.0 \
		and state != FighterState.DEAD \
		and state != FighterState.HITSTUN \
		and state != FighterState.BLOCKSTUN \
		and state != FighterState.SPECIAL


func _try_start_special() -> bool:
	_special_requested = false
	if not is_special_ready() or not is_on_floor():
		return false
	_start_special()
	return true


func _start_special() -> void:
	_special_fired = false
	_active_attack = ""
	_queued_attack = ""
	_hit_targets.clear()
	_set_attack_hitbox_active(false)
	_enter_state(FighterState.SPECIAL)
	# Cooldown starts the moment the move is committed, not when it connects.
	_special_cooldown = _special_ability.cooldown()
	velocity.x = 0.0
	_play_anim(_special_ability.user_animation(), true)
	attack_started.emit("special:" + _special_ability.id())
	_broadcast_critical_network_state()


func _process_special(delta: float) -> void:
	_advance_state_frames(delta)
	velocity.x = move_toward(velocity.x, 0.0, 2200.0 * delta)
	if _special_ability == null:
		_finish_special()
		return
	if not _special_fired and _state_frame >= _special_ability.windup_frames():
		_fire_special()
	if _state_frame >= _special_ability.total_frames():
		_finish_special()


func _fire_special() -> void:
	_special_fired = true
	if _special_ability == null:
		return
	var dir := facing_dir
	var origin := special_hand_position()
	# Authoritative cast (deals damage) on this machine...
	_special_ability.cast(self, true, origin, dir)
	# ...and a visual-only copy on the other peer so both screens match.
	if multiplayer.has_multiplayer_peer():
		_rpc_cast_special.rpc(_special_ability.id(), origin, dir)


func _finish_special() -> void:
	_special_fired = false
	if is_on_floor():
		_enter_state(FighterState.IDLE)
		_play_anim("idle")
	else:
		_enter_state(FighterState.JUMP)
		_play_anim("idle")


@rpc("authority", "call_remote", "reliable")
func _rpc_cast_special(ability_id: String, origin: Vector2, dir: int) -> void:
	if is_multiplayer_authority():
		return
	var ability := SpecialRegistry.make(ability_id)
	if ability == null:
		return
	ability.cast(self, false, origin, dir)


# World-space spawn point of a thrown object — a "hand" in front of the fighter.
func special_hand_position() -> Vector2:
	return global_position + Vector2(46.0 * float(facing_dir), -96.0)


# Adds a special's effect node into the shared world (the Players container).
func spawn_world_effect(node: Node2D) -> void:
	var parent := get_parent()
	if parent != null:
		parent.add_child(node)
	else:
		add_child(node)


# Routes a special's hit through the exact same path as a melee hit: over the
# network to the target's authority if remote, otherwise applied directly.
func deal_special_hit(target, attack_name: String) -> void:
	if _is_remote_network_player() or target == null or not is_instance_valid(target):
		return
	if not target.has_method("receive_hit"):
		return
	var data := get_attack_payload(attack_name)
	if data.is_empty():
		return
	if _try_send_network_hit(target, data, attack_name):
		return
	target.receive_hit(int(data["damage"]), self, float(data["hit_knockback"]), attack_name)


# Like deal_special_hit but waits `delay` seconds first — lets a telegraph
# (e.g. the Scottish wind gust sweeping across) play before the hit lands.
func deal_special_hit_after(target, attack_name: String, delay: float) -> void:
	if delay <= 0.0:
		deal_special_hit(target, attack_name)
		return
	await get_tree().create_timer(delay).timeout
	if target != null and is_instance_valid(target):
		deal_special_hit(target, attack_name)


# ── HUD helpers ──────────────────────────────────────────────────────────────
func has_special() -> bool:
	return _special_ability != null


func get_special_name() -> String:
	return "" if _special_ability == null else _special_ability.display_name()


func get_special_cooldown_remaining() -> float:
	return _special_cooldown


func get_special_cooldown_total() -> float:
	return 0.0 if _special_ability == null else _special_ability.cooldown()


# Test/debug helper — instantly recharges the special.
func reset_special_cooldown() -> void:
	_special_cooldown = 0.0


func _try_start_dash() -> bool:
	if bot_enabled or _dash_cooldown > 0.0 or not _is_forward_input(_move_dir):
		return false
	var tapped_forward := (_right_pressed and facing_dir > 0) or (_left_pressed and facing_dir < 0)
	if not tapped_forward:
		return false

	var now := Time.get_ticks_msec() / 1000.0
	if _move_dir > 0:
		if now - _last_right_tap <= DOUBLE_TAP_TIME:
			_start_dash()
			return true
		_last_right_tap = now
	else:
		if now - _last_left_tap <= DOUBLE_TAP_TIME:
			_start_dash()
			return true
		_last_left_tap = now
	return false


func _start_dash() -> void:
	_dash_cooldown = DASH_COOLDOWN
	_dash_dir = facing_dir
	_last_left_tap = -10.0
	_last_right_tap = -10.0
	_enter_state(FighterState.DASH)
	_play_anim("dash", true)


func _try_start_slide() -> bool:
	if _is_simple() or bot_enabled or _slide_cooldown > 0.0 or _slide_lockout:
		return false
	if not is_on_floor() or not _down_held or _move_dir == 0:
		return false
	var pressed_slide_chord := _down_pressed or (_down_held and (_left_pressed or _right_pressed))
	if not pressed_slide_chord:
		return false
	_start_slide(_move_dir)
	return true


func _start_slide(direction: int) -> void:
	_slide_cooldown = SLIDE_COOLDOWN
	_slide_lockout = true
	_slide_dir = int(sign(direction))
	if _slide_dir == 0:
		_slide_dir = facing_dir
	facing_dir = _slide_dir
	_enter_state(FighterState.SLIDE)
	_play_anim("slide", true)


func receive_hit(amount: int, attacker: Node2D, knockback: float = 260.0, attack_name := "") -> Dictionary:
	if _is_remote_network_player() or state == FighterState.DEAD:
		return {"connected": false}
	# MK anti-spam: while still invulnerable from the last hit, the attack passes
	# through harmlessly (no damage, no block) -- you can't be mash-locked.
	if _hit_invuln_timer > 0.0:
		return {"connected": false}

	var data := {}
	if attacker != null and attacker.has_method("get_attack_payload"):
		data = attacker.call("get_attack_payload", attack_name)
	if data.is_empty():
		data = {
			"damage": amount,
			"chip_damage": maxi(1, amount / 8),
			"guard_damage": maxf(10.0, float(amount) * 2.0),
			"hit_knockback": knockback,
			"block_knockback": knockback * 0.75,
			"self_block_recoil": knockback * 0.65,
			"hitstun": 18,
			"blockstun": 10,
			"hitstop": 5,
		}

	if _should_block_attack(data):
		return _receive_blocked_hit(data, attacker)

	return _receive_clean_hit(data, attacker, attack_name)


func _receive_clean_hit(data: Dictionary, attacker: Node2D, attack_name: String) -> Dictionary:
	_hit_invuln_timer = HIT_INVULN_TIME   # MK: brief post-hit invulnerability.
	var attacker_id := int(attacker.get("player_id")) if attacker != null else 0
	var proration := _register_received_attack(attacker_id, attack_name)
	var damage := maxi(1, int(ceil(float(data["damage"]) * float(proration["damage_scale"]))))
	var hitstun_frames := maxi(4, int(data["hitstun"]) - int(proration["hitstun_penalty"]))
	var hit_from_dir := _hit_direction_from(attacker)

	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	took_hit.emit(damage, attacker_id)
	_grant_combat_super(attacker, damage)
	_set_attack_hitbox_active(false)
	_active_attack = ""
	_queued_attack = ""

	if health <= 0:
		state = FighterState.DEAD
		velocity.x = float(hit_from_dir) * float(data["hit_knockback"])
		velocity.y = minf(velocity.y, -180.0)
		_reset_visual_tint()
		_play_anim("death", true)
		_start_hitstop(int(data["hitstop"]))
		_broadcast_critical_network_state()
		died.emit(player_id)
		return {"connected": true, "blocked": false}

	_enter_state(FighterState.HITSTUN, hitstun_frames)
	velocity.x = float(hit_from_dir) * float(data["hit_knockback"])
	velocity.y = minf(velocity.y, -120.0)
	sprite.modulate = Color(1.0, 0.72, 0.72, 1.0)
	_play_anim("hit", true)
	_start_hitstop(int(data["hitstop"]))
	if attacker != null and attacker.has_method("_start_hitstop"):
		attacker.call("_start_hitstop", int(data["hitstop"]))
	_broadcast_critical_network_state()
	return {"connected": true, "blocked": false}


func _receive_blocked_hit(data: Dictionary, attacker: Node2D) -> Dictionary:
	var attacker_id := int(attacker.get("player_id")) if attacker != null else 0
	var hit_from_dir := _hit_direction_from(attacker)
	var guard_damage := float(data["guard_damage"])
	guard_meter = maxf(guard_meter - guard_damage, 0.0)
	_guard_regen_delay = GUARD_REGEN_DELAY

	if guard_meter <= 0.0:
		return _receive_guard_break(data, attacker, attacker_id, hit_from_dir)

	var chip := int(data["chip_damage"])
	health = maxi(health - chip, 1)
	health_changed.emit(health, max_health)
	blocked_hit.emit(chip, attacker_id)

	_enter_state(FighterState.BLOCKSTUN, int(data["blockstun"]))
	velocity.x = float(hit_from_dir) * float(data["block_knockback"])
	velocity.y = minf(velocity.y, 0.0)
	_set_attack_hitbox_active(false)
	_active_attack = ""
	_queued_attack = ""
	_apply_block_visual(true)
	_start_hitstop(int(data["hitstop"]))
	if attacker != null:
		if attacker.has_method("_start_hitstop"):
			attacker.call("_start_hitstop", int(data["hitstop"]))
		_apply_recoil_to_fighter(attacker, -hit_from_dir, float(data["self_block_recoil"]))
	_broadcast_critical_network_state()
	return {"connected": true, "blocked": true}


func _receive_guard_break(data: Dictionary, attacker: Node2D, attacker_id: int, hit_from_dir: int) -> Dictionary:
	_hit_invuln_timer = HIT_INVULN_TIME   # MK: brief post-hit invulnerability.
	var damage := maxi(1, int(data["chip_damage"]) + 8)
	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	took_hit.emit(damage, attacker_id)
	_grant_combat_super(attacker, damage)
	guard_meter = 0.0
	_set_attack_hitbox_active(false)
	_active_attack = ""
	_queued_attack = ""

	if health <= 0:
		state = FighterState.DEAD
		velocity.x = float(hit_from_dir) * float(data["hit_knockback"])
		velocity.y = minf(velocity.y, -180.0)
		_reset_visual_tint()
		_play_anim("death", true)
		_broadcast_critical_network_state()
		died.emit(player_id)
		return {"connected": true, "blocked": false}

	_enter_state(FighterState.HITSTUN, GUARD_BREAK_STUN_FRAMES)
	velocity.x = float(hit_from_dir) * maxf(float(data["block_knockback"]), 560.0)
	velocity.y = minf(velocity.y, -150.0)
	sprite.modulate = Color(1.0, 0.50, 0.24, 1.0)
	_play_anim("hit", true)
	_start_hitstop(int(data["hitstop"]) + 4)
	if attacker != null and attacker.has_method("_start_hitstop"):
		attacker.call("_start_hitstop", int(data["hitstop"]) + 4)
	_broadcast_critical_network_state()
	return {"connected": true, "blocked": false}


func _register_received_attack(attacker_id: int, attack_name: String) -> Dictionary:
	# MK fighters use the post-hit invuln window instead of damage proration.
	if _is_simple() or attacker_id == 0 or attack_name == "":
		return {"damage_scale": 1.0, "hitstun_penalty": 0}
	if attacker_id != _last_received_attacker_id or _repeat_hit_timer <= 0.0:
		_recent_received_attacks.clear()

	var same_attack_count := 0
	for recent in _recent_received_attacks:
		if recent == attack_name:
			same_attack_count += 1

	_recent_received_attacks.append(attack_name)
	while _recent_received_attacks.size() > SPAM_WINDOW_SIZE:
		_recent_received_attacks.pop_front()

	_last_received_attacker_id = attacker_id
	_repeat_hit_timer = SPAM_WINDOW_TIME

	return {
		"damage_scale": SPAM_DAMAGE_SCALES[mini(same_attack_count, SPAM_DAMAGE_SCALES.size() - 1)],
		"hitstun_penalty": SPAM_HITSTUN_FRAME_PENALTIES[mini(same_attack_count, SPAM_HITSTUN_FRAME_PENALTIES.size() - 1)],
	}


func _apply_recoil_to_fighter(fighter: Node, push_dir: int, force: float) -> void:
	if fighter == null or not fighter.has_method("apply_external_recoil"):
		return
	var target_peer_id := fighter.get_multiplayer_authority()
	if multiplayer.has_multiplayer_peer() and target_peer_id != multiplayer.get_unique_id():
		fighter.rpc_id(target_peer_id, "_rpc_apply_external_recoil", player_id, push_dir, force)
	else:
		fighter.call("apply_external_recoil", push_dir, force)


func apply_external_recoil(push_dir: int, force: float) -> void:
	if _is_remote_network_player() or state == FighterState.DEAD:
		return
	velocity.x = float(push_dir) * force
	_broadcast_critical_network_state()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_apply_external_recoil(source_player_id: int, push_dir: int, force: float) -> void:
	if not is_multiplayer_authority():
		return
	var source := _find_fighter_by_player_id(source_player_id)
	if source == null or source.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return
	apply_external_recoil(push_dir, force)


# --- Super meter -----------------------------------------------------------

# Add to this fighter's super meter; emit super_full once when it tops out.
func add_super(amount: float) -> void:
	if amount <= 0.0:
		return
	super_meter = clampf(super_meter + amount, 0.0, super_max)
	super_meter_changed.emit(super_meter, super_max)
	if super_meter >= super_max and not _super_full_sent:
		_super_full_sent = true
		super_full.emit(player_id)


func reset_super() -> void:
	super_meter = 0.0
	_super_full_sent = false
	super_meter_changed.emit(super_meter, super_max)


# Reward both sides of a confirmed hit (gated so the plain online match is
# unaffected: meter only moves when the controller has enabled the system).
func _grant_combat_super(attacker: Node2D, damage: int) -> void:
	# This runs on the VICTIM's authority. The victim gains meter locally; the
	# attacker must gain on ITS OWN authority (here it is the remote copy, which
	# the network sync would otherwise overwrite), so route it via RPC.
	if super_fill_enabled:
		add_super(float(damage) * SUPER_METER_PER_DMG_TAKEN)
	if attacker != null and attacker != self:
		attacker.grant_deal_meter.rpc(damage)


@rpc("any_peer", "call_local", "reliable")
func grant_deal_meter(damage: int) -> void:
	# Applied only on the fighter's own authority (the one that actually owns
	# this meter), so the dealt-damage gain isn't lost to the position sync.
	if is_multiplayer_authority() and super_fill_enabled:
		add_super(float(damage) * SUPER_METER_PER_DMG_DEALT)


# Damage dealt by a resolved super attack (from the minigame outcome). Routes a
# lethal result through the normal death path so the controller's `died` handler
# runs the resurrect/round logic.
func apply_super_damage(amount: int) -> void:
	if amount <= 0 or state == FighterState.DEAD:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	took_hit.emit(amount, 0)
	if health <= 0:
		state = FighterState.DEAD
		velocity = Vector2(0.0, -180.0)
		_set_attack_hitbox_active(false)
		_active_attack = ""
		_queued_attack = ""
		_reset_visual_tint()
		_play_anim("death", true)
		died.emit(player_id)
	else:
		sprite.modulate = Color(1.0, 0.72, 0.72, 1.0)
		_enter_state(FighterState.HITSTUN, 18)
		_play_anim("hit", true)


func reset_fighter(start_position: Vector2, reset_health := true) -> void:
	global_position = start_position
	velocity = Vector2.ZERO
	guard_meter = GUARD_MAX
	_guard_regen_delay = 0.0
	_dash_cooldown = 0.0
	_slide_cooldown = 0.0
	_slide_lockout = false
	_hitstop_timer = 0.0
	_hit_invuln_timer = 0.0
	_active_attack = ""
	_queued_attack = ""
	_hit_targets.clear()
	_combo_input_buffer.clear()
	_recent_received_attacks.clear()
	_last_received_attacker_id = 0
	_repeat_hit_timer = 0.0
	_network_sync_timer = 0.0
	_special_cooldown = 0.0
	_special_fired = false
	_special_requested = false
	_special_tap_count = 0
	_last_special_tap = -10.0
	_resolve_special_ability()
	if reset_health:
		health = max_health
		health_changed.emit(health, max_health)
	_set_attack_hitbox_active(false)
	sprite.speed_scale = 1.0
	_reset_visual_tint()
	_update_facing()
	_enter_state(FighterState.IDLE)
	_play_anim("idle", true)


func _mcp_state() -> Dictionary:
	return {
		"player_id": player_id,
		"health": health,
		"max_health": max_health,
		"guard": guard_meter,
		"state": _state_name(),
		"facing_dir": facing_dir,
		"accept_local_input": accept_local_input,
		"bot_enabled": bot_enabled,
		"bot_mode": _bot_mode,
		"active_attack": _active_attack,
		"state_frame": _state_frame,
	}


func _sync_network_state(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not is_multiplayer_authority():
		return
	_network_sync_timer -= delta
	if _network_sync_timer > 0.0:
		return
	_network_sync_timer = NETWORK_SYNC_INTERVAL
	_send_network_state(false)


func _broadcast_critical_network_state() -> void:
	if not multiplayer.has_multiplayer_peer() or not is_multiplayer_authority():
		return
	_network_sync_timer = NETWORK_SYNC_INTERVAL
	_send_network_state(true)


func _send_network_state(reliable: bool) -> void:
	var args := [
		global_position,
		velocity,
		facing_dir,
		int(state),
		health,
		guard_meter,
		_active_attack,
		_state_frame,
		str(sprite.animation),
		sprite.frame,
		sprite.is_playing(),
		sprite.modulate,
		super_meter,
	]
	if reliable:
		_rpc_apply_critical_network_state.rpc(args)
	else:
		_rpc_apply_network_state.rpc(args)


@rpc("authority", "call_remote", "unreliable")
func _rpc_apply_network_state(args: Array) -> void:
	_apply_network_state(args)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_critical_network_state(args: Array) -> void:
	_apply_network_state(args)


func _apply_network_state(args: Array) -> void:
	if is_multiplayer_authority() or args.size() < 12:
		return
	global_position = args[0]
	velocity = args[1]
	facing_dir = int(args[2])
	state = int(args[3])
	var previous_health := health
	health = int(args[4])
	guard_meter = float(args[5])
	_active_attack = str(args[6])
	_state_frame = int(args[7])
	if previous_health != health:
		health_changed.emit(health, max_health)
	_apply_remote_sprite(str(args[8]), int(args[9]), bool(args[10]), args[11])
	if args.size() > 12:
		super_meter = float(args[12])
		super_meter_changed.emit(super_meter, super_max)
	_update_attack_hitbox_shape()
	_update_attack_hitbox_for_frame()


func _apply_remote_sprite(animation_name: String, frame_index: int, playing: bool, color: Color) -> void:
	sprite.flip_h = facing_dir < 0
	sprite.modulate = color
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation_name):
		return
	if sprite.animation != animation_name:
		sprite.play(animation_name)
	var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
	if frame_count > 0:
		sprite.frame = clampi(frame_index, 0, frame_count - 1)
	if playing:
		if not sprite.is_playing():
			sprite.play(animation_name)
	else:
		sprite.pause()


func get_attack_payload(attack_name: String) -> Dictionary:
	var base_attack_name := attack_name
	if attack_name.contains(":"):
		base_attack_name = attack_name.split(":")[0]
	if _active_attack == base_attack_name:
		return _current_attack_hit_data()
	if _special_hit_defs.has(base_attack_name):
		return _special_hit_defs[base_attack_name].duplicate(true)
	if not _attack_defs.has(base_attack_name):
		return {}
	return _attack_defs[base_attack_name].duplicate(true)


func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	_try_hit_area(area)


func _check_attack_overlaps() -> void:
	for area in attack_hitbox.get_overlapping_areas():
		_try_hit_area(area)


func _try_hit_area(area: Area2D) -> void:
	if _is_remote_network_player() or state != FighterState.ATTACK or _active_attack == "":
		return
	var target := _find_fighter_from_area(area)
	if target == null or target == self:
		return
	var target_id := target.get_instance_id()
	var hit_id := _current_attack_hit_id()
	var hit_key := "%s:%s" % [target_id, hit_id]
	if _hit_targets.has(hit_key):
		return
	_hit_targets[hit_key] = true

	var data := _current_attack_hit_data()
	if _try_send_network_hit(target, data, hit_id):
		_attack_landed = true
		return

	if target.has_method("receive_hit"):
		var result = target.receive_hit(int(data["damage"]), self, float(data["hit_knockback"]), hit_id)
		if result is Dictionary and bool(result.get("connected", false)):
			_attack_landed = not bool(result.get("blocked", false))
			_attack_blocked = bool(result.get("blocked", false))


func _try_send_network_hit(target: Node, data: Dictionary, attack_hit_id: String) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	if not target.has_method("_is_remote_network_player") or not bool(target.call("_is_remote_network_player")):
		return false
	var target_peer_id := target.get_multiplayer_authority()
	if target_peer_id <= 0 or target_peer_id == multiplayer.get_unique_id():
		return false
	target.rpc_id(target_peer_id, "_rpc_receive_hit_from_peer", int(data["damage"]), player_id, float(data["hit_knockback"]), attack_hit_id)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_hit_from_peer(amount: int, attacker_player_id: int, knockback: float, attack_name: String) -> void:
	if not is_multiplayer_authority() or attacker_player_id == player_id:
		return
	var attacker := _find_fighter_by_player_id(attacker_player_id)
	if attacker == null or attacker.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return
	receive_hit(amount, attacker, knockback, attack_name)


func _find_fighter_by_player_id(search_player_id: int) -> Node2D:
	var players_root := get_parent()
	if players_root != null:
		for child in players_root.get_children():
			if child != self and child is Node2D and child.has_method("receive_hit") and int(child.get("player_id")) == search_player_id:
				return child
	if opponent != null and int(opponent.get("player_id")) == search_player_id:
		return opponent
	return null


func _find_fighter_from_area(area: Area2D) -> Node:
	var node: Node = area
	while node != null:
		if node.has_method("receive_hit"):
			return node
		node = node.get_parent()
	return null


func _update_attack_hitbox_for_frame() -> void:
	var active := state == FighterState.ATTACK and _is_attack_hitbox_active_frame()
	_set_attack_hitbox_active(active)
	if active:
		_check_attack_overlaps()


func _set_attack_hitbox_active(active: bool) -> void:
	attack_hitbox.monitoring = active
	attack_hitbox_shape.disabled = not active


func _update_attack_hitbox_shape() -> void:
	var offset := Vector2(84.0, -86.0)
	var size := Vector2(96.0, 82.0)
	if _active_attack != "" and _attack_defs.has(_active_attack):
		var data := _current_attack_hit_data()
		offset = data["hitbox_offset"]
		size = data["hitbox_size"]
	attack_hitbox.position = Vector2(offset.x * facing_dir, offset.y)
	var shape := attack_hitbox_shape.shape as RectangleShape2D
	if shape != null:
		shape.size = size


func _resolve_pushbox_overlap() -> void:
	if opponent == null or not is_instance_valid(opponent) or not opponent.has_method("get_pushbox_rect"):
		return
	if state == FighterState.DEAD or int(opponent.get("state")) == FighterState.DEAD:
		return
	var mine := get_pushbox_rect()
	var theirs: Rect2 = opponent.call("get_pushbox_rect")
	if not mine.intersects(theirs):
		return
	var overlap := minf(mine.end.x, theirs.end.x) - maxf(mine.position.x, theirs.position.x)
	if overlap <= 0.0:
		return
	var side := signf(global_position.x - opponent.global_position.x)
	if side == 0.0:
		side = -1.0 if player_id == 1 else 1.0
	global_position.x += side * overlap * 0.5


func get_pushbox_rect() -> Rect2:
	var size := Vector2(PUSHBOX_WIDTH, PUSHBOX_HEIGHT)
	var shape := body_shape.shape as RectangleShape2D
	if shape != null:
		size = shape.size
	return Rect2(global_position + Vector2(-size.x * 0.5, PUSHBOX_Y_OFFSET - size.y * 0.5), size)


func _resolve_opponent() -> void:
	if opponent != null and is_instance_valid(opponent):
		return
	if opponent_path != NodePath():
		opponent = get_node_or_null(opponent_path)
		if opponent != null:
			return
	for fighter in get_tree().get_nodes_in_group("fighters"):
		if fighter != self and fighter is Node2D:
			opponent = fighter
			return


func _read_local_inputs() -> void:
	_left_pressed = _consume_just_pressed(KEY_A)
	_right_pressed = _consume_just_pressed(KEY_D)
	_down_pressed = _consume_just_pressed(KEY_S)
	_move_dir = 0
	if Input.is_physical_key_pressed(KEY_A):
		_move_dir -= 1
	if Input.is_physical_key_pressed(KEY_D):
		_move_dir += 1
	# People (english/georgian/scotish) walk + jump (W) + hand kick (J) +
	# leg kick (K) + hard hit / heavy (L), and double-tap O fires the special.
	# They still have no crouch/dash/slide (no art); blocking IS allowed (hold I).
	var simple := _is_simple()
	_down_held = Input.is_physical_key_pressed(KEY_S) and not simple
	if not _down_held:
		_slide_lockout = false
	_guard_held = Input.is_physical_key_pressed(GUARD_KEY)
	_jump_pressed = _consume_just_pressed(KEY_W)
	_attack_requests.clear()
	_special_requested = false

	var light_pressed := _consume_just_pressed(KEY_J)
	var medium_pressed := _consume_just_pressed(KEY_K)
	var l_pressed := _consume_just_pressed(KEY_L)
	var heavy_pressed := l_pressed
	if light_pressed:
		_record_combo_input("light")
	if medium_pressed:
		_record_combo_input("medium")
	if heavy_pressed:
		_record_combo_input("heavy")

	# Special move: a quick double-tap of the dedicated special key ("OO").
	var now := Time.get_ticks_msec() / 1000.0
	if _consume_just_pressed(SPECIAL_KEY):
		if _last_special_tap > 0.0 and (now - _last_special_tap) <= SPECIAL_TAP_INTERVAL:
			_special_tap_count += 1
		else:
			_special_tap_count = 1
		_last_special_tap = now
		if is_special_ready() and _special_tap_count >= SPECIAL_TAP_COUNT:
			_special_requested = true
			_special_tap_count = 0
			_last_special_tap = -10.0

	# Hand-drawn fighters use real chained animations (J->K->L) instead of the
	# placeholder full_combo, so skip the auto-combo for them.
	if not simple and ((light_pressed and medium_pressed and heavy_pressed) or _consume_full_combo_sequence()):
		_attack_requests.append("full_combo")
		_combo_input_buffer.clear()
		return

	if light_pressed:
		_attack_requests.append("light")
	if medium_pressed:
		_attack_requests.append("medium")
	if heavy_pressed:
		_attack_requests.append("heavy")

	# When the chord fires this frame, suppress the fresh normal attack so the
	# press converts cleanly into the special instead.
	if _special_requested:
		_attack_requests.clear()


func _record_combo_input(attack_name: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_combo_input_buffer.append({"attack": attack_name, "time": now})
	while _combo_input_buffer.size() > 0 and now - float(_combo_input_buffer[0]["time"]) > FULL_COMBO_INPUT_WINDOW:
		_combo_input_buffer.pop_front()
	while _combo_input_buffer.size() > 6:
		_combo_input_buffer.pop_front()


func _consume_full_combo_sequence() -> bool:
	var wanted := ["light", "medium", "heavy"]
	var wanted_index := wanted.size() - 1
	for i in range(_combo_input_buffer.size() - 1, -1, -1):
		if str(_combo_input_buffer[i]["attack"]) == wanted[wanted_index]:
			wanted_index -= 1
			if wanted_index < 0:
				return true
	return false


func _update_bot_ai(delta: float) -> void:
	_move_dir = 0
	_down_held = false
	_down_pressed = false
	_guard_held = false
	_jump_pressed = false
	_left_pressed = false
	_right_pressed = false
	_attack_requests.clear()
	_bot_attack_cooldown = maxf(_bot_attack_cooldown - delta, 0.0)
	_bot_mode_timer = maxf(_bot_mode_timer - delta, 0.0)

	if state == FighterState.DEAD or state == FighterState.HITSTUN or state == FighterState.BLOCKSTUN:
		return
	if opponent == null or not is_instance_valid(opponent):
		return

	var distance_x := opponent.global_position.x - global_position.x
	var abs_distance := absf(distance_x)
	var to_opponent := int(signf(distance_x))
	if to_opponent == 0:
		to_opponent = facing_dir

	if _bot_mode_timer <= 0.0:
		_choose_bot_mode(abs_distance)

	match _bot_mode:
		"approach":
			_move_dir = to_opponent
		"retreat":
			_move_dir = -to_opponent
		"guard":
			_guard_held = guard_meter >= GUARD_MIN_TO_BLOCK
		"jump":
			_jump_pressed = is_on_floor()
			_move_dir = to_opponent if _bot_rng.randf() < 0.45 else -to_opponent
		"poke":
			if abs_distance > bot_attack_range * 0.85:
				_move_dir = to_opponent
			elif _bot_attack_cooldown <= 0.0:
				_attack_requests.append("light" if _bot_rng.randf() < 0.62 else "medium")
				_bot_attack_cooldown = _bot_rng.randf_range(0.24, 0.48)
		"heavy":
			if abs_distance > bot_attack_range:
				_move_dir = to_opponent
			elif _bot_attack_cooldown <= 0.0:
				_attack_requests.append("heavy")
				_bot_attack_cooldown = _bot_rng.randf_range(0.50, 0.90)
		"combo":
			if abs_distance > bot_attack_range * 0.92:
				_move_dir = to_opponent
			elif _bot_attack_cooldown <= 0.0:
				_attack_requests.append("full_combo")
				_bot_attack_cooldown = _bot_rng.randf_range(0.90, 1.45)
		_:
			pass

	if not _is_simple() and int(opponent.get("state")) == FighterState.ATTACK and abs_distance <= bot_attack_range and guard_meter >= GUARD_MIN_TO_BLOCK and _bot_rng.randf() < 0.45:
		_attack_requests.clear()
		_guard_held = true
		_move_dir = 0


func _choose_bot_mode(abs_distance: float) -> void:
	# People only walk + kick: keep their bot to approach / retreat / poke.
	if _is_simple():
		var r := _bot_rng.randf()
		if abs_distance > bot_attack_range * 0.9:
			_bot_mode = "approach" if r < 0.82 else "retreat"
		else:
			_bot_mode = "poke" if r < 0.72 else "retreat"
		_bot_mode_timer = _bot_rng.randf_range(0.18, 0.62)
		return

	var roll := _bot_rng.randf()
	if abs_distance < bot_preferred_range:
		if roll < 0.24:
			_bot_mode = "retreat"
		elif roll < 0.42:
			_bot_mode = "guard"
		elif roll < 0.58:
			_bot_mode = "jump"
		elif roll < 0.86:
			_bot_mode = "poke"
		elif roll < 0.95:
			_bot_mode = "heavy"
		else:
			_bot_mode = "combo"
	elif abs_distance < bot_attack_range * 1.65:
		if roll < 0.20:
			_bot_mode = "retreat"
		elif roll < 0.34:
			_bot_mode = "guard"
		elif roll < 0.52:
			_bot_mode = "jump"
		elif roll < 0.78:
			_bot_mode = "approach"
		elif roll < 0.93:
			_bot_mode = "poke"
		else:
			_bot_mode = "combo"
	else:
		if roll < 0.18:
			_bot_mode = "wait"
		elif roll < 0.36:
			_bot_mode = "jump"
		elif roll < 0.48:
			_bot_mode = "guard"
		else:
			_bot_mode = "approach"
	_bot_mode_timer = _bot_rng.randf_range(0.18, 0.62)


func _poll_key_edges() -> void:
	_just_pressed.clear()
	if not _has_local_input():
		_key_down.clear()
		return
	for key_code in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_J, KEY_K, KEY_L, KEY_O, GUARD_KEY]:
		var pressed := Input.is_physical_key_pressed(key_code)
		var was_pressed := bool(_key_down.get(key_code, false))
		_just_pressed[key_code] = pressed and not was_pressed
		_key_down[key_code] = pressed


func _consume_just_pressed(key_code: Key) -> bool:
	var result := bool(_just_pressed.get(key_code, false))
	_just_pressed[key_code] = false
	return result


func _has_local_input() -> bool:
	if not accept_local_input:
		return false
	if multiplayer.has_multiplayer_peer():
		return is_multiplayer_authority()
	return true


func _is_remote_network_player() -> bool:
	return multiplayer.has_multiplayer_peer() and not is_multiplayer_authority()


func _can_guard() -> bool:
	return is_on_floor() and guard_meter >= GUARD_MIN_TO_BLOCK and state != FighterState.HITSTUN and state != FighterState.DEAD


func _should_block_attack(data: Dictionary) -> bool:
	if bool(data.get("unblockable", false)) or not is_on_floor():
		return false
	if guard_meter < GUARD_MIN_TO_BLOCK:
		return false
	if not (state == FighterState.IDLE or state == FighterState.WALK or state == FighterState.CROUCH or state == FighterState.BLOCK or state == FighterState.BLOCKSTUN):
		return false
	return _guard_held or state == FighterState.BLOCKSTUN


func _is_forward_input(input_dir: int) -> bool:
	return input_dir != 0 and sign(input_dir) == facing_dir


func _ground_speed_for_input(input_dir: int) -> float:
	if input_dir == 0:
		return 0.0
	return float(input_dir) * (WALK_SPEED if _is_forward_input(input_dir) else BACKWARD_SPEED)


func _update_facing() -> void:
	if state != FighterState.DASH and state != FighterState.SLIDE and state != FighterState.ATTACK and state != FighterState.SPECIAL and state != FighterState.HITSTUN and state != FighterState.BLOCKSTUN and state != FighterState.DEAD:
		if opponent != null and is_instance_valid(opponent):
			var distance := opponent.global_position.x - global_position.x
			if absf(distance) > 2.0:
				facing_dir = 1 if distance > 0.0 else -1
	sprite.flip_h = facing_dir < 0
	_update_attack_hitbox_shape()


func _enter_state(new_state: FighterState, timer_frames := 0) -> void:
	if state == new_state and timer_frames == 0:
		return
	state = new_state
	_state_frame = 0
	_frame_accum = 0.0
	_state_timer = float(timer_frames)
	if new_state != FighterState.ATTACK:
		_set_attack_hitbox_active(false)


func _attack_data() -> Dictionary:
	if _active_attack == "" or not _attack_defs.has(_active_attack):
		return {}
	return _attack_defs[_active_attack]


func _current_attack_segment(data := {}) -> Dictionary:
	if data.is_empty():
		data = _attack_data()
	if data.is_empty() or not data.has("hit_segments"):
		return {}
	var segments: Array = data["hit_segments"]
	for segment in segments:
		if _state_frame >= int(segment["start"]) and _state_frame < int(segment["end"]):
			return segment
	return {}


func _current_attack_hit_data() -> Dictionary:
	var data := _attack_data().duplicate(true)
	if data.is_empty():
		return {}
	var segment := _current_attack_segment(data)
	if segment.is_empty():
		return data
	for key in segment.keys():
		if key != "start" and key != "end" and key != "hit_id":
			data[key] = segment[key]
	return data


func _current_attack_hit_id() -> String:
	var data := _attack_data()
	var segment := _current_attack_segment(data)
	if segment.is_empty():
		return _active_attack
	return "%s:%s" % [_active_attack, str(segment.get("hit_id", "hit"))]


func _is_attack_hitbox_active_frame() -> bool:
	var data := _attack_data()
	if data.is_empty():
		return false
	if data.has("hit_segments"):
		return not _current_attack_segment(data).is_empty()
	return _attack_phase() == "active"


func _attack_total_frames(data: Dictionary) -> int:
	return int(data["startup"]) + int(data["active"]) + int(data["recovery"])


func _attack_phase() -> String:
	if state != FighterState.ATTACK or _active_attack == "":
		return "none"
	var data := _attack_data()
	if _state_frame < int(data["startup"]):
		return "startup"
	if _state_frame < int(data["startup"]) + int(data["active"]):
		return "active"
	if _state_frame < _attack_total_frames(data):
		return "recovery"
	return "done"


func _attack_movement_scale(data: Dictionary) -> float:
	match _attack_phase():
		"startup":
			return float(data["move_startup"])
		"active":
			return float(data["move_active"])
		"recovery":
			return float(data["move_recovery"])
		_:
			return 1.0


func _start_hitstop(frames: int) -> void:
	if frames <= 0:
		return
	_hitstop_timer = maxf(_hitstop_timer, float(frames) * FRAME_TIME)
	sprite.speed_scale = 0.0


func _set_guard_visual() -> void:
	sprite.modulate = Color(0.38, 0.62, 1.0, 1.0)


func _reset_visual_tint() -> void:
	sprite.modulate = Color.WHITE


# Show the block pose while guarding. Fighters with a drawn block sprite hold it
# (no tint); the placeholder (no block art) falls back to the old blue idle.
func _apply_block_visual(force := false) -> void:
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("block"):
		_reset_visual_tint()
		_play_anim("block", force)
	else:
		_set_guard_visual()
		_play_anim("idle", force)


func _play_anim(animation_name: String, force := false) -> void:
	if sprite.animation == animation_name and sprite.is_playing() and not force:
		return
	sprite.speed_scale = 1.0
	sprite.play(animation_name)


func _hit_direction_from(attacker: Node2D) -> int:
	if attacker == null:
		return -facing_dir
	var direction := int(signf(global_position.x - attacker.global_position.x))
	return direction if direction != 0 else -facing_dir


func _state_name() -> String:
	match state:
		FighterState.IDLE:
			return "idle"
		FighterState.WALK:
			return "walk"
		FighterState.CROUCH:
			return "crouch"
		FighterState.JUMP:
			return "jump"
		FighterState.DASH:
			return "dash"
		FighterState.SLIDE:
			return "slide"
		FighterState.ATTACK:
			return "attack"
		FighterState.SPECIAL:
			return "special"
		FighterState.BLOCK:
			return "block"
		FighterState.BLOCKSTUN:
			return "blockstun"
		FighterState.HITSTUN:
			return "hitstun"
		FighterState.DEAD:
			return "dead"
		_:
			return "unknown"
