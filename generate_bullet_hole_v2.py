import os, random, math
from PIL import Image, ImageDraw

def draw_bullet_hole(draw, cx, cy, radius, type="standard"):
    # 1. Dark crater/hole core
    core_r = radius * 0.4
    core_col = (10, 10, 10, 255)
    draw.ellipse([cx-core_r, cy-core_r, cx+core_r, cy+core_r], fill=core_col)
    
    # 2. Impact ring (darker than surface)
    ring_r = radius * 0.8
    draw.ellipse([cx-ring_r, cy-ring_r, cx+ring_r, cy+ring_r], outline=(40, 40, 40, 200), width=random.randint(2, 4))
    
    # 3. Highlights (crucial for "depth" in pixel art)
    # Bottom-right highlight suggests an inset hole
    hi_col = (100, 100, 100, 150)
    draw.arc([cx-core_r, cy-core_r, cx+core_r, cy+core_r], 0, 180, fill=hi_col, width=1)

    if type == "cracked":
        # Add jagged cracks
        num_cracks = random.randint(3, 6)
        for _ in range(num_cracks):
            angle = random.uniform(0, math.pi * 2)
            length = random.uniform(radius * 0.6, radius * 1.5)
            ex, ey = cx + math.cos(angle) * length, cy + math.sin(angle) * length
            draw.line([cx + math.cos(angle)*core_r, cy + math.sin(angle)*core_r, ex, ey], fill=(50, 50, 50, 150), width=1)
            
    elif type == "crater":
        # Rougher larger impact
        for _ in range(12):
            angle = random.uniform(0, math.pi * 2)
            dist = random.uniform(0, radius * 1.2)
            px, py = cx + math.cos(angle) * dist, cy + math.sin(angle) * dist
            pr = random.randint(1, 3)
            draw.ellipse([px-pr, py-pr, px+pr, py+pr], fill=(30, 30, 30, 180))

    elif type == "splash":
        # Debris splatter
        for _ in range(15):
            angle = random.uniform(0, math.pi * 2)
            dist = random.uniform(radius * 0.5, radius * 2.0)
            sx, sy = cx + math.cos(angle) * dist, cy + math.sin(angle) * dist
            sr = random.randint(1, 2)
            draw.point((sx, sy), fill=(60, 60, 60, 100))

def create_bullet_hole_sheet(output_path):
    # 128x128 sheet with 4 64x64 holes
    sheet = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    types = ["standard", "cracked", "crater", "splash"]
    
    for i in range(4):
        hole_img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        draw = ImageDraw.Draw(hole_img)
        draw_bullet_hole(draw, 32, 32, 20, types[i])
        
        # Paste into sheet
        sheet.paste(hole_img, ((i % 2) * 64, (i // 2) * 64))
        
    sheet.save(output_path)
    print(f"Saved: {output_path}")

if __name__ == "__main__":
    os.makedirs(r"j:\BoomerShooter\boomer-shooter\Assets\Effects", exist_ok=True)
    create_bullet_hole_sheet(r"j:\BoomerShooter\boomer-shooter\Assets\Effects\bullet_hole_sheet.png")
