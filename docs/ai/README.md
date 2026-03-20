# AI Reference Docs

This directory is the agent-oriented documentation hub for the repository. It is meant to shorten the time needed to understand the current project shape before editing code.

Use these docs for:

- locating entrypoints and major subsystems
- understanding runtime and scene flow
- finding multiplayer authority and replication boundaries
- identifying the main files involved in a system
- spotting areas where edits are likely to have cross-system impact

Rules for using these docs:

- Start here, then open the most relevant subsystem doc before making assumptions.
- Use docs to orient yourself, then confirm behavior in code.
- Prefer the code when a doc and implementation disagree.

Maintenance expectations:

- Update the relevant doc in this directory whenever a change materially alters a system, runtime flow, file ownership boundary, multiplayer behavior, data shape, or verification path.
- Add a new doc and link it from this README when new systems become large enough that agents would otherwise need to rediscover the architecture repeatedly.
- Keep docs concise and current rather than aspirational. Remove or revise stale statements when code changes.
- In task handoffs, explicitly note which docs were updated or why a docs update was not needed.

Current pilot coverage:

- [repo-map.md](repo-map.md)
- [runtime-overview.md](runtime-overview.md)
- [networking-and-replication.md](networking-and-replication.md)
- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
- [ui-and-player-experience.md](ui-and-player-experience.md)
- [world-interactions-and-props.md](world-interactions-and-props.md)
- [data-resources-and-content.md](data-resources-and-content.md)
- [testing-and-debugging.md](testing-and-debugging.md)

Known gaps in this first pass:

- top-level support folders outside the game project are only summarized
- lighting, release/export flow, and editor tooling do not yet have dedicated subsystem docs
- addon internals are intentionally not documented beyond how the project uses them
