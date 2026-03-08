import os
import random
from PIL import Image, ImageDraw

def apply_shading(draw, x, y, scale, color):
    draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

def create_base_img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

# --- Palettes ---
c_wood = [(40, 20, 10, 255), (70, 40, 20, 255), (100, 60, 30, 255), (130, 80, 40, 255)]
c_metal = [(40, 40, 45, 255), (80, 80, 90, 255), (120, 120, 130, 255)]
c_bone = [(150, 150, 140, 255), (200, 200, 190, 255), (240, 240, 230, 255)]
c_fire = [(200, 50, 0, 200), (255, 100, 0, 255), (255, 200, 0, 255), (255, 255, 200, 255)]
c_stone = [(40, 40, 45, 255), (70, 70, 80, 255), (100, 100, 110, 255)]
c_web = [(200, 200, 200, 50), (200, 200, 200, 100), (255, 255, 255, 150)]

# --- Universal Props ---

def draw_barrel(draw, scale):
    for y in range(4, 28):
        w = 10 if 8 < y < 24 else 8
        for x in range(16 - w, 16 + w):
            color = c_wood[2]
            if x == 16 - w or x == 16 + w - 1 or y in (4, 27): color = c_wood[0]
            elif x < 16: color = c_wood[3]
            if x % 4 == 0: color = c_wood[1] # Planks
            apply_shading(draw, x, y, scale, color)
    for y in (8, 22): # Hoops
        for x in range(6, 26): apply_shading(draw, x, y, scale, c_metal[1])

def draw_crate(draw, scale):
    for y in range(8, 24):
        for x in range(8, 24):
            color = c_wood[2]
            if x in (8, 9, 22, 23) or y in (8, 9, 22, 23): color = c_wood[1]
            if x == 8 or y == 8 or x == 23 or y == 23: color = c_wood[0]
            if x == y or 31 - x == y: color = c_wood[1] # X bracing
            apply_shading(draw, x, y, scale, color)

def draw_skull_pile(draw, scale):
    def skull(cx, cy):
        for y in range(cy-2, cy+3):
            for x in range(cx-2, cx+3):
                if (x-cx)**2 + (y-cy)**2 < 6: apply_shading(draw, x, y, scale, c_bone[2])
        apply_shading(draw, cx-1, cy, scale, (0,0,0,255)) # eyes
        apply_shading(draw, cx+1, cy, scale, (0,0,0,255))
    for cx, cy in [(14, 24), (18, 26), (12, 28), (20, 24), (16, 22)]:
        skull(cx, cy)
        
def draw_cobweb(draw, scale):
    # Top right corner web
    for y in range(0, 16):
        for x in range(16, 32):
            if (x+y) % 6 == 0 or x == 31 or y == 0:
                if x + y > 20:
                    apply_shading(draw, x, y, scale, c_web[random.randint(1,2)])

def draw_broken_pillar(draw, scale):
    for y in range(12, 32):
        for x in range(12, 20):
            if y < 16 and (x % 3 == 0 or random.random() > 0.7): continue # Top crumble
            color = c_stone[2] if x < 16 else c_stone[1]
            if x in (12, 19): color = c_stone[0]
            apply_shading(draw, x, y, scale, color)

def draw_wall_torch(draw, scale):
    # Bracket
    for y in range(16, 24):
        apply_shading(draw, 15, y, scale, c_metal[1])
        apply_shading(draw, 16, y, scale, c_metal[0])
    for x in range(12, 20): apply_shading(draw, x, 20, scale, c_metal[1])
    # Fire
    for dy in range(-4, 5):
        for dx in range(-3, 4):
            if dy + abs(dx) < 2 and random.random() > 0.2:
                apply_shading(draw, 15 + dx, 14 + dy, scale, c_fire[random.randint(1,3)])

# --- Crypt Biome ---

