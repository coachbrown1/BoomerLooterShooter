import sys

file_path = "J:/BoomerShooter/boomer-shooter/project.godot"
with open(file_path, "r") as f:
    content = f.read()

input_section = """
shoot={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}
"""

# inject input section
content = content.replace("[input]", "[input]\n" + input_section)

with open(file_path, "w") as f:
    f.write(content)
print("Added shoot input.")
