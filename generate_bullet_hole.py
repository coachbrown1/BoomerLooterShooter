import os
from PIL import Image, ImageDraw

def create_bullet_hole(output_path):
    # A small 64x64 texture
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    cx, cy = 32, 32
    
    # Inner hole (black)
    draw.ellipse([cx-4, cy-4, cx+4, cy+4], fill=(20, 20, 20, 255))
    
    # Cracked impact ring (dark gray/rust)
    draw.ellipse([cx-12, cy-12, cx+12, cy+12], outline=(60, 60, 60, 180), width=2)
    
    # Outer dust/splash (very transparent dark)
    for i in range(12):
        import random
        angle = random.uniform(0, 6.28)
        dist = random.uniform(8, 22)
        ex, ey = cx + dist * 1.5 * (random.uniform(0.5, 1.0) * (angle + 1) % 1.5), cy + dist * 0.5
        # Skip drawing complex cracks, keep it simple and boomer shooter style
        r_scat = random.randint(1, 3)
        draw.ellipse([ex-r_scat, ey-r_scat, ex+r_scat, ey+r_scat], fill=(40, 40, 40, 100))

    img.save(output_path)
    print(f"Saved bullet hole template: {output_path}")

if __name__ == "__main__":
    os.makedirs(r"j:\BoomerShooter\boomer-shooter\Assets\Effects", exist_ok=True)
    create_bullet_hole(r"j:\BoomerShooter\boomer-shooter\Assets\Effects\bullet_hole.png")
