import os
import random
from PIL import Image, ImageDraw

def apply_shading(draw, x, y, scale, color):
    draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

def get_base_color(base_idx, x, y, palette, default=0):
    # Deterministic base color for border consistency
    return palette[(x * 7 + y * 13 + base_idx) % 2 + 1]

def generate_stone_wall(output_path, variant=1):
    random.seed(variant * 100) # Different internal variations
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    scale = 8
    grid_size = 32
    
    c_stone = [(40, 40, 45, 255), (70, 70, 80, 255), (100, 100, 110, 255), (130, 130, 140, 255)]
    c_mortar = (20, 20, 25, 255)
    
    brick_width = 8
    brick_height = 4
    
    for by in range(0, grid_size, brick_height):
        offset = (by // brick_height % 2) * (brick_width // 2)
        for bx in range(-brick_width, grid_size, brick_width):
            start_x = bx + offset
            start_y = by
            
            # Deterministic base color so edges of ALL variants match!
            base_color_idx = get_base_color(1, bx, by, c_stone)
            
            for y in range(brick_height):
                for x in range(brick_width):
                    px = start_x + x
                    py = start_y + y
                    
                    if 0 <= px < grid_size and 0 <= py < grid_size:
                        is_border = (x == brick_width - 1 or y == brick_height - 1)
                        is_edge_pixel = (px <= 1 or px >= grid_size - 2 or py <= 1 or py >= grid_size - 2)
                        
                        if is_border:
                            apply_shading(draw, px, py, scale, c_mortar)
                        else:
                            color = base_color_idx
                            if x == 0 or y == 0: color = c_stone[2] # Highlight
                            elif x == brick_width - 2 or y == brick_height - 2: color = c_stone[1] # Shadow
                            
                            # Add random cracks/divots in the CENTER of the variants (leave edges mostly clean to ensure seamlessness)
                            if not is_edge_pixel and random.random() > 0.8:
                                color = c_stone[0]
                                
                            # Variant specific extreme details in the center of the bricks
                            if variant == 2 and not is_edge_pixel and random.random() > 0.9:
                                color = (40, 60, 45, 255) # Mossy patch
                            if variant == 3 and not is_edge_pixel and random.random() > 0.9:
                                color = (30, 30, 35, 255) # Deep cracks
                            
                            apply_shading(draw, px, py, scale, color)
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path}")

def generate_cobblestone_floor(output_path, variant=1):
    random.seed(variant * 200)
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    scale = 8
    grid_size = 32
    
    c_stone = [(30, 30, 30, 255), (50, 50, 50, 255), (80, 80, 80, 255), (110, 110, 110, 255)]
    c_dirt = (20, 15, 10, 255)
    
    draw.rectangle([0, 0, width, height], fill=c_dirt)
    
    # We use a fixed random seed FOR THE GRID so the stones are placed identically
    # on the edges across all variants, but inner stones can change or be missing!
    grid_rnd = random.Random(42) 
    
    for y in range(0, grid_size, 4):
        for x in range(0, grid_size, 4):
            # Same base layout
            skip_prob = 0.8 if grid_rnd.random() > 0.8 else 0.0
            
            # Variant specific gaps only in the middle
            is_edge = (x <  4 or x >= grid_size - 4 or y < 4 or y >= grid_size - 4)
            if not is_edge:
                if random.random() > 0.6: skip_prob = 1.0 # Miss a stone!
                
            if skip_prob == 1.0: continue
            
            w = grid_rnd.randint(2, 4)
            h = grid_rnd.randint(2, 4)
            jx = x + grid_rnd.randint(-1, 1)
            jy = y + grid_rnd.randint(-1, 1)
            
            base_col_idx = grid_rnd.randint(1, 2)
            
            for dy in range(h):
                for dx in range(w):
                    px = (jx + dx) % grid_size
                    py = (jy + dy) % grid_size
                    
                    if (dx == 0 and dy == 0) or (dx == w-1 and dy == h-1) or \
                       (dx == w-1 and dy == 0) or (dx == 0 and dy == h-1):
                        continue
                    
                    color = c_stone[base_col_idx]
                    if dx == 1 and dy == 1: color = c_stone[base_col_idx + 1]
                    elif dx == w - 1 or dy == h - 1: color = c_stone[base_col_idx - 1]
                        
                    # Inner color noise
                    if not is_edge and random.random() > 0.8:
                        if variant == 2: color = (40, 50, 40, 255) # Greenish
                        if variant == 3: color = (60, 50, 40, 255) # Brownish
                        
                    apply_shading(draw, px, py, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path}")

def generate_wood_ceiling(output_path, variant=1):
    random.seed(variant * 300)
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    scale = 8
    grid_size = 32
    
    c_wood = [(20, 10, 5, 255), (40, 20, 10, 255), (60, 30, 15, 255), (90, 50, 25, 255)]
    plank_height = 4
    
    for py in range(0, grid_size, plank_height):
        # Base color deterministic so edge matches
        plank_color_base = (py // plank_height) % 2 + 1 
        
        for x in range(grid_size):
            apply_shading(draw, x, py, scale, c_wood[0])
            
        for y in range(1, plank_height):
            for x in range(grid_size):
                color = c_wood[plank_color_base]
                is_edge_x = (x <= 1 or x >= grid_size - 2)
                
                # Wood grain
                grain_rnd = random.random()
                if is_edge_x: 
                    # Deterministic grain on edges
                    grain_rnd = (x * 13 + py * 7) % 100 / 100.0
                    
                if grain_rnd > 0.7:
                    color = c_wood[plank_color_base - 1] if grain_rnd > 0.85 else c_wood[plank_color_base + 1]
                
                if y == 1: color = c_wood[plank_color_base + 1] # Highlight
                
                # Variant damage/rot
                if not is_edge_x and variant == 2 and random.random() > 0.95:
                    color = c_wood[0] # Missing chunk
                if not is_edge_x and variant == 3 and random.random() > 0.9:
                    color = (40, 30, 30, 255) # Rot/dark damp spot
                    
                apply_shading(draw, x, py + y, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path}")

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Environment"
    
    for v in range(1, 4):
        generate_stone_wall(os.path.join(base_dir, f"stone_wall_v{v}.png"), v)
        generate_cobblestone_floor(os.path.join(base_dir, f"cobblestone_floor_v{v}.png"), v)
        generate_wood_ceiling(os.path.join(base_dir, f"wood_ceiling_v{v}.png"), v)
