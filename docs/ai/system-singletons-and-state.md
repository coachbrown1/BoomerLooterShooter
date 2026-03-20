# System Singletons And State

## Purpose

Capture the small but important global state and singleton-style scripts that are easy to miss because they are light on code but central to scene-to-scene behavior.

## Key Files

- `boomer-shooter/project.godot`
- `boomer-shooter/Scripts/System/game_state.gd`
- `boomer-shooter/Scripts/Systems/event_bus.gd`
- `boomer-shooter/Scripts/Networking/network_session.gd`
- `boomer-shooter/Scripts/Networking/network_player_manager.gd`

## Main Data Flow

- `project.godot` registers the autoload layer used across scenes:
  - `NetworkSession`
  - `NetSession`
  - `NetworkPlayerManager`
  - `GlobalEventBus`
- `GameState` is not configured as an autoload entry, but is used like a static singleton through `class_name` and static vars.
- `GameState` currently persists:
  - player inventory snapshot
  - three hub chest snapshots
  - whether the run has already been initialized
  - dungeon biome/grid/seed configuration
- `EventBus` exists as an autoloaded global surface but is currently minimal, so it is more of a reserved integration point than a heavily used event hub.

## Important State And Resources

- `GameState` is the bridge between the hub and dungeon scene transitions.
- `NetworkSession` and `NetworkPlayerManager` are the real always-on runtime globals that own session lifecycle and player roster state.
- Because these scripts live outside any single scene, bugs here often affect every gameplay scene.

## Multiplayer/Authority Notes

- Global state should stay narrow and explicit. Avoid turning singletons into catch-all storage for scene-local behavior.
- Any new cross-scene multiplayer state should be reviewed carefully for ownership and reset behavior.
- If `EventBus` starts carrying real gameplay traffic later, it should be documented and kept separate from authoritative networking responsibilities.

## Safe Edit Guidance

- Prefer scene-local managers for scene-local behavior and use globals only when the data or behavior truly spans scenes.
- Keep `GameState` payloads serializable and stable because multiple systems assume these fields survive scene changes.
- If you add a new autoload or expand `EventBus`, update this doc and the repo map immediately.

## Related Docs

- [repo-map.md](repo-map.md)
- [runtime-overview.md](runtime-overview.md)
- [networking-and-replication.md](networking-and-replication.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
