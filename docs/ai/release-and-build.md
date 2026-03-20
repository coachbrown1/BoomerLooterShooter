# Release And Build

## Purpose

Summarize how the project is configured for export and where release packaging logic currently lives.

## Key Files

- `boomer-shooter/export_presets.cfg`
- `boomer-shooter/Scripts/Release/build_windows_release.ps1`
- `boomer-shooter/project.godot`
- `boomer-shooter/build/`

## Main Data Flow

- Godot export configuration is stored in `export_presets.cfg`.
- The active preset in the repo is `Windows Desktop`, exporting to `build/windows/BoomerShooter.exe`.
- `build_windows_release.ps1` automates a Windows release bundle:
  - validate Godot executable and project paths
  - ensure export templates are installed
  - read the version from `project.godot`
  - import project assets in headless mode
  - export the release executable
  - stage the `.exe` and `.pck`
  - optionally apply `release_README.txt`
  - zip the final bundle unless `-SkipZip` is used

## Important State And Resources

- The release script expects a local Godot 4.6 stable console executable by default.
- It also expects Windows export templates under `%APPDATA%\\Godot\\export_templates\\4.6.stable`.
- Output is versioned under the `boomer-shooter/build/windows-release/` tree, with a version-named subdirectory per build.
- Application metadata such as product name, version, and description are partly duplicated between `project.godot` and `export_presets.cfg`.

## Multiplayer/Authority Notes

- Release/build flow does not define gameplay authority, but exported builds still need to preserve the project’s multiplayer startup and verification assumptions.
- If networking CLI args or bootstrap automation behavior changes, verify release packaging still exports a runnable build with the expected runtime entrypoint.

## Safe Edit Guidance

- Keep the version source aligned with `project.godot` if changing export or packaging scripts.
- If you change export targets or templates, update both the PowerShell wrapper and `export_presets.cfg` together.
- Treat build output directories as generated artifacts rather than source files.
- If release instructions expand beyond Windows, add a dedicated doc section or sibling doc instead of overloading the current one.

## Related Docs

- [repo-map.md](repo-map.md)
- [runtime-overview.md](runtime-overview.md)
- [testing-and-debugging.md](testing-and-debugging.md)
