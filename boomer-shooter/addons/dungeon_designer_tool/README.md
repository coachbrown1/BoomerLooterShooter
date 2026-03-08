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
6. Edit biome fields (textures, props, lights, handcrafted scene pools, enemy roster).
7. Click `Save Selected Biome`.
