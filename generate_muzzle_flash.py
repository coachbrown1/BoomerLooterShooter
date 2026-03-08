import os, random
from PIL import Image, ImageDraw

def create_muzzle_flash_sheet(output_path):
    # Create 4 frames of muzzle flashes in a 2x2 grid
    sheet = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    
    for i in range(4):
        frame = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        draw = ImageDraw.Draw(frame)
        cx, cy = 64, 64
        
        # Draw some firey sparks/blobs
        for _ in range(8):
            angle = random.uniform(0, 3.14159 * 2)
            dist = random.uniform(5, 45)
            x, y = cx + dist * 1.5 * (1.2 if i%2==0 else 0.8) * (3.14159 % (angle+1)), cy + dist * 0.5
            
            # Use deterministic randoms for better shape
            r = random.randint(10, 30)
            col = random.choice([(255, 200, 50, 255), (255, 120, 0, 255), (255, 255, 200, 255)])
            draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=col)
            
            # Radiating spikes
            for _ in range(3):
                sa = angle + random.uniform(-0.5, 0.5)
                sl = random.uniform(30, 60)
                draw.line([cx, cy, cx + sl * (1.1 if i%2 else 0.9) * (angle+1), cy + sl * (0.8 if i>2 else 1.2)], fill=(255, 255, 180, 255), width=random.randint(2, 5))

        sheet.paste(frame, ((i % 2) * 128, (i // 2) * 128))
        
    sheet.save(output_path)
    print(f"Saved: {output_path}")

if __name__ == "__main__":
    os.makedirs(r"j:\BoomerShooter\boomer-shooter\Assets\Weapons", exist_ok=True)
    create_muzzle_flash_sheet(r"j:\BoomerShooter\boomer-shooter\Assets\Weapons\muzzle_flash_sheet.png")
