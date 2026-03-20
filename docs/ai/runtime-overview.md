# Runtime Overview

## Purpose

Describe the high-level runtime path from project startup through hub and dungeon play so agents can quickly identify which scene and manager own a behavior.

## Key Files

- `boomer-shooter/project.godot`
- `boomer-shooter/Scenes/System/bootstrap.tscn`
- `boomer-shooter/Scripts/Networking/network_bootstrap.gd`
- `boomer-shooter/Scenes/World/hub.tscn`
- `boomer-shooter/Scripts/World/hub_manager.gd`
- `boomer-shooter/Scenes/World/dungeon.tscn`
- `boomer-shooter/Scripts/Dungeon/dungeon_manager.gd`
- `boomer-shooter/Scripts/System/game_state.gd`

## Main Data Flow

- Godot launches `bootstrap.tscn` as the main scene.
- `network_bootstrap.gd` handles the title/menu flow for:
  - single-player
  - hosting
  - joining
  - verifier automation runs from command-line args
- Normal play starts in the hub scene after match start.
- `HubManager` configures storage chests, connects the portal menu, bakes navigation, and delegates player spawning to `NetworkPlayerManager`.
- Entering the portal writes biome/grid/seed settings into `GameState`, snapshots the local inventory, saves hub chest payloads, then changes scene to the dungeon.
- `DungeonManager` reads `GameState`, generates or receives the floor, places players, owns world-spawned enemies and loot, and coordinates host-authoritative dungeon replication.

## Important State And Resources

- `GameState.player_inventory_snapshot`: inventory/equipment/weapons carried between hub and dungeon.
- `GameState.hub_chest_snapshots`: three hub storage chest payloads persisted across scene changes.
- `GameState.dungeon_biome_override`, `dungeon_grid_min`, `dungeon_grid_max`, `dungeon_seed`: portal-selected dungeon configuration.
- Bootstrap command-line automation args support local verification flows and auto-start behavior.

## Multiplayer/Authority Notes

- Match setup starts in bootstrap, but gameplay authority shifts to the active world manager.
- `HubManager` handles replicated hub interactions such as entering the dungeon and syncing world loot drops.
- `DungeonManager` is the main authoritative runtime owner once the dungeon scene is active.
- Clients in multiplayer generally wait for host-owned world state rather than generating gameplay-critical state locally.

## Safe Edit Guidance

- For startup or session-flow changes, inspect `network_bootstrap.gd` first.
- For hub-only behaviors, prefer `HubManager` and hub scene nodes instead of patching dungeon logic.
- For dungeon behavior, check whether the change belongs in generation, encounter spawning, player management, or combat before editing.
- Preserve `GameState` handoff fields when modifying scene transitions.

## Related Docs

- [repo-map.md](repo-map.md)
- [networking-and-replication.md](networking-and-replication.md)
- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
