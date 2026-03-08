import os
from PIL import Image, ImageDraw
import random

def apply_shading(draw, x, y, scale, color):
    draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

def generate_health_potion(output_path):
    width, height = 64, 64
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4 # 16x16 grid
    
    c_glass = [(150, 200, 255, 100), (200, 230, 255, 150), (255, 255, 255, 200)]
    c_liquid = [(150, 0, 0, 255), (200, 20, 20, 255), (255, 50, 50, 255)]
    c_cork = [(100, 60, 30, 255), (150, 90, 50, 255)]
    
    # Cork
    apply_shading(draw, 7, 2, scale, c_cork[0])
    apply_shading(draw, 8, 2, scale, c_cork[1])
    apply_shading(draw, 7, 3, scale, c_cork[0])
    apply_shading(draw, 8, 3, scale, c_cork[0])
    
    # Neck
    apply_shading(draw, 6, 4, scale, c_glass[1])
    apply_shading(draw, 9, 4, scale, c_glass[0])
    
    # Bowl
    for y in range(5, 14):
        w = 4 + (y - 4) if y < 10 else 9 - (y - 9)
        for x in range(8 - w//2, 8 + w//2):
            # Liquid level
            if y > 6:
                color = c_liquid[2] if x < 6 else (c_liquid[1] if x < 10 else c_liquid[0])
                if y == 7: color = c_liquid[2] # Surface reflection
            else:
                color = c_glass[1] if x < 7 else c_glass[0]
                
            # Specular highlight
            if x == 5 and 7 <= y <= 9: color = c_glass[2]
            
            # Rim shadow
            if x == 8 - w//2 or x == 8 + w//2 - 1: color = c_glass[0]
            
            apply_shading(draw, x, y, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)

def generate_ammo_box(output_path):
    width, height = 64, 64
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4 # 16x16 grid
    
    c_box = [(40, 50, 40, 255), (60, 80, 60, 255), (90, 110, 90, 255)] # Dark olive green
    c_metal = [(80, 80, 80, 255), (150, 150, 150, 255)]
    c_bullet = [(200, 150, 50, 255), (255, 200, 100, 255)]
    
    # Box base
    for y in range(6, 14):
        for x in range(3, 13):
            color = c_box[2]
            if x in (3, 12) or y == 13: color = c_box[0]
            elif x > 9: color = c_box[1]
            apply_shading(draw, x, y, scale, color)
            
    # Metal latches / corners
    for x in (3, 12):
        for y in (6, 13):
            apply_shading(draw, x, y, scale, c_metal[1])
            
    # Bullet icon on side
    apply_shading(draw, 7, 9, scale, c_bullet[0])
    apply_shading(draw, 8, 9, scale, c_bullet[1])
    apply_shading(draw, 7, 10, scale, c_bullet[0])
    apply_shading(draw, 8, 10, scale, c_bullet[1])
    apply_shading(draw, 7, 8, scale, c_bullet[1]) # tip
    
    # Open lid (top)
    for y in range(3, 6):
        for x in range(2, 12):
            color = c_box[1] if x < 8 else c_box[0]
            apply_shading(draw, x, y, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)

def generate_exit_portal(output_path):
    width, height = 128, 128
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4 # 32x32 grid
    
    c_stone = [(50, 50, 60, 255), (80, 80, 90, 255), (120, 120, 130, 255)]
    c_portal = [(200, 50, 255, 100), (150, 100, 255, 180), (255, 200, 255, 255)]
    
    # Portal swirl
    for y in range(4, 28):
        for x in range(8, 24):
            dx, dy = x - 16, y - 16
            dist = dx*dx + dy*dy
            if dist < 120:
                color = c_portal[2] if dist < 16 else (c_portal[1] if dist < 64 else c_portal[0])
                if random.random() > 0.5: color = c_portal[random.randint(0,2)]
                apply_shading(draw, x, y, scale, color)
                
    # Stone Archway
    for y in range(2, 30):
        for x in range(4, 28):
            dx, dy = x - 16, y - 16
            dist = dx*dx + dy*dy
            # Draw arch shape
            if 120 <= dist <= 200 and y < 16:
                color = c_stone[1] if (x+y)%2==0 else c_stone[2]
                if dist > 180: color = c_stone[0]
                apply_shading(draw, x, y, scale, color)
            # Pillars
            elif y >= 16 and (4 <= x <= 8 or 23 <= x <= 27):
                color = c_stone[2] if x in (4, 23) else c_stone[1]
                if x in (8, 27): color = c_stone[0]
                apply_shading(draw, x, y, scale, color)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)

