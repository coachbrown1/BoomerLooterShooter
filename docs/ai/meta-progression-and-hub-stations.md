# Meta Progression And Hub Stations

## Purpose

Define the planned long-term progression architecture for repeated castle runs, centered on hub interactable stations and a master unlock tree.

## Status

- Phase 1 backend implementation exists in `boomer-shooter/Scripts/System/meta_progression.gd`.
- Phase 1 UI implementation exists in `boomer-shooter/Scripts/UI/war_table_menu.gd` and `boomer-shooter/Scripts/UI/drill_hall_panel.gd`.
- The War Table station is instantiated from `boomer-shooter/Scenes/Props/Castle/prop_castle_war_table.tscn` and opened from the hub.
- Current code still uses the existing hub, portal, dungeon, inventory, and chest flow documented elsewhere.
- Treat this file as the canonical target design when implementing the feature incrementally.

## Design Goals

- Give repeated castle runs several simultaneous long-term payoffs.
- Anchor each major progression track to a physical interactable station in the hub.
- Use one master progression surface to gradually reveal and unlock the other systems.
- Keep host authority over any shared or multiplayer-relevant progression outcomes.
- Introduce systems in phases so players are not overloaded early.

## Planned Station Set

- `War Table`: master meta-progression station and sprawling unlock tree. Backed by the `MetaProgression` autoload singleton.
- `Drill Hall`: player build progression driven by run XP.
- `Bounty Board`: optional contracts that change run goals.
- `Quartermaster`: rotating vendor driven by a run-earned currency.
- `Chapel of Pacts`: shrine or faction reputation progression.
- `Artificer's Forge`: gear refinement with limited item crafting potential.
- `Relic Archive`: long-term collection and endgame assembly.

## War Table

### Role

- The `War Table` is the first and primary progression station in the hub.
- It is the gatekeeper for the rest of the long-term systems.
- Its tree should feel like a campaign map or conquest board rather than a flat talent menu.

### Visual/UX Rules

- Start with a small visible root cluster.
- Most nodes remain hidden until the player unlocks adjacent or prerequisite nodes.
- Nearby locked nodes may be hinted or silhouetted.
- Distant branches should remain fully hidden.
- One late-game node named `Roll Credits` should be visible far inside the tree from the start.
- `Roll Credits` remains permanently locked until the future endgame path for destroying the dungeon is implemented.

### Branch Structure

- `Campaign`: broad castle progression, room or layer access, castle difficulty, castle reward shaping, and endgame pathing.
- `Doctrine`: unlocks `Castle XP` and the player build-specialization loop.
- `Contracts`: unlocks contract selection, rerolls, and higher contract tiers.
- `Pacts`: unlocks in-run shrines, faction favor, and faction-specific rewards.
- `Black Market`: unlocks run currency drops and the `Quartermaster`.
- `Forgecraft`: unlocks gear refinement and the `Artificer's Forge`.
- `Relics`: unlocks long-term relic collection, archive functions, and future endgame gates.

### Unlock Model

- Root nodes should use only the baseline long-term currency from successful castle runs.
- Mid-tree nodes should start requiring proof items, milestone clears, or progress from other branches.
- Major station unlock nodes should be explicit milestones with strong UI and hub feedback.
- Late nodes should require cross-branch progress so the player cannot ignore every other system.
- `Roll Credits` should not be spendable with currency; it should require the future dungeon-destruction win condition.

## Planned Unlock Sequence

### Phase 0: Foundation

- Available at start:
  - `War Table`
  - a small root cluster of `Campaign` nodes
  - a baseline long-term currency earned from successful castle runs
- Player learns:
  - repeated runs feed permanent progression
  - much of the tree is hidden
  - other systems exist but are not yet available

### Phase 1: Doctrine

- `War Table` unlocks `Drill Hall`
- Castle runs begin awarding `Castle XP`
- Level-ups grant build-specialization points

This should be the first major branch because it is the easiest long-term loop for players to understand.

### Phase 2: Contracts

- `War Table` unlocks `Bounty Board`
- Players can activate one contract before a run
- Initial contracts should be simple and readable

This adds replay variation without forcing a new currency or crafting loop immediately.

### Phase 3: Black Market

- `War Table` unlocks run currency drops
- `War Table` unlocks `Quartermaster`
- The vendor should start with a small rotating pool

This gives failed or low-loot runs a reliable fallback reward path.

### Phase 4: Pacts

- `War Table` unlocks shrine spawn eligibility in the castle
- `War Table` unlocks `Chapel of Pacts`
- Shrine outcomes begin feeding long-term faction favor

