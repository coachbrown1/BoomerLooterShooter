# Dungeon Designer Tool

Editor dock for dungeon-focused tuning. Three tabs, each with a clearly labeled panel layout.

## What it edits

- `DungeonManager` values from `res://Scenes/World/dungeon.tscn`
- Default dungeon content from `res://Data/dungeons/default_dungeon_content.tres`

---

## Tabs

### Dungeon Layout

**Quick Layout** — Grid Size Min/Max and Generation Seed spinboxes.
- `Load From Scene` — pulls current values from the DungeonManager in the open scene.
- `Apply + Save Layout` — pushes spinbox values to DungeonManager and saves the scene.

**Preview Generation** — Builds the dungeon in-editor so you can inspect room placement without pressing Play.
- `Create Preview` — saves current layout, then calls `generate_floor()` on the manager.
- `Clear Preview` — removes generated preview geometry.

**Preview Room Jump** — Navigate the editor camera to any room in a generated preview.
- Pick a room from the dropdown (START / EXIT / handcrafted rooms).
- `Refresh Rooms` — repopulates the dropdown from the current preview.
- `Go To Room` — moves the editor camera, a PreviewRoomFocus marker, and the Player node.

**Layout Inspector** — Full EditorInspector for all DungeonManager exported fields.

---

### Dungeon Content

Directly edits `res://Data/dungeons/default_dungeon_content.tres`.

**Stitched Scenes**
- Start Room Scene, Default Room Scene — single-scene pickers with an `Open` button each.
- Special Room Scenes — list with Add (searchable picker + Add button), Remove, ↑, ↓, Open.
  The picker always re-scans for new scenes when opened, so newly created rooms appear immediately.
- Special Room Chance — 0–1 float.
- Corridor Scene, Doorway Assembly Scene — single-scene pickers.

**Environment** — Fog Light Color picker.

**Enemies** — Enemy Scenes array editor (same controls as Special Room Scenes).

**Validation** — `Validate Dungeon Content` checks required fields and reports any missing ones.

Action buttons at the top: `Refresh`, `Save Dungeon Content`, `Open Content Resource`.

---

### Handcrafted Rooms

Three clearly separated panels, scrollable.

#### Room Wizard

Create an authored room scene from the active dungeon templates and optionally register it.

1. Enter a **Scene Name** (alphanumeric + underscores; placeholder derives prefix from the active start room, e.g. `Castle_`).
2. Choose a **Base Type**: Start Room Template, Default Room Template, or Special Room Template.
3. Choose **Register In Content**:
   - *Do Not Register* — saves the scene only.
   - *Set As Start Room* / *Set As Default Room* — replaces the current slot (confirmation dialog shown if a scene is already assigned).
   - *Add To Special Room Pool* — appends to the pool.
4. Click `Create Handcrafted Room`.

The tool clones the matching template scene, saves it under `res://Scenes/Dungeon/Handcrafted/`, registers it if requested, then opens it automatically. The Content tab options refresh immediately so the new scene is available in all pickers.

#### Room Playtest

- Dropdown shows all scenes under `Scenes/Dungeon/Handcrafted/` and `Scenes/Dungeon/Rooms/`, labeled with their directory (`Handcrafted/Castle_Start`, `Rooms/castle_default_room`) so they're easy to tell apart.
- `Refresh Room List` — rescans and repopulates the dropdown.
- `Open Selected Room` — opens exactly the scene selected in the dropdown (ignores the currently edited scene).
- `Playtest Selected Room` — if the currently open scene is a room, uses that; otherwise uses the dropdown selection. Saves a playtest config to `.tmp` and launches `handcrafted_room_playtest.tscn`.

#### Content Pool

Toggles the selected (or currently open) room in the active special room pool.
- Removing from the pool shows a confirmation dialog before making the change.
- Status line shows whether the current room is in the pool.

---

## Status Bar

The three-line rolling log at the top of the dock shows the most recent messages. Newer messages appear at the top; older entries dim progressively. Errors are shown in red.

---

## Typical workflow

1. Open the **Dungeon Designer** dock (auto-enabled in `project.godot`).
2. **Dungeon Layout** tab → `Open Dungeon Scene` → set Grid Size Min/Max and Seed → `Apply + Save Layout`.
3. `Create Preview` → use **Preview Room Jump** to inspect room placement.
4. **Dungeon Content** tab → edit Stitched Scenes, Environment, Enemies → `Save Dungeon Content`.
5. **Handcrafted Rooms** tab → use the **Room Wizard** to create new room scenes → edit geometry → use **Room Playtest** to test them in isolation.
6. Use **Content Pool** to add finished rooms to the special room pool.
