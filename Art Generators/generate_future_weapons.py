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
c_steel = [(15, 20, 25, 255), (35, 45, 55, 255), (60, 75, 90, 255), (90, 110, 130, 255)]
c_metal = [(20, 20, 25, 255), (60, 60, 70, 255), (110, 110, 120, 255), (180, 180, 190, 255), (240, 240, 250, 255)]
c_plasma_blue = [(0, 50, 100, 255), (0, 150, 255, 255), (150, 220, 255, 255), (255, 255, 255, 255)]
c_plasma_orange = [(100, 30, 0, 255), (255, 100, 0, 255), (255, 200, 0, 255), (255, 255, 200, 255)]

# --- Weapon Draw Functions ---

def draw_plasma_railgun(frame, draw, scale, frame_w):
    # Shoots Magic Bolt (proj_magic.png)
    off_x = frame * (frame_w // scale)
    recoil = (1 if frame == 1 else 0, 2 if frame == 1 else 0)
    
    for y in range(12, 32):
        dist = y - 12
        cx = 18 + int(dist * 0.2) # Slanted view
        w = 2 + int(dist * 0.3)
        
        for x in range(cx - w, cx + w + 1):
            color = c_steel[1]
            # Top rail
            if y < 20 and cx - 1 <= x <= cx + 1:
                color = c_plasma_blue[1] if frame == 1 else c_plasma_blue[0]
                if x == cx: color = c_plasma_blue[2]
            # Body highlights
            elif x == cx - w: color = c_steel[2]
            elif x == cx + w: color = c_steel[0]
            
            # Glowing side vents
            if dist % 4 == 0 and abs(x-cx) == w-1:
                 color = c_plasma_blue[1]
                 
            apply_shading(draw, x, y, scale, color, off_x + recoil[0], recoil[1])

def draw_heavy_incinerator(frame, draw, scale, frame_w):
    # Shoots Fireball (proj_fireball.png)
    off_x = frame * (frame_w // scale)
    recoil = (2 if frame == 1 else 0, 5 if frame == 1 else 0) # Heavy kick
    
    for y in range(10, 32):
        dist = y - 10
        cx = 14 + int(dist * 0.1) # Bulky, left-leaning hold
        w = 4 + int(dist * 0.4) # Very wide barrel
        
        for x in range(cx - w, cx + w + 1):
            color = c_metal[1]
            # Heat shroud
            if y < 18:
                if (x+y) % 3 == 0: color = c_metal[0] # Vents
                if frame == 1: # Internal glow during fire
                     if cx - 2 <= x <= cx + 2: color = c_plasma_orange[1]
            
            # Tank/Body
            if y >= 22:
                if x < cx: color = c_steel[1]
                else: color = c_steel[0]
                # Heat hazard stripes
                if (x+y) % 4 == 0 and x < cx - 2: color = (200, 180, 0, 255) # Yellow
            
            if x == cx - w: color = c_metal[2]
            elif x == cx + w: color = c_metal[0]
            
            apply_shading(draw, x, y, scale, color, off_x + recoil[0], recoil[1])

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Weapons"
    
    generate_weapon_viewmodel("PlasmaRailgun", draw_plasma_railgun, os.path.join(base_dir, "weapon_plasma_railgun_viewmodel.png"))
    generate_weapon_viewmodel("HeavyIncinerator", draw_heavy_incinerator, os.path.join(base_dir, "weapon_heavy_incinerator_viewmodel.png"))
