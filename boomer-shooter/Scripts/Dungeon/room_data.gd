extends RefCounted
class_name RoomData

enum RoomType { START, NORMAL, EXIT, SPECIAL }

var id: int = 0
var grid_rect: Rect2i		# tile coordinates (x, y, w, h)
var room_type: RoomType = RoomType.NORMAL
var biome: String = "crypt"
var connected_to: Array = []	# Array of int room IDs
var theme_tag: String = "standard"
var reserved_tiles: Array = []	# Array of Vector2i
var corridor_ids: Array = []	# Array of int
var doorway_ids: Array = []	# Array of int
var doorway_candidates: Array = []	# Array of { "tile", "orientation", "wall_line_key" }
# Per-room material variants used by the builder.
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
