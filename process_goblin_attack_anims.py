import os
from PIL import Image

def make_transparent(img):
    img = img.convert("RGBA")
    new_data = []
    # Threshold for white/near-white or black background grid
    for item in img.getdata():
        if item[0] > 240 and item[1] > 240 and item[2] > 240:
            new_data.append((255, 255, 255, 0))
        elif item[0] < 20 and item[1] < 20 and item[2] < 20: 
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append(item)
    img.putdata(new_data)
    return img

def process_attack_grid(grid_path, target_size=(128, 128)):
    img = Image.open(grid_path).convert("RGBA")
    img = make_transparent(img)
    w, h = img.size
    cell_w, cell_h = w // 2, h // 2
    
    positions = [(0, 0), (cell_w, 0), (0, cell_h), (cell_w, cell_h)]
    attack_frames = []
    
    for (x, y) in positions:
        frame = img.crop((x, y, x + cell_w, y + cell_h))
        bbox = frame.getbbox()
        if bbox:
            sprite = frame.crop(bbox)
            sw, sh = sprite.size
            ratio = min(120 / sw, 120 / sh)
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

def build_8_frame_sheet(old_sheet_path, attack_grid_path, new_sheet_path):
    old_sheet = Image.open(old_sheet_path).convert("RGBA")
    old_w, old_h = old_sheet.size
    frame_w = old_w // 5
    frame_h = old_h
    
    attack_frames = process_attack_grid(attack_grid_path, (frame_w, frame_h))
    
    new_sheet = Image.new("RGBA", (frame_w * 8, frame_h), (0, 0, 0, 0))
    
    # 0: Idle, 1: Walk
    new_sheet.paste(old_sheet.crop((0, 0, frame_w * 2, frame_h)), (0, 0))
    
    # 2, 3, 4, 5: Attack 1..4
    for i, af in enumerate(attack_frames):
        new_sheet.paste(af, (frame_w * (2 + i), 0))
        
    # 6: Hurt (old 3), 7: Death (old 4)
    new_sheet.paste(old_sheet.crop((frame_w * 3, 0, frame_w * 5, frame_h)), (frame_w * 6, 0))
    
    new_sheet.save(new_sheet_path)
    print(f"Saved {new_sheet_path}")

def generate_emissive(sheet_path, target_path):
    # Generates a simple emissive mask searching for yellow eyes
    img = Image.open(sheet_path).convert("RGBA")
    emissive = Image.new("RGBA", img.size, (0, 0, 0, 0))
    
    data = img.getdata()
    e_data = []
    for item in data:
        r, g, b, a = item
        # Yellowish
        if r > 150 and g > 150 and b < 100 and a > 0:
            e_data.append((r, g, b, a))
        else:
            e_data.append((0, 0, 0, 0))
    emissive.putdata(e_data)
    emissive.save(target_path)
    print(f"Saved emissive {target_path}")

if __name__ == "__main__":
    assets = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies"
    previews = r"j:\BoomerShooter\sprite_previews"
    
    melee_grid = os.path.join(previews, "Newgoblinmelee.jpg")
    melee_sheet = os.path.join(assets, "GoblinForward", "goblin_forward_spritesheet.png")
    melee_e_sheet = os.path.join(assets, "GoblinForward", "goblin_forward_spritesheet_e.png")
    
    ranged_grid = os.path.join(previews, "newgoblinranged.jpg")
    ranged_sheet = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_spritesheet.png")
    ranged_e_sheet = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_spritesheet_e.png")
    
    build_8_frame_sheet(melee_sheet, melee_grid, melee_sheet)
    generate_emissive(melee_sheet, melee_e_sheet)
    
    build_8_frame_sheet(ranged_sheet, ranged_grid, ranged_sheet)
    generate_emissive(ranged_sheet, ranged_e_sheet)
