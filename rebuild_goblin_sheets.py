import os
from PIL import Image

def make_transparent(img):
    img = img.convert("RGBA")
    data = img.getdata()
    # Mask out white backgrounds or very dark grids
    new_data = [
        (255, 255, 255, 0) if (p[0] > 240 and p[1] > 240 and p[2] > 240) or (p[0] < 20 and p[1] < 20 and p[2] < 20) else p
        for p in data
    ]
    img.putdata(new_data)
    return img

def process_attack_grid(grid_path, target_size=(128, 128)):
    print(f"Processing grid: {grid_path}")
    img = Image.open(grid_path).convert("RGBA")
    img = make_transparent(img)
    w, h = img.size
    
    cell_w, cell_h = w // 2, h // 2
    positions = [(0, 0), (cell_w, 0), (0, cell_h), (cell_w, cell_h)]
    
    attack_frames = []
    for i, (x, y) in enumerate(positions):
        frame = img.crop((x, y, x + cell_w, y + cell_h))
        bbox = frame.getbbox()
        if bbox:
            sprite = frame.crop(bbox)
            sw, sh = sprite.size
            ratio = min(min(120 / sw, 120 / sh), 1.0)
            new_size = (int(sw * ratio), int(sh * ratio))
            sprite = sprite.resize(new_size, Image.BILINEAR)
            
            final_frame = Image.new("RGBA", target_size, (0, 0, 0, 0))
            offset_x = (target_size[0] - new_size[0]) // 2
            offset_y = (target_size[1] - new_size[1]) // 2
            final_frame.paste(sprite, (offset_x, offset_y), sprite)
            attack_frames.append(final_frame)
        else:
            attack_frames.append(Image.new("RGBA", target_size, (0, 0, 0, 0)))
            
    return attack_frames

def build_pure_8_frame_sheet(idle_path, attack_grid_path, new_sheet_path):
    print(f"Building pure 8-frame sheet from {idle_path}")
    idle = Image.open(idle_path).convert("RGBA")
    
    frame_w, frame_h = idle.size # Should be 128x128
    
    attack_frames = process_attack_grid(attack_grid_path, (frame_w, frame_h))
    
    new_sheet = Image.new("RGBA", (frame_w * 8, frame_h), (0, 0, 0, 0))
    
    # 0: Idle
    new_sheet.paste(idle, (0, 0))
    
    # 1: Walk (Slight bob down)
    walk_img = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    walk_img.paste(idle, (0, 8))
    new_sheet.paste(walk_img, (frame_w, 0))
    
    # 2, 3, 4, 5: Attack
    for i, af in enumerate(attack_frames):
        new_sheet.paste(af, (frame_w * (2 + i), 0))
        
    # 6: Hurt (Flash red, shift back/up slightly)
    # Tint red
    hurt_img = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    hurt_img.paste(idle, (-4, -4))
    red_tint = Image.new("RGBA", (frame_w, frame_h), (255, 0, 0, 100))
    hurt_flash = Image.alpha_composite(hurt_img, red_tint)
    # Restore alpha
    hurt_flash.putalpha(idle.split()[3])
    hf_final = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    hf_final.paste(hurt_flash, (-4, -4), hurt_flash)
    new_sheet.paste(hf_final, (frame_w * 6, 0))
    
    # 7: Death (Squish to half height)
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
    
    # Melee
    melee_grid = os.path.join(previews, "Newgoblinmelee.jpg")
    melee_idle = os.path.join(assets, "GoblinForward", "goblin_forward_idle.png")
    melee_sheet = os.path.join(assets, "GoblinForward", "goblin_forward_spritesheet.png")
    melee_e_sheet = os.path.join(assets, "GoblinForward", "goblin_forward_spritesheet_e.png")
    
    build_pure_8_frame_sheet(melee_idle, melee_grid, melee_sheet)
    generate_emissive(melee_sheet, melee_e_sheet)
    
    # Ranged
    ranged_grid = os.path.join(previews, "newgoblinranged.jpg")
    ranged_idle = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_idle.png")
    ranged_sheet = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_spritesheet.png")
    ranged_e_sheet = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_spritesheet_e.png")
    
    build_pure_8_frame_sheet(ranged_idle, ranged_grid, ranged_sheet)
    generate_emissive(ranged_sheet, ranged_e_sheet)
    print("Done.")
