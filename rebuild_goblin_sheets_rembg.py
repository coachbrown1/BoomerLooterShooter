import os
from PIL import Image
try:
    from rembg import remove, new_session
except ImportError:
    print("rembg not installed. Skipping.")
    exit(1)

def process_attack_grid(grid_path, target_size=(128, 128)):
    print(f"Processing grid with rembg: {grid_path}")
    session = new_session("u2net")
    img = Image.open(grid_path).convert("RGBA")
    w, h = img.size
    
    cell_w, cell_h = w // 2, h // 2
    positions = [(0, 0), (cell_w, 0), (0, cell_h), (cell_w, cell_h)]
    
    attack_frames = []
    
    for i, (x, y) in enumerate(positions):
        frame = img.crop((x, y, x + cell_w, y + cell_h))
        bg_removed = remove(frame, session=session)
        
        # Hard alpha pass to avoid fuzzy outlines
        hard_data = []
        for p in bg_removed.getdata():
            if p[3] > 64:
                hard_data.append((p[0], p[1], p[2], 255))
            else:
                hard_data.append((0, 0, 0, 0))
        bg_removed.putdata(hard_data)
        
        bbox = bg_removed.getbbox()
        if bbox:
            sprite = bg_removed.crop(bbox)
            sw, sh = sprite.size
            ratio = min(120 / sw, 120 / sh)
            new_size = (int(sw * ratio), int(sh * ratio))
            sprite = sprite.resize(new_size, Image.NEAREST)
            
            final_frame = Image.new("RGBA", target_size, (0, 0, 0, 0))
            offset_x = (target_size[0] - new_size[0]) // 2
            offset_y = (128 - new_size[1]) # Align to floor
            final_frame.paste(sprite, (offset_x, offset_y), sprite)
            attack_frames.append(final_frame)
        else:
            attack_frames.append(Image.new("RGBA", target_size, (0, 0, 0, 0)))
            
    return attack_frames

def build_pure_8_frame_sheet(idle_path, attack_grid_path, new_sheet_path):
    print(f"Building pure 8-frame sheet from {idle_path}")
    idle = Image.open(idle_path).convert("RGBA")
    frame_w, frame_h = idle.size
    
    attack_frames = process_attack_grid(attack_grid_path, (frame_w, frame_h))
    
    new_sheet = Image.new("RGBA", (frame_w * 8, frame_h), (0, 0, 0, 0))
    new_sheet.paste(idle, (0, 0))
    
    walk_img = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    walk_img.paste(idle, (0, 8))
    new_sheet.paste(walk_img, (frame_w, 0))
    
    for i, af in enumerate(attack_frames):
        new_sheet.paste(af, (frame_w * (2 + i), 0))
        
    hurt_img = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    hurt_img.paste(idle, (-4, -4))
    red_tint = Image.new("RGBA", (frame_w, frame_h), (255, 0, 0, 100))
    hurt_flash = Image.alpha_composite(hurt_img, red_tint)
    hurt_flash.putalpha(idle.split()[3])
    hf_final = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    hf_final.paste(hurt_flash, (-4, -4), hurt_flash)
    new_sheet.paste(hf_final, (frame_w * 6, 0))
    
    death_img = idle.resize((frame_w, frame_h // 2), Image.NEAREST)
    death_frame = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    red_wash = Image.new("RGBA", (frame_w, frame_h // 2), (100, 0, 0, 100))
    death_tinted = Image.alpha_composite(death_img, red_wash)
    death_tinted.putalpha(death_img.split()[3])
    death_frame.paste(death_tinted, (0, frame_h - (frame_h // 2)))
    new_sheet.paste(death_frame, (frame_w * 7, 0))
    
    new_sheet.save(new_sheet_path)
    print(f"Saved {new_sheet_path}")

def generate_emissive(sheet_path, target_path):
    print(f"Generating emissive for {sheet_path}")
    img = Image.open(sheet_path).convert("RGBA")
    emissive = Image.new("RGBA", img.size, (0, 0, 0, 0))
    data = img.getdata()
    e_data = [
        (p[0], p[1], p[2], p[3]) if (p[0] > 150 and p[1] > 150 and p[2] < 100 and p[3] > 0) else (0, 0, 0, 0)
        for p in data
    ]
    emissive.putdata(e_data)
    emissive.save(target_path)
    print(f"Saved emissive {target_path}")

if __name__ == "__main__":
    assets = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies"
    previews = r"j:\BoomerShooter\sprite_previews"
    
    # Ranged ONLY for now to fix it fast
    ranged_grid = os.path.join(previews, "newgoblinranged.jpg")
    ranged_idle = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_idle.png")
    ranged_sheet = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_spritesheet.png")
    ranged_e_sheet = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_spritesheet_e.png")
    
    build_pure_8_frame_sheet(ranged_idle, ranged_grid, ranged_sheet)
    generate_emissive(ranged_sheet, ranged_e_sheet)
    print("Done Archer Refurbish")
