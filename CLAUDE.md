# 2D Online Fighting Game

**This game MUST be multiplayer — exactly 2 players, connected to each other over the internet.** The game cannot be played solo or locally; both players join the same session remotely.

A 2-player online fighting game built in Godot 4. Players connect over the internet and fight each other, with minigames embedded into the experience.

## Project Structure

```
fighting-game/
├── characters/          ← Character movement, attacks, hitboxes (work here for fighters)
├── minigames/
│   ├── typeracer/       ← Typeracer minigame (work here for typeracer)
│   └── object_throw/    ← Object throw minigame (work here for object throw)
├── networking/          ← Multiplayer sync, lobby, connection logic
├── scenes/              ← Root/main scenes that tie everything together
└── assets/              ← Shared sprites, sounds, fonts
```

## Tech Stack

- **Engine**: Godot 4.x
- **Multiplayer**: Godot's built-in `MultiplayerAPI` with ENet (UDP) for peer-to-peer or dedicated server
- **Language**: GDScript

## Multiplayer Architecture

Use Godot's high-level multiplayer API:
- `ENetMultiplayerPeer` for peer-to-peer connections over the internet
- One player acts as host, the other joins via IP or relay
- RPCs (`@rpc`) for syncing player state, attacks, and minigame events
- Consider `MultiplayerSynchronizer` for position sync

## Sections & Who Works Where

| Folder | Responsibility |
|--------|---------------|
| `characters/` | Fighter logic: movement, jump, dash, attacks, hitboxes, health |
| `minigames/typeracer/` | Typeracer minigame: word generation, input sync, scoring |
| `minigames/object_throw/` | Object throw minigame: physics objects, throwing, collision, scoring |
| `networking/` | Connection setup, lobby, RPC wrappers, latency handling |
| `scenes/` | Main scene, game manager, HUD, scene transitions |

## Conventions

- Scene files: `PascalCase.tscn`
- Script files: `snake_case.gd`
- Node names: `PascalCase`
- Signals: `snake_case`
- Each major feature gets its own scene + script pair

## Getting Started

1. Open `project.godot` in Godot 4
2. Navigate to the folder matching your assigned section (see table above)
3. Read the `CLAUDE.md` inside that folder for section-specific context