This phase adds optional in-run tradeoffs once the player already understands the base run loop.

### Phase 5: Forgecraft

- `War Table` unlocks `Artificer's Forge`
- Gear can be rerolled, improved, or corrupted within item-specific limits

This should come after players already have enough drop volume to care about item shaping.

### Phase 6: Relics

- `War Table` unlocks `Relic Archive`
- Castle completion begins paying toward long-term relic sets and endgame preparation

This is the late-game macro progression layer and should connect back into the `Campaign` branch.

## System Specs

### 1. Castle XP And Build Progression

- Primary station: `Drill Hall`
- Unlocked by: `War Table` `Doctrine` branch
- Run reward: `Castle XP`
- Main outputs:
  - player levels
  - specialization points
  - build-defining passive unlocks
- Intended node types:
  - mobility
  - survivability
  - ammo economy
  - elite or chest utility
  - curse or shrine tolerance

Keep this separate from the `War Table` so the master tree does not become responsible for every small player-stat upgrade.

### 2. Contracts

- Primary station: `Bounty Board`
- Unlocked by: `War Table` `Contracts` branch
- Main flow:
  - choose a contract in hub before entering the castle
  - complete optional objective during the run
  - claim or auto-award long-term rewards after success
- Expansion path:
  - rerolls
  - higher-rarity contracts
  - multiple contract slots if the game later needs them

Keep the first implementation to one active contract slot and a small objective pool.

### 3. Quartermaster Economy

- Primary station: `Quartermaster`
- Unlocked by: `War Table` `Black Market` branch
- Run reward: a vendor-specific currency
- Main outputs:
  - rotating offers
  - targeted upgrade materials
  - future utility items, keys, sigils, or cosmetics

The first implementation should keep refresh rules simple and deterministic enough to debug.

### 4. Shrines, Pacts, And Faction Favor

- Primary station: `Chapel of Pacts`
- Unlocked by: `War Table` `Pacts` branch
- In-run source: optional shrine interactions inside the castle
- Main outputs:
  - faction favor or reputation
  - faction reward tracks
  - faction-tagged contracts or run modifiers later

Shrines should present a clear cost, constraint, or risk before the player commits.

### 5. Gear Refinement

- Primary station: `Artificer's Forge`
- Unlocked by: `War Table` `Forgecraft` branch
- Main outputs:
  - reroll affix
  - seal affix
  - improve tier
  - corrupt item
- Core constraint:
  - every item needs a limited refinement budget such as `forge_potential`

Limited item potential is important because it preserves loot excitement and prevents every good drop from becoming trivially perfect.

### 6. Relic Collection

- Primary station: `Relic Archive`
- Unlocked by: `War Table` `Relics` branch
- Run reward: relic fragments, relic pieces, or milestone relic claims
- Main outputs:
  - set completion tracking
  - future throne-room or endgame access
  - future dungeon-destruction path hooks

This system should be the longest-horizon chase and should not be fully front-loaded.

## Shared Data Model

The feature should use one centralized persistence model rather than each station inventing separate save logic.

### Planned Persistent Data Areas

- `meta_progression`
- `war_table`
- `castle_xp`
- `contracts`
- `quartermaster`
- `factions`
- `forgecraft`
- `relics`
- `hub_station_unlocks`

### War Table Data Needs

- node id
- node branch
- node visibility state
- node unlock state
- prerequisite node ids
- prerequisite milestone flags
- cost payload
- unlock payload or emitted event

### Reward Payload Needs

- long-term currencies
- station unlock flags
- per-system XP or favor gains
- milestone items or proof tokens
- end-of-run summary entries for UI

## Ownership And Authority

- Hub station interactions should route through the hub-side authoritative manager rather than living as isolated local-only scene logic.
- Any station that changes shared progression state in multiplayer should resolve through host authority and then replicate the resulting state.
- Run-earned progression should be awarded from a canonical run-resolution path, not from scattered ad hoc triggers.
- The `War Table` should unlock systems by setting explicit persistent flags or node states, not by inferring unlocks from scene composition.
- The Phase 1 backend currently stores this data in `user://meta_progression.json`.
- The Phase 1 UI surfaces the War Table tree and Drill Hall summary without implementing later stations yet.

## UI And Scene Guidance

- Each major progression system should exist as a physical interactable station in `hub.tscn`.
- Locked stations may exist visually before activation, but should communicate a locked state and unlocking source.
- The `War Table` tree can be presented as a dedicated overlay or panel, but the station should still exist physically in the hub world.
- Prefer thin station scene scripts that delegate to centralized systems for progression logic and persistence.

