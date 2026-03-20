# Repo Map

## Purpose

Provide a fast map of the repository, the main entrypoints, and the boundaries between project-owned code and external/plugin surfaces.

## Key Files

- `AGENTS.md`: repo-wide AI instructions and multiplayer verification guidance.
- `boomer-shooter/project.godot`: Godot project config, main scene, autoloads, plugin enablement, and input map.
- `boomer-shooter/Scenes/System/bootstrap.tscn`: runtime entry scene.
- `boomer-shooter/Scripts/Networking/network_bootstrap.gd`: menu/bootstrap controller and scene handoff into hub or dungeon.
- `boomer-shooter/Scripts/System/game_state.gd`: static singleton-style state used across scene transitions.
- `boomer-shooter/Scripts/Debug/multiplayer_verifier.gd`: in-game verifier scenarios used by PowerShell harness scripts.

## Main Data Flow

- The repo root contains shared instructions and support content.
- The actual game lives under `boomer-shooter/`.
- Godot starts at `Scenes/System/bootstrap.tscn`, which runs `network_bootstrap.gd`.
- Bootstrap either launches single-player directly, starts or joins a multiplayer session, or runs verifier automation via command-line args.
- Runtime scene changes mainly move between `Scenes/World/hub.tscn` and `Scenes/World/dungeon.tscn`.

## Important State And Resources

- Autoloads declared in `project.godot`:
  - `NetworkSession`
  - `NetSession` (second alias to the same script)
  - `NetworkPlayerManager`
  - `GlobalEventBus`
- `GameState` is not an autoload entry, but is used as a static class for persistent run data such as inventory snapshots, hub chest contents, and dungeon configuration.
- Multiplayer and regression harness scripts live under `boomer-shooter/Scripts/Debug/` and are invoked by PowerShell wrappers in `boomer-shooter/Scripts/Debug/*.ps1`.

## Top-Level Layout

- `boomer-shooter/`: main Godot project.
- `boomer-shooter/Scenes/`: runtime scene assets grouped by domain.
- `boomer-shooter/Scripts/`: gameplay, networking, world, UI, and data scripts.
- `boomer-shooter/Data/`: authored resources such as gear, biome, and enemy roster data.
- `boomer-shooter/tests/`: focused GUT tests.
- `boomer-shooter/addons/gut/`: third-party testing plugin used by the project.
- `boomer-shooter/addons/dungeon_designer_tool/`: editor plugin used to support dungeon authoring workflows.
- `.Jules/` and `boomer-shooter/.Jules/`: lightweight local notes, not a substitute for code or the new `docs/ai` docs.
- `Art Generators/`, `MaterialMaker/`, `sprite_previews/`: support content outside the runtime game project.

## Multiplayer/Authority Notes

- This is a co-op project with server-authoritative gameplay expectations.
- Networking ownership is centered around `NetworkSession`, `NetworkPlayerManager`, and world-specific managers such as `HubManager` and `DungeonManager`.
- Multiplayer verification instructions and supported scenarios are documented in `AGENTS.md`.

## Safe Edit Guidance

- Most gameplay/runtime changes should stay inside `boomer-shooter/`.
- Treat `addons/gut` and `addons/dungeon_designer_tool` as plugin surfaces; document how the game uses them, but avoid changing addon internals unless the task explicitly requires it.
- Check `project.godot`, the active scene, and the relevant manager script before inventing a new entrypoint.

## Related Docs

- [README.md](README.md)
- [runtime-overview.md](runtime-overview.md)
- [networking-and-replication.md](networking-and-replication.md)
