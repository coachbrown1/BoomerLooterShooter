# Inventory, Gear, And Chests

## Purpose

Describe the inventory model, generated gear data, weapon-slot integration, and chest synchronization rules used across hub and dungeon play.

## Key Files

- `boomer-shooter/Scripts/Inventory/inventory_system.gd`
- `boomer-shooter/Scripts/Inventory/inventory_item_data.gd`
- `boomer-shooter/Scripts/Inventory/slot_ref.gd`
- `boomer-shooter/Scripts/Data/gear_catalog_data.gd`
- `boomer-shooter/Scripts/Data/gear_line_data.gd`
- `boomer-shooter/Data/gear/gear_catalog.tres`
- `boomer-shooter/Scripts/Environment/interactable_chest.gd`
- `boomer-shooter/Scripts/World/hub_manager.gd`
- `boomer-shooter/Scripts/System/game_state.gd`
- `boomer-shooter/Scripts/Weapons/weapon_manager.gd`

## Main Data Flow

- Each player owns an `InventorySystem`.
- `_init_slots()` creates four inventory sections:
  - equipment slots
  - weapon slots
  - storage slots
  - chest storage when a chest is open
- `initialize_with_weapon_manager()` links inventory to `WeaponManager`, seeds a starter crossbow, and seeds starter gear if needed.
- Inventory snapshots are dictionary payloads used for:
  - hub-to-dungeon persistence
  - restoring the hub loadout after returning
  - chest synchronization payloads
- `try_move_item()` validates source and destination slots, swaps items, updates signals, and syncs active chest state when the chest section is involved.
- `WeaponManager` listens to `weapon_slots_changed` so the equipped inventory weapons determine which scene-local weapon nodes are active.

## Important State And Resources

- Equipment slots:
  - `helmet`
  - `chest`
  - `arms`
  - `legs`
  - `feet`
  - `utility_primary`
  - `utility_secondary`
- Slot counts:
  - 4 weapon slots
  - 10 player storage slots
  - 16 default chest slots
- `GearCatalogData` composes item generation from:
  - authored gear lines in `gear_catalog.tres`
  - built-in weapon definitions and rarity stats
  - rarity-weighted random generation
  - affix rolling
- `InventoryItemData` payloads are the common wire format for saves, chest sync, loot pickups, and runtime inventory state.

## Chest Behavior

- `InteractableChest` is a world object that:
  - belongs to `interactable` and `interactable_chest`
  - can lazily populate deterministic loot using `GearCatalogData`
  - opens through `InventorySystem.open_chest()`
  - exposes storage as both object copies and serializable payloads
- Hub chests are special:
  - `HubManager` renames them to storage chests
  - disables default random loot generation by setting item counts to zero
  - restores their payload from `GameState.hub_chest_snapshots`
- Dungeon or world chests can generate loot from stable chest identity plus dungeon seed.

## Multiplayer/Authority Notes

- Shared chest contents are not purely local UI state. When chest slots change, the active chest sync path must update the authoritative world state.
- Hub and dungeon chest interactions should preserve host authority over the shared payload seen by both peers.
- Inventory weapon state and chest state interact with dungeon replication and the multiplayer verifier, especially the `shared-chest` scenario.
- When changing inventory payload shapes, verify all consumers:
  - hub persistence
  - chest sync
  - loot pickups
  - weapon-manager integration

## Safe Edit Guidance

- Keep slot-section rules centralized in `inventory_system.gd`; avoid scattering inventory validity logic into UI or world scripts.
- Treat `InventoryItemData.to_dict()` and `from_dict()` compatibility as important because many systems depend on those payloads.
- If you add new stats or item types, trace through gear generation, equipment stat aggregation, HUD display, weapon stat application, and chest serialization.
- For shared-chest changes, validate with the local chest verifier before relying on reasoning alone.

## Related Docs

- [runtime-overview.md](runtime-overview.md)
- [networking-and-replication.md](networking-and-replication.md)
- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