def generate_door(output_path, is_metal=False):
    width, height = 128, 128
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = 4 # 32x32 grid
    
    c_wood = [(40, 20, 10, 255), (70, 40, 20, 255), (100, 60, 30, 255)]
    c_metal = [(40, 40, 40, 255), (80, 80, 80, 255), (120, 120, 120, 255)]
    
    if is_metal:
        # Portcullis
        for y in range(2, 30):
            for x in range(4, 28):
                # Vertical bars
                if x % 6 == 0 or x % 6 == 1:
                    apply_shading(draw, x, y, scale, c_metal[2] if x%6==0 else c_metal[1])
                # Horizontal bars
                elif y % 8 == 0 or y % 8 == 1:
                    apply_shading(draw, x, y, scale, c_metal[1] if y%8==0 else c_metal[0])
    else:
        # Wooden Door
        for y in range(2, 30):
            for x in range(4, 28):
                color = c_wood[2]
                # Wood grain
                if random.random() > 0.7: color = c_wood[1]
                # Plank gaps
                if x % 4 == 0: color = c_wood[0]
                # Edge shadow
                if x == 4 or x == 27 or y == 2 or y == 29: color = c_wood[0]
                
                apply_shading(draw, x, y, scale, color)
                
        # Iron bands
        for y in (6, 7, 24, 25):
            for x in range(4, 28):
                apply_shading(draw, x, y, scale, c_metal[1] if y in (6,24) else c_metal[0])
        
        # Doorknob/Ring
        apply_shading(draw, 22, 15, scale, c_metal[2])
        apply_shading(draw, 23, 15, scale, c_metal[1])

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)

def generate_projectiles():
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Projectiles"
    os.makedirs(base_dir, exist_ok=True)
    scale = 2 # 16x16 image -> 8x8 grid
    
    def apply_proj(draw, x, y, color):
        draw.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=color)

    # Fireball
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(2, 6):
        for x in range(2, 6):
            c = (255, 255, 0, 255) if x+y < 8 else (255, 100, 0, 255)
            if x==2 or y==2: c = (255, 50, 0, 200)
            apply_proj(d, x, y, c)
    img.save(os.path.join(base_dir, "proj_fireball.png"))
    
    # Magic Bolt (Blue)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    apply_proj(d, 3, 3, (255, 255, 255, 255))
    apply_proj(d, 2, 3, (0, 255, 255, 200))
    apply_proj(d, 4, 3, (0, 255, 255, 200))
    apply_proj(d, 3, 2, (0, 255, 255, 200))
    apply_proj(d, 3, 4, (0, 255, 255, 200))
    img.save(os.path.join(base_dir, "proj_magic.png"))
    
    # Arrow
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(1, 6):
        apply_proj(d, i, i, (150, 100, 50, 255)) # Shaft
    apply_proj(d, 5, 5, (200, 200, 200, 255)) # Arrowhead
    apply_proj(d, 6, 5, (200, 200, 200, 255))
    apply_proj(d, 5, 6, (200, 200, 200, 255))
    apply_proj(d, 0, 1, (255, 255, 255, 255)) # Fletching
    apply_proj(d, 1, 0, (255, 255, 255, 255))
    img.save(os.path.join(base_dir, "proj_arrow.png"))
    
    # Bullet/Pellet
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    apply_proj(d, 3, 3, (255, 200, 0, 255))
    apply_proj(d, 3, 4, (200, 150, 0, 255))
    apply_proj(d, 4, 3, (255, 255, 100, 255))
    img.save(os.path.join(base_dir, "proj_bullet.png"))
    print(f"Generated projectiles in {base_dir}")

if __name__ == "__main__":
    pickups_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Pickups"
    env_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Environment"
    
    generate_health_potion(os.path.join(pickups_dir, "pickup_health.png"))
    generate_ammo_box(os.path.join(pickups_dir, "pickup_ammo.png"))
    
    generate_exit_portal(os.path.join(env_dir, "exit_portal.png"))
    generate_door(os.path.join(env_dir, "door_wood.png"), is_metal=False)
    generate_door(os.path.join(env_dir, "door_metal.png"), is_metal=True)
    
    generate_projectiles()
    
    print("Pickups, portal, doors, and projectiles generated successfully.")
