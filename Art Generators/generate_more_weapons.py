import os
from PIL import Image, ImageDraw
import random

def apply_shading(draw, x, y, scale, color, offset_x=0, offset_y=0):
    draw.rectangle([
        (x + offset_x) * scale, 
        (y + offset_y) * scale, 
        (x + 1 + offset_x) * scale - 1, 
        (y + 1 + offset_y) * scale - 1
    ], fill=color)

def generate_weapon_viewmodel(name, draw_func, output_path):
    frame_w, frame_h = 256, 256
    num_frames = 2
    img = Image.new("RGBA", (frame_w * num_frames, frame_h), (0, 0, 0, 0))
    scale = 8
    draw = ImageDraw.Draw(img)
    
    draw_func(0, draw, scale, frame_w) # Idle
    draw_func(1, draw, scale, frame_w) # Shoot
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {name} at {output_path}")

# --- Color Palettes ---
c_metal = [(20, 20, 25, 255), (60, 60, 70, 255), (110, 110, 120, 255), (180, 180, 190, 255), (240, 240, 250, 255)]
c_wood = [(30, 20, 10, 255), (60, 40, 20, 255), (100, 60, 30, 255), (150, 90, 40, 255)]
c_brass = [(80, 50, 20, 255), (130, 90, 30, 255), (180, 140, 40, 255), (240, 200, 60, 255)]
c_magic = [(50, 0, 100, 255), (100, 50, 200, 255), (180, 100, 255, 255), (255, 255, 255, 255)]
c_fire = [(200, 30, 0, 255), (255, 100, 0, 255), (255, 200, 0, 255), (255, 255, 200, 255)]

# --- Weapon Draw Functions ---

def draw_shotgun(frame, draw, scale, frame_w):
    off_x = frame * (frame_w // scale)
    recoil = (2 if frame == 1 else 0, 4 if frame == 1 else 0) # x, y
    
    for y in range(12, 32):
        dist = y - 12
        cx = 16 + int(dist * 0.3)
        w = 2 + int(dist * 0.5)
        
        for x in range(cx - w, cx + w + 1):
            if dist < 12: # Barrels (Double Barrel)
                color = c_metal[1]
                if x == cx - w or x == cx + w: color = c_metal[0]
                elif x == cx: color = c_metal[0] # gap between barrels
                elif x == cx - w + 1 or x == cx + w - 1: color = c_metal[3]
                apply_shading(draw, x, y, scale, color, off_x + recoil[0], recoil[1])
            else: # Stock
                color = c_wood[2]
                if x == cx - w: color = c_wood[3]
                elif x == cx + w: color = c_wood[0]
                apply_shading(draw, x, y, scale, color, off_x + recoil[0], recoil[1])

def draw_crossbow(frame, draw, scale, frame_w):
    off_x = frame * (frame_w // scale)
    recoil = (0, 2 if frame == 1 else 0)
    
    for y in range(10, 32):
        dist = y - 10
        cx = 16
        w = 1 + int(dist * 0.4)
        
        # Main body
        if dist > 8:
            for x in range(cx - w, cx + w + 1):
                color = c_wood[2]
                if x == cx - w: color = c_wood[3]
                elif x == cx + w: color = c_wood[0]
                apply_shading(draw, x, y, scale, color, off_x, recoil[1])
        
        # Arms (Wings)
        if dist == 10:
            for x in range(cx - 12, cx + 13):
                color = c_metal[2]
                if abs(x - cx) > 10: color = c_metal[0]
                apply_shading(draw, x, y, scale, color, off_x, recoil[1])
                
        # String
        if frame == 0 and dist == 14: # pulled back
            for x in range(cx - 10, cx + 11):
                apply_shading(draw, x, y, scale, (200, 200, 200, 255), off_x, recoil[1])
        elif frame == 1 and dist == 11: # fired
             for x in range(cx - 11, cx + 12):
                apply_shading(draw, x, y, scale, (200, 200, 200, 255), off_x, recoil[1])

def draw_wand(frame, draw, scale, frame_w):
    off_x = frame * (frame_w // scale)
    shake = (random.randint(-1, 1) if frame == 1 else 0, random.randint(-1, 1) if frame == 1 else 0)
    
    for y in range(14, 32):
        dist = y - 14
        cx = 18 # Held to the right
        w = 1
        
        for x in range(cx - w, cx + w + 1):
            color = c_wood[1]
            if dist < 4: color = c_magic[random.randint(1, 3)] # Glowing tip
            elif dist < 10: color = c_brass[2] # Ring
            apply_shading(draw, x, y, scale, color, off_x + shake[0], shake[1])

def draw_firestaff(frame, draw, scale, frame_w):
    off_x = frame * (frame_w // scale)
    glow = (random.randint(-1, 1) if frame == 1 else 0, random.randint(-1, 1) if frame == 1 else 0)
    
    # Staff pole
    for y in range(12, 32):
        dist = y - 12
        cx = 14 # Held to the left
        w = 2 if dist > 8 else 1
        for x in range(cx - w, cx + w + 1):
            color = c_wood[0]
            if dist < 6: color = c_fire[0] # Heat glow
            apply_shading(draw, x, y, scale, color, off_x, 0)
            
    # Fire Orb at tip
    for dy in range(-4, 5):
        for dx in range(-4, 5):
            if dx*dx + dy*dy < 16:
                color = c_fire[random.randint(2, 3)] if frame == 1 else c_fire[1]
                apply_shading(draw, 14 + dx, 10 + dy, scale, color, off_x + glow[0], glow[1])

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Weapons"
    
    generate_weapon_viewmodel("Shotgun", draw_shotgun, os.path.join(base_dir, "weapon_shotgun_viewmodel.png"))
    generate_weapon_viewmodel("Crossbow", draw_crossbow, os.path.join(base_dir, "weapon_crossbow_viewmodel.png"))
    generate_weapon_viewmodel("Wand", draw_wand, os.path.join(base_dir, "weapon_wand_viewmodel.png"))
    generate_weapon_viewmodel("FireStaff", draw_firestaff, os.path.join(base_dir, "weapon_firestaff_viewmodel.png"))
