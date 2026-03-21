# System Singletons And State

## Purpose

Capture the small but important global state and singleton-style scripts that are central to scene-to-scene behavior.

## Key Files

- `boomer-shooter/project.godot`
- `boomer-shooter/Scripts/System/game_state.gd`
- `boomer-shooter/Scripts/Systems/event_bus.gd`
- `boomer-shooter/Scripts/Networking/network_session.gd`
- `boomer-shooter/Scripts/Networking/network_player_manager.gd`

## Main Data Flow

- `project.godot` registers the autoload layer used across scenes.
- `GameState` is a static singleton-style script used to persist cross-scene data.
- `GameState` currently persists:
  - player inventory snapshot
  - three hub chest snapshots
  - whether the run has already been initialized
  - dungeon grid min/max and seed configuration

## Important State And Resources

- `GameState` is the bridge between hub and dungeon transitions.
- `NetworkSession` and `NetworkPlayerManager` remain the main always-on multiplayer globals.

## Multiplayer/Authority Notes

- Keep global state narrow and explicit.
- New cross-scene multiplayer state should be reviewed carefully for reset behavior and ownership.

## Safe Edit Guidance

- Prefer scene-local managers for scene-local behavior.
- Keep `GameState` payloads serializable and stable because multiple systems assume these fields survive scene changes.
- Update this doc whenever `GameState` gains or loses a field.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [hub-workflow-and-persistence.md](hub-workflow-and-persistence.md)
- [networking-and-replication.md](networking-and-replication.md)
