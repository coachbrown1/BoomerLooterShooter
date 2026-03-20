# Enemies And Rosters

## Purpose

Document the enemy script hierarchy, the role of roster resources, and the conventions that determine how new enemy types should fit into dungeon encounters.

## Key Files

- `boomer-shooter/Scripts/Enemies/enemy_base.gd`
- `boomer-shooter/Scripts/Enemies/enemy_melee.gd`
- `boomer-shooter/Scripts/Enemies/enemy_ranged.gd`
- `boomer-shooter/Scripts/Enemies/enemy_chaser.gd`
- `boomer-shooter/Scripts/Enemies/death_knight_boss.gd`
- `boomer-shooter/Scripts/Data/enemy_roster_data.gd`
- `boomer-shooter/Data/enemies/fallback_enemy_roster.tres`
- `boomer-shooter/Scenes/Enemies/`
- `boomer-shooter/Scripts/Systems/encounter_system.gd`

## Main Data Flow

- `EncounterSystem` selects enemy scenes from biome data or the fallback roster and instantiates them into dungeon rooms.
- `EnemyBase` provides the shared runtime contract:
  - health and hitbox wiring
  - target selection
  - room-aware aggro behavior
  - authoritative state machine
  - network proxy mode and snapshot application
  - billboard animation coordination
- `EnemyMelee` mostly specializes `_execute_attack()` to damage the player when in range.
- `EnemyRanged` specializes movement to keep distance and spawns projectile scenes during attacks.
- Specific enemy scripts such as goblins, cultists, fungi, or bosses tune exports and override behavior on top of the shared base classes.
- `DeathKnightBoss` is a notable exception: it implements a larger custom state machine with phases, dash logic, beam attacks, and bespoke proxy state.

## Important State And Resources

- Common enemy tuning exports include:
  - movement speed
  - attack damage and range
  - aggro and windup timing
  - base health
  - spawn cost
  - minimum floor
- `EnemyRosterData` is intentionally simple: it is just an array of enemy scenes.
- Biome-specific enemy pools usually come from biome data, with `fallback_enemy_roster.tres` acting as a safety net.
- Enemy scene files under `Scenes/Enemies/` are the runtime prefabs consumed by encounter spawning and multiplayer replication.

## Multiplayer/Authority Notes

- Host authority owns enemy logic, damage, death, and snapshot generation.
- Clients should treat enemies as proxies unless they are the host or in single-player.
- Enemy visual animation is part of replicated enemy state in this project, so changes to billboard or attack-frame logic can affect the dedicated animation replication scenario.
- New enemy behavior should define how it serializes into the existing snapshot model, or explicitly extend that model if needed.

## Safe Edit Guidance

- Start from the nearest shared base class before creating one-off logic in a concrete enemy.
- If a new enemy needs custom movement or attacks, keep shared replication and death behavior aligned with `EnemyBase` unless there is a strong reason not to.
- When changing spawn cost or min-floor behavior, remember `EncounterSystem` uses those fields to build its budgeted spawn pool.
- If you add a new enemy family, update the relevant biome enemy scenes or fallback roster resource rather than relying on code-only discovery.

## Related Docs

- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
- [projectiles-and-area-effects.md](projectiles-and-area-effects.md)
- [dungeon-generation-and-world.md](dungeon-generation-and-world.md)
- [networking-and-replication.md](networking-and-replication.md)
