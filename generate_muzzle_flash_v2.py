import os, random, math
from PIL import Image, ImageDraw

def create_muzzle_flash_sheet(output_path):
    # Create 4 frames of muzzle flashes in a 2x2 grid
    sheet = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    
    for i in range(4):
        frame = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        draw = ImageDraw.Draw(frame)
        cx, cy = 64, 64
        
        # 1. Main energy blob
        r_main = random.randint(15, 30)
        draw.ellipse([cx-r_main, cy-r_main*0.7, cx+r_main, cy+r_main*0.7], fill=(255, 255, 200, 255))
        draw.ellipse([cx-r_main*0.6, cy-r_main*0.4, cx+r_main*0.6, cy+r_main*0.4], fill=(255, 255, 255, 255))
        
        # 2. Spiky sparks
        num_spikes = random.randint(6, 12)
        for _ in range(num_spikes):
            angle = random.uniform(0, math.pi * 2)
            length = random.uniform(30, 60)
            width = random.randint(2, 6)
            
            # Tapered line (simple)
            ex, ey = cx + math.cos(angle) * length, cy + math.sin(angle) * length
            draw.line([cx, cy, ex, ey], fill=(255, 200, 50, 255), width=width)
            
            # White core
            draw.line([cx, cy, cx + math.cos(angle) * length * 0.4, cy + math.sin(angle) * length * 0.4], fill=(255, 255, 255, 255), width=max(1, width-2))
        
        # 3. Small floating sparks
        for _ in range(15):
            angle = random.uniform(0, math.pi * 2)
            dist = random.uniform(10, 50)
            sx, sy = cx + math.cos(angle) * dist, cy + math.sin(angle) * dist
            sr = random.randint(1, 3)
            draw.ellipse([sx-sr, sy-sr, sx+sr, sy+sr], fill=(255, 120, 0, 255))

        sheet.paste(frame, ((i % 2) * 128, (i // 2) * 128))
    
    # Save it!
    sheet.save(output_path)
    print(f"Saved: {output_path}")

if __name__ == "__main__":
    os.makedirs(r"j:\BoomerShooter\boomer-shooter\Assets\Weapons", exist_ok=True)
    create_muzzle_flash_sheet(r"j:\BoomerShooter\boomer-shooter\Assets\Weapons\muzzle_flash_sheet.png")
