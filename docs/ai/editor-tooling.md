# Editor Tooling

## Purpose

Document the project-specific editor tooling that helps authors tune dungeon layout and biome content without editing everything manually in raw scenes and resources.

## Key Files

- `boomer-shooter/addons/dungeon_designer_tool/README.md`
- `boomer-shooter/addons/dungeon_designer_tool/plugin.gd`
- `boomer-shooter/addons/dungeon_designer_tool/dungeon_designer_dock.gd`
- `boomer-shooter/project.godot`
- `boomer-shooter/Scenes/World/dungeon.tscn`
- `boomer-shooter/Data/biomes/biome_dungeon_database.tres`

## Main Data Flow

- The `dungeon_designer_tool` plugin is enabled in `project.godot`.
- `plugin.gd` registers a dock named `Dungeon Designer` in the Godot editor.
- `dungeon_designer_dock.gd` builds a three-tab editor workflow:
  - `Dungeon Layout`
  - `Biome Data`
  - `Handcrafted Rooms`
- The layout tab can:
  - open the dungeon scene
  - inspect `DungeonManager`
  - load and apply generation values
  - create and clear previews
  - jump the editor camera to preview rooms
- The biome tab can:
  - load the biome database
  - select a biome resource
  - edit biome-linked properties and scene references
  - validate and save the selected biome
- The handcrafted rooms tab can:
  - create new handcrafted room scenes through the built-in wizard
  - optionally register new handcrafted rooms into the selected biome
  - open the new room scene immediately for authoring
  - launch a dedicated single-room playtest harness for a selected handcrafted room

## Important State And Resources

- The dock works primarily against:
  - `res://Scenes/World/dungeon.tscn`
  - `res://Data/biomes/biome_dungeon_database.tres`
- The handcrafted room wizard writes new scenes under:
  - `res://Scenes/Dungeon/Handcrafted/`
- Single-room handcrafted playtests use:
  - `res://Scenes/World/handcrafted_room_playtest.tscn`
  - `res://Scripts/World/handcrafted_room_playtest.gd`
  - `res://.tmp/handcrafted_room_playtest.cfg`
- Handcrafted-room authoring helpers also include:
  - `res://Scenes/Dungeon/anchored_box_body.tscn`
  - This reusable `StaticBody3D` keeps mesh and collision aligned while letting designers scale from a chosen anchored side instead of always expanding from the center.
  - `res://Scripts/Dungeon/handcrafted_enemy_spawner.gd`
  - In the editor, handcrafted enemy spawners render an in-scene radius preview ring and spawn point ticks based on `spawn_radius`, `spawn_count`, and `vertical_offset`.
- It dynamically discovers option lists for textures, scenes, enemies, props, handcrafted rooms, doors, and light scenes.
- The tool is editor-only and should not be treated as a runtime gameplay dependency.

## Multiplayer/Authority Notes

- Editor tooling does not own networking behavior directly, but it can influence multiplayer by changing dungeon generation data, room scenes, enemy rosters, and biome assets.
- If a tooling edit changes content contracts used at runtime, make sure the corresponding runtime docs and validation expectations stay aligned.

## Safe Edit Guidance

- Prefer documenting how the project uses this addon rather than changing the addon casually.
- If a task requires editing the tool, verify whether the change belongs in the plugin UI or in the underlying runtime/resource scripts instead.
- Keep editor-only behavior separated from runtime code paths.
- Wizard-generated handcrafted scenes should preserve the runtime contract expected by `DungeonManager`, especially start-room `PlayerSpawn` usage and handcrafted spawner node types.
- Normal-room wizard output is based directly on the crossroom shell so designers start from the same authored room shape used by the existing handcrafted crossroom setup.
- The room playtest harness is intentionally lightweight and does not replace full dungeon or multiplayer verification; use it for local room iteration, not replication validation.
- Update the addon README and `docs/ai` summary if the workflow or edited resources change materially.

## Related Docs

- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [data-resources-and-content.md](data-resources-and-content.md)
- [repo-map.md](repo-map.md)
