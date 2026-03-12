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

## Preview workflow

1. In `Dungeon Layout`, set `Generation Seed` (or leave `0` to auto-pick one on preview).
2. Click `Create Preview` to build the level directly in the editor scene.
3. Inspect the generated level in-editor.
4. Use `Preview Room Jump` to select START/EXIT/custom rooms and jump focus.
5. Press Play to run the same layout (seed is saved into the scene).
6. Click `Clear Preview` to remove generated preview geometry from the editor scene.
