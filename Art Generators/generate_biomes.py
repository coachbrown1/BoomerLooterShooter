import os
import random
from PIL import Image, ImageDraw

def apply_shading(draw, x, y, scale, color):
    draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

def generate_noise_texture(size, colors, smoothness=1, seed=0):
    rnd = random.Random(seed)
    
    grid = [[rnd.choice(colors) for _ in range(size)] for _ in range(size)]
    for _ in range(smoothness):
        new_grid = [[grid[y][x] for x in range(size)] for y in range(size)]
        for y in range(size):
            for x in range(size):
                neighbors = []
                for dy in [-1, 0, 1]:
                    for dx in [-1, 0, 1]:
                        nx = (x + dx) % size
                        ny = (y + dy) % size
                        neighbors.append(grid[ny][nx])
                # Find most common neighbor color using our deterministic random 
                # (to break ties consistently without relying on set order)
                counter = {}
                for n in neighbors: counter[n] = counter.get(n, 0) + 1
                max_count = max(counter.values())
                best_colors = [k for k, v in counter.items() if v == max_count]
                new_grid[y][x] = rnd.choice(best_colors)
        grid = new_grid
    return grid

def save_biome_set(biome_name, colors_wall, colors_floor, colors_ceil, dir_path, variant=1):
    os.makedirs(dir_path, exist_ok=True)
    size = 32
    scale = 8 # 256x256 image
    
    # Base pattern is always identically seeded per biome so v1, v2, v3 edges perfectly interlock
    base_seed_w = hash(biome_name + "wall") % 10000
    base_seed_f = hash(biome_name + "floor") % 10000
    base_seed_c = hash(biome_name + "ceil") % 10000

    # Variant specific detail seed
    rnd_v = random.Random(variant * 777)

    # Wall
    img_w = Image.new("RGBA", (256, 256), (0, 0, 0, 255))
    d_w = ImageDraw.Draw(img_w)
    grid_w = generate_noise_texture(size, colors_wall, 2, base_seed_w)
    for y in range(size):
        for x in range(size):
            c = grid_w[y][x]
            is_border_px = (x <= 1 or y <= 1 or x >= size - 2 or y >= size - 2)
            
            # Base horizontal strata logic
            if y % 4 == 0:
                c = colors_wall[0]
            elif y % 4 == 1 and ((x*5+y*7)%100) > 50:
                c = colors_wall[-1]
                
            # Variant overlays (cracks, moss)
            if not is_border_px:
                if variant == 2 and rnd_v.random() > 0.95: c = colors_wall[0] # Deep gouge/crack
                if variant == 3 and rnd_v.random() > 0.9: c = (50, 70, 40, 255) # Greenish mold spots
                
            apply_shading(d_w, x, y, scale, c)
    img_w.save(os.path.join(dir_path, f"{biome_name}_wall_v{variant}.png"))

    # Floor
    img_f = Image.new("RGBA", (256, 256), (0, 0, 0, 255))
    d_f = ImageDraw.Draw(img_f)
    grid_f = generate_noise_texture(size, colors_floor, 3, base_seed_f)
    for y in range(size):
        for x in range(size):
            c = grid_f[y][x]
            is_border_px = (x <= 1 or y <= 1 or x >= size - 2 or y >= size - 2)
            
            # Base cracks
            if ((x*13+y*17)%100) > 95: c = colors_floor[0]
            
            # Variant details
            if not is_border_px:
                if biome_name == "lava":
                    if variant == 2 and rnd_v.random() > 0.9: c = (255, 100, 0, 255) # Extra magma glow
                    if variant == 3 and rnd_v.random() > 0.95: c = (0, 0, 0, 255) # Ash patches
                elif biome_name == "fungal":
                    if variant == 2 and rnd_v.random() > 0.95: c = (100, 255, 150, 200) # Slime puddle
                else: 
                    if variant == 3 and rnd_v.random() > 0.95: c = (80, 20, 20, 255) # Blood/rot
                    
            apply_shading(d_f, x, y, scale, c)
    img_f.save(os.path.join(dir_path, f"{biome_name}_floor_v{variant}.png"))

    # Ceiling
    img_c = Image.new("RGBA", (256, 256), (0, 0, 0, 255))
    d_c = ImageDraw.Draw(img_c)
    grid_c = generate_noise_texture(size, colors_ceil, 1, base_seed_c)
    for y in range(size):
        for x in range(size):
            c = grid_c[y][x]
            is_border_px = (x <= 1 or y <= 1 or x >= size - 2 or y >= size - 2)
            
            # Variant details
            if not is_border_px:
                if biome_name == "fungal" and variant == 2 and rnd_v.random() > 0.9:
                    c = (0, 255, 100, 255) # Extra bio-luminescence
                if variant == 3 and rnd_v.random() > 0.95:
                    c = colors_ceil[0] # Dark spots/holes
                    
            apply_shading(d_c, x, y, scale, c)
    img_c.save(os.path.join(dir_path, f"{biome_name}_ceiling_v{variant}.png"))

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Environment"
    
    c_crypt = [(30, 40, 50, 255), (50, 60, 70, 255), (70, 80, 90, 255), (40, 60, 50, 255)]
    c_fungal_wall = [(40, 20, 50, 255), (60, 30, 70, 255), (30, 60, 40, 255)] 
    c_fungal_floor = [(30, 30, 20, 255), (50, 50, 30, 255), (60, 80, 40, 255)]
    c_fungal_ceil = [(20, 10, 30, 255), (40, 20, 60, 255), (0, 255, 100, 255)]
    c_lava_wall = [(20, 10, 10, 255), (40, 20, 20, 255), (80, 40, 20, 255), (30, 30, 35, 255)]
    c_lava_floor = [(10, 10, 15, 255), (30, 30, 35, 255), (255, 60, 0, 255), (255, 150, 0, 255)]
    c_lava_ceil = [(10, 5, 5, 255), (20, 10, 10, 255), (30, 20, 20, 255)]

    for v in range(1, 4):
        save_biome_set("crypt", c_crypt, c_crypt, [(20, 25, 30, 255), (30, 40, 50, 255)], os.path.join(base_dir, "Crypt"), v)
        save_biome_set("fungal", c_fungal_wall, c_fungal_floor, c_fungal_ceil, os.path.join(base_dir, "Fungal"), v)
        save_biome_set("lava", c_lava_wall, c_lava_floor, c_lava_ceil, os.path.join(base_dir, "Lava"), v)
        
    print("Biome variant sets generated successfully.")
