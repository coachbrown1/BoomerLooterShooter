from PIL import Image
import os

enemy_dir = "J:/BoomerShooter/boomer-shooter/Assets/Enemies"

for enemy_folder in sorted(os.listdir(enemy_dir)):
    folder_path = os.path.join(enemy_dir, enemy_folder)
    if not os.path.isdir(folder_path):
        continue
    for f in os.listdir(folder_path):
        if f.endswith("_spritesheet.png"):
            img_path = os.path.join(folder_path, f)
            img = Image.open(img_path).convert("RGBA")
            w, h = img.size

            # Sample a row of pixels vertically centered to find column breaks
            # We'll scan horizontally along the vertical midpoint looking for full-alpha vs empty columns
            # This tells us roughly where frames start/end
            mid_y = h // 2

            # Try to guess frame count by finding consistent frame size
            # Since all are 4:1 or 2:1 ratio, check common frame counts
            candidates = []
            for ncols in [2, 4, 8]:
                frame_w = w // ncols
                for nrows in [1, 2, 4]:
                    frame_h = h // nrows
                    if frame_w == frame_h:
                        candidates.append((ncols, nrows, frame_w, frame_h))

            print(f"{enemy_folder}: {w}x{h} -> candidates: {candidates}")
