# Projectiles And Area Effects

## Purpose

Document the shared projectile base class, projectile-specialization pattern, and the area-effect hazards that can persist after impact.

## Key Files

- `boomer-shooter/Scripts/Projectiles/projectile.gd`
- `boomer-shooter/Scripts/Projectiles/energy_orb.gd`
- `boomer-shooter/Scripts/Projectiles/death_knight_beam.gd`
- `boomer-shooter/Scripts/Effects/mage_hazard_pool.gd`
- `boomer-shooter/Scenes/Projectiles/`
- `boomer-shooter/Scenes/Effects/fireball_explosion.tscn`

## Main Data Flow

- `Projectile` is the shared Area3D-based projectile primitive.
- Common projectile behavior includes:
  - initial direction-to-velocity setup
  - body and area collision handling
  - lifetime timeout cleanup
  - optional gravity drop
  - optional explosion damage
  - shooter filtering to prevent self-hit
- On impact, the projectile resolves a damage target by walking up the collider hierarchy until it finds:
  - a `HitboxComponent`
  - or a node with `take_damage()`
- Explosive projectiles can spawn a visual explosion and apply area damage using a shape query.
- Specialized projectile scripts override impact behavior when needed. Example:
  - `EnergyOrb` spawns a `MageHazardPool` on impact instead of using the default explosion path.

## Important State And Resources

- Core projectile state includes:
  - `direction`
  - `velocity`
  - `shooter`
  - `network_visual_only`
  - `_did_impact`
- `network_visual_only` is the key split between replicated visuals and gameplay-authoritative projectile outcomes.
- `MageHazardPool` is both VFX and gameplay because it damages players on a tick over its lifetime.

## Multiplayer/Authority Notes

- Projectile visuals may exist on clients as replicated presentation, but gameplay damage should remain host-authoritative.
- `network_visual_only` is the built-in escape hatch for rendering a synced projectile or explosion without applying duplicate damage locally.
- If a new projectile adds persistent hazards, make sure both the initial impact and the spawned hazard follow the project’s authority model.

## Safe Edit Guidance

- Keep the base `Projectile` generic. Special-case behavior should usually live in a subtype.
- When changing collision or damage target resolution, verify both direct-hit and explosion paths.
- If you add a new projectile subtype, document whether it is:
  - hitscan replacement
  - direct-hit projectile
  - explosive projectile
  - hazard-spawning projectile
- Trace interactions with enemy hitboxes, player damage, world collision, and network visual replication together.

## Related Docs

- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
- [components-effects-and-lighting.md](components-effects-and-lighting.md)
- [networking-and-replication.md](networking-and-replication.md)
