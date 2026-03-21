## GameState — static singleton persisting player and hub data across scene loads.
## No autoload registration needed; Godot parses class_name scripts automatically.
class_name GameState

## Full inventory snapshot (equipment / weapons / storage) captured on each scene transition.
static var player_inventory_snapshot: Dictionary = {}

## Saved contents of the three hub storage chests (array of item-dict arrays).
static var hub_chest_snapshots: Array = [[], [], []]

## True once the player has left the hub at least once (prevents re-applying starter
## inventory on every hub visit).
static var initialized: bool = false

## Dungeon generation config set via the hub portal menu.
static var dungeon_grid_min: int = 10
static var dungeon_grid_max: int = 10
static var dungeon_seed: int = 0
