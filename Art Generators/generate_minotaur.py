import os
import random
from PIL import Image, ImageDraw

def generate_minotaur(output_path):
    width = 256
    height = 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 8
    
    def draw_pixel(x, y, color):
        draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

    # Palette Ramping (Fur from shadow to highlight)
    c_fur = [
        (40, 20, 10, 255),   # 0: Outline / Deep Shadow
        (70, 35, 15, 255),   # 1: Shadow
        (100, 55, 25, 255),  # 2: Base
        (130, 75, 35, 255),  # 3: Mid-highlight
        (150, 95, 45, 255),  # 4: Highlight
    ]
    
    # Horn Palette
    c_horn = [
        (60, 50, 40, 255),   # 0: Shadow
        (120, 110, 100, 255),# 1: Base
        (200, 190, 170, 255),# 2: Highlight
    ]
    
    c_eye = (255, 30, 30, 255)
    
    # Armor/Metal
    c_metal = [
        (40, 40, 45, 255),   # 0: Shadow
        (100, 100, 110, 255),# 1: Base
        (180, 180, 190, 255),# 2: Highlight
        (230, 230, 240, 255) # 3: Specular
    ]
    
    # Wood
    c_wood = [
        (40, 20, 10, 255),
        (80, 50, 30, 255),
        (110, 70, 40, 255)
    ]

    # --- Draw Body (With Shading) ---
    
    # Chest & Abs
    for y in range(8, 22):
        for x in range(10, 22):
            color = c_fur[2] # Base
            # Deep shadows / Outlines
            if x in (10, 21) or y in (8, 21): 
                color = c_fur[0]
            # Shadow gradient from right and bottom
            elif x > 18 or y > 18 or (x > 16 and y > 14):
                color = c_fur[1]
            # Highlights (Top left light source)
            elif (12 <= x <= 15 and 9 <= y <= 13): 
                color = c_fur[4]
            elif (11 <= x <= 16 and 9 <= y <= 15):
                color = c_fur[3]
                
            # Pec definition (shadows)
            if y == 13 and 12 <= x <= 19:
                color = c_fur[0]
            if x == 15 and 9 <= y <= 15:
                color = c_fur[0]

            # Texture variation (Random dithering)
            if color == c_fur[2] and random.random() > 0.7:
                color = c_fur[1]

            # Only draw if not outside bounds
            if (not (y > 15 and x < 12)) and (not (y > 15 and x > 19)):
                draw_pixel(x, y, color)

    # Legs
    for y in range(22, 28):
        # Left leg
        for x in range(11, 15): 
            color = c_fur[3] if x < 13 else c_fur[1]
            if x == 11 or x == 14: color = c_fur[0]
            draw_pixel(x, y, color)
        # Right leg (further back/shadowed)
        for x in range(17, 21): 
            color = c_fur[1] if x < 19 else c_fur[0]
            if x == 17 or x == 20: color = c_fur[0]
            draw_pixel(x, y, color)
            
    # Hooves (Metal)
    for y in range(28, 30):
        for x in range(10, 15): 
            color = c_metal[2] if x < 12 else c_metal[1]
            if x in (10,14) or y == 29: color = c_metal[0]
            draw_pixel(x, y, color)
        for x in range(17, 22): 
            color = c_metal[1] if x < 19 else c_metal[0]
            if x in (17,21) or y == 29: color = c_metal[0]
            draw_pixel(x, y, color)

    # Arms
    for y in range(9, 18):
        # Left arm (highlighted)
        for x in range(6, 10): 
            color = c_fur[3] if x < 8 else c_fur[2]
            if x in (6,9) or y == 17: color = c_fur[0]
            draw_pixel(x, y, color)
        # Right arm (shadowed)
        for x in range(22, 26): 
            color = c_fur[1] if x < 24 else c_fur[0]
            if x in (22,25) or y == 17: color = c_fur[0]
            draw_pixel(x, y, color)
            
    # Head
    for y in range(2, 9):
        for x in range(12, 20):
            # Skip corners for rounded head
            if (y == 2 and x in (12, 19)): continue
            
            color = c_fur[2]
            if x in (12, 19) or y == 2: color = c_fur[0]
            elif x < 15 and y < 6: color = c_fur[3] # Highlight top left
            elif x > 16 or y > 6: color = c_fur[1]  # Shadow bottom right
            
            # Snout
            if y > 5 and 13 <= x <= 18: 
                color = c_fur[0] if x > 16 else c_fur[1]
                if y == 8: color = c_fur[0] # Bottom snout shadow
                
            draw_pixel(x, y, color)

    # Eyes
    draw_pixel(14, 5, c_eye)
    draw_pixel(17, 5, c_eye)
    draw_pixel(14, 4, c_fur[0]) # Eyebrows
    draw_pixel(17, 4, c_fur[0])

    # Horns
    # Left horn
    draw_pixel(11, 4, c_horn[1])
    draw_pixel(11, 3, c_horn[2])
    draw_pixel(10, 3, c_horn[2])
    draw_pixel(9, 2, c_horn[1])
    draw_pixel(10, 2, c_horn[0])
    draw_pixel(8, 1, c_horn[0])
    
    # Right horn (shadowed)
    draw_pixel(20, 4, c_horn[0])
    draw_pixel(21, 3, c_horn[1])
    draw_pixel(22, 2, c_horn[0])
    draw_pixel(21, 2, c_horn[0])
    draw_pixel(23, 1, c_horn[0])

    # Armor - Loincloth
    c_cloth = [(60, 10, 10, 255), (120, 20, 20, 255), (180, 40, 40, 255)]
    for y in range(20, 25):
        for x in range(14, 18):
            color = c_cloth[1]
            if x == 14: color = c_cloth[2]
            if x == 17 or y == 24: color = c_cloth[0]
            # Simple cloth folding
            if (x+y) % 2 == 0: color = c_cloth[0]
            draw_pixel(x, y, color)

    # Weapon - Huge Axe in Right Hand
    # Shaft
    for y in range(5, 25):
        draw_pixel(24, y, c_wood[2]) # Highlight
        draw_pixel(25, y, c_wood[0]) # Shadow
        
    # Axe Head
    for y in range(6, 14):
        for x in range(26, 30):
            color = c_metal[1]
            if x == 26 or y in (6, 13): color = c_metal[0]
            elif x == 27 and y < 10: color = c_metal[2]
            draw_pixel(x, y, color)
            
    # Axe Blade (Curved)
    for y in range(5, 15):
        x = 30
        color = c_metal[2]
        if y == 5 or y == 14: color = c_metal[0]
        if y in (8, 9, 10): 
            draw_pixel(31, y, c_metal[3]) # Specular shine on edge
        draw_pixel(x, y, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")

if __name__ == "__main__":
    godot_assets_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\Minotaur"
    output_file = os.path.join(godot_assets_dir, "minotaur_idle.png")
    generate_minotaur(output_file)
