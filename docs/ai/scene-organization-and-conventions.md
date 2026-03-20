# Scene Organization And Conventions

## Purpose

Provide a quick reference for how scenes are organized in the Godot project and which conventions matter when locating or adding scene assets.

## Key Files

- `boomer-shooter/Scenes/System/`
- `boomer-shooter/Scenes/World/`
- `boomer-shooter/Scenes/UI/`
- `boomer-shooter/Scenes/Weapons/`
- `boomer-shooter/Scenes/Enemies/`
- `boomer-shooter/Scenes/Projectiles/`
- `boomer-shooter/Scenes/Props/`
- `boomer-shooter/Scenes/Dungeon/`
- `boomer-shooter/Scenes/Effects/`
- `boomer-shooter/project.godot`

## Main Data Flow

- Scene folders are organized mostly by domain, not by technical layer.
- Common high-value scene groups are:
  - `System`: startup/bootstrap
  - `World`: top-level playable spaces like hub and dungeon
  - `UI`: HUD and screens
  - `Weapons`, `Enemies`, `Projectiles`, `Props`, `Effects`: gameplay prefabs
  - `Dungeon`: reusable procedural pieces and handcrafted overlays
- Runtime managers usually live in scripts, while scenes act as configured prefab containers wired into those managers.

## Important Conventions

- Many behaviors are scene-configured on top of shared scripts rather than implemented as one script per asset type.
- Scene names often line up with gameplay domain names, but not always with script names. Example:
  - weapon scenes specialize `weapon.gd`
  - enemy scenes often specialize shared base enemy scripts
- World scenes are the main ownership boundary:
  - hub scene logic belongs to `HubManager`
  - dungeon scene logic belongs to `DungeonManager`
- Handcrafted dungeon content lives under `Scenes/Dungeon/Handcrafted/` and is meant to integrate with generated space, not replace it wholesale.

## Multiplayer/Authority Notes

- Scene placement alone does not imply authority. Always identify which manager or autoload owns the replicated behavior for a scene instance.
- Prefab edits can still change replicated behavior if they alter collision, projectile type, chest contents, interactable nodes, or enemy presentation tied to snapshots.

## Safe Edit Guidance

- Before creating a new scene, check whether an existing domain folder already matches the asset’s role.
- Prefer following the existing scene-plus-shared-script pattern instead of creating redundant scripts for every configured prefab.
- When documenting or discussing a feature, mention both the scene path and the owning script or manager if the ownership is not obvious from the scene itself.
- If a new scene category becomes large enough, add a dedicated doc rather than overloading the repo map.

## Related Docs

- [repo-map.md](repo-map.md)
- [weapon-families-and-scene-config.md](weapon-families-and-scene-config.md)
- [biomes-and-handcrafted-content.md](biomes-and-handcrafted-content.md)
