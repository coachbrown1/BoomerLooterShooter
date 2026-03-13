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

## 7. Multiplayer TODOs

- [ ] Fix client-side enemy animation playback in co-op. Current state: enemy movement/state replication works, but clients still intermittently see static/non-updating enemy visuals.
