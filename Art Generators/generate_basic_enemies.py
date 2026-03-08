import os
import random
from PIL import Image, ImageDraw

def apply_shading(draw, x, y, scale, color):
    """Helper to draw scaled pixels"""
    draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

def generate_goblin(output_path):
    width, height = 128, 128
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4
    
    c_skin = [(40, 80, 20, 255), (70, 110, 30, 255), (100, 150, 50, 255), (130, 180, 70, 255)]
    c_leather = [(60, 30, 10, 255), (100, 60, 20, 255), (130, 80, 40, 255), (160, 100, 50, 255)]
    c_metal = [(80, 80, 80, 255), (120, 120, 120, 255), (160, 160, 160, 255), (220, 220, 230, 255)]
    c_eye = (255, 255, 0, 255)
    
    # Body (Leather Armor)
    for y in range(16, 24):
        for x in range(12, 20): 
            color = c_leather[2]
            if x in (12, 19) or y == 23: color = c_leather[0]
            elif x < 15 and y < 19: color = c_leather[3]
            elif x > 16 or y > 20: color = c_leather[1]
            apply_shading(draw, x, y, scale, color)
    
    # Head (Green Skin)
    for y in range(8, 16):
        for x in range(10, 22): 
            color = c_skin[2]
            if x in (10, 21) or y in (8, 15): color = c_skin[0]
            elif x < 14 and y < 12: color = c_skin[3]
            elif x > 17 or y > 13: color = c_skin[1]
            apply_shading(draw, x, y, scale, color)
    
    # Ears
    for x in range(4, 10):
        color = c_skin[3] if x > 6 else c_skin[2]
        apply_shading(draw, x, 10, scale, color)
        apply_shading(draw, x, 11, scale, c_skin[1])
    for x in range(22, 28):
        color = c_skin[1]
        apply_shading(draw, x, 10, scale, color)
        apply_shading(draw, x, 11, scale, c_skin[0])
        
    # Eyes
    apply_shading(draw, 13, 11, scale, c_eye)
    apply_shading(draw, 14, 11, scale, c_eye)
    apply_shading(draw, 17, 11, scale, c_eye)
    apply_shading(draw, 18, 11, scale, c_eye)
    
    # Legs (Shadowed)
    for y in range(24, 30):
        for x in range(13, 16): 
            color = c_skin[1] if x < 15 else c_skin[0]
            apply_shading(draw, x, y, scale, color)
        for x in range(16, 19): 
            color = c_skin[0]
            apply_shading(draw, x, y, scale, color)
        
    # Arm & Dagger
    for y in range(16, 22):
        for x in range(8, 12): 
            color = c_skin[2] if x < 10 else c_skin[1]
            apply_shading(draw, x, y, scale, color)
            
    # Dagger blade
    for y in range(10, 20):
        apply_shading(draw, 7, y, scale, c_metal[2] if y < 15 else c_metal[1]) # Blade core
        apply_shading(draw, 6, y, scale, c_metal[3] if y < 13 else c_metal[2]) # Sharp edge highlight

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")

def generate_skeleton(output_path, is_crossbow=False):
    width, height = 128, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4
    
    c_bone = [(100, 100, 90, 255), (150, 150, 140, 255), (200, 200, 190, 255), (240, 240, 230, 255)]
    c_wood = [(50, 30, 10, 255), (100, 60, 30, 255), (140, 90, 40, 255)]
    c_metal = [(80, 80, 80, 255), (180, 180, 180, 255), (240, 240, 255, 255)]
    
    # Ribcage
    for y in range(15, 25):
        if y % 2 == 0:
            for x in range(12, 20): 
                color = c_bone[2]
                if x in (12, 19): color = c_bone[0]
                elif x < 15: color = c_bone[3]
                elif x > 16: color = c_bone[1]
                apply_shading(draw, x, y, scale, color)
        else:
            apply_shading(draw, 15, y, scale, c_bone[1]) # Spine
            apply_shading(draw, 16, y, scale, c_bone[0])
            
    # Skull
    for y in range(6, 14):
        for x in range(12, 20): 
            color = c_bone[2]
            if x in (12, 19) or y == 6 or y == 13: color = c_bone[0]
            elif x < 15 and y < 10: color = c_bone[3]
            elif x > 16 or y > 11: color = c_bone[1]
            apply_shading(draw, x, y, scale, color)
            
    # Eye sockets
    for x in range(13, 15):
        for y in range(9, 11): apply_shading(draw, x, y, scale, (0,0,0,255))
    for x in range(17, 19):
        for y in range(9, 11): apply_shading(draw, x, y, scale, (0,0,0,255))
    
    # Left eye glow
    apply_shading(draw, 13, 9, scale, (100, 200, 255, 255))
    
    # Legs (Shadowed and thin)
    for y in range(26, 40):
        apply_shading(draw, 13, y, scale, c_bone[2] if y < 32 else c_bone[1])
        apply_shading(draw, 18, y, scale, c_bone[1] if y < 32 else c_bone[0]) # Back leg darker
        
    # Arms
    for y in range(15, 25):
        apply_shading(draw, 10, y, scale, c_bone[2])
        apply_shading(draw, 21, y, scale, c_bone[1])

    if is_crossbow:
        # Crossbow
        for x in range(6, 26):
            color = c_wood[2] if x < 16 else c_wood[1]
            if x == 6 or x == 25: color = c_wood[0]
            apply_shading(draw, x, 22, scale, color)
        for y in range(20, 26):
            apply_shading(draw, 15, y, scale, c_wood[1])
            apply_shading(draw, 16, y, scale, c_metal[1])
            apply_shading(draw, 17, y, scale, c_metal[2]) # highlight on metal track
    else:
        # Sword
        for y in range(10, 30):
            apply_shading(draw, 9, y, scale, c_metal[1])
            if y < 20: apply_shading(draw, 8, y, scale, c_metal[2]) # Edge highlight

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")

