## 2024-03-10 - Improved Crosshair Visibility
**Learning:** The default crosshair was a solid red square (`ColorRect`), which could blend into certain backgrounds (like blood or red enemies) and had poor contrast in diverse lighting.
**Action:** Changed the crosshair in `hud.tscn` to consist of a white inner square and a slightly larger black outline square, ensuring it is visible against any background. Always consider contrast against dynamic 3D backgrounds for HUD elements.

## 2024-05-15 - Interactive Tooltips for Inventory Slots
**Learning:** Default Godot `Button` components do not provide visual feedback for clickability (like the pointer hand cursor in CSS) and empty slots provided no context to the user about their contents or purpose. This causes poor UX and discoverability.
**Action:** Adding `mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND` to interactive UI elements and dynamically updating `tooltip_text` properties provides native, accessible feedback without custom popup nodes. Always utilize native `Control` properties for micro-interactions before building custom UI overlays.

## 2026-03-12 - Differentiated Inventory Feedback Colors
**Learning:** By default, all inventory interaction feedback (e.g., "Selected Item", "Slot is empty") used the same red error styling (`Color(1, 0.4, 0.4, 1)`). This confused normal interactions with errors, frustrating users and leading to poor discoverability. Also, manually instantiated `Button` elements (like the "X" close button) require explicit setup for common UX behaviors.
**Action:** Always differentiate informational messages from error messages with distinct colors (e.g. neutral white/yellow for info, red for errors) to provide clear state changes. Furthermore, consistently assign `mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND` to custom interactive buttons built in code so that they match the expected native behavior.
## 2024-03-14 - Main Menu Button Discoverability
**Learning:** Default Godot `Button` components in .tscn files (like the main menu bootstrap) do not provide visual pointer feedback for clickability by default, which can make the UI feel unresponsive or unpolished.
**Action:** Always add `mouse_default_cursor_shape = 2` (Control.CURSOR_POINTING_HAND) to all `Button` nodes in main menu scenes to ensure consistent UX and clear interactive states.
