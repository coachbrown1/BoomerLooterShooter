# Dungeon Designer Tool

Editor dock for dungeon-focused tuning.

## What it edits

- `DungeonManager` values from `res://Scenes/World/dungeon.tscn`
- Default dungeon content from `res://Data/dungeons/default_dungeon_content.tres`

## Typical workflow

1. Open Godot editor (plugin auto-enabled in `project.godot`).
2. In the `Dungeon Designer` dock, use the `Dungeon Layout` tab and click `Open Dungeon Scene`.
3. In `Quick Layout Controls`, edit:
   - Grid Size Min/Max
   - Generation Seed
4. Click `Apply + Save Layout`.
5. Switch to the `Dungeon Content` tab.
6. Use the custom sections to edit:
   - start room scene
   - default room scene
   - special room scene pool + chance
   - corridor scene
   - fog color
   - enemy scene roster
7. Click `Validate Dungeon Content` to catch missing required fields.
8. Click `Save Dungeon Content`.

## Tabs

- `Dungeon Layout`: grid size, generation seed, preview generation, and preview-room jumping.
- `Dungeon Content`: default dungeon content editing and validation.
- `Handcrafted Rooms`: authored room scene creation through the room wizard and single-room playtesting.

## Preview workflow

1. In `Dungeon Layout`, set `Generation Seed` (or leave `0` to auto-pick one on preview).
2. Click `Create Preview` to save the current seed/layout settings, then build the level directly in the editor scene.
3. Inspect the generated level in-editor.
4. Use `Preview Room Jump` to select START/EXIT/custom rooms and jump focus.
5. Press Play to run the same layout (seed is saved into the scene).
6. Click `Clear Preview` to remove generated preview geometry from the editor scene.

## Handcrafted room wizard

1. Switch to the `Handcrafted Rooms` tab.
2. In `Handcrafted Room Wizard`, enter a scene name.
3. Choose a base type:
   - `Start Room Template`
   - `Default Room Template`
   - `Special Room Template`
4. Optionally register the new scene into the active default dungeon content as:
   - start room
   - default room
   - special room pool
5. Click `Create Handcrafted Room`.
6. The tool saves the scene under `res://Scenes/Dungeon/Handcrafted/` and opens it immediately.

### Wizard output

- Templates are cloned from the active stitched room scenes instead of building runtime-generated shells.
- New rooms keep authored geometry, doorway filler nodes, and exported room metadata (`room_role_tags`, `supported_doorway_profiles`, `allowed_rotation_degrees`).
- Designers should edit those saved scenes directly; gameplay should match the authored scene apart from intentional rotation and doorway open/closed state.

## Single-room playtest

1. Switch to the `Handcrafted Rooms` tab.
2. Open the room you want to test, or pick one from `Room Playtest`.
3. Click `Playtest Selected Room`.
4. The tool writes the selected room scene into `.tmp`, then launches `res://Scenes/World/handcrafted_room_playtest.tscn`.

### Playtest behavior

- The harness spawns the selected handcrafted room on a large flat floor.
- If the room has a `PlayerSpawn`, the player starts there and uses its facing.
- If the room contains `HandcraftedEnemySpawner` markers with assigned enemy scenes, those enemies spawn for local combat testing.
- Handcrafted enemy spawners now use a box volume preview and box-based spawn area sizing instead of a capped radius field.
- `RoomBoundsDebug` guides are hidden during the playtest run.
