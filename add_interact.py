import sys

file_path = "J:/BoomerShooter/boomer-shooter/project.godot"
with open(file_path, "r") as f:
    content = f.read()

if "interact" not in content:
    lines = content.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("shoot="):
            lines.insert(i+1, 'interact={')
            lines.insert(i+2, '"deadzone": 0.5,')
            lines.insert(i+3, '"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":70,"key_label":0,"unicode":102,"location":0,"echo":false,"script":null)')
            lines.insert(i+4, ']}')
            break
            
    with open(file_path, "w") as f:
        f.write("\n".join(lines))
    print("Added interact to project.godot")
else:
    print("interact already exists")
