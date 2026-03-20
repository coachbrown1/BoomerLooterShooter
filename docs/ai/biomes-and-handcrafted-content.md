# Biomes And Handcrafted Content

## Purpose

Describe how biome resources shape dungeon presentation and how handcrafted room scenes fit into the otherwise procedural generation pipeline.

## Key Files

- `boomer-shooter/Scripts/Data/biome_dungeon_data.gd`
- `boomer-shooter/Scripts/Data/biome_dungeon_database.gd`
- `boomer-shooter/Data/biomes/biome_dungeon_database.tres`
- `boomer-shooter/Data/biomes/*.tres`
- `boomer-shooter/Scripts/Dungeon/dungeon_manager.gd`
- `boomer-shooter/Scripts/Dungeon/dungeon_builder.gd`
- `boomer-shooter/Scripts/Dungeon/prop_placer.gd`
- `boomer-shooter/Scenes/Dungeon/Handcrafted/`
- `boomer-shooter/addons/dungeon_designer_tool/dungeon_designer_dock.gd`

## Main Data Flow

- `DungeonManager` resolves the active biome through the biome database after generation chooses or inherits a biome ID.
- `BiomeDungeonData` acts as the content contract that feeds multiple systems:
  - tile textures and material settings
  - door and doorway scenes
  - handcrafted start and normal room scenes
  - lighting defaults
  - prop pools
  - enemy scene pools
  - exit portal texture
- After generation, `DungeonManager` uses biome data to:
  - assign handcrafted room overlays
  - update environment and materials
  - pass content into `DungeonBuilder`
  - pass prop pools into `PropPlacer`
  - pass enemy pools into `EncounterSystem`
- Handcrafted room scenes under `Scenes/Dungeon/Handcrafted/` are layered into the generated floor rather than replacing the entire dungeon system.

## Important State And Resources

- `BiomeDungeonData` contains both visual and gameplay-relevant content references, which makes it one of the broadest authored resource contracts in the project.
- `handcrafted_start_room_scene`, `handcrafted_normal_room_scenes`, and `handcrafted_quadrant_room_scenes` are especially important for authored set pieces.
- Doorway and light scene references in biome data can change how generated spaces feel without changing the generator itself.
- The dungeon designer plugin is the main editor workflow for tuning these resources without editing every property manually.

## Multiplayer/Authority Notes

- Even though biome data is resource-driven, authoritative world generation still belongs to the host in multiplayer.
- Any new biome-driven content that affects shared gameplay must still be replicated correctly once spawned into the world.
- Deterministic biome content choices matter for verifier stability and client consistency.

## Safe Edit Guidance

- Treat `BiomeDungeonData` as a shared schema. If you add or rename properties, trace every consumer before landing the change.
- Prefer biome-resource edits for presentation or content-variation work and generation-script edits only when the procedural rules themselves need to change.
- When adding handcrafted content, document whether it is start-only, normal-room only, quadrant-only, or reusable across multiple biome contexts.
- If a biome change affects enemy rosters, props, doors, or lighting, update the relevant subsystem docs as well.

## Related Docs

- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [data-resources-and-content.md](data-resources-and-content.md)
- [editor-tooling.md](editor-tooling.md)
- [enemies-and-rosters.md](enemies-and-rosters.md)
