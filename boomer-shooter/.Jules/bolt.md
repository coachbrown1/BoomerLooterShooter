## 2024-03-24 - Caching Godot Scene Tree Group Fetches
**Learning:** Frequent calls to `get_tree().get_nodes_in_group(...)` or `get_first_node_in_group(...)` inside high-frequency functions (like `_process`, `_physics_process`, or repeatedly triggered events like `_update_hud` when firing a weapon) incur expensive O(N) scene tree traversal overhead, scaling poorly with game complexity.
**Action:** Lazily cache group fetching results in variables on the first execution (or during `_ready`), reducing the computational complexity from O(N) to O(1) for subsequent calls.
