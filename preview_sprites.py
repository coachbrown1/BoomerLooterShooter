from PIL import Image, ImageDraw
import os

enemy_dir = "J:/BoomerShooter/boomer-shooter/Assets/Enemies"
out_dir = "J:/BoomerShooter/sprite_previews"
os.makedirs(out_dir, exist_ok=True)

# Draw grid lines on each sheet at 4 cols x 1 row AND 2 cols x 1 row
for enemy_folder in sorted(os.listdir(enemy_dir)):
    folder_path = os.path.join(enemy_dir, enemy_folder)
    if not os.path.isdir(folder_path):
        continue
    for f in os.listdir(folder_path):
        if f.endswith("_spritesheet.png"):
            img_path = os.path.join(folder_path, f)
            img = Image.open(img_path).convert("RGBA")
            w, h = img.size

            # Scale up small sheets for visibility
            scale = max(1, 256 // h)
            display = img.resize((w * scale, h * scale), Image.NEAREST)

            dw, dh = display.size
            draw = ImageDraw.Draw(display)

            # Draw red grid lines at 4 cols, 1 row
            for col in range(1, 4):
                x = dw * col // 4
                draw.line([(x, 0), (x, dh)], fill=(255, 0, 0, 255), width=2)

            display.save(os.path.join(out_dir, f"{enemy_folder}_preview.png"))
            print(f"Saved {enemy_folder}_preview.png  ({w}x{h})")

print("Done")
