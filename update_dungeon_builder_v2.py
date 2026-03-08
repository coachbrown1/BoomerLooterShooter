
import os

filepath = r"j:\BoomerShooter\boomer-shooter\Scripts\Dungeon\dungeon_builder.gd"
with open(filepath, 'r') as f:
    content = f.read()

# Crystal (Room center)
# Original sprite colors: was green. New is purple/cyan.
# Let's go with a nice cyan/teal light and purple-ish sprite tint
content = content.replace("Color(0.6, 1.2, 0.6) # brightened green", "Color(1.2, 1.0, 1.4) # brightened purple/white")
content = content.replace("Color(0.3, 1.0, 0.3) # green", "Color(0.2, 0.6, 1.0) # cyan/blue")

# Scattered Crystal
content = content.replace('"color": Color(0.3, 1.0, 0.3),   # green crystal glow', '"color": Color(0.4, 0.3, 0.9),   # purple crystal glow')

# Scattered Mushroom
content = content.replace('"color": Color(0.7, 0.2, 1.0),   # purple mushroom glow', '"color": Color(0.2, 1.0, 0.5),   # green mushroom glow')

with open(filepath, 'w') as f:
    f.write(content)

print("Successfully updated dungeon_builder.gd v2")
