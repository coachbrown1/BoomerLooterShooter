import os
import random
from PIL import Image, ImageDraw

def apply_shading(draw, x, y, scale, color):
    draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

def generate_flaming_skull(output_path):
    width, height = 128, 128
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4
    
    c_bone = [(150, 150, 140, 255), (200, 200, 190, 255), (230, 230, 210, 255), (255, 255, 240, 255)]
    c_fire = [
        (200, 30, 30, 150),  # 0: Outer edge / Smoke
        (255, 80, 20, 200),  # 1: Red/Orange flame
        (255, 150, 50, 255), # 2: Yellow/Orange flame
        (255, 255, 150, 255) # 3: Core white-hot flame
    ]
    
    # Flames (Layered particle-like generation)
    for y in range(4, 28):
        for x in range(6, 26):
            if random.random() > 0.3:
                # Closer to center/bottom = hotter
                heat = 0
                if 10 <= x <= 21: heat += 1
                if 13 <= x <= 18: heat += 1
                if y > 12: heat += 1
                if y > 18: heat += 1
                
                heat -= random.randint(0, 2) # Random flicker
                heat = max(0, min(3, heat))
                
                # Apply upward drift to flames
                drift_y = y - random.randint(0, 4)
                if drift_y >= 0:
                    apply_shading(draw, x, drift_y, scale, c_fire[heat])
                
    # Skull
    for y in range(12, 22):
        for x in range(10, 22):
            color = c_bone[2]
            if x in (10, 21) or y in (12, 21): color = c_bone[0]
            elif x < 15 and y < 16: color = c_bone[3]
            elif x > 17 or y > 18: color = c_bone[1]
            apply_shading(draw, x, y, scale, color)
            
    # Eye sockets
    for x in range(12, 15):
        for y in range(15, 18): apply_shading(draw, x, y, scale, (30,0,0,255))
    for x in range(17, 20):
        for y in range(15, 18): apply_shading(draw, x, y, scale, (30,0,0,255))
        
    # Glowing eyes (Heat core)
    apply_shading(draw, 13, 16, scale, c_fire[3])
    apply_shading(draw, 18, 16, scale, c_fire[3])
    apply_shading(draw, 13, 15, scale, c_fire[2]) # slight glow bleed
    apply_shading(draw, 18, 15, scale, c_fire[2])

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")

