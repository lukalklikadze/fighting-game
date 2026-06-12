# Minigame 2 — Object Throw

A physics-based minigame where both players pick up and throw objects at each other (or at targets). The player who lands more hits or deals more damage within the time limit wins.

## Your Scope

- Spawn throwable physics objects in the arena
- Allow players to pick up, aim, and throw objects
- Detect hits and track score per player
- Sync object positions and throw events over the network
- Declare a winner and emit a signal the main game can react to

## Folder Layout (create as needed)

```
minigames/object_throw/
├── scripts/
│   ├── throw_manager.gd       ← Round logic: spawn objects, timer, scoring
│   ├── throwable_object.gd    ← RigidBody2D object: pickup, throw, hit detection
│   └── throw_player.gd        ← Player controller adapted for this minigame
└── scenes/
    ├── ObjectThrowMinigame.tscn  ← Root scene
    ├── ThrowableObject.tscn      ← Individual throwable item (rock, crate, etc.)
    └── ObjectThrowUI.tscn        ← Score, timer HUD
```

## Multiplayer Notes

- Use `MultiplayerSpawner` to sync object spawning across peers
- Object physics run on the host; clients receive position updates via `MultiplayerSynchronizer`
- Throw events are sent from the throwing player to the host via `@rpc("any_peer")`
- Host applies the impulse, simulates physics, and syncs back
- Emit `minigame_won(winner_peer_id)` when the round ends

## Key Godot APIs

- `RigidBody2D` for physics objects
- `MultiplayerSpawner` — attach to the minigame root to auto-sync spawned objects
- `MultiplayerSynchronizer` — sync `position`, `linear_velocity` of each object
- `@rpc("any_peer")` for throw events
- `Area2D` for pickup radius detection

## Suggested Signal Interface

```gdscript
signal minigame_won(winner_peer_id: int)
signal minigame_draw()
```

The main game scene connects to these signals and applies the reward/penalty.
