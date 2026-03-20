# Dungeon Designer Tool

Editor dock for dungeon-focused tuning.

## What it edits

- `DungeonManager` values from `res://Scenes/World/dungeon.tscn`
- Biome resources from `res://Data/biomes/biome_dungeon_database.tres`

## Typical workflow

1. Open Godot editor (plugin auto-enabled in `project.godot`).
2. In the `Dungeon Designer` dock, use the `Dungeon Layout` tab and click `Open Dungeon Scene`.
3. In `Quick Layout Controls`, edit:
   - Grid Size Min/Max
   - Room Size (tiles)
   - Corridor Width/Length (tiles)
4. Click `Apply + Save Layout`.
5. Switch to the `Biome Data` tab and pick a biome.
6. Use the custom sections to edit:
   - Surface textures
   - Doors + handcrafted room scenes
   - Lighting (ambient + wall/floor prop lights)
   - Prop scene pools
   - Enemy scene roster
7. Click `Validate Selected Biome` to catch missing required fields.
8. Click `Save Selected Biome`.

## Tabs

- `Dungeon Layout`: generation values, preview generation, and preview-room jumping.
- `Biome Data`: biome resource editing and validation.
- `Handcrafted Rooms`: handcrafted room scene creation through the room wizard and single-room playtesting.

## Preview workflow

1. In `Dungeon Layout`, set `Generation Seed` (or leave `0` to auto-pick one on preview).
2. Click `Create Preview` to build the level directly in the editor scene.
3. Inspect the generated level in-editor.
4. Use `Preview Room Jump` to select START/EXIT/custom rooms and jump focus.
5. Press Play to run the same layout (seed is saved into the scene).
6. Click `Clear Preview` to remove generated preview geometry from the editor scene.

## Handcrafted room wizard

1. Switch to the `Handcrafted Rooms` tab.
2. In `Handcrafted Room Wizard`, enter a scene name.
3. Choose a base type:
   - `Start Room Skeleton`
   - `Normal Room Skeleton`
   - `Quadrant Composite Room`
4. Optionally register the new scene into the currently selected biome as:
   - start room
   - normal room
   - quadrant module pool
5. Click `Create Handcrafted Room`.
6. The tool saves the scene under `res://Scenes/Dungeon/Handcrafted/` and opens it immediately.

### Wizard output

- Start room skeletons include:
  - `PlayerSpawn`
  - a spawn pad
  - doorway socket markers
  - room bounds debug guides
- Normal room skeletons include:
  - the same crossroom shell setup used by `Castle_Crossroom`
  - an `Encounter/EnemySpawner` marker
  - the crossroom's built-in quadrant anchors and room guides
- Quadrant composite rooms start from the existing crossroom shell so designers can focus on quadrant content first.

## Single-room playtest

1. Switch to the `Handcrafted Rooms` tab.
2. Open the room you want to test, or pick one from `Room Playtest`.
3. Click `Playtest Selected Room`.
4. The tool writes the selected room + biome into `.tmp`, then launches `res://Scenes/World/handcrafted_room_playtest.tscn`.

### Playtest behavior

- The harness spawns the selected handcrafted room on a large flat floor.
- If the room has a `PlayerSpawn`, the player starts there and uses its facing.
- If the room contains `HandcraftedEnemySpawner` markers with assigned enemy scenes, those enemies spawn for local combat testing.
- `RoomBoundsDebug` guides are hidden during the playtest run.
