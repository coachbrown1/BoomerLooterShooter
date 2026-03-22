extends "res://addons/gut/test.gd"

const MetaProgressionScript = preload("res://Scripts/System/meta_progression.gd")

const TEST_SAVE_PATH := "user://test_meta_progression_roundtrip.json"

func after_each() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

func test_phase_one_graph_has_expected_visibility_and_locks() -> void:
	var progression = MetaProgressionScript.new()
	progression.reset_progression()

	assert_true(progression.is_node_visible("campaign_root_a"))
	assert_true(progression.is_node_visible("campaign_root_b"))
	assert_true(progression.is_node_visible("doctrine_primer"))
	assert_false(progression.is_node_visible("contracts_placeholder"))
	assert_false(progression.is_node_visible("black_market_placeholder"))
	assert_false(progression.is_node_visible("pacts_placeholder"))
	assert_false(progression.is_node_visible("forgecraft_placeholder"))
	assert_false(progression.is_node_visible("relics_placeholder"))
	assert_true(progression.is_node_visible("roll_credits"))

	assert_false(progression.can_unlock_node("roll_credits"))
	assert_false(progression.can_unlock_node("campaign_root_a"))
	assert_false(progression.can_unlock_node("unlock_drill_hall"))

	progression.free()

func test_save_and_load_roundtrip_preserves_progression_state() -> void:
	var progression = MetaProgressionScript.new()
	progression.set_save_path(TEST_SAVE_PATH)
	progression.reset_progression()
	progression.grant_currency("war_table", 6, false)
	assert_true(progression.unlock_node("campaign_root_a", false))
	assert_true(progression.unlock_node("campaign_root_b", false))
	assert_true(progression.unlock_node("doctrine_primer", false))
	assert_true(progression.unlock_node("unlock_drill_hall", false))
	assert_true(progression.grant_castle_xp(260, false))
	progression.set_milestone("first_clear", true, false)
	assert_true(progression.save_progression())
	progression.free()

	var loaded = MetaProgressionScript.new()
	loaded.set_save_path(TEST_SAVE_PATH)
	assert_true(loaded.load_progression())
	assert_eq(loaded.get_war_table_currency(), 1)
	assert_true(loaded.is_node_unlocked("campaign_root_a"))
	assert_true(loaded.is_node_unlocked("campaign_root_b"))
	assert_true(loaded.is_node_unlocked("doctrine_primer"))
	assert_true(loaded.is_node_unlocked("unlock_drill_hall"))
	assert_true(loaded.is_station_unlocked("drill_hall"))
	assert_true(loaded.can_award_castle_xp())
	var castle_state: Dictionary = loaded.get_castle_xp_state()
	assert_eq(castle_state.get("level", 0), 2)
	assert_eq(castle_state.get("unspent_points", 0), 2)
	assert_eq(castle_state.get("xp", 0), 10)
	assert_true(loaded.get_milestone("first_clear"))
	loaded.free()
