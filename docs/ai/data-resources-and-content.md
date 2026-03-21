# Data Resources And Content

## Purpose

Explain where authored gameplay content lives and how scripts consume resource-based data for gear, dungeon content, enemy pools, and room scenes.

## Key Files

- `boomer-shooter/Scripts/Data/gear_catalog_data.gd`
- `boomer-shooter/Scripts/Data/gear_line_data.gd`
- `boomer-shooter/Data/gear/gear_catalog.tres`
- `boomer-shooter/Scripts/Data/default_dungeon_content.gd`
- `boomer-shooter/Data/dungeons/default_dungeon_content.tres`
- `boomer-shooter/Scripts/Data/enemy_roster_data.gd`
- `boomer-shooter/Data/enemies/fallback_enemy_roster.tres`
- `boomer-shooter/Scenes/Dungeon/Rooms/`
- `boomer-shooter/Scenes/Dungeon/Handcrafted/`
- `boomer-shooter/Scenes/Dungeon/Corridors/`

## Main Data Flow

- The project relies heavily on Godot resources for authored content instead of hardcoding most content choices in runtime scripts.
- Gear content still comes from gear resources and generated affix/stat systems.
- Dungeon content now comes from a single `DefaultDungeonContent` resource that defines:
  - start room scene
  - default room scene
  - special room scene pool and chance
  - corridor scene
  - fog color
  - enemy scene pool
- `DungeonManager` reads `default_dungeon_content.tres` and passes that resource into room assignment, scene stitching, environment updates, and encounter selection.
- `EncounterSystem` prefers enemy scenes from the active dungeon content resource and falls back only when needed.

## Important State And Resources

- `Data/dungeons/` now contains the active stitched dungeon content resource.
- `Scenes/Dungeon/Rooms/` contains stitched default room scenes.
- `Scenes/Dungeon/Handcrafted/` contains authored start and special room scenes plus any other reusable authored rooms.
- `Scenes/Dungeon/Corridors/` contains authored corridor scenes used by the stitcher.

## Multiplayer/Authority Notes

- Resource-driven content is not a replacement for replication logic.
- Deterministic resource selection still matters because both peers need the same authored geometry layout before replicated world objects appear.

## Safe Edit Guidance

- Extend `DefaultDungeonContent` when the single stitched dungeon contract needs new authored references.
- Avoid reviving biome-specific runtime branches unless the whole content model is intentionally changing again.
- When adding new resource fields, trace every consumer before relying on the new property.

## Related Docs

- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [editor-tooling.md](editor-tooling.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
