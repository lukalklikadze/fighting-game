# Minigame 1 — Typeracer

A typing minigame where both players race to type a word or phrase. The faster/more accurate player wins the round and gains an in-game advantage (e.g., a buff, extra health, or a special move charge).

## Your Scope

- Display a random word/phrase to both players simultaneously
- Capture keyboard input and compare against the target text in real time
- Sync both players' progress over the network
- Declare a winner and emit a signal the main game can react to
- (Optional) Show a progress bar or character highlighting for typed letters

## Folder Layout (create as needed)

```
minigames/typeracer/
├── scripts/
│   ├── typeracer_manager.gd   ← Game logic: word pick, timer, scoring
│   ├── typeracer_input.gd     ← Per-player input capture and validation
│   └── word_list.gd           ← Word/phrase bank (or load from .txt)
└── scenes/
    ├── TyperacerMinigame.tscn  ← Root scene for the minigame
    └── TyperacerUI.tscn        ← HUD: word display, progress, timer
```

## Multiplayer Notes

- The host picks the word and sends it to the client via RPC before the round starts
- Each player's typed progress is sent to the host via `@rpc("any_peer")`
- Host validates and rebroadcasts confirmed progress to all peers
- Emit a signal `minigame_won(winner_peer_id)` when finished — main game listens for this

## Key Godot APIs

- `LineEdit` or `TextEdit` for input capture
- `@rpc("any_peer", "call_local")` for syncing typed characters
- `Timer` for countdown/time limit
- `RichTextLabel` with BBCode for highlighting correctly-typed letters

## Suggested Signal Interface

```gdscript
signal minigame_won(winner_peer_id: int)
signal minigame_draw()
```

The main game scene connects to these signals and applies the reward/penalty.
