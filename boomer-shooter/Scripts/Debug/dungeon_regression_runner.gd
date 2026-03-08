extends SceneTree

const DungeonRegressionScript = preload("res://Scripts/Debug/dungeon_regression.gd")

func _init() -> void:
	var cfg := _parse_args(OS.get_cmdline_user_args())
	var runs: int = int(cfg.get("runs", 100))
	var floor_num: int = int(cfg.get("floor", 1))
	var seed_base: int = int(cfg.get("seed", 1000))
	var regression = DungeonRegressionScript.new()
	var result: Dictionary = regression.run(runs, floor_num, seed_base)
	var failures: Array = result.get("failures", [])

	print("DungeonRegression: runs=%d floor=%d seed_base=%d" % [runs, floor_num, seed_base])
	if failures.is_empty():
		print("DungeonRegression: PASS (no failures)")
		quit(0)
		return

	print("DungeonRegression: FAIL failures=%d" % failures.size())
	var max_print := mini(25, failures.size())
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
	quit(1)

func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {
		"runs": 100,
		"floor": 1,
		"seed": 1000,
	}
	var i := 0
	while i < args.size():
		var k := str(args[i])
		if i + 1 >= args.size():
			break
		var v := str(args[i + 1])
		match k:
			"--runs":
				out["runs"] = int(v)
			"--floor":
				out["floor"] = int(v)
			"--seed":
				out["seed"] = int(v)
		i += 2
	return out
