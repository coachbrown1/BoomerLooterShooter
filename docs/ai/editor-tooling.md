# Editor Tooling

## Purpose

Document the project-specific editor tooling that now targets single default dungeon content authoring instead of biome authoring.

## Key Files

- `boomer-shooter/addons/dungeon_designer_tool/dungeon_designer_dock.gd`
- `boomer-shooter/addons/dungeon_designer_tool/README.md`
- `boomer-shooter/addons/dungeon_designer_tool/plugin.cfg`
- `boomer-shooter/Scenes/World/dungeon.tscn`
- `boomer-shooter/Data/dungeons/default_dungeon_content.tres`
- `boomer-shooter/Scenes/World/handcrafted_room_playtest.tscn`
- `boomer-shooter/Scripts/World/handcrafted_room_playtest.gd`

## Main Data Flow

- The `Dungeon Designer` dock still has three editor workflows:
  - `Dungeon Layout`
  - `Dungeon Content`
  - `Handcrafted Rooms`
- The layout tab edits `DungeonManager` settings on `res://Scenes/World/dungeon.tscn`, generates preview floors, and jumps to preview room locations.
- The content tab edits `res://Data/dungeons/default_dungeon_content.tres`:
  - start room scene
  - default room scene
  - special room pool and chance
  - corridor scene
  - fog color
  - enemy scene pool
- The room wizard clones authored template scenes from the active content resource instead of generating runtime-shell skeletons.
- The playtest harness now only needs a room scene path; it no longer carries biome data.

## Important State And Resources

- The dock's runtime-facing content contract is `DefaultDungeonContent`.
- Room playtests write `res://.tmp/handcrafted_room_playtest.cfg`.
- Room authoring still happens under `res://Scenes/Dungeon/Handcrafted/`, but the playtest picker also includes stitched room scenes under `res://Scenes/Dungeon/Rooms/`.

## Multiplayer/Authority Notes

- The addon is editor-only, but it edits resources consumed by host-authoritative dungeon generation.
- Changes to doorway profiles, room scenes, corridor scenes, or enemy pools can affect verifier stability and multiplayer consistency.

## Safe Edit Guidance

- Keep tool changes aligned with the runtime content contract in `default_dungeon_content.gd`.
- Prefer cloning or editing authored room scenes over adding more runtime generation behavior.
- Wizard-generated room scenes should preserve exported room metadata so `DungeonManager` can fit and rotate them correctly.
- The single-room playtest is for local room iteration only; use the multiplayer verifier harness for replication checks.

## Related Docs

- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [data-resources-and-content.md](data-resources-and-content.md)
- [runtime-overview.md](runtime-overview.md)
