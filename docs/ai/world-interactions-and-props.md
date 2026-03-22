# World Interactions And Props

## Purpose

Document the non-enemy world objects that players interact with and the managers that mediate those interactions in hub and dungeon scenes.

## Key Files

- `boomer-shooter/Scripts/World/hub_manager.gd`
- `boomer-shooter/Scripts/Dungeon/dungeon_manager.gd`
- `boomer-shooter/Scripts/Environment/interactable_chest.gd`
- `boomer-shooter/Scripts/Props/loot_pickup.gd`
- `boomer-shooter/Scripts/Props/portal.gd`
- `boomer-shooter/Scripts/Props/war_table_station.gd`
- `boomer-shooter/Scripts/Dungeon/door.gd`
- `boomer-shooter/Scripts/Props/*.gd`
- `boomer-shooter/Scenes/Props/`

## Main Data Flow

- Hub and dungeon scenes each have a world manager that acts as the interaction authority.
- `Portal` is a simple signal emitter; hub flow is owned by `HubManager`, not the portal itself.
- `WarTableStation` is the hub's first long-term progression interactable and emits a hub-side signal when used.
- `InteractableChest` owns lid animation and storage payloads, but the inventory and world managers control when chest state is opened, moved, and synchronized.
- `LootPickup` can represent three classes of pickup:
  - item/gear
  - ammo
  - health
- Ammo and health pickups auto-collect on collision with the locally controlled player. Gear stays interaction-based.
- World managers receive pickup requests and resolve authoritative spawn, pickup, and despawn behavior.
- `DungeonDoor` is an interactable world gate with open state and collision disablement, but multiplayer open-state propagation is handled by dungeon networking flow.

## Important State And Resources

- `HubManager` belongs to the `world_item_drop_manager` group and also handles network loot spawning in the hub.
- `WarTableStation` belongs to the `interactable` and `war_table_station` groups so the player raycast and hub manager can discover it.
- `DungeonManager` maintains network IDs for spawned enemies and loot pickups in the dungeon.
- `InteractableChest` uses deterministic seeded loot generation for non-hub chests based on chest identity and current dungeon seed.
- `LootPickup.get_item_snapshot()` produces a UI-friendly or wire-friendly payload depending on pickup type.
- Gear `LootPickup` visuals now keep the icon untinted and use a separate rarity-colored beacon effect so item art stays readable while rarity remains visible in-world.
- `LootPickup` landing now resolves against actual support below the drop and continues falling when there is no floor directly underneath, so drops can fall off ledges instead of freezing in mid-air.
- Common dungeon filler props such as `prop_crate.tscn` and `prop_barrel.tscn` now instance Blender-authored `.glb` assets from `boomer-shooter/Assets/Props/Common/` instead of generating visuals procedurally in script.
- Blocking prop collision for those common props lives under a `StaticBody3D` child in the prop scene, not as a loose `CollisionShape3D` under the visual root.

## Multiplayer/Authority Notes

- Remote physics bodies should not be allowed to locally finalize pickups on both machines. `LootPickup` already gates auto-pickup to the locally controlled player.
- Chest state, loot pickup despawn, and dungeon door open state should be treated as shared world state with host authority.
- If a new interactable affects shared progression or inventory, route it through the relevant world manager rather than leaving it as a fully local scene-node interaction.

## Safe Edit Guidance

- Keep world interaction authority in `HubManager` or `DungeonManager` for shared gameplay state.
- Use props for presentation and local interaction hooks, but centralize replicated outcomes in the active world manager.
- When adding a new pickup or interactable type, check HUD/tooltips, inventory integration, and replication behavior together.
- For chest changes, remember hub chests and dungeon/randomized chests have different persistence rules.
- If a prop visual change affects the crate or barrel mesh path, regenerate the Blender source in `Art Generators/create_prop_assets.py` and re-export the `.glb` files instead of rebuilding those props in GDScript.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
- [networking-and-replication.md](networking-and-replication.md)
