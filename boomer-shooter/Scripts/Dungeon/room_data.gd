extends RefCounted
class_name RoomData

enum RoomType { START, NORMAL, EXIT, SPECIAL }

var id: int = 0
var lattice_coord: Vector2i = Vector2i(-1, -1)
var grid_rect: Rect2i		# tile coordinates (x, y, w, h)
var room_type: RoomType = RoomType.NORMAL
var connected_to: Array = []	# Array of int room IDs
var theme_tag: String = "standard"
var reserved_tiles: Array = []	# Array of Vector2i
var corridor_ids: Array = []	# Array of int
var doorway_ids: Array = []	# Array of int
var doorway_candidates: Array = []	# Array of { "tile", "orientation", "wall_line_key" }
var doorway_walls: Array = []	# Array of String: "north", "south", "east", "west"
var assigned_scene: PackedScene = null
var assigned_scene_path: String = ""
var assigned_scene_role: String = "default"
var chosen_rotation_degrees: int = 0
# Deprecated compatibility fields kept so legacy non-runtime scripts still parse
# during the cutover. The active dungeon path uses the assigned_* fields above.
var has_handcrafted_layout: bool = false
var handcrafted_scene: PackedScene = null
var handcrafted_scene_path: String = ""
var surface_profile := {
	"floor_variant": 0,
	"wall_variant": 0,
	"ceiling_variant": 0,
}

func get_center_tile() -> Vector2i:
	return Vector2i(
		grid_rect.position.x + grid_rect.size.x / 2,
		grid_rect.position.y + grid_rect.size.y / 2
	)

func get_world_center(tile_size: float) -> Vector3:
	var c = get_center_tile()
	return Vector3(c.x * tile_size, 0.0, c.y * tile_size)
