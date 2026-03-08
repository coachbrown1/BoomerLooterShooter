from PIL import Image
import os

def process_sporehusk_final(input_path, output_dir):
    print(f"Processing SporeHusk with FINAL coordinates and label stripping...")
    img = Image.open(input_path).convert("RGBA")
    
    # Remove white background
    data = img.getdata()
    new_data = []
    for p in data:
        if p[0] > 240 and p[1] > 240 and p[2] > 240:
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append(p)
    img.putdata(new_data)
    
    def get_clean_sprite(box):
        sprite = img.crop(box)
        # Strip the bottom part where labels usually sit (about 40-50 pixels)
        w, h = sprite.size
        sprite = sprite.crop((0, 0, w, h - 45))
        bbox = sprite.getbbox()
        if bbox:
            return sprite.crop(bbox)
        return None

    frames = []
    # 0: Idle
    frames.append(get_clean_sprite((32, 288, 224, 576)))
    # 1: Walk
    frames.append(get_clean_sprite((256, 288, 448, 576)))
    
    # 2, 3, 4: Attacks (split 704px into 3)
    attack_strip = img.crop((480, 288, 1184, 576))
    aw = attack_strip.size[0] // 3
    for i in range(3):
        # Manually clean attack frames
        s = attack_strip.crop((i * aw, 0, (i + 1) * aw, 288 - 45))
        b = s.getbbox()
        if b: frames.append(s.crop(b))
        else: frames.append(None)
        
    # 5: Hurt
    hurt_frame = get_clean_sprite((800, 608, 1056, 864))
    
    # 6: Death
    death_frame = get_clean_sprite((1184, 288, 1536, 576))
    
    # Build final sheet
    final_sheet = Image.new("RGBA", (128 * 8, 128), (0, 0, 0, 0))
    
    sequence = [
        frames[0], # Idle
        frames[1], # Walk
        frames[2], # A1
        frames[3], # A2
        frames[4], # A3
        frames[4], # A4
        hurt_frame, # Hurt
        death_frame # Death
    ]
    
    for i, sprite in enumerate(sequence):
        if sprite:
            sw, sh = sprite.size
            ratio = min(120/sw, 120/sh)
            new_size = (int(sw * ratio), int(sh * ratio))
            sprite_res = sprite.resize(new_size, Image.BILINEAR)
            
            offset_x = (128 - new_size[0]) // 2
            offset_y = (128 - new_size[1]) // 2
            final_sheet.paste(sprite_res, (i * 128 + offset_x, offset_y), sprite_res)
            
    # Save
    os.makedirs(output_dir, exist_ok=True)
    sheet_path = os.path.join(output_dir, "sporehusk_spritesheet.png")
    final_sheet.save(sheet_path)
    
    idle_path = os.path.join(output_dir, "sporehusk_idle.png")
    final_sheet.crop((0, 0, 128, 128)).save(idle_path)
    
    # Emissive mask
    emissive = Image.new("RGBA", final_sheet.size, (0, 0, 0, 0))
    e_data = []
    for p in final_sheet.getdata():
        if p[1] > 180 and p[0] < 220 and p[3] > 0:
            e_data.append((p[0], p[1], p[2], p[3]))
        else:
            e_data.append((0, 0, 0, 0))
    emissive.putdata(e_data)
    e_path = os.path.join(output_dir, "sporehusk_spritesheet_e.png")
    emissive.save(e_path)
    
    print(f"Final Clean SporeHusk: {sheet_path}")

if __name__ == "__main__":
    process_sporehusk_final(
        r"j:\BoomerShooter\sprite_previews\SporeHusk.png",
        r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\SporeHusk"
    )
