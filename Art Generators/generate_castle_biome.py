import os
import random
from PIL import Image, ImageDraw

def apply_shading(draw, x, y, scale, color):
    draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

def generate_castle_wall(output_path, variant=1):
    random.seed(variant * 100)
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    scale = 8
    grid_size = 32
    
    c_stone = [(35, 35, 45, 255), (60, 60, 75, 255), (90, 90, 105, 255), (130, 130, 145, 255)]
    c_mortar = (15, 15, 20, 255)
    
    brick_width = 16
    brick_height = 8
    
    for by in range(0, grid_size, brick_height):
        offset = (by // brick_height % 2) * (brick_width // 2)
        for bx in range(-brick_width, grid_size, brick_width):
            start_x = bx + offset
            start_y = by
            
            # Deterministic base color so all variant edges align
            base_color_idx = (bx*3 + by*7) % 2 + 1 
            
            for y in range(brick_height):
                for x in range(brick_width):
                    px = start_x + x
                    py = start_y + y
                    
                    if 0 <= px < grid_size and 0 <= py < grid_size:
                        is_edge = (x == brick_width - 1 or y == brick_height - 1)
                        is_border_px = (px <= 1 or py <= 1 or px >= grid_size - 2 or py >= grid_size - 2)
                        
                        if is_edge:
                            apply_shading(draw, px, py, scale, c_mortar)
                        else:
                            color = c_stone[base_color_idx]
                            if x == 0 or y == 0: color = c_stone[base_color_idx + 1]
                            elif x == brick_width - 2 or y == brick_height - 2: color = c_stone[base_color_idx - 1]
                            
                            # Random variant details only in the interior to preserve seamless tiling
                            if not is_border_px:
                                if x % 4 == 0 and random.random() > 0.9: color = c_stone[0] # Vertical crack
                                if variant == 2 and random.random() > 0.95: color = (100, 100, 90, 255) # Discoloration
                                if variant == 3 and random.random() > 0.95: color = (40, 50, 40, 255) # Damp moss
                                
                            apply_shading(draw, px, py, scale, color)
    
    img.save(output_path)

def generate_castle_floor(output_path, variant=1):
    random.seed(variant * 200)
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    scale = 8
    grid_size = 32
    
    c_stone = [(40, 40, 40, 255), (65, 65, 65, 255), (95, 95, 100, 255), (120, 120, 125, 255)]
    c_mortar = (20, 20, 20, 255)
    slab_size = 16
    
    for sy in range(0, grid_size, slab_size):
        for sx in range(0, grid_size, slab_size):
            base_col_idx = (sx*5 + sy*11) % 2 + 1
            
            for y in range(slab_size):
                for x in range(slab_size):
                    px = sx + x
                    py = sy + y
                    
                    is_border_px = (px <= 1 or py <= 1 or px >= grid_size - 2 or py >= grid_size - 2)
                    
                    if x == slab_size - 1 or y == slab_size - 1:
                        apply_shading(draw, px, py, scale, c_mortar)
                    else:
                        color = c_stone[base_col_idx]
                        if x == 0 or y == 0: color = c_stone[base_col_idx + 1]
                        elif x == slab_size - 2 or y == slab_size - 2: color = c_stone[base_col_idx - 1]
                        
                        if not is_border_px:
                            # Subtle wear
                            if random.random() > 0.97: color = c_stone[0]
                            if variant == 2 and random.random() > 0.9: color = c_stone[max(0, base_col_idx - 1)]
                            if variant == 3 and random.random() > 0.95: color = (100, 30, 30, 255) # Blood spots
                            
                        apply_shading(draw, px, py, scale, color)

    img.save(output_path)

def generate_castle_ceiling(output_path, variant=1):
    random.seed(variant * 300)
    width, height = 256, 256
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    scale = 8
    grid_size = 32
    
    c_wood = [(15, 10, 5, 255), (30, 20, 10, 255), (50, 35, 15, 255), (80, 55, 25, 255)]
    c_iron = [(20, 20, 25, 255), (45, 45, 50, 255), (80, 80, 90, 255)]
    plank_width = 8
    
    for px in range(0, grid_size, plank_width):
        base_col = (px*7) % 2 + 1
        
        for x in range(plank_width):
            for y in range(grid_size):
                is_border_px = (px+x <= 1 or py <= 1 or px+x >= grid_size - 2 or py >= grid_size - 2)
                
                if x == plank_width - 1:
                    color = c_wood[0]
                else:
                    color = c_wood[base_col]
                    if x == 0: color = c_wood[base_col + 1]
                    
                    if not is_border_px and random.random() > 0.8: # grain
                        color = c_wood[base_col - 1] if random.random() > 0.5 else c_wood[min(3, base_col + 1)]
                        
                    # Variants
                    if not is_border_px and variant == 2 and random.random() > 0.95: color = c_wood[0] # Deep gouge
                    if not is_border_px and variant == 3 and random.random() > 0.9: color = (40, 30, 30, 255) # Dark stain
                        
                apply_shading(draw, px + x, y, scale, color)
                
    # Iron Cross-Beams
    for y in (0, 1, 15, 16, 30, 31):
        for x in range(grid_size):
            color = c_iron[1]
            if y % 2 == 0: color = c_iron[2]
            else: color = c_iron[0]
            # Rivets
            if x % 8 == 0: color = (120, 120, 130, 255)
            
            # Add rust for variants
            if variant == 2 and random.random() > 0.8: color = (100, 50, 30, 255) # Extra rusty band
            if variant == 3 and random.random() > 0.9: color = (60, 30, 20, 255)
            
            apply_shading(draw, x, y, scale, color)

    img.save(output_path)

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Environment\Castle"
    os.makedirs(base_dir, exist_ok=True)
    
    for v in range(1, 4):
        generate_castle_wall(os.path.join(base_dir, f"castle_wall_v{v}.png"), v)
        generate_castle_floor(os.path.join(base_dir, f"castle_floor_v{v}.png"), v)
        generate_castle_ceiling(os.path.join(base_dir, f"castle_ceiling_v{v}.png"), v)
        print(f"Castle biome variant {v} generated.")
