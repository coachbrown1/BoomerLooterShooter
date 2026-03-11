
## 2024-05-18 - Avoid repeated tree traversal in Godot `weapon.gd`
**Learning:** Frequent calls to `get_tree().get_first_node_in_group("player")` within heavily used methods like `fire()` cause unnecessary performance overhead by repeatedly traversing the scene tree.
**Action:** When a parent node (like `WeaponManager`) already maintains a reference to a heavily accessed node (like `player`), inject or access this cached reference directly (`weapon_manager.player`) to avoid traversing the tree, falling back to the group lookup only when necessary.
