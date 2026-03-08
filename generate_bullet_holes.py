import os, random, math
from PIL import Image, ImageDraw

def draw_bullet_hole(draw, cx, cy, radius, type="standard"):
    # Dark crater/hole core
    core_r = radius * 0.45
    draw.ellipse([cx-core_r, cy-core_r, cx+core_r, cy+core_r], fill=(15, 15, 15, 255))
    
    # Impact ring
    ring_r = radius * 0.85
    draw.ellipse([cx-ring_r, cy-ring_r, cx+ring_r, cy+ring_r], outline=(40, 40, 40, 220), width=3)
    
    # Highlights (Bottom-right highlight) - makes it look INSET
    draw.arc([cx-core_r, cy-core_r, cx+core_r, cy+core_r], 0, 180, fill=(120, 120, 120, 150), width=1)

    if type == "cracked":
        for _ in range(10):
            angle = random.uniform(0, 6.28)
            length = random.uniform(radius * 0.8, radius * 1.8)
            ex, ey = cx + math.cos(angle) * length, cy + math.sin(angle) * length
            draw.line([cx + math.cos(angle)*core_r, cy + math.sin(angle)*core_r, ex, ey], fill=(55, 55, 55, 120), width=1)
    elif type == "crater":
        for _ in range(30):
            angle = random.uniform(0, 6.28)
            dist = random.uniform(2, radius * 1.3)
            px, py = cx + math.cos(angle) * dist, cy + math.sin(angle) * dist
            draw.point((px, py), fill=(35, 35, 35, 200))
    elif type == "splash":
        for _ in range(8):
            angle = random.uniform(0, 6.28)
            dist = random.uniform(radius * 0.6, radius * 1.6)
            sx, sy = cx + math.cos(angle) * dist, cy + math.sin(angle) * dist
            draw.ellipse([sx-1, sy-1, sx+1, sy+1], fill=(50, 50, 50, 180))

def create_variants(base_path):
    os.makedirs(base_path, exist_ok=True)
    types = ["standard", "cracked", "crater", "splash"]
    for i, t in enumerate(types):
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        draw_bullet_hole(ImageDraw.Draw(img), 32, 32, 22, t)
        p = os.path.join(base_path, f"bullet_hole_{i}.png")
        img.save(p)
        print(f"Saved: {p}")

if __name__ == "__main__":
    create_variants(r"j:\BoomerShooter\boomer-shooter\Assets\Effects")