## Recommended Implementation Order

1. Add a persistent meta-progression data model that survives game restarts and scene changes.
2. Implement a generic `War Table` node graph system with hidden, visible, and unlocked node states.
3. Add a canonical run-resolution payout path that can distribute long-term rewards.
4. Implement `Drill Hall` and `Castle XP` first.
5. Implement `Bounty Board` second.
6. Implement `Quartermaster` third.
7. Implement `Chapel of Pacts` fourth.
8. Implement `Artificer's Forge` fifth.
9. Implement `Relic Archive` last.

## First Slice Recommendation

The first production slice should include:

- persistent meta-progression save data
- `War Table` station
- a small `Campaign` root cluster
- one real station unlock branch: `Doctrine`
- one working downstream station: `Drill Hall`
- placeholder hidden nodes and placeholder station locks for the later branches

This slice establishes the architecture without forcing all downstream systems to be complete immediately.

## Phase 1 Execution Spec

This section breaks the first production slice into concrete implementation tasks for future agents.

### Phase 1 Goal

Ship the minimum viable permanent progression loop:

- the player can interact with the `War Table` in the hub
- the `War Table` shows a small root cluster plus hidden future branches
- successful castle runs award baseline progression currency
- the player can unlock the `Doctrine` station path from the `War Table`
- the `Drill Hall` becomes interactable once unlocked
- castle runs award `Castle XP` only after `Doctrine` is unlocked

### Phase 1 Deliverables

- persistent meta-progression save data that survives game restart
- a `War Table` world station in the hub
- a `War Table` UI or overlay for node browsing and unlocks
- a small authored node graph for:
  - root `Campaign` nodes
  - one `Doctrine` branch
  - placeholder hidden branches for later systems
  - distant visible `Roll Credits` node
- a canonical run-result reward hook for long-term progression payouts
- a locked `Drill Hall` world station that becomes usable after unlock
- a first-pass `Castle XP` and specialization-point backend

### Recommended Runtime Ownership

- `HubManager` should remain the authority entrypoint for hub station interactions.
- `DungeonManager` should remain the authority entrypoint for run completion and reward payout triggers.
- A new progression-focused system should own persistent meta data and reward application instead of overloading `GameState`.
- `GameState` should continue handling scene-transition state unless and until a broader save architecture replaces it.

### Recommended New Systems

These names are recommended implementation targets, not finalized file locks.

- `boomer-shooter/Scripts/System/meta_progression_state.gd`
  - in-memory runtime representation of permanent progression data
- `boomer-shooter/Scripts/System/meta_progression_store.gd`
  - disk save and load wrapper for permanent progression data
- `boomer-shooter/Scripts/System/war_table_graph.gd`
  - graph resource or helper for node definitions and unlock rules
- `boomer-shooter/Scripts/UI/war_table_menu.gd`
  - UI surface for the `War Table`
- `boomer-shooter/Scripts/Props/war_table.gd`
  - interactable station hook in the hub
- `boomer-shooter/Scripts/Props/drill_hall_station.gd`
  - interactable station hook for `Drill Hall`

If the project later gains a more general profile or save system, fold these responsibilities into that system rather than duplicating persistence logic.

### Recommended Data Shape For Phase 1

The Phase 1 persistent payload should stay narrow:

- `currencies`
  - baseline war-table currency only
- `war_table`
  - unlocked node ids
  - discovered node ids
  - visible node ids if discovery is stored explicitly
- `hub_station_unlocks`
  - at minimum `war_table` and `drill_hall`
- `castle_xp`
  - current level
  - current xp
  - unspent specialization points
- `milestones`
  - optional flags for first clear or later migration hooks

Do not add contracts, faction favor, forge state, vendor inventory, or relic sets to the live save schema during Phase 1 unless implementation actually needs placeholders.

### War Table Phase 1 Node Set

The first node graph should be intentionally small.

- Root visible nodes:
  - one free or very cheap introduction node
  - one baseline currency-efficiency or reward node
  - one path-leading node that points toward `Doctrine`
- Doctrine path:
  - one prerequisite node
  - one `Unlock Drill Hall` node
  - one or two small follow-up nodes if the UI needs the branch to feel non-trivial
- Future placeholders:
  - hidden anchor nodes for `Contracts`, `Black Market`, `Pacts`, `Forgecraft`, and `Relics`
  - visible but inaccessible `Roll Credits`

The first graph should prove hidden-node reveal logic without requiring a giant content-authoring pass.

### Hub Scene Tasks

