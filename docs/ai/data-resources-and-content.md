# Data Resources And Content

## Purpose

Explain where authored gameplay content lives and how scripts consume resource-based data for gear, biomes, enemy rosters, and handcrafted room content.

## Key Files

- `boomer-shooter/Scripts/Data/gear_catalog_data.gd`
- `boomer-shooter/Scripts/Data/gear_line_data.gd`
- `boomer-shooter/Data/gear/gear_catalog.tres`
- `boomer-shooter/Scripts/Data/biome_dungeon_data.gd`
- `boomer-shooter/Scripts/Data/biome_dungeon_database.gd`
- `boomer-shooter/Data/biomes/*.tres`
- `boomer-shooter/Scripts/Data/enemy_roster_data.gd`
- `boomer-shooter/Data/enemies/fallback_enemy_roster.tres`
- `boomer-shooter/Scenes/Dungeon/Handcrafted/`

## Main Data Flow

- The project relies heavily on Godot resources for content authoring rather than hardcoding everything in runtime scripts.
- Gear content is composed from:
  - gear line definitions
  - authored rarity variants
  - generated implicit stats
  - generated affix rolls
  - built-in weapon definitions
- Biome content is composed from `BiomeDungeonData` resources that define:
  - textures and materials
  - doorway and door scenes
  - handcrafted room scenes
  - lighting defaults
  - prop scene lists
  - enemy scene lists
- `DungeonManager` resolves biome data via the biome database and then passes it into generation, geometry building, prop placement, and encounter selection.
- `EncounterSystem` prefers enemy scenes from the active biome and falls back to the fallback roster resource if needed.

## Important State And Resources

- `Data/gear/` contains concrete gear resources grouped by slot family.
- `Data/biomes/` contains authored biome resources and the biome database resource.
- `Scenes/Dungeon/Handcrafted/` contains authored room scenes referenced by biome data.
- `BiomeDungeonData` is broad and effectively acts as the biome content contract for dungeon systems.

## Multiplayer/Authority Notes

- Content resources are not a replacement for replication logic. Adding a resource-driven gameplay object still requires explicit authority and sync handling in runtime systems.
- Deterministic resource selection matters when host-generated content must be represented consistently on clients.

## Safe Edit Guidance

- Prefer extending resource data when adding content variation that matches existing patterns.
- Prefer runtime code changes only when the data model cannot express the new behavior safely.
- When adding new stats or content keys, trace every consumer before relying on the new field:
  - generation code
  - UI labels
  - equipment stat aggregation
  - verifier expectations or tests
- Avoid inventing new resource conventions when an existing resource script already defines the contract.

## Related Docs

- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
