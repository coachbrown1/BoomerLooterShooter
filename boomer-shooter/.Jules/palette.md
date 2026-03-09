## 2024-03-09 - HUD Text Contrast & Readability
**Learning:** Default Godot `Label` nodes lack inherent contrast against complex 3D backgrounds in the boomer-shooter project, leading to readability issues for critical info like Health and Ammo.
**Action:** Always apply a `LabelSettings` resource with `outline_color` and `shadow_color` to critical HUD text elements to ensure high contrast and readability across varying environments.
