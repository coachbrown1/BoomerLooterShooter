# Testing And Debugging

## Purpose

Summarize the project’s automated checks, multiplayer verifier workflows, and debug helpers so agents can choose the smallest relevant validation path for a change.

## Key Files

- `AGENTS.md`
- `boomer-shooter/Scripts/Debug/multiplayer_verifier.gd`
- `boomer-shooter/Scripts/Debug/run_multiplayer_verifier.ps1`
- `boomer-shooter/Scripts/Debug/run_multiplayer_chest_verifier.ps1`
- `boomer-shooter/Scripts/Debug/dungeon_regression.gd`
- `boomer-shooter/Scripts/Debug/dungeon_regression_runner.gd`
- `boomer-shooter/Scripts/Debug/run_dungeon_regression_editor.gd`
- `boomer-shooter/tests/data/test_gear_catalog.gd`
- `boomer-shooter/tests/network/test_spawn_offsets.gd`
- `boomer-shooter/addons/gut/`

## Main Data Flow

- Multiplayer validation uses PowerShell wrappers to launch a local host and client, then exercises scripted verifier scenarios inside the game via command-line args.
- The in-game verifier writes JSON and log artifacts under `boomer-shooter/.tmp/mp_verify_*`.
- `AGENTS.md` is the canonical, maintained list of supported multiplayer scenarios and when to use them.
- Dungeon generation regression checks are separate from multiplayer verification and focus on procedural layout invariants.
- Focused unit-style coverage uses the GUT plugin under `boomer-shooter/tests/`.

## Important State And Resources

- `multiplayer_verifier.gd` supports scenarios such as:
  - dungeon generation sync
  - player replication
  - health replication
  - chest sync
  - door sync
  - weapon state and visual sync
  - enemy damage, death, loot, and animation replication
  - long-run soak
- `dungeon_regression.gd` validates structural dungeon properties such as:
  - start and exit placement
  - connectivity and bidirectionality
  - corridor and doorway validity
  - room overlap and reachability
- `test_gear_catalog.gd` is a good example of a data-contract test: it verifies item counts, slots, rarities, stat families, and generated affix behavior.

## Multiplayer/Authority Notes

- Multiplayer changes should prefer the existing verifier over reasoning alone whenever there is already scenario coverage.
- When adding a replicated feature, consider whether a new verifier scenario is justified so regressions can be caught locally.
- Verifier scenarios implicitly document the expected authority model for a feature. Keep code and scenario expectations aligned.
- `dungeon-generation-sync` is the focused verifier for host/client dungeon floor parity: it compares the generated floor contract after sync rather than only checking spawn/floor settling.

## Safe Edit Guidance

- Use the smallest relevant validation surface:
  - targeted GUT tests for data or isolated logic
  - dungeon regression for generation-shape changes
  - multiplayer verifier for replicated gameplay behavior
- If a harness fails, inspect the per-run logs and JSON artifacts instead of assuming the first error message is complete.
- Avoid broad “run everything” validation unless the change is cross-cutting enough to justify it.

## Related Docs

- [networking-and-replication.md](networking-and-replication.md)
- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [data-resources-and-content.md](data-resources-and-content.md)