def generate_orc(output_path):
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 8
    
    c_skin = [(30, 80, 30, 255), (50, 110, 50, 255), (70, 150, 70, 255), (100, 180, 100, 255)]
    c_armor = [(40, 40, 40, 255), (80, 80, 80, 255), (120, 120, 120, 255), (160, 160, 160, 255)]
    c_blood = [(100, 0, 0, 255), (150, 0, 0, 255), (200, 0, 0, 255)]
    c_leather = [(50, 30, 20, 255), (90, 50, 30, 255), (130, 80, 50, 255)]
    
    # Body Bulk
    for y in range(8, 20):
        for x in range(10, 24): 
            color = c_skin[2]
            if x in (10, 23) or y == 19: color = c_skin[0]
            elif x < 15 and y < 14: color = c_skin[3]
            elif x > 19 or y > 16: color = c_skin[1]
            apply_shading(draw, x, y, scale, color)
            
    # Muscle definition
    apply_shading(draw, 16, 12, scale, c_skin[0]) # chest gap
    apply_shading(draw, 17, 12, scale, c_skin[0])
    
    # Head
    for y in range(4, 9):
        for x in range(14, 20): 
            color = c_skin[2]
            if x in (14, 19) or y == 4: color = c_skin[0]
            elif x < 17 and y < 6: color = c_skin[3]
            apply_shading(draw, x, y, scale, color)
            
    # Face details
    apply_shading(draw, 15, 6, scale, (255,0,0,255)) # angry eyes
    apply_shading(draw, 18, 6, scale, (255,0,0,255))
    apply_shading(draw, 14, 8, scale, c_armor[3]) # tusks highlight
    apply_shading(draw, 14, 9, scale, c_armor[2])
    apply_shading(draw, 19, 8, scale, c_armor[3])
    apply_shading(draw, 19, 9, scale, c_armor[2])
    
    # Shoulders/Armor
    for y in range(7, 10):
        for x in range(8, 12): 
            color = c_armor[2] if x < 10 else c_armor[1]
            if y == 7: color = c_armor[3] # Top ridge highlight
            apply_shading(draw, x, y, scale, color)
        for x in range(22, 26): 
            color = c_armor[1] if x > 23 else c_armor[0]
            if y == 7: color = c_armor[2]
            apply_shading(draw, x, y, scale, color)
        
    # Legs (Leather pants)
    for y in range(20, 28):
        for x in range(12, 16): 
            apply_shading(draw, x, y, scale, c_leather[2] if x < 14 else c_leather[1])
        for x in range(18, 22): 
            apply_shading(draw, x, y, scale, c_leather[1] if x < 20 else c_leather[0])
            
    # Big Axe
    for y in range(2, 22):
        apply_shading(draw, 25, y, scale, c_leather[0]) # Handle shadow
        apply_shading(draw, 26, y, scale, c_leather[2]) # Handle highlight
        
    for y in range(4, 12):
        for x in range(27, 32):
            color = c_armor[2]
            if x == 27 or y in (4, 11): color = c_armor[0]
            elif x == 31: color = c_armor[3] # Sharp edge
            
            # Bloody axe
            if y > 7 and x >= 29: 
                color = c_blood[2]
                if random.random() > 0.5: color = c_blood[1]
                
            apply_shading(draw, x, y, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")

def generate_cultist(output_path):
    width, height = 128, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4
    
    c_robe = [(30, 10, 50, 255), (60, 20, 90, 255), (90, 40, 130, 255), (120, 60, 160, 255)]
    c_trim = [(120, 100, 30, 255), (180, 150, 40, 255), (240, 210, 60, 255)]
    c_magic = [(50, 150, 50, 200), (100, 255, 100, 255), (180, 255, 180, 255)]
    
    # Robe body
    for y in range(8, 30):
        w = 10 + (y - 8)//2
        for x in range(16 - w//2, 16 + w//2):
            color = c_robe[2]
            if x == 16 - w//2 or x == 16 + w//2 - 1: color = c_robe[0] # Edge shadow
            elif x < 16: color = c_robe[3] # Left side highlight
            
            # Folds in robe
            if (x + y) % 4 == 0: color = c_robe[1]
            apply_shading(draw, x, y, scale, color)
            
    # Hood
    for y in range(4, 10):
        for x in range(12, 20): 
            color = c_robe[2]
            if y == 4 or x in (12, 19): color = c_robe[0]
            elif x < 15 and y < 6: color = c_robe[3]
            apply_shading(draw, x, y, scale, color)
            
    # Void face
    for y in range(6, 9):
        for x in range(14, 18): apply_shading(draw, x, y, scale, (0,0,0,255))
        
    # Glowing eyes (Magic)
    apply_shading(draw, 15, 7, scale, c_magic[1])
    apply_shading(draw, 16, 7, scale, c_magic[1])
    apply_shading(draw, 15, 6, scale, c_magic[2]) # Sub-pixel bright spot
    
    # Gold Trim at bottom
    for y in range(28, 30):
        for x in range(6, 26): 
            color = c_trim[2] if x < 12 else (c_trim[1] if x < 20 else c_trim[0])
            if y == 29: color = c_trim[0]
            apply_shading(draw, x, y, scale, color)
            
    # Magic hand (Particle glow)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            if random.random() > 0.4:
                dist = abs(dx) + abs(dy)
                color = c_magic[2] if dist == 0 else (c_magic[1] if dist < 2 else c_magic[0])
                apply_shading(draw, 6 + dx, 16 + dy, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")

def generate_death_knight(output_path):
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 8
    
    c_armor = [(15, 15, 20, 255), (40, 40, 45, 255), (80, 80, 90, 255), (140, 140, 150, 255)]
    c_glow = [(20, 80, 150, 255), (50, 150, 255, 255), (150, 220, 255, 255)]
    c_cape = [(40, 10, 10, 255), (100, 20, 20, 255), (180, 40, 40, 255)]
    
    # Cape (Background)
    for y in range(10, 28):
        for x in range(8, 26): 
            color = c_cape[1]
            if x < 12: color = c_cape[2]
            elif x > 20: color = c_cape[0]
            if (x+y) % 3 == 0: color = c_cape[0] # Folds
            apply_shading(draw, x, y, scale, color)
        
    # Armor Body
    for y in range(8, 20):
        for x in range(12, 22): 
            color = c_armor[2]
            if x in (12, 21) or y in (8, 19): color = c_armor[0]
            elif x < 16 and y < 14: color = c_armor[3] # Highlight
            elif x > 18 or y > 16: color = c_armor[1] # Shadow
            
            # Segment lines
            if y % 4 == 0: color = c_armor[0]
            apply_shading(draw, x, y, scale, color)
            
    # Helmet
    for y in range(4, 9):
        for x in range(14, 20): 
            color = c_armor[2]
            if x in (14, 19) or y == 4: color = c_armor[0]
            elif x < 17 and y < 6: color = c_armor[3]
            apply_shading(draw, x, y, scale, color)
            
    # Visor glow
    apply_shading(draw, 15, 6, scale, c_glow[0])
    apply_shading(draw, 16, 6, scale, c_glow[1])
    apply_shading(draw, 17, 6, scale, c_glow[2])
    apply_shading(draw, 18, 6, scale, c_glow[1])
    
    # Shield
    for y in range(12, 24):
        for x in range(6, 12): 
            color = c_armor[2]
            if x == 6 or y in (12, 23): color = c_armor[0]
            elif x == 11: color = c_armor[1] # Inner rim shadow
            elif x < 9: color = c_armor[3] # Outer curve highlight
            apply_shading(draw, x, y, scale, color)
            
    # Shield emblem (Glowing Rune)
    apply_shading(draw, 9, 17, scale, c_glow[1])
    apply_shading(draw, 8, 18, scale, c_glow[1])
    apply_shading(draw, 9, 18, scale, c_glow[2]) # Center bright
    apply_shading(draw, 10, 18, scale, c_glow[1])
    apply_shading(draw, 9, 19, scale, c_glow[1])
    
    # Greatsword (With energy core)
    for y in range(2, 26):
        # Sword body
        apply_shading(draw, 24, y, scale, c_armor[2] if y > 14 else c_armor[1])
        apply_shading(draw, 25, y, scale, c_armor[0])
        
        # Energy edge
        if y < 18:
            heat = c_glow[2] if y < 10 else (c_glow[1] if y < 15 else c_glow[0])
            apply_shading(draw, 24, y, scale, heat)
            if random.random() > 0.5:
                apply_shading(draw, 23, y, scale, c_glow[0]) # bleed

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")
    
def generate_kobold(output_path):
    width, height = 128, 128
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4
    
    c_scales = [(100, 30, 10, 255), (150, 50, 20, 255), (200, 80, 40, 255), (240, 120, 60, 255)]
    c_belly = [(120, 100, 60, 255), (180, 150, 90, 255), (220, 190, 120, 255)]
    c_flask = [(50, 150, 50, 180), (100, 255, 100, 220), (200, 255, 200, 255)]
    
    # Tail (Background)
    for x in range(6, 12): 
        color = c_scales[1] if x > 8 else c_scales[0]
        apply_shading(draw, x, 20, scale, color)
        if x % 2 == 0: apply_shading(draw, x, 19, scale, c_scales[0]) # Spikes
    
    # Body
    for y in range(14, 22):
        for x in range(12, 18): 
            color = c_scales[2]
            if x in (12, 17): color = c_scales[0]
            elif x < 15: color = c_scales[3]
            elif x == 16: color = c_belly[1] # Lighter belly on side
            apply_shading(draw, x, y, scale, color)
        
    # Head & Snout
    for y in range(10, 15):
        for x in range(13, 17): 
            color = c_scales[2] if x < 15 else c_scales[1]
            if y == 10: color = c_scales[3]
            apply_shading(draw, x, y, scale, color)
            
        for x in range(15, 20): 
            color = c_belly[1] if y > 12 else c_scales[2]
            if x == 19: color = c_scales[0]
            if y == 12 and x < 18: color = c_scales[3] # snout bridge highlight
            apply_shading(draw, x, y + 2, scale, color)
            
    # Eye
    apply_shading(draw, 14, 11, scale, (200, 150, 0, 255)) # Dark yellow
    apply_shading(draw, 15, 11, scale, (255, 255, 0, 255)) # Bright yellow
    apply_shading(draw, 15, 11, scale, (0, 0, 0, 255)) # vertical slit pupil
    
    # Arm
    for y in range(16, 20): 
        apply_shading(draw, 10, y, scale, c_scales[2] if y < 18 else c_scales[1])
        
    # Acid Flask
    for y in range(14, 18):
        for x in range(7, 10): 
            color = c_flask[1]
            if x == 7 or y == 17: color = c_flask[0]
            elif x == 8 and y == 15: color = c_flask[2] # Specular highlight
            apply_shading(draw, x, y, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")
    
def generate_gargoyle(output_path):
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 8
    
    c_stone = [(40, 40, 45, 255), (80, 80, 90, 255), (130, 130, 140, 255), (180, 180, 190, 255)]
    c_moss = [(30, 60, 30, 255), (50, 100, 50, 255)]
    
    # Wings (Background)
    for y in range(4, 20):
        for x in range(4, 14): 
            color = c_stone[1]
            if y < 8 or x < 8: color = c_stone[2] # Top edge highlight
            if (x+y) % 4 == 0: color = c_stone[0] # Veins/cracks
            apply_shading(draw, x, y, scale, color)
        for x in range(18, 28): 
            color = c_stone[0] # Right wing shadowed
            if y < 8 or x > 24: color = c_stone[1] 
            if (x+y) % 4 == 0: color = c_stone[0]
            apply_shading(draw, x, y, scale, color)
        
    # Crouched Body
    for y in range(12, 24):
        for x in range(12, 20): 
            color = c_stone[2]
            if x in (12, 19) or y == 23: color = c_stone[0]
            elif x < 15 and y < 16: color = c_stone[3]
            elif x > 17 or y > 18: color = c_stone[1]
            
            # Add moss occasionally
            if random.random() > 0.8 and y > 16: color = c_moss[1]
            apply_shading(draw, x, y, scale, color)
            
    # Head
    for y in range(8, 13):
        for x in range(13, 19): 
            color = c_stone[2]
            if x in (13, 18) or y == 8: color = c_stone[0]
            elif x < 16 and y < 11: color = c_stone[3]
            apply_shading(draw, x, y, scale, color)
            
    # Glowing Eyes
    apply_shading(draw, 15, 10, scale, (255, 50, 50, 255)) 
    apply_shading(draw, 17, 10, scale, (200, 0, 0, 255)) # Right eye shadowed glow
    
    # Horns
    apply_shading(draw, 13, 7, scale, c_stone[1])
    apply_shading(draw, 12, 6, scale, c_stone[2]) # Left horn highlight
    apply_shading(draw, 18, 7, scale, c_stone[0])
    apply_shading(draw, 19, 6, scale, c_stone[0])

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Refined)")

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies"
    
    files = {
        "FlamingSkull": ("flaming_skull_idle.png", generate_flaming_skull),
        "Orc": ("orc_idle.png", generate_orc),
        "Cultist": ("cultist_idle.png", generate_cultist),
        "DeathKnight": ("death_knight_idle.png", generate_death_knight),
        "Kobold": ("kobold_idle.png", generate_kobold),
        "Gargoyle": ("gargoyle_idle.png", generate_gargoyle)
    }
    
    for folder, (filename, func) in files.items():
        out_path = os.path.join(base_dir, folder, filename)
        func(out_path)