def draw_coffin(draw, scale):
    for y in range(4, 28):
        w = 6 if 8 < y < 20 else 4
        for x in range(16 - w, 16 + w):
            color = c_stone[2] if x < 16 else c_stone[1]
            if x == 16 - w or x == 16 + w - 1 or y in (4, 27): color = c_stone[0]
            if x == 16: color = c_stone[0] # Center line
            apply_shading(draw, x, y, scale, color)

def draw_tombstone(draw, scale):
    for y in range(10, 32):
        w = 8
        if y < 14: w = 8 - (14 - y) # Rounded top
        for x in range(16 - w, 16 + w):
            color = c_stone[2] if x < 16 else c_stone[1]
            if x == 16 - w or x == 16 + w - 1 or y == 10: color = c_stone[0]
            if 14 < y < 22 and 12 < x < 20 and (x+y)%3==0: color = c_stone[0] # Engraving grooves
            apply_shading(draw, x, y, scale, color)

def draw_iron_maiden(draw, scale):
    for y in range(4, 30):
        w = 7 if 8 < y < 24 else 5
        for x in range(16 - w, 16 + w):
            color = c_metal[1]
            if x == 16 - w or x == 16 + w - 1 or y in (4, 29): color = c_metal[0]
            if x == 16: color = (10, 10, 10, 255) # Deep split
            if y % 4 == 0: color = c_metal[2] # Bands
            apply_shading(draw, x, y, scale, color)
    # Spikes inside
    for y in (12, 16, 20):
        apply_shading(draw, 15, y, scale, c_metal[2])
        apply_shading(draw, 17, y, scale, c_metal[2])

def draw_candelabra(draw, scale):
    # Stand
    for y in range(16, 30): apply_shading(draw, 16, y, scale, c_metal[1])
    for x in range(12, 21): apply_shading(draw, x, 30, scale, c_metal[1])
    # Arms
    for x in range(10, 23): apply_shading(draw, x, 16, scale, c_metal[1])
    # Candles
    for cx in (10, 16, 22):
        for y in range(12, 16): apply_shading(draw, cx, y, scale, (200, 200, 200, 255)) # Wax
        apply_shading(draw, cx, 11, scale, c_fire[3]) # Flame
        apply_shading(draw, cx, 10, scale, c_fire[1])

def draw_banner(draw, scale):
    # Rod
    for x in range(6, 26): apply_shading(draw, x, 2, scale, c_wood[0])
    # Cloth
    for y in range(3, 26):
        for x in range(8, 24):
            if y > 20 and (x % 4 == 0 or random.random() > 0.7): continue # Tears
            color = (150, 20, 30, 255) if x < 16 else (100, 10, 20, 255) # Red cloth
            if x == 8 or x == 23: color = (50, 0, 10, 255)
            # Emblem/Trim
            if 12 < x < 20 and 8 < y < 16: color = (200, 150, 50, 255) # Gold logo
            apply_shading(draw, x, y, scale, color)

def draw_bone_pile(draw, scale):
    for i in range(20):
        x = random.randint(8, 24)
        y = random.randint(24, 30)
        apply_shading(draw, x, y, scale, c_bone[2])
        apply_shading(draw, x+1, y, scale, c_bone[1])

# --- Fungal Biome ---

c_fungus = [(50, 10, 100, 255), (100, 30, 150, 255), (150, 60, 200, 255)]
c_glow = [(0, 150, 50, 150), (0, 200, 100, 200), (0, 255, 150, 255)]

def draw_giant_mushroom(draw, scale):
    # Stalk
    for y in range(16, 30):
        for x in range(14, 19): apply_shading(draw, x, y, scale, c_bone[1])
    # Cap
    for y in range(6, 16):
        w = y - 4 if y < 12 else 12 - (y-10)
        for x in range(16 - w, 16 + w):
            color = c_fungus[2] if y < 10 else c_fungus[1]
            if x == 16 - w or x == 16 + w - 1 or y == 6: color = c_fungus[0]
            if random.random() > 0.9: color = c_glow[2] # Glowing spots
            apply_shading(draw, x, y, scale, color)

