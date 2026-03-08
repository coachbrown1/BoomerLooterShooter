@tool
extends EditorScript

const DungeonRegressionScript = preload("res://Scripts/Debug/dungeon_regression.gd")

# Adjust these defaults as needed before running the script in the editor.
const DEFAULT_RUNS: int = 20
const DEFAULT_FLOOR: int = 1
const DEFAULT_SEED_BASE: int = 1000
const MAX_PRINT_FAILURES: int = 25
const YIELD_EVERY_SEEDS: int = 2

func _run() -> void:
	var regression = DungeonRegressionScript.new()
	var failures: Array = []
	var tree := Engine.get_main_loop() as SceneTree
	for i in range(DEFAULT_RUNS):
		var seed := DEFAULT_SEED_BASE + i
		var failure: Dictionary = regression.check_seed(DEFAULT_FLOOR, seed)
		if not failure.is_empty():
			failures.append(failure)
		if tree != null and ((i + 1) % YIELD_EVERY_SEEDS == 0):
			print("DungeonRegression(Editor): progress %d/%d" % [i + 1, DEFAULT_RUNS])
			await tree.process_frame

	print(
		"DungeonRegression(Editor): runs=%d floor=%d seed_base=%d" % [
			DEFAULT_RUNS,
			DEFAULT_FLOOR,
			DEFAULT_SEED_BASE,
		]
	)

	if failures.is_empty():
		print("DungeonRegression(Editor): PASS (no failures)")
		return

	print("DungeonRegression(Editor): FAIL failures=%d" % failures.size())
	var max_print := mini(MAX_PRINT_FAILURES, failures.size())
	for i in range(max_print):
		var f: Dictionary = failures[i]
		print(
			"  seed=%d rooms=%d corridors=%d doorways=%d reasons=%s" % [
				int(f.get("seed", -1)),
				int(f.get("rooms", -1)),
				int(f.get("corridors", -1)),
				int(f.get("doorways", -1)),
				", ".join(f.get("reasons", [])),
			]
		)
	if failures.size() > max_print:
		print("  ... %d additional failures omitted" % (failures.size() - max_print))
