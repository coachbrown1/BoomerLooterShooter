# Mobility And Abilities

## Purpose

Describe the utility-item ability system that gives players dash, grapple, and jet-pack behavior, including how those abilities integrate with equipment stats, HUD state, and multiplayer authority.

## Key Files

- `boomer-shooter/Scripts/Player/player_mobility_controller.gd`
- `boomer-shooter/Scripts/Player/player.gd`
- `boomer-shooter/Scripts/Inventory/inventory_system.gd`
- `boomer-shooter/Scripts/Data/gear_catalog_data.gd`
- `boomer-shooter/Scripts/UI/hud.gd`
- `boomer-shooter/Scripts/Networking/network_player_manager.gd`

## Main Data Flow

- Mobility abilities come from equipped utility items in the inventory system.
- `Player` owns the controller instance and calls:
  - `setup()`
  - `apply_equipment()`
  - `physics_update()`
- `PlayerMobilityController` resolves the active utility abilities from equipped items and exposes three supported ability families:
  - `dash_pack`
  - `grapple_hook`
  - `jet_pack`
- The controller tracks resource and active-state timers such as:
  - dash time and cooldown
  - grapple anchor and active state
  - jet fuel and recharge delay
- The controller also emits HUD-facing state via `_refresh_hud()` and packages state for replication through `build_state_snapshot()`.

## Important State And Resources

- Utility slots are:
  - `utility_primary`
  - `utility_secondary`
- The controller stores both slot assignment and active ability metadata, including item names and rarity for HUD display.
- Equipment stats modify mobility values such as:
  - dash speed and cooldown
  - grapple range and pull speed
  - jet thrust, fuel, and recharge
  - air control
- `Player` movement logic defers to the controller for dash, grapple, and jet behavior during `_physics_process()`.

## Multiplayer/Authority Notes

- Non-host clients do not directly finalize mobility actions. `PlayerMobilityController` routes requests through `NetworkPlayerManager.request_mobility_action()`.
- The host applies authoritative actions and sends mobility state back through player snapshots.
- Mobility state is part of the replicated player state model, so edits here can affect both feel and correctness in co-op.
- Any new mobility ability should define:
  - local input behavior
  - authoritative request path
  - snapshot serialization
  - HUD presentation

## Safe Edit Guidance

- Keep raw input detection in the controller, but keep authoritative routing aligned with `NetworkPlayerManager`.
- If you add a new utility ability, update:
  - gear data/content
  - inventory equipment handling
  - controller state serialization
  - HUD status rendering
  - multiplayer verification if the ability is replicated
- Avoid mixing generic movement tuning with utility-ability rules unless both truly need to change together.

## Related Docs

- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
- [ui-and-player-experience.md](ui-and-player-experience.md)
- [networking-and-replication.md](networking-and-replication.md)
- [data-resources-and-content.md](data-resources-and-content.md)