def draw_slime_pool(draw, scale):
    for y in range(24, 30):
        w = 12 if 25 < y < 29 else 8
        for x in range(16 - w, 16 + w):
            if random.random() > 0.8: continue
            color = c_glow[1] if x < 16 else c_glow[0]
            if y == 26 and x % 3 == 0: color = c_glow[2] # Specular hit
            apply_shading(draw, x, y, scale, color)

def draw_vine_wall(draw, scale):
    for i in range(5):
        x = random.randint(4, 28)
        length = random.randint(10, 30)
        for y in range(0, length):
            color = (30, 100, 30, 255) if random.random() > 0.5 else (20, 60, 20, 255)
            # Vines wander
            if random.random() > 0.5: x += random.choice([-1, 1])
            apply_shading(draw, x, y, scale, color)
            apply_shading(draw, x+1, y, scale, color)

def draw_fungal_pods(draw, scale):
    # Draw a few bulbous pods
    for px, py in [(12, 26), (20, 28), (16, 24)]:
        for y in range(py-3, py+4):
            for x in range(px-3, px+4):
                if (x-px)**2 + (y-py)**2 < 12:
                    color = c_fungus[1] if x < px else c_fungus[0]
                    if x == px and y == py: color = c_glow[2] # Center vent
                    apply_shading(draw, x, y, scale, color)

def draw_moss_rock(draw, scale):
    for y in range(20, 30):
        w = 8 if 22 < y < 28 else 5
        for x in range(16 - w, 16 + w):
            color = c_stone[2] if x < 16 else c_stone[1]
            if x == 16 - w or x == 16 + w - 1 or y == 20: color = c_stone[0]
            if random.random() > 0.5 and y < 26: color = (40, 120, 40, 255) # Moss
            apply_shading(draw, x, y, scale, color)

def draw_biology_crystal(draw, scale):
    for y in range(10, 30):
        w = 3 if 14 < y < 28 else 1
        for x in range(16 - w, 16 + w):
            color = c_glow[2] if x == 15 else c_glow[1]
            if x in (16 - w, 16 + w - 1): color = c_glow[0]
            apply_shading(draw, x, y, scale, color)

# --- Lava Biome ---

c_magma = [(100, 0, 0, 255), (200, 50, 0, 255), (255, 150, 0, 255), (255, 255, 100, 255)]
c_obsidian = [(10, 10, 15, 255), (30, 30, 40, 255), (60, 60, 80, 255)]

def draw_lava_crack(draw, scale):
    x = 16
    for y in range(16, 32):
        if random.random() > 0.5: x += random.choice([-1, 1])
        w = 2 if 20 < y < 28 else 1
        for dx in range(-w, w+1):
            color = c_magma[3] if dx == 0 else c_magma[1]
            apply_shading(draw, x+dx, y, scale, color)

def draw_obsidian_spike(draw, scale):
    for y in range(8, 30):
        w = (y - 4) // 3
        for x in range(16 - w, 16 + w):
            color = c_obsidian[2] if x == 15 else c_obsidian[1]
            if x == 16 - w or x == 16 + w - 1: color = c_obsidian[0]
            # Sharp reflective edge
            if x == 14 and random.random() > 0.5: color = (100, 100, 150, 255) 
            apply_shading(draw, x, y, scale, color)

def draw_ember_brazier(draw, scale):
    # Stand
    for y in range(18, 30):
        apply_shading(draw, 14, y, scale, c_metal[1])
        apply_shading(draw, 17, y, scale, c_metal[1])
    # Bowl
    for y in range(14, 18):
        for x in range(10, 22):
            color = c_metal[2] if x < 16 else c_metal[1]
            if x in (10, 21): color = c_metal[0]
            apply_shading(draw, x, y, scale, color)
    # Coals and Fire
    for y in range(12, 16):
        for x in range(12, 20):
            if random.random() > 0.3:
                apply_shading(draw, x, y, scale, c_magma[random.randint(1,3)])
            else:
                apply_shading(draw, x, y, scale, c_metal[0]) # Ash/Black coal

