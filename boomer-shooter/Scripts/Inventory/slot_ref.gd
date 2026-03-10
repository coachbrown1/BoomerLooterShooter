extends RefCounted
class_name SlotRef

var section: StringName = &""
var index: int = -1
var slot_name: StringName = &""

static func equipment(slot_name_value: StringName) -> SlotRef:
	var ref := SlotRef.new()
	ref.section = &"equipment"
	ref.slot_name = slot_name_value
	return ref

static func weapon(slot_index: int) -> SlotRef:
	var ref := SlotRef.new()
	ref.section = &"weapons"
	ref.index = slot_index
	return ref

static func storage(slot_index: int) -> SlotRef:
	var ref := SlotRef.new()
	ref.section = &"storage"
	ref.index = slot_index
	return ref

func is_equal(other: SlotRef) -> bool:
	if other == null:
		return false
	return section == other.section and index == other.index and slot_name == other.slot_name

func to_key() -> String:
	if section == &"equipment":
		return "equipment:%s" % String(slot_name)
	return "%s:%d" % [String(section), index]
