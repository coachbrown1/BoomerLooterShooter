# Runtime Overview

## Purpose

Describe the high-level runtime path from startup through hub and dungeon play after the dungeon cutover to a single default content set.

## Key Files

- `boomer-shooter/project.godot`
- `boomer-shooter/Scenes/System/bootstrap.tscn`
- `boomer-shooter/Scripts/Networking/network_bootstrap.gd`
- `boomer-shooter/Scenes/World/hub.tscn`
- `boomer-shooter/Scripts/World/hub_manager.gd`
- `boomer-shooter/Scenes/World/dungeon.tscn`
- `boomer-shooter/Scripts/Dungeon/dungeon_manager.gd`
- `boomer-shooter/Scripts/System/game_state.gd`
- `boomer-shooter/Scripts/System/meta_progression.gd`

## Main Data Flow

- Godot launches `bootstrap.tscn`.
- `MetaProgression` loads permanent progression data before the bootstrap scene hands off into hub or dungeon flow.
- `network_bootstrap.gd` handles title/menu flow, multiplayer startup, and verifier automation.
- Normal play starts in the hub scene.
- `HubManager` owns hub chests, the portal menu, the War Table menu, navigation bake, and player spawning.
- Entering the portal writes only grid and seed settings into `GameState`, snapshots inventory, saves hub chest contents, and changes to the dungeon scene.
- `DungeonManager` reads that config, generates the lattice floor, assigns room scenes from the default dungeon content resource, stitches authored rooms/corridors, and owns host-authoritative dungeon gameplay.

## Important State And Resources

- `GameState.player_inventory_snapshot`
- `GameState.hub_chest_snapshots`
- `GameState.initialized`
- `GameState.dungeon_grid_min`
- `GameState.dungeon_grid_max`
- `GameState.dungeon_seed`
- `MetaProgression` long-term state for the War Table, castle XP, and hub station unlocks

## Multiplayer/Authority Notes

- `HubManager` owns hub-side replicated interactions.
- `DungeonManager` is the authoritative world manager once the dungeon scene loads.
- `MetaProgression` owns persistent progression state that should survive restart.
- Clients still wait for host-owned gameplay state even though the stitched geometry is deterministic.

## Safe Edit Guidance

- For scene-flow changes, inspect `network_bootstrap.gd`, `hub_manager.gd`, and `dungeon_manager.gd` together.
- Preserve `GameState` handoff fields when modifying hub-to-dungeon transitions.
- If you add a new cross-scene dungeon option, update both this doc and `system-singletons-and-state.md`.

## Related Docs

- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [hub-workflow-and-persistence.md](hub-workflow-and-persistence.md)
- [networking-and-replication.md](networking-and-replication.md)
