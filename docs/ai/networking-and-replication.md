# Networking And Replication

## Purpose

Document the session lifecycle, player replication model, and host-authoritative world sync rules used by the project.

## Key Files

- `boomer-shooter/project.godot`
- `boomer-shooter/Scripts/Networking/network_session.gd`
- `boomer-shooter/Scripts/Networking/network_player_manager.gd`
- `boomer-shooter/Scripts/Networking/network_bootstrap.gd`
- `boomer-shooter/Scripts/World/hub_manager.gd`
- `boomer-shooter/Scripts/Dungeon/dungeon_manager.gd`
- `boomer-shooter/Scripts/Debug/multiplayer_verifier.gd`
- `boomer-shooter/Scripts/Debug/run_multiplayer_verifier.ps1`
- `boomer-shooter/Scripts/Debug/run_multiplayer_chest_verifier.ps1`

## Main Data Flow

- `NetworkSession` owns ENet session lifecycle:
  - host game
  - join game
  - leave game
  - start match
  - peer connect and disconnect signals
- Bootstrap listens to `NetworkSession` signals to update menu state and change into the active scene.
- `NetworkPlayerManager` is an autoload that exists across scenes and is responsible for:
  - spawning players for the current roster
  - keeping a peer_id to player dictionary
  - syncing the roster to clients
  - broadcasting player snapshots from the host
  - forwarding client mobility requests to the host
- During multiplayer:
  - clients submit their local player snapshot to peer 1
  - the host applies allowed fields to the authoritative player node
  - the host broadcasts authoritative snapshots back to every client
- World managers handle non-player replicated state:
  - `HubManager` handles hub world loot interactions and dungeon-entry RPC flow
  - `DungeonManager` handles floor sync, enemy snapshots, loot pickup replication, chest sync, weapon state sync, and other dungeon-scoped replication

## Important State And Resources

- `NetworkSession` state:
  - `_peer`
  - `_host`
  - `_active`
  - `_match_started`
- `NetworkPlayerManager` state:
  - `_player_by_peer_id`
  - `_spawn_positions`
- Important session signals:
  - `session_started`
  - `peer_joined`
  - `peer_left`
  - `match_started`
  - `session_ended`
  - `connection_failed`
- `project.godot` autoloads:
  - `NetworkSession`
  - `NetSession`
  - `NetworkPlayerManager`
  - `GlobalEventBus`

## Authority Model

- Host authority is the default for gameplay-critical state.
- `NetworkSession.start_match()` only succeeds on the host and only after a client is connected.
- `NetworkPlayerManager.rpc_npm_submit_state()` strips client-owned snapshots of `health` and `mobility` before applying them on the host.
- Host snapshots send authoritative health and mobility back to the local owner as well as remote peers.
- Clients request host action for mobility abilities, weapon fire or reload, door interactions, chest changes, and loot interactions rather than applying those outcomes locally.
- Dungeon enemies use host-generated snapshots for movement, health, state, and current animation frame so proxies do not drift.

## Verification Harness

- The main in-game verifier is `Scripts/Debug/multiplayer_verifier.gd`.
- PowerShell wrappers launch a local host and client and collect artifacts under `boomer-shooter/.tmp/mp_verify_*`.
- `AGENTS.md` is the authoritative index of supported scenarios and expected behavior.
- Existing coverage includes:
  - player replication and health
  - door interaction
  - weapon state and visual replication
  - projectile and enemy damage
  - enemy death and loot
  - shared chest sync
  - enemy animation replication
  - long-run soak

## Multiplayer/Authority Notes

- Add new gameplay features with a clear answer to: what runs on the host, what clients request, and what state gets replicated back.
- Do not let clients finalize enemy health, chest contents, world pickups, or other shared world state on their own.
- When adding visual-only replication, verify whether it still needs host coordination to keep peers in sync.
- Be careful with scene-local RPCs versus autoload RPCs. Autoload RPCs are consistent across scenes and are preferred for player/session surfaces.

## Safe Edit Guidance

- Start with `network_session.gd` for session-lifecycle bugs.
- Start with `network_player_manager.gd` for player ownership, roster, movement snapshot, and local versus remote control issues.
- Start with `hub_manager.gd` or `dungeon_manager.gd` for world-state replication issues.
- Extend the verifier whenever a change touches replicated gameplay behavior and a focused automation path is practical.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