def draw_charred_bones(draw, scale):
    for i in range(15):
        x = random.randint(10, 22)
        y = random.randint(26, 30)
        color = c_bone[0] if random.random() > 0.5 else (20, 20, 20, 255) # Charred
        apply_shading(draw, x, y, scale, color)

def draw_magma_rock(draw, scale):
    for y in range(20, 30):
        w = 8 if 22 < y < 28 else 6
        for x in range(16 - w, 16 + w):
            color = c_obsidian[1]
            if x == 16 - w or x == 16 + w - 1 or y == 20: color = c_obsidian[0]
            # Magma veins
            if (x*y) % 7 == 0: color = c_magma[2]
            apply_shading(draw, x, y, scale, color)

def draw_sulfur_vent(draw, scale):
    # Base
    for y in range(24, 30):
        w = 7 if y > 26 else 5
        for x in range(16 - w, 16 + w):
            color = (150, 150, 50, 255) if x < 16 else (100, 100, 30, 255) # Yellow-ish rock
            if x == 16 - w or x == 16 + w - 1: color = (50, 50, 20, 255)
            apply_shading(draw, x, y, scale, color)
    # Gas (Opacity)
    for i in range(20):
        x = random.randint(12, 20)
        y = random.randint(8, 22)
        apply_shading(draw, x, y, scale, (200, 255, 100, 100))

# --- GENERATION QUEUE ---

props = {
    # Universal
    "prop_barrel.png": draw_barrel,
    "prop_crate.png": draw_crate,
    "prop_skull_pile.png": draw_skull_pile,
    "prop_cobweb.png": draw_cobweb,
    "prop_broken_pillar.png": draw_broken_pillar,
    "prop_wall_torch.png": draw_wall_torch,
    
    # Crypt
    "Crypt/prop_crypt_coffin.png": draw_coffin,
    "Crypt/prop_crypt_tombstone.png": draw_tombstone,
    "Crypt/prop_crypt_iron_maiden.png": draw_iron_maiden,
    "Crypt/prop_crypt_candelabra.png": draw_candelabra,
    "Crypt/prop_crypt_banner.png": draw_banner,
    "Crypt/prop_crypt_bone_pile.png": draw_bone_pile,
    
    # Fungal
    "Fungal/prop_fungal_mushroom.png": draw_giant_mushroom,
    "Fungal/prop_fungal_slime_pool.png": draw_slime_pool,
    "Fungal/prop_fungal_vines.png": draw_vine_wall,
    "Fungal/prop_fungal_pods.png": draw_fungal_pods,
    "Fungal/prop_fungal_moss_rock.png": draw_moss_rock,
    "Fungal/prop_fungal_crystal.png": draw_biology_crystal,

    # Lava
    "Lava/prop_lava_crack.png": draw_lava_crack,
    "Lava/prop_lava_spike.png": draw_obsidian_spike,
    "Lava/prop_lava_brazier.png": draw_ember_brazier,
    "Lava/prop_lava_charred_bones.png": draw_charred_bones,
    "Lava/prop_lava_magma_rock.png": draw_magma_rock,
    "Lava/prop_lava_sulfur_vent.png": draw_sulfur_vent
}

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Environment"
    os.makedirs(os.path.join(base_dir, "Crypt"), exist_ok=True)
    os.makedirs(os.path.join(base_dir, "Fungal"), exist_ok=True)
    os.makedirs(os.path.join(base_dir, "Lava"), exist_ok=True)
    
    scale = 4 # 128x128 output size for all props since these are rendered as billboard sprites
    w, h = 128, 128
    
    for filename, func in props.items():
        img = create_base_img(w, h)
        draw = ImageDraw.Draw(img)
        
        func(draw, scale)
        
        out_path = os.path.join(base_dir, filename)
        img.save(out_path)
        print(f"Generated {out_path}")
