import os, random, math
from PIL import Image, ImageDraw

def draw_blood_splatter(draw, cx, cy, radius, type="standard"):
    # Arcade Blood Colors
    base_col = (180, 0, 0, 255)
    dark_col = (100, 0, 0, 255)
    hi_col = (255, 50, 50, 150) # Wet highlight
    
    if type == "standard":
        num_blobs = random.randint(3, 7)
        for _ in range(num_blobs):
            angle = random.uniform(0, 6.28)
            dist = random.uniform(0, radius * 0.8)
            bx, by = cx + math.cos(angle) * dist, cy + math.sin(angle) * dist
            br = random.uniform(radius * 0.3, radius * 0.7)
            draw.ellipse([bx-br, by-br, bx+br, by+br], fill=base_col)
            # Add highlight to each blob for depth
            draw.ellipse([bx-br*0.4, by-br*0.6, bx+br*0.2, by-br*0.3], fill=hi_col)
            
    elif type == "spray":
        # Thousands of tiny drops
        for _ in range(35):
            angle = random.uniform(-0.5, 0.5) + math.pi/2 # mostly one direction
            dist = random.uniform(radius * 0.2, radius * 2.5)
            sx, sy = cx + math.cos(angle) * dist, cy + math.sin(angle) * dist
            sr = random.randint(1, 4)
            draw.ellipse([sx-sr, sy-sr, sx+sr, sy+sr], fill=base_col)
            
    elif type == "puddle":
        # More solid and irregular
        points = []
        for i in range(12):
            angle = (i / 12) * math.pi * 2
            r_dist = radius * random.uniform(0.6, 1.2)
            points.append((cx + math.cos(angle) * r_dist, cy + math.sin(angle) * r_dist))
        draw.polygon(points, fill=dark_col)
        # Inner lighter core
        draw.ellipse([cx-radius*0.6, cy-radius*0.6, cx+radius*0.6, cy+radius*0.6], fill=base_col)
        draw.ellipse([cx-radius*0.3, cy-radius*0.4, cx-radius*0.1, cy-radius*0.2], fill=hi_col)

    elif type == "splash":
        # Impact splash
        for i in range(10):
            angle = random.uniform(0, 6.28)
            dist = random.uniform(radius * 0.8, radius * 1.8)
            draw.line([cx, cy, cx + math.cos(angle)*dist, cy + math.sin(angle)*dist], fill=base_col, width=random.randint(2, 6))

def create_variants(base_path):
    os.makedirs(base_path, exist_ok=True)
    types = ["standard", "spray", "puddle", "splash"]
    for i, t in enumerate(types):
        img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        draw_blood_splatter(ImageDraw.Draw(img), 64, 64, 45, t)
        p = os.path.join(base_path, f"blood_splatter_{i}.png")
        img.save(p)
        print(f"Saved: {p}")

if __name__ == "__main__":
    create_variants(r"j:\BoomerShooter\boomer-shooter\Assets\Effects")
