# AI Agent Rules

This file is the canonical instruction set for any AI agent working in this repository, including Codex, Claude, Gemini, and similar tools. Apply these rules across the entire repo, including the Godot project under `boomer-shooter/`.

## 1. Git And Branch Safety

- Before doing any work, sync remote state first:
  - Run `git fetch origin`.
  - Inspect the current branch and worktree with `git status --short --branch`.
  - Check whether the branch is ahead, behind, or diverged before editing files.
- If the worktree is clean and the current branch is behind its remote, update from remote before making changes.
- If local uncommitted changes, conflicts, or branch divergence make an update risky, stop and report the state instead of forcing a pull, merge, or rebase.
- Never use destructive Git commands such as `git reset --hard`, `git checkout --`, force-push, or history rewriting unless the user explicitly asks for them.
- Never overwrite, revert, or discard changes you did not make unless the user explicitly instructs you to do so.

## 2. Explore Before Editing

- Read the relevant files and nearby code before proposing or making changes. Do not edit from prompt assumptions alone.
- Check for existing guidance first, especially `AGENTS.md`, project docs, `.Jules` notes, and surrounding code patterns.
- Prefer targeted searches and targeted reads over broad sweeps.
- Do not invent APIs, file names, gameplay rules, or architecture when the repository already provides a source of truth.

## 3. Scope And Change Discipline

- Keep changes narrowly scoped to the requested task.
- Avoid opportunistic refactors unless they are required to complete the task safely.
- Prefer making one coherent change set instead of mixing unrelated cleanup into the same work.
- For large, cross-cutting, or high-risk work, make a plan before editing. Small localized changes can proceed after inspection.
- Preserve existing project conventions, including naming, directory structure, asset organization, and Godot-specific patterns already used in the repo.
- Change generated files, imported assets, or binary files only when necessary, and mention those changes explicitly in the handoff.

## 4. Validation Expectations

- Validate with the smallest relevant check available for the change.
- Run targeted tests first when the repo provides them.
- If no targeted tests exist, run the most relevant project check available.
- When fixing a bug, verify the actual code path and likely repro path before and after the change when feasible.
- When adding behavior, add or update focused tests where practical instead of relying only on reasoning.
- If validation cannot be run, say so clearly and explain why.

## 5. Communication And Handoff

- Surface blockers early: risky Git state, missing assets, unclear intent, failing tests, or inability to validate.
- State assumptions when they affect implementation decisions.
- When a task is complete, ask the user whether they want the completed changes committed and pushed.
- If you prepare a commit, include only files changed by the work you performed.
- If `git status` includes files you did not modify, do not include those files in the commit. Leave them in the changelist untouched and mention them in the handoff when relevant.
- In the final handoff, report:
  - what changed
  - how it was validated
  - any risks, assumptions, or unverified areas
- Inspect `git status` again before handoff so the reported change set matches the actual repo state.

## 6. Practical Best Practices

- Prefer safe, reversible edits over clever shortcuts.
- Match existing style and patterns before introducing new ones.
- Do not broaden task scope without a clear reason tied to correctness, safety, or requested outcomes.
- If repo instructions conflict, follow the more specific instruction for the files or subsystem you are changing.

## 7. Multiplayer and Replication

- This is a co-op game. All gameplay features, state changes, and visual effects must be appropriately replicated across the network.
- Use Godot's multiplayer synchronization systems (MultiplayerSynchronizer, RPCs) and ensure that gameplay-critical logic is server-authoritative.
- When building or modifying a feature, always consider how it will behave for both the host and connected clients.

## 8. Multiplayer TODOs

- [ ] Fix client-side enemy animation playback in co-op. Current state: enemy movement/state replication works, but clients still intermittently see static/non-updating enemy visuals.

## 9. Multiplayer Verification Harness

- Generalized runner:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario '<scenario>'
  ```
- Current supported scenarios:
  - `spawn-floor-stability`
  - `player-replication`
  - `player-health-replication`
  - `client-disconnect`
  - `door-replication`
  - `weapon-state-sync`
  - `weapon-visual-replication`
  - `projectile-damage-replication`
  - `enemy-damage-replication`
  - `enemy-death-replication`
  - `enemy-animation-replication`
  - `long-run-soak`
  - `shared-chest`
- For multiplayer chest/inventory sync work, prefer the local automated harness before relying on reasoning alone.
- Run the harness from the workspace root with:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_chest_verifier.ps1'
  ```
- What it does:
  - launches a local headless host and client
  - auto-connects and auto-starts the match
  - opens the same chest on both peers
  - moves one item from the chest on the host
  - verifies the client sees the same updated chest contents
