# Support Folders And Local Notes

## Purpose

Explain the top-level folders outside the Godot runtime project so agents know which ones are active source, support tooling, generated previews, or lightweight local notes.

## Key Files

- `J:\BoomerShooter\.Jules\bolt.md`
- `J:\BoomerShooter\.Jules\palette.md`
- `J:\BoomerShooter\Art Generators\create_chest_asset.py`
- `J:\BoomerShooter\Art Generators\fantasy_ui_icon_set.png`
- `J:\BoomerShooter\Art Generators\hud_frame_kit.png`
- `J:\BoomerShooter\Art Generators\inventory_micro_badges.png`
- `J:\BoomerShooter\MaterialMaker\material_maker_1_5p1_windows\material_maker.exe`
- `J:\BoomerShooter\sprite_previews\`

## Main Data Flow

- `boomer-shooter/` remains the actual game project and should still be treated as the default source tree for gameplay work.
- `.Jules/` contains short local notes and reminders. These are useful orientation aids but are not authoritative architecture docs.
- `Art Generators/` contains support assets and scripts related to generating or staging UI or prop art resources.
- `MaterialMaker/` contains a local Material Maker installation and its bundled docs, which is a support tool rather than project runtime code.
- `sprite_previews/` contains preview and exploratory art images used for iteration and visual reference.

## Important State And Resources

- `.Jules/bolt.md` and `.Jules/palette.md` currently capture narrow implementation lessons rather than complete subsystem docs.
- `Art Generators/` includes generated UI atlas source images that are referenced by the HUD and related UI scripts.
- `MaterialMaker/` is effectively a checked-in local tool bundle.
- `sprite_previews/` appears to be a working folder for concept or processed sprite references, not a gameplay script surface.

## Multiplayer/Authority Notes

- These folders are mostly outside gameplay authority concerns, but assets created here can still affect runtime presentation once imported into the Godot project.
- Do not assume support-folder content is automatically wired into runtime code; verify references from the game project before treating support assets as live dependencies.

## Safe Edit Guidance

- Prefer editing `boomer-shooter/` for gameplay changes unless the task specifically involves source art, preview assets, or local tooling.
- Treat `.Jules/` as supplementary notes, not canonical project documentation.
- If a support-folder asset becomes part of a stable runtime workflow, document the connection in the relevant subsystem doc under `docs/ai/`.
- Avoid broad cleanup in these folders unless the task is specifically about asset/tool organization.

## Related Docs

- [repo-map.md](repo-map.md)
- [ui-and-player-experience.md](ui-and-player-experience.md)
- [editor-tooling.md](editor-tooling.md)
