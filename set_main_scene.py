import sys

file_path = "J:/BoomerShooter/boomer-shooter/project.godot"
with open(file_path, "r") as f:
    content = f.read()

# Update main scene
content = content.replace(
    'run/main_scene="res://Scenes/World/test_room.tscn"',
    'run/main_scene="res://Scenes/World/dungeon.tscn"'
)

with open(file_path, "w") as f:
    f.write(content)

print("Main scene updated to dungeon.tscn")
