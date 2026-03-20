# Components, Effects, And Lighting

## Purpose

Describe the shared low-level gameplay components and the smaller visual systems that many combat and world scenes compose together.

## Key Files

- `boomer-shooter/Scripts/Components/health_component.gd`
- `boomer-shooter/Scripts/Components/hitbox_component.gd`
- `boomer-shooter/Scripts/Components/billboard_sprite.gd`
- `boomer-shooter/Scripts/Effects/blood_splatter.gd`
- `boomer-shooter/Scripts/Effects/bullet_hole.gd`
- `boomer-shooter/Scripts/Effects/mage_hazard_pool.gd`
- `boomer-shooter/Scripts/Lighting/flicker_light.gd`
- `boomer-shooter/Scripts/Environment/torch_vfx.gd`
- `boomer-shooter/Scripts/Environment/fungal_prop_vfx.gd`

## Main Data Flow

- `HealthComponent` is the shared health primitive for damageable actors. It owns current and max health plus `health_changed` and `died` signals.
- `HitboxComponent` is a lightweight forwarding surface that routes incoming damage into a referenced `HealthComponent`.
- `BillboardSprite` provides enemy or prop sprite presentation rules:
  - fixed-Y billboard behavior
  - simple frame animation
  - bounce-walk mode
  - local duplication of outline materials so scenes do not mutate shared resources in-editor
- Effects scripts are generally self-contained scene behaviors that configure visuals at spawn time and then clean themselves up.
- Lighting/VFX helper scripts mostly modify child nodes and materials rather than owning gameplay state.

## Important State And Resources

- `HealthComponent` is intentionally minimal; actor-specific authority and death consequences live in higher-level scripts such as `Player`, `EnemyBase`, or world managers.
- `BillboardSprite` uses node properties like `hframes`, `vframes`, `frame`, `animate`, and `base_y` to drive sprite-sheet behavior.
- `MageHazardPool` is both a visual effect and a gameplay hazard because it ticks player damage over time.
- `FlickerLight`, `torch_vfx.gd`, and `fungal_prop_vfx.gd` are reusable scene embellishment scripts that make authored scenes feel alive without needing manager-level logic.

## Multiplayer/Authority Notes

- Shared components should stay authority-agnostic where possible; authority decisions belong in the owning actor or manager.
- Visual effect scripts are usually local presentation, but anything that applies gameplay damage, collision, or shared timing must still respect the project’s host-authoritative model.
- `BillboardSprite` interacts with enemy animation replication because host snapshots may need to drive proxy frame state on clients.

## Safe Edit Guidance

- Keep `HealthComponent` and `HitboxComponent` generic. Do not bake player-only or enemy-only policy into them unless the project explicitly standardizes on it.
- When changing `BillboardSprite`, verify that enemy proxy visuals and editor preview behavior still work.
- Separate cosmetic-only effect changes from gameplay-affecting hazard changes.
- Avoid mutating shared material resources from effect or billboard scripts unless the resource is duplicated locally first.

## Related Docs

- [combat-actors-and-weapons.md](combat-actors-and-weapons.md)
- [world-interactions-and-props.md](world-interactions-and-props.md)
- [networking-and-replication.md](networking-and-replication.md)
