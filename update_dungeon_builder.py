
import os

filepath = r"j:\BoomerShooter\boomer-shooter\Scripts\Dungeon\dungeon_builder.gd"
with open(filepath, 'r') as f:
    content = f.read()

# For the room crystal
content = content.replace("sprite.pixel_size = 0.02", "sprite.pixel_size = 0.005")

# For the scattered crystal
content = content.replace('"pixel_size": 0.016,', '"pixel_size": 0.004,')

# For the scattered mushroom
content = content.replace('"pixel_size": 0.014,', '"pixel_size": 0.0035,')

with open(filepath, 'w') as f:
    f.write(content)

print("Successfully updated dungeon_builder.gd")