1. Add a physical `War Table` station to [hub.tscn](J:/BoomerShooter/boomer-shooter/Scenes/World/hub.tscn).
2. Add a physical but locked `Drill Hall` station or placeholder interactable to [hub.tscn](J:/BoomerShooter/boomer-shooter/Scenes/World/hub.tscn).
3. Route both interactions through [hub_manager.gd](J:/BoomerShooter/boomer-shooter/Scripts/World/hub_manager.gd).
4. Locked stations should surface why they are locked and which `War Table` path unlocks them.

Do not add the other future stations to the first slice unless their visual placeholders materially help the hub layout.

### Run Reward Hook Tasks

1. Identify the canonical success path in [dungeon_manager.gd](J:/BoomerShooter/boomer-shooter/Scripts/Dungeon/dungeon_manager.gd).
2. Add one authoritative post-run payout function for long-term progression rewards.
3. Award only:
   - baseline `War Table` currency on successful completion
   - `Castle XP` if `Doctrine` is already unlocked
4. Keep reward shaping simple in Phase 1:
   - no rarity tiers
   - no shrine bonuses
   - no contract multipliers
   - no vendor currency yet

If a clean success path does not exist yet, create one explicit path rather than scattering progression rewards across multiple exits.

### UI Tasks

1. Build a focused `War Table` menu rather than mixing the graph into the existing HUD.
2. The menu should support:
   - current currency display
   - node selection
   - hidden versus visible versus unlocked state rendering
   - unlock confirmation
   - unlock failure messaging when requirements are not met
3. The menu should show `Roll Credits` in the distance from the start.
4. `Drill Hall` can use a very small temporary UI in Phase 1:
   - current level
   - current xp
   - unspent points
   - placeholder specialization categories if spending is not fully implemented yet

Phase 1 should prove the architecture first; it does not need final art or a finished sprawling presentation.

### Multiplayer Rules For Phase 1

- Hub station unlock attempts should resolve on the host.
- The resulting persistent progression state should replicate or otherwise refresh correctly for connected clients in the hub.
- Run-completion rewards should be granted only once from the authoritative dungeon outcome.
- Do not let each client independently grant permanent rewards to itself.

If multiplayer persistence is too large for the first slice, the minimum acceptable fallback is:

- host-authoritative unlock and reward logic
- hub refresh so both peers see unlocked stations during the same session
- explicit documentation of any restart or client-join limitations

### Validation Targets For Phase 1

At minimum, validate the following:

1. Progression save data persists across closing and relaunching the game.
2. `War Table` unlocks remain unlocked after restart.
3. `Drill Hall` remains locked until the relevant `War Table` node is purchased.
4. Castle completion awards baseline progression currency once per successful run.
5. `Castle XP` does not award before `Doctrine` unlock and does award after unlock.
6. In multiplayer, only the host resolves the permanent reward and station unlock outcome.

No automated verifier exists yet for meta progression, so the first slice will likely need targeted manual validation plus any focused script-level tests that are practical.

### Phase 1 Out Of Scope

- contracts
- vendor inventory and refresh logic
- shrine spawning and faction favor
- item forging
- relic set collection
- final endgame win condition
- fully authored sprawling `War Table` content
- final station art pass

### Recommended Build Order Inside Phase 1

1. Add meta-progression save and load support.
2. Add `War Table` graph definitions and unlock evaluation.
3. Add hub `War Table` station and menu.
4. Add post-run baseline currency payout.
5. Add `Doctrine` unlock path and locked `Drill Hall` station.
6. Add `Castle XP` backend and simple `Drill Hall` UI.
7. Validate persistence and multiplayer authority behavior.

### Suggested Follow-Up After Phase 1

Phase 2 should likely implement `Bounty Board` next, because it adds replay variation without forcing a full economy, crafting, or faction layer.

## Safe Edit Guidance

- Keep this document synchronized with implementation progress; move finished behavior into the relevant runtime docs once it becomes real.
- When adding persistent data, also update `system-singletons-and-state.md` or any eventual save-system documentation.
- When adding hub stations, also update `hub-workflow-and-persistence.md`, `world-interactions-and-props.md`, and `ui-and-player-experience.md` as appropriate.
- When adding multiplayer-facing progression state, update `networking-and-replication.md` with the authority model and verification expectations.
- Avoid documenting planned node names or currencies in multiple places unless they are intentionally finalized.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [hub-workflow-and-persistence.md](hub-workflow-and-persistence.md)
- [system-singletons-and-state.md](system-singletons-and-state.md)
- [ui-and-player-experience.md](ui-and-player-experience.md)
- [world-interactions-and-props.md](world-interactions-and-props.md)
