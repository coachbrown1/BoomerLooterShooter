# Dungeon Generation And World

## Purpose

Explain how the dungeon scene is built after the single-default-dungeon cutover, which systems own layout fitting, scene stitching, exits, enemy spawning, and multiplayer sync.

## Key Files

- `boomer-shooter/Scripts/Dungeon/dungeon_manager.gd`
- `boomer-shooter/Scripts/Dungeon/dungeon_generator.gd`
- `boomer-shooter/Scripts/Dungeon/dungeon_stitcher.gd`
- `boomer-shooter/Scripts/Dungeon/room_data.gd`
- `boomer-shooter/Scripts/Dungeon/standard_dungeon_room.gd`
- `boomer-shooter/Scripts/Dungeon/handcrafted_room_layout.gd`
- `boomer-shooter/Scripts/Systems/encounter_system.gd`
- `boomer-shooter/Scripts/Data/default_dungeon_content.gd`
- `boomer-shooter/Data/dungeons/default_dungeon_content.tres`

## Architecture

1. `DungeonGenerator` produces the lattice graph: room cells, corridor links, start/exit assignment, and the raw doorway candidates for each room.
2. `DungeonManager` assigns authored scenes from `DefaultDungeonContent` before stitching:
   - one authored start room
   - one default room scene for most normal rooms
   - a seeded subset of special room scenes
3. `DungeonManager` fits those scenes to the topology by:
   - checking each room scene's exported doorway profiles
   - rotating the scene to a valid orientation
   - pruning only non-critical side branches when a special room intentionally supports fewer openings
   - falling back to another scene or the default room if no valid fit exists
4. `DungeonStitcher` instantiates only authored room scenes and authored corridor scenes. Runtime structural work is limited to scene rotation and doorway filler enable/disable.
5. `EncounterSystem` consumes the active dungeon content resource for enemy scene selection.

## Room And Corridor Contract

### Standard rooms

- `StandardDungeonRoom` is the minimal stitched-room contract for default authored rooms.
- Scenes expose:
  - `room_role_tags`
  - `supported_doorway_profiles`
  - `allowed_rotation_degrees`
- Runtime only toggles `Walls/Wall{Dir}/Wall{Dir}_Fill` collision/visibility to match finalized open walls.

### Handcrafted rooms

- `HandcraftedRoomLayout` now behaves as a metadata + doorway-toggle base only.
- It no longer generates shell meshes, floors, ceilings, or walls at runtime.
- Designers must author final geometry, collision, props, and lights directly in the scene.
- Scenes can intentionally support reduced doorway sets such as a single-door start room or special room.

### Corridors

- Corridors are fully authored scenes referenced by `DefaultDungeonContent.corridor_scene`.
- Runtime instantiates and rotates them for east-west versus north-south placement only.

## Main Data Flow

- The hub portal writes grid min, grid max, and seed into `GameState`.
- `DungeonManager.generate_floor()`:
  - clears old world children
  - runs `DungeonGenerator`
  - loads the single `dungeon_content` resource
  - assigns room scenes and fits topology
  - stitches authored rooms and corridors
  - bakes navigation from static colliders
  - places players and the exit
  - initializes host-authoritative enemy spawning
- `DungeonManager._process()` advances progressive room spawning based on the authoritative player's current room.

## Important State And Resources

- `DungeonManager` stores:
  - `_rooms`
  - `_room_lookup`
  - `_active_dungeon_content`
  - `_room_instances_by_id`
  - `_room_scene_contract_cache`
- `RoomData` active placement fields are:
  - `assigned_scene`
  - `assigned_scene_path`
  - `assigned_scene_role`
  - `chosen_rotation_degrees`
  - `doorway_walls`
- `default_dungeon_content.tres` is the active content contract for stitched dungeon presentation.

## Multiplayer/Authority Notes

- The host remains authoritative for gameplay-critical floor state, enemy spawning, loot, exits, and other shared world objects.
- Clients still rely on deterministic layout generation plus replicated world state from the host.
- Geometry is now simpler to reason about because the runtime no longer generates structural meshes, material overrides, props, or doorway assemblies after the fact.

## Safe Edit Guidance

- Layout-graph rules belong in `dungeon_generator.gd`.
- Scene assignment, rotation fitting, and branch pruning belong in `dungeon_manager.gd`.
- Room and corridor presentation changes belong in the authored `.tscn` files.
- If a room scene changes its doorway profile support, update the exported metadata in the scene root to match the authored walls.
- If you expand the default content contract, update this doc and `editor-tooling.md` together.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [data-resources-and-content.md](data-resources-and-content.md)
- [editor-tooling.md](editor-tooling.md)
- [networking-and-replication.md](networking-and-replication.md)
