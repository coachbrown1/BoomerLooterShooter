# Hub Workflow And Persistence

## Purpose

Document the hub gameplay loop, including storage chests, portal flow, and the state that survives the transition into the dungeon.

## Key Files

- `boomer-shooter/Scripts/World/hub_manager.gd`
- `boomer-shooter/Scenes/World/hub.tscn`
- `boomer-shooter/Scripts/Environment/interactable_chest.gd`
- `boomer-shooter/Scripts/Props/portal.gd`
- `boomer-shooter/Scripts/Props/war_table_station.gd`
- `boomer-shooter/Scripts/UI/dungeon_config_menu.gd`
- `boomer-shooter/Scripts/UI/war_table_menu.gd`
- `boomer-shooter/Scripts/System/game_state.gd`

## Main Data Flow

- `HubManager` owns hub gameplay and connects the portal interaction.
- `HubManager` also connects the War Table station interaction and opens `WarTableMenu` from the hub.
- Interacting with the portal opens `DungeonConfigMenu`, which writes grid min, grid max, and seed into `GameState`.
- Interacting with the War Table opens a dedicated progression menu that reads and writes `MetaProgression`.
- Entering the dungeon snapshots the current inventory, saves the hub chest payloads, marks the run initialized, and changes to the dungeon scene.
- In multiplayer, clients request entry from the host and the host broadcasts the scene transition.

## Important State And Resources

- `GameState.player_inventory_snapshot`
- `GameState.hub_chest_snapshots`
- `GameState.initialized`
- `GameState.dungeon_grid_min`
- `GameState.dungeon_grid_max`
- `GameState.dungeon_seed`

## Multiplayer/Authority Notes

- Only the local player should see and operate the portal config menu.
- Only the local player should see and operate the War Table menu.
- Hub pickups and storage still need authoritative handling even though the hub is non-procedural.

## Safe Edit Guidance

- Keep portal UI flow, persistence writes, and scene transition logic in `HubManager` unless there is a strong reason to split them.
- Keep War Table interaction flow in `HubManager` unless the hub gets a more general station dispatcher.
- If you add another portal-configured dungeon option, update `GameState`, `dungeon_config_menu.gd`, and this doc together.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [system-singletons-and-state.md](system-singletons-and-state.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
