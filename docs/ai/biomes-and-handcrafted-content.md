# Dungeon Content And Handcrafted Rooms

## Purpose

Describe the current stitched dungeon content contract and how handcrafted room scenes fit into the single-default-dungeon pipeline.

## Key Files

- `boomer-shooter/Scripts/Data/default_dungeon_content.gd`
- `boomer-shooter/Data/dungeons/default_dungeon_content.tres`
- `boomer-shooter/Scripts/Dungeon/dungeon_manager.gd`
- `boomer-shooter/Scripts/Dungeon/handcrafted_room_layout.gd`
- `boomer-shooter/Scenes/Dungeon/Handcrafted/`
- `boomer-shooter/Scenes/Dungeon/Rooms/`

## Main Data Flow

- `DefaultDungeonContent` is the active dungeon content contract for runtime generation.
- `DungeonManager` uses that resource to choose the authored start room, default room, special room pool, corridor scene, and enemy pool.
- Handcrafted rooms are no longer overlays on top of generated shell geometry.
- Instead, every stitched room scene is treated as authoritative authored content, with runtime limited to rotation and doorway filler toggling.

## Important State And Resources

- The current castle-authored content acts as the canonical default dungeon presentation.
- Handcrafted room roots should export:
  - `room_role_tags`
  - `supported_doorway_profiles`
  - `allowed_rotation_degrees`
- Special rooms may intentionally support fewer openings than a raw lattice cell, which allows topology pruning before stitching.

## Multiplayer/Authority Notes

- Authored room content still participates in host-authoritative dungeon generation.
- Deterministic scene selection and rotation remain important for verifier stability and client consistency.

## Safe Edit Guidance

- Prefer editing the room `.tscn` directly when changing presentation.
- If a room deliberately closes certain doorways, make sure its exported doorway profiles match the authored layout.
- Do not reintroduce runtime shell generation, runtime structural prop placement, or biome-driven content lookups without updating the whole content model and docs.

## Related Docs

- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [editor-tooling.md](editor-tooling.md)
- [data-resources-and-content.md](data-resources-and-content.md)
