# Combat Actors And Weapons

## Purpose

Summarize how players, enemies, weapons, projectiles, health, hit detection, and loot drops fit together during combat.

## Key Files

- `boomer-shooter/Scripts/Player/player.gd`
- `boomer-shooter/Scripts/Player/player_mobility_controller.gd`
- `boomer-shooter/Scripts/Weapons/weapon_manager.gd`
- `boomer-shooter/Scripts/Weapons/weapon.gd`
- `boomer-shooter/Scripts/Enemies/enemy_base.gd`
- `boomer-shooter/Scripts/Enemies/*.gd`
- `boomer-shooter/Scripts/Projectiles/projectile.gd`
- `boomer-shooter/Scripts/Components/health_component.gd`
- `boomer-shooter/Scripts/Components/hitbox_component.gd`
- `boomer-shooter/Scripts/Props/loot_pickup.gd`

## Main Data Flow

- `Player` owns movement, camera, local-versus-remote control mode, HUD hookup, inventory linkage, and mobility ability delegation.
- `WeaponManager` manages the scene-local weapon nodes, ammo reserve state, slot mapping, and HUD ammo updates.
- `Weapon` handles fire cadence, reload behavior, recoil and FOV kick, hitscan or projectile spawning, and network fire requests for non-host clients.
- `EnemyBase` provides the common state machine for idle, chase, windup, attack, cooldown, and death, plus health and billboard animation handling.
- Specialized enemy scripts extend `EnemyBase` for melee, ranged, boss, or biome-specific behavior.
- Projectiles are separate scene/script units used by projectile weapons and enemy ranged attacks.
- Enemy death can produce replicated loot pickups that are later consumed by the player inventory path.

## Important State And Resources

- Player networking fields decide whether the node is the local owner or a remote proxy.
- Equipment stats can modify:
  - move speed
  - sprinting
  - jump
  - max health
  - damage reduction
  - recoil recovery
  - weapon-specific combat stats
- Weapon state includes:
  - current slot
  - current mag
  - reserve ammo snapshot
  - viewmodel visibility
- Enemy snapshots include:
  - position
  - velocity
  - AI state
  - health
  - animation frame and animate flag

## Multiplayer/Authority Notes

- Player local input runs only on the owning peer; remote players consume replicated snapshots.
- Host authority is required for health, mobility actions, enemy damage outcomes, enemy death, loot pickup spawn and despawn, and authoritative weapon state.
- Enemy client proxies use host-driven position and visual snapshots to avoid animation drift.
- Non-host weapon fire and reload paths request host action through world-manager replication hooks rather than finalizing combat outcomes locally.

## Safe Edit Guidance

- For player-input issues, inspect ownership and input gating before changing movement or weapon code.
- For combat replication issues, trace both the local weapon path and the host-authoritative world-manager path.
- For enemy behavior changes, separate AI-state edits from proxy-visual replication edits.
- If a combat change affects shared outcomes, extend or run the relevant multiplayer verifier scenario.

## Related Docs

- [networking-and-replication.md](networking-and-replication.md)
- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [inventory-gear-and-chests.md](inventory-gear-and-chests.md)
