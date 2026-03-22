# UI And Player Experience

## Purpose

Describe the UI surfaces that players actually interact with during a run, including HUD, inventory, pause flow, and the hub dungeon-config menu.

## Key Files

- `boomer-shooter/Scripts/UI/hud.gd`
- `boomer-shooter/Scripts/UI/war_table_menu.gd`
- `boomer-shooter/Scripts/UI/drill_hall_panel.gd`
- `boomer-shooter/Scripts/UI/inventory_slot_button.gd`
- `boomer-shooter/Scripts/UI/inventory_world_drop_target.gd`
- `boomer-shooter/Scripts/UI/dungeon_config_menu.gd`
- `boomer-shooter/Scripts/UI/victory_screen.gd`
- `boomer-shooter/Scenes/UI/hud.tscn`
- `boomer-shooter/Scenes/UI/victory_screen.tscn`
- `boomer-shooter/Scripts/Player/player.gd`

## Main Data Flow

- The local player initializes HUD integration in `Player._init_hud()`.
- `hud.gd` is a large runtime-built UI controller rather than a thin static scene script.
- HUD responsibilities include:
  - health and ammo display
  - mobility status
  - teammate and session-role indicators
  - world-item tooltip
  - center status prompt
  - toast stack
  - inventory panel and chest section
  - pause menu and display settings
- Inventory UI is driven from `InventorySystem` snapshots and slot refs, with drag or move interactions delegated back into inventory logic rather than implemented as independent UI state.
- `DungeonConfigMenu` is created dynamically by `HubManager` when the local player interacts with the portal.
- `WarTableMenu` is created dynamically by `HubManager` when the local player interacts with the War Table station.
- `DrillHallPanel` is a dedicated summary panel inside the War Table menu for Castle XP and specialization progress.

## Important State And Resources

- HUD caches local and teammate player references for refresh loops.
- Inventory UI mirrors the four underlying storage sections:
  - equipment
  - weapons
  - storage
  - chest
- HUD iconography is loaded from generated UI atlas textures and runtime asset paths.
- The pause menu currently includes resolution and fullscreen controls directly in the HUD layer.

## Multiplayer/Authority Notes

- UI should primarily represent local or already-replicated state, not invent authoritative state.
- Teammate and session-role UI are derived from network player/session state.
- Shared chest UI is only the front end for replicated chest state; authoritative data still lives in world and inventory systems.
- War Table progression UI reads from the `MetaProgression` autoload and should remain a thin surface over persistent state.
- World-item tooltips and pickup toasts should respect local ownership so both peers do not present duplicate interactions.

## Safe Edit Guidance

- Keep inventory rules in `InventorySystem`; use UI scripts to present and route actions, not to define slot legality.
- For new HUD modules, confirm whether the data source is local-only, replicated, or host-authoritative before adding polling or signals.
- Because `hud.gd` is broad, isolate edits to one subsection when possible instead of mixing unrelated HUD changes together.
- For interaction prompts tied to world objects, trace the flow through player interaction code and the relevant world manager.

## Related Docs

- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
- [world-interactions-and-props.md](world-interactions-and-props.md)
