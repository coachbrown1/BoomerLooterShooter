from PIL import Image, ImageDraw
import os

def generate_arrow(output_path):
    # 64x64 for a projectile is enough
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # 4x scale for pixel look
    scale = 4
    
    c_wood = (120, 80, 40, 255)
    c_metal = (180, 180, 200, 255)
    c_feather = (220, 220, 220, 255)
    
    # Draw shaft (middle line)
    # Arrow points right
    # (x, y) coordinates in "pixel" units (16x16 grid)
    mid_y = 8
    for x in range(3, 14):
        draw.rectangle([x * scale, mid_y * scale, (x + 1) * scale - 1, (mid_y + 1) * scale - 1], fill=c_wood)
        
    # Draw head (point)
    draw.rectangle([13 * scale, mid_y * scale, 14 * scale - 1, (mid_y + 1) * scale - 1], fill=c_metal)
    draw.rectangle([14 * scale, mid_y * scale, 15 * scale - 1, (mid_y + 1) * scale - 1], fill=c_metal)
    # widen slightly
    draw.rectangle([13 * scale, (mid_y - 1) * scale, 14 * scale - 1, mid_y * scale - 1], fill=c_metal)
    draw.rectangle([13 * scale, (mid_y + 1) * scale, 14 * scale - 1, (mid_y + 2) * scale - 1], fill=c_metal)
    
    # Draw fletching (feathers)
    for y in [-1, 0, 1]:
        draw.rectangle([2 * scale, (mid_y + y) * scale, 4 * scale - 1, (mid_y + y + 1) * scale - 1], fill=c_feather)
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated arrow to {output_path}")

if __name__ == "__main__":
    out = r"j:\BoomerShooter\boomer-shooter\Assets\Projectiles\arrow.png"
    generate_arrow(out)
