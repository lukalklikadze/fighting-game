# Characters — Movement & Attacks

This folder owns everything related to playable fighters: movement, animations, attacks, hitboxes, hurtboxes, and health.

## Your Scope

- Player movement: walk, run, jump, double-jump, dash, crouch
- Attack system: light/medium/heavy attacks, specials, combos
- Hitbox / hurtbox system (use `Area2D` nodes)
- Health and stun/knockback state machine
- Input handling (support both local and remote player inputs)

## Folder Layout (create as needed)

```
characters/
├── scripts/
│   ├── player.gd           ← Main player controller
│   ├── attack_handler.gd   ← Attack logic, combos
│   ├── hitbox.gd           ← Hitbox Area2D logic
│   └── hurtbox.gd          ← Hurtbox Area2D logic
└── scenes/
    ├── Player.tscn          ← Base player scene
    ├── Hitbox.tscn          ← Reusable hitbox scene
    └── Hurtbox.tscn         ← Reusable hurtbox scene
```

## Multiplayer Notes

- Player 1 is the host (multiplayer authority = 1)
- Player 2 is the client (multiplayer authority = 2)
- Use `set_multiplayer_authority(peer_id)` on each player node
- Movement input should only run on the authoritative peer, then sync position via `MultiplayerSynchronizer` or `@rpc`
- Attacks must be validated server-side (host) to prevent cheating

## Key Godot APIs

- `CharacterBody2D` for the player body
- `Area2D` for hitboxes/hurtboxes
- `AnimationPlayer` for attack animations
- `@rpc("any_peer")` to send attack events to the host
- `@rpc("authority")` to broadcast confirmed hits to all clients

## State Machine

Recommended player states:
`IDLE` → `WALK` → `JUMP` → `ATTACK` → `BLOCK` → `HIT` → `DEAD`

Use an enum and `match` statement in `_physics_process`.

## Arcade Combat Notes

- Attacks should be driven by frame data first: startup frames, active frames, recovery frames, hitstun, blockstun, hitstop, and cancel windows.
- Fast attacks should recover quickly and chain more easily.
- Slow/heavy attacks should deal more damage but be punishable during startup and recovery.
- Keep block behavior separate from block animation so the real block sprite can be added later without rewriting combat logic.