def generate_cube(output_path):
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 8
    
    c_slime = [
        (40, 100, 40, 180),  # 0: Core/Deep
        (80, 180, 80, 150),  # 1: Mid
        (130, 240, 130, 120),# 2: Outer
        (200, 255, 200, 200) # 3: Edge Highlights / Specular
    ]
    c_bone = [(150, 150, 140, 180), (220, 220, 200, 200)]
    
    # Cube body
    for y in range(4, 28):
        for x in range(4, 28):
            color = c_slime[1]
            
            # Thick edges
            if x in (4, 27) or y in (4, 27): 
                color = c_slime[3]
            # Darker core
            elif 10 <= x <= 22 and 10 <= y <= 22:
                color = c_slime[0]
            # Surface reflections
            elif (x == 6 or y == 6) and x < 24 and y < 24:
                color = c_slime[3]
            # Specular dots
            elif random.random() > 0.95:
                color = c_slime[3]
                
            # Floating bones inside (obscured by slime)
            if (x, y) in [(10, 15), (11, 15), (15, 20), (16, 20), (17, 20), (20, 10), (21, 10)]: 
                color = c_bone[1]
            elif (x, y) in [(10, 16), (15, 21), (20, 11)]:
                color = c_bone[0] # shadow on bones
                
            apply_shading(draw, x, y, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")
    
def generate_beholder(output_path):
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 8
    
    c_flesh = [(50, 20, 20, 255), (100, 40, 40, 255), (160, 60, 60, 255), (200, 90, 90, 255)]
    c_eye_white = [(150, 150, 160, 255), (255, 255, 255, 255)]
    c_eye_iris = [(100, 0, 0, 255), (255, 50, 50, 255), (255, 150, 150, 255)]
    c_tooth = [(150, 150, 100, 255), (255, 255, 200, 255)]
    
    # Main Body (Sphere with spherical shading)
    for y in range(6, 25):
        for x in range(6, 25):
            dist_sq = (x-15.5)**2 + (y-15.5)**2
            if dist_sq <= 81: # radius 9
                # Spherical shading gradient
                if x < 12 and y < 12: color = c_flesh[3] # Highlight top-left
                elif x > 18 or y > 18: color = c_flesh[1] # Shadow bottom-right
                elif dist_sq > 64: color = c_flesh[0] # Rim shadow
                else: color = c_flesh[2] # Base
                
                # Texture
                if random.random() > 0.8: color = c_flesh[1]
                
                apply_shading(draw, x, y, scale, color)
                
    # Giant Central Eye
    for y in range(9, 17):
        for x in range(11, 21):
            if (x-15.5)**2 + (y-13)**2 <= 16:
                color = c_eye_white[1] if y < 15 and x < 18 else c_eye_white[0]
                apply_shading(draw, x, y, scale, color)
                
    # Pupil/Iris
    apply_shading(draw, 14, 12, scale, c_eye_iris[1])
    apply_shading(draw, 15, 12, scale, c_eye_iris[1])
    apply_shading(draw, 16, 12, scale, c_eye_iris[1])
    apply_shading(draw, 15, 13, scale, (0,0,0,255)) # Pupil
    apply_shading(draw, 16, 13, scale, (0,0,0,255))
    apply_shading(draw, 14, 11, scale, c_eye_white[1]) # Specular highlight on eye
    apply_shading(draw, 15, 11, scale, c_eye_white[1])
    
    # Mouth (Jagged Maw)
    for x in range(11, 21):
        apply_shading(draw, x, 20, scale, (30, 0, 0, 255)) # Dark mouth interior
        if x % 2 == 0:
            apply_shading(draw, x, 19, scale, c_tooth[1])
            apply_shading(draw, x, 18, scale, c_tooth[0]) # Tooth root shadow
            apply_shading(draw, x, 21, scale, c_tooth[1])
        else:
            apply_shading(draw, x, 20, scale, c_tooth[0]) # Bottom teeth background
            
    # Eyestalks
    stalk_ends = [(4, 4), (10, 1), (24, 2), (28, 6)]
    for sx, sy in stalk_ends:
        cx, cy = 15, 12
        steps = max(abs(sx-cx), abs(sy-cy)) + 1
        for i in range(steps):
            px = int(sx + (cx-sx)*(i/steps))
            py = int(sy + (cy-sy)*(i/steps))
            color = c_flesh[1] if (px+py)%2==0 else c_flesh[2]
            apply_shading(draw, px, py, scale, color)
        
        # Mini eye at end of stalk
        apply_shading(draw, sx-1, sy, scale, c_flesh[0]) # Socket ring
        apply_shading(draw, sx+1, sy, scale, c_flesh[0])
        apply_shading(draw, sx, sy-1, scale, c_flesh[0])
        apply_shading(draw, sx, sy+1, scale, c_flesh[0])
        
        apply_shading(draw, sx, sy, scale, c_eye_white[1])
        apply_shading(draw, sx, sy, scale, c_eye_iris[2]) # Small glowing iris

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies"
    
    files = {
        "Goblin": ("goblin_idle.png", generate_goblin),
        "Skeleton": ("skeleton_idle.png", lambda p: generate_skeleton(p, False)),
        "SkeletonCrossbow": ("skeleton_crossbow_idle.png", lambda p: generate_skeleton(p, True)),
        "GelatinousCube": ("cube_idle.png", generate_cube),
        "Beholder": ("beholder_idle.png", generate_beholder)
    }
    
    for folder, (filename, func) in files.items():
        out_path = os.path.join(base_dir, folder, filename)
        func(out_path)