- Expected success output:
  - `Multiplayer chest verification PASS`
- For the client-startup floor regression, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'spawn-floor-stability'
  ```
- What `spawn-floor-stability` does:
  - launches a local headless host and client
  - waits for match start and floor sync
  - verifies each peer gets a local player
  - samples the player's Y position and floor contact during the initial settle window
  - fails if the client never stabilizes on the floor or drops too far below its spawn point
- For player roster and snapshot replication, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'player-replication'
  ```
- What `player-replication` does:
  - launches a local headless host and client
  - verifies both peers see a two-player roster
  - validates local versus remote player ownership flags in the roster snapshot
  - forces a client movement update and confirms the host receives it
  - forces a host movement update and confirms the client receives it
- For authoritative player health replication, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'player-health-replication'
  ```
- What `player-health-replication` does:
  - launches a local headless host and client
  - has the host apply authoritative damage to the client-owned player
  - confirms the host keeps the damaged health value instead of being overwritten by a client snapshot
  - confirms the client local player converges to the replicated authoritative health
- For client disconnect cleanup, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'client-disconnect'
  ```
- What `client-disconnect` does:
  - launches a local headless host and client
  - has the client leave the session through `NetworkSession.leave_game()`
  - confirms the host removes the disconnected peer's player and shrinks the roster to one player
- For door interaction replication, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'door-replication'
  ```
- What `door-replication` does:
  - launches a local headless host and client
  - has the client request a door interaction through the normal multiplayer interaction path
  - confirms the authoritative host opens the matched door
  - confirms the client receives the replicated open state for that same door
- For authoritative weapon fire/reload state sync, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'weapon-state-sync'
  ```
- What `weapon-state-sync` does:
  - launches a local headless host and client
  - switches the client to a finite-ammo weapon
  - validates one authoritative fire request updates weapon mag state on both peers
  - validates one authoritative reload request restores the expected mag state on both peers
- For replicated weapon visual effects, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'weapon-visual-replication'
  ```
- What `weapon-visual-replication` does:
  - launches a local headless host and client
  - has the host fire a hitscan weapon and then a projectile weapon
  - confirms the client observes the replicated hitscan visual spawn
  - confirms the client observes the replicated projectile visual spawn
- For authoritative projectile damage replication, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'projectile-damage-replication'
  ```
- What `projectile-damage-replication` does:
  - launches a local headless host and client
  - has the client fire a host-authoritative fireball at a live networked enemy
  - confirms the host observes projectile damage or kill on that enemy
  - confirms the client proxy converges on the same replicated health/death outcome
- For authoritative enemy damage replication, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'enemy-damage-replication'
  ```
- What `enemy-damage-replication` does:
  - launches a local headless host and client
  - has the client send a host-authoritative rifle fire request against a live networked enemy
  - confirms the host observes enemy health drop from that fire request
  - confirms the client proxy converges on the same replicated enemy health result
- For authoritative enemy death/despawn replication, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'enemy-death-replication'
  ```
- What `enemy-death-replication` does:
  - launches a local headless host and client
  - has the client kill a live networked enemy through the host-authoritative rifle fire path
  - confirms the host observes both enemy death and later despawn
  - confirms the client sees the replicated death state before the proxy is removed
- For enemy animation replication, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'enemy-animation-replication'
  ```
- What `enemy-animation-replication` does:
  - launches a local headless host and client
  - samples the same replicated enemy on both peers over a short window
  - confirms enemy visual animation activity is present on the host sample
  - confirms the client proxy also exhibits replicated frame or animate-state changes
- For a long-running multiplayer stability pass, run:
  ```powershell
  & 'J:\BoomerShooter\boomer-shooter\Scripts\Debug\run_multiplayer_verifier.ps1' -Scenario 'long-run-soak'
  ```
- What `long-run-soak` does:
  - launches a local headless host and client
  - keeps the session alive for an extended sample window
  - verifies both peers retain valid local/remote players throughout the run
  - verifies player replication and enemy replication continue producing updates during the soak
- Harness artifacts are written under `boomer-shooter/.tmp/mp_verify_*`.
- If the harness fails, inspect `launcher.log`, `host.log`, `host.err.log`, `client.log`, `client.err.log`, and any `*_error.json` files in that run directory.
- Current automated coverage includes client spawn/floor stability, player roster/snapshot replication, player health replication, client disconnect cleanup, door interaction replication, weapon fire/reload state sync, replicated weapon visual effects, authoritative projectile damage replication, authoritative enemy damage replication, enemy death/despawn replication, enemy animation replication, a long-run multiplayer soak pass, and shared chest loot/chest sync behavior. It does not validate all multiplayer systems.
