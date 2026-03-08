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

def generate_rifle_viewmodel(output_path):
    frame_w, frame_h = 256, 256
    num_frames = 2
    img = Image.new("RGBA", (frame_w * num_frames, frame_h), (0, 0, 0, 0))
    scale = 8 # Each "pixel" in our drawing grid is 8x8 actual pixels
    
    c_wood = [(30, 20, 10, 255), (60, 40, 20, 255), (100, 60, 30, 255), (150, 90, 40, 255)]
    c_metal = [(20, 20, 25, 255), (60, 60, 70, 255), (110, 110, 120, 255), (180, 180, 190, 255), (240, 240, 250, 255)]
    c_steel = [(15, 20, 25, 255), (35, 45, 55, 255), (60, 75, 90, 255), (90, 110, 130, 255)]
    
    c_flash = [(255, 255, 0, 180), (255, 120, 0, 220), (255, 255, 255, 255)]
    
    def draw_rifle(frame_index, draw):
        grid_offset_x = frame_index * (frame_w // scale)  # 32 grid units per frame
        
        # Recoil: When firing, the gun punches back (down and slightly right in our 2D foreshortening)
        recoil_y = 3 if frame_index == 1 else 0
        recoil_x = 2 if frame_index == 1 else 0
        
        # We will draw layer by layer from the furthest point (barrel tip) to the nearest point (stock/grip at bottom screen)
        # Screen height is 32 units. 
        # Barrel tip will be near y=12, Center x=16
        # Stock will extend down to y=31, Center x=20 (giving it a slight angled hold)
        
        for y in range(12, 32):
            dist = y - 12  # 0 to 19 (depth map basically)
            cx = 16 + int(dist * 0.25)  # Shifts slightly right as it comes closer
            
            # Barrel segment (Far)
            if dist < 8:
                w = 1 + int(dist * 0.2)  # width grows from 1 to 2
                for x in range(cx - w, cx + w + 1):
                    color = c_metal[2]
                    if x == cx - w: color = c_metal[4] # Highlight on upper/left curve
                    elif x == cx + w: color = c_metal[0] # Shadow on under/right curve
                    
                    # Iron Sight at tip
                    if dist == 1 and x == cx: color = c_metal[1]
                    # Barrel ribbing
                    if dist % 3 == 0: color = c_metal[1]
                    
                    apply_shading(draw, x, y, scale, color, grid_offset_x + recoil_x, recoil_y)
                    
            # Receiver segment (Mid) - Made to look blocky and mechanical
            elif dist < 14:
                w = 2 + int(dist * 0.4) # width grows up to 4
                for x in range(cx - w, cx + w + 1):
                    # Blocky steel lower receiver
                    color = c_steel[2]
                    
                    if x == cx - w: color = c_steel[3] # Left edge highlight
                    elif x == cx + w: color = c_steel[0] # Right edge shadow
                    elif x == cx: color = c_steel[1] # Center indentation groove
                    
                    # Top action rail (Metal)
                    if cx - 1 <= x <= cx + 1 and dist % 2 == 0:
                        color = c_metal[2]
                        if x == cx - 1: color = c_metal[4]
                    
                    apply_shading(draw, x, y, scale, color, grid_offset_x + recoil_x, recoil_y)
                    
            # Stock/Grip segment (Near) — gun only, no hands
            else:
                w = 4 + int(dist * 0.5) # width grows up to ~7
                for x in range(cx - w, cx + w + 1):
                    # Wooden stock base
                    color = c_wood[2]
                    if x == cx - w: color = c_wood[3]    # Left highlight
                    elif x >= cx + w - 1: color = c_wood[0]  # Right shadow
                    # Wood grain streaks
                    if (x + y) % 3 == 0: color = c_wood[1]
                    
                    # Metal action / bolt on top
                    if cx - 2 <= x <= cx + 1:
                        color = c_metal[2]
                        if x == cx - 1: color = c_metal[4] # shine
                        if x == cx + 1: color = c_metal[0] # depth groove
                            
                    apply_shading(draw, x, y, scale, color, grid_offset_x + recoil_x, recoil_y)

        # Muzzle Flash for Frame 1
        if frame_index == 1:
            flash_x = 16 + grid_offset_x
            flash_y = 11  # Centered right at the barrel tip
            
            # Draw an explosive star shape
            for dy in range(-4, 5):
                for dx in range(-5, 6):
                    dist = abs(dx) + abs(dy * 1.5) # slightly flattened vertically due to perspective
                    if dist <= 5:
                        if dist <= 1: color = c_flash[2] # White core
                        elif dist <= 3: color = c_flash[0] # Yellow middle
                        else: color = c_flash[1] # Orange edges
                        
                        # Add chaotic flicker
                        if random.random() > 0.2:
                            px = flash_x + dx - grid_offset_x
                            py = flash_y + dy
                            # The flash stays anchored at the original tip position (not affected by recoil moving the gun away)
                            apply_shading(draw, px, py, scale, color, grid_offset_x, 0)
                            
            # Gun smoke
            for _ in range(6):
                sx = flash_x - grid_offset_x + random.randint(-4, 4)
                sy = flash_y - random.randint(1, 5)
                scolor = (200, 200, 200, random.randint(50, 150))
                apply_shading(draw, sx, sy, scale, scolor, grid_offset_x, 0)

    draw = ImageDraw.Draw(img)
    draw_rifle(0, draw) # Idle
    draw_rifle(1, draw) # Shoot

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path)
    print(f"Generated {output_path} (Foreshortened View)")

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Weapons"
    generate_rifle_viewmodel(os.path.join(base_dir, "weapon_rifle_viewmodel.png"))
