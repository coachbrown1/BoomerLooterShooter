# Hub Workflow And Persistence

## Purpose

Document the hub as a gameplay loop of its own, including player spawn, storage chests, portal flow, item drops, and the state that survives the transition into the dungeon.

## Key Files

- `boomer-shooter/Scripts/World/hub_manager.gd`
- `boomer-shooter/Scenes/World/hub.tscn`
- `boomer-shooter/Scripts/Environment/interactable_chest.gd`
- `boomer-shooter/Scripts/Props/portal.gd`
- `boomer-shooter/Scripts/UI/dungeon_config_menu.gd`
- `boomer-shooter/Scripts/System/game_state.gd`
- `boomer-shooter/Scripts/Networking/network_player_manager.gd`

## Main Data Flow

- `HubManager` is the active scene owner for hub gameplay.
- On `_ready()`, it:
  - captures mouse mode
  - configures the three storage chests
  - connects the portal interaction
  - bakes navigation
  - delegates player spawning to `NetworkPlayerManager`
- When players are ready, the local player’s inventory snapshot is restored from `GameState` if the run has already been initialized.
- Storage chests in the hub are special-purpose persistence containers rather than randomized loot chests.
- Interacting with the portal opens `DungeonConfigMenu`, which writes biome, grid, and seed values into `GameState`.
- Entering the dungeon snapshots the current player inventory, saves hub chest payloads, marks the run initialized, and changes scene to the dungeon.

## Important State And Resources

- `GameState.player_inventory_snapshot` preserves the player’s carried state between hub and dungeon.
- `GameState.hub_chest_snapshots` preserves all three storage chest contents.
- The three hub chests are renamed and forced to zero random loot generation during `_configure_chests()`.
- `HubManager` also owns hub-side network loot pickup spawning and interaction handling through the `world_item_drop_manager` role.

## Multiplayer/Authority Notes

- Only the local player should see and operate the dungeon-config menu.
- In multiplayer, non-host clients request dungeon entry from the host rather than changing scenes directly.
- Shared hub pickups and storage behavior still need authoritative handling even though the hub is a calmer space than the dungeon.
- If hub behavior changes, verify whether the change affects both single-player and hosted-client flow.

## Safe Edit Guidance

- Keep portal UI flow, persistence writes, and scene transition logic in `HubManager` unless there is a strong reason to split them.
- Do not treat hub chests like ordinary procedural chests; their persistence rules are different.
- If you add new hub-persistent state, update `GameState` and this doc together.
- For hub interaction changes, trace both inventory persistence and network item-drop handling before editing.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
- [system-singletons-and-state.md](system-singletons-and-state.md)
- [world-interactions-and-props.md](world-interactions-and-props.md)
