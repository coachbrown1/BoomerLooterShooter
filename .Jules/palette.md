## 2024-03-10 - Improved Crosshair Visibility
**Learning:** The default crosshair was a solid red square (`ColorRect`), which could blend into certain backgrounds (like blood or red enemies) and had poor contrast in diverse lighting.
**Action:** Changed the crosshair in `hud.tscn` to consist of a white inner square and a slightly larger black outline square, ensuring it is visible against any background. Always consider contrast against dynamic 3D backgrounds for HUD elements.

## 2024-05-15 - Interactive Tooltips for Inventory Slots
**Learning:** Default Godot `Button` components do not provide visual feedback for clickability (like the pointer hand cursor in CSS) and empty slots provided no context to the user about their contents or purpose. This causes poor UX and discoverability.
**Action:** Adding `mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND` to interactive UI elements and dynamically updating `tooltip_text` properties provides native, accessible feedback without custom popup nodes. Always utilize native `Control` properties for micro-interactions before building custom UI overlays.
