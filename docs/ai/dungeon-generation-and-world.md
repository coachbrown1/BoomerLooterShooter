# Dungeon Generation And World

## Purpose

Explain how the dungeon scene is built, how biome and run settings flow in, and which systems own world-spawned enemies, props, exits, loot, and room progression.

## Key Files

- `boomer-shooter/Scripts/Dungeon/dungeon_manager.gd`
- `boomer-shooter/Scripts/Dungeon/dungeon_generator.gd`
- `boomer-shooter/Scripts/Dungeon/dungeon_builder.gd`
- `boomer-shooter/Scripts/Dungeon/prop_placer.gd`
- `boomer-shooter/Scripts/Dungeon/room_data.gd`
- `boomer-shooter/Scripts/Systems/encounter_system.gd`
- `boomer-shooter/Scripts/World/hub_manager.gd`
- `boomer-shooter/Scripts/System/game_state.gd`
- `boomer-shooter/Scripts/Data/biome_dungeon_database.gd`
- `boomer-shooter/Data/biomes/biome_dungeon_database.tres`

## Main Data Flow

- The hub portal writes dungeon configuration into `GameState`.
- `DungeonManager._ready()` decides whether the local scene is:
  - single-player
  - multiplayer host
  - multiplayer client waiting for host sync
- On the host or in single-player, `generate_floor()` performs the generation pipeline:
  - clear previous world children under `NavigationRegion3D`
  - configure `DungeonGenerator` from `GameState`
  - generate the tile grid, rooms, corridors, doorways, and seed
  - resolve biome data from the biome database
  - assign handcrafted room layouts and overlays
  - build geometry through `DungeonBuilder`
  - place props through `PropPlacer`
  - bake navigation
  - place players
  - place the exit
  - initialize progressive enemy spawning
- `EncounterSystem` turns room metadata plus biome roster data into enemy scene instances using a threat-budget model.
- During runtime, `DungeonManager._process()` watches the authoritative player room and spawns room-local enemies as progression advances.

## Important State And Resources

- `DungeonManager` stores:
  - `_rooms`
  - `_room_lookup`
  - `_room_tile_owner`
  - `_spawned_enemy_rooms`
  - `_active_biome_data`
  - network maps for enemies and loot pickups
- Biome resources live under `boomer-shooter/Data/biomes/`.
- Enemy roster data can come from biome data or fall back to `Data/enemies/fallback_enemy_roster.tres`.
- Handcrafted room scenes live under `boomer-shooter/Scenes/Dungeon/Handcrafted/`.
- The verifier path can force a deterministic dungeon seed when needed.

## Hub To Dungeon Handoff

- `HubManager` opens the dungeon config menu from the portal.
- Confirming the menu updates `GameState.dungeon_biome_override`, grid size bounds, and seed.
- `HubManager` snapshots the local inventory and hub chest payloads before scene change.
- In multiplayer, clients request dungeon entry from the host and the host broadcasts the scene transition RPC.

## Multiplayer/Authority Notes

- In multiplayer, only the host should generate the gameplay-critical floor and own authoritative enemy or shared world state.
- Clients can enter the dungeon scene before all replicated floor state is ready, so avoid assuming local world generation ran on clients.
- Enemy snapshots, chest sync, loot pickup replication, weapon-state replication, and floor sync all route through `DungeonManager`.
- Keep deterministic seed handling stable for verifier scenarios and debugging.

## Safe Edit Guidance

- Generation-shape changes usually belong in `dungeon_generator.gd` or `dungeon_builder.gd`, not in combat or networking code.
- Room-progression enemy spawn changes usually belong in `DungeonManager` plus `EncounterSystem`.
- If a new world object needs replication, decide whether `DungeonManager` should own its network identity and sync lifecycle.
- Preserve hub-to-dungeon `GameState` fields when adjusting portal or generation settings.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [networking-and-replication.md](networking-and-replication.md)
- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
