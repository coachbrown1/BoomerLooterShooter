import os
from PIL import Image

def generate_sprite_sheet(idle_image_path, output_path):
    try:
        img = Image.open(idle_image_path).convert("RGBA")
    except Exception as e:
        print(f"Failed to open {idle_image_path}: {e}")
        return

    w, h = img.size
    
    # Create a 4-frame sprite sheet (Idle, Walk, Attack, Death)
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    
    # Frame 0: Idle (Copy)
    sheet.paste(img, (0, 0))
    
    # Frame 1: Walk (Slight bob down, maybe stretch X very slightly)
    # Just shift down by 4 pixels (since our grid scale is 4 or 8)
    walk_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    walk_img.paste(img, (0, 8)) # Bob down 8 pixels
    sheet.paste(walk_img, (w, 0))
    
    # Frame 2: Attack (Lunge forward/tilt)
    # We will just shift left and up slightly
    attack_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    attack_img.paste(img, (-8, -8))
    # Add a red tint layer simulating rage/attack
    red_tint = Image.new("RGBA", (w, h), (255, 0, 0, 30))
    attack_glow = Image.alpha_composite(attack_img, red_tint)
    # Only keep the original alpha channel
    attack_glow.putalpha(img.split()[3]) 
    attack_img.paste(attack_glow, (0,0), attack_img)
    sheet.paste(attack_img, (w * 2, 0))
    
    # Frame 3: Death (Collapse: scale Y down by half, align to bottom, tint red and dark)
    death_img = img.resize((w, h // 2), Image.NEAREST)
    death_frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # Tint dark red
    red_wash = Image.new("RGBA", (w, h // 2), (100, 0, 0, 100))
    death_tinted = Image.alpha_composite(death_img, red_wash)
    death_tinted.putalpha(death_img.split()[3])
    # Paste at the bottom
    death_frame.paste(death_tinted, (0, h - (h // 2)))
    sheet.paste(death_frame, (w * 3, 0))

    sheet.save(output_path)
    print(f"Generated sprite sheet: {output_path}")

if __name__ == "__main__":
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies"
    
    if not os.path.exists(base_dir):
        print("Enemies directory not found!")
        exit()
        
    for enemy_folder in os.listdir(base_dir):
        folder_path = os.path.join(base_dir, enemy_folder)
        if os.path.isdir(folder_path):
            # Find the idle image
            for f in os.listdir(folder_path):
                if f.endswith("_idle.png"):
                    idle_path = os.path.join(folder_path, f)
                    
                    # Create the new sprite sheet name
                    base_name = f.replace("_idle.png", "")
                    sheet_name = f"{base_name}_spritesheet.png"
                    sheet_path = os.path.join(folder_path, sheet_name)
                    
                    generate_sprite_sheet(idle_path, sheet_path)
