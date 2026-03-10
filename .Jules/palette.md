## 2024-03-10 - Improved Crosshair Visibility
**Learning:** The default crosshair was a solid red square (`ColorRect`), which could blend into certain backgrounds (like blood or red enemies) and had poor contrast in diverse lighting.
**Action:** Changed the crosshair in `hud.tscn` to consist of a white inner square and a slightly larger black outline square, ensuring it is visible against any background. Always consider contrast against dynamic 3D backgrounds for HUD elements.
