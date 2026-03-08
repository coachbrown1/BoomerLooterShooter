import sys
import re

file_path = "J:/BoomerShooter/boomer-shooter/Scenes/UI/hud.tscn"
with open(file_path, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if "type=\"CenterContainer\"" in line or "type=\"ColorRect\"" in line or "type=\"MarginContainer\"" in line or "type=\"HBoxContainer\"" in line or "type=\"Label\"" in line:
        # Add mouse_filter = 2 below it
        new_lines.append("mouse_filter = 2\n")

with open(file_path, "w") as f:
    f.writelines(new_lines)
print("Updated HUD mouse filters")
