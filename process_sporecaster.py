import os
from PIL import Image, ImageOps

def process_sporecaster(input_path, output_dir):
    img = Image.open(input_path).convert("RGBA")
    w, h = img.size
    
    # Divide into 4 quadrants
    mid_x, mid_y = w // 2, h // 2
    
    # Quadrants: (left, top, right, bottom)
    margin = 5
    idle_raw = img.crop((margin, margin, mid_x - margin, mid_y - margin))
    walk_raw = img.crop((mid_x + margin, margin, w - margin, mid_y - margin))
    attack_raw = img.crop((margin, mid_y + margin, mid_x - margin, h - margin))
    death_raw = img.crop((mid_x + margin, mid_y + margin, w - margin, h - margin))
    
    raw_frames = [idle_raw, walk_raw, attack_raw, death_raw]
    processed_frames = []
    emissive_frames = []
    
    target_size = (256, 256)
    
    for i, frame in enumerate(raw_frames):
        # 1. Make transparent
        data = frame.getdata()
        new_data = []
        e_data = []
        
        for item in data:
            r, g, b, a = item
            # White background detection (r,g,b > 240)
            if r > 240 and g > 240 and b > 240:
                new_data.append((0, 0, 0, 0))
                e_data.append((0, 0, 0, 0))
            else:
                new_data.append(item)
                # Emissive: Green glow
                # The glow is very green: high G, lower R/B
                if g > 180 and g > r * 1.1 and g > b * 1.1:
                    e_data.append(item)
                else:
                    e_data.append((0, 0, 0, 0))
        
        frame.putdata(new_data)
        
        # 2. Crop to content
        bbox = frame.getbbox()
        if bbox:
            frame = frame.crop(bbox)
            
            # Create emissive frame matching the crop
            # Temporary frame to put data back
            temp_e = Image.new("RGBA", raw_frames[i].size, (0, 0, 0, 0))
            temp_e.putdata(e_data)
            e_frame = temp_e.crop(bbox)
            
            # Resize to fit target_size nicely
            sw, sh = frame.size
            ratio = min(230 / sw, 230 / sh) # slightly smaller than 256
            new_size = (int(sw * ratio), int(sh * ratio))
            
            frame = frame.resize(new_size, Image.BILINEAR)
            e_frame = e_frame.resize(new_size, Image.BILINEAR)
            
            # Center in target_size
            final_f = Image.new("RGBA", target_size, (0, 0, 0, 0))
            final_e = Image.new("RGBA", target_size, (0, 0, 0, 0))
            
            offset_x = (target_size[0] - new_size[0]) // 2
            # Align to bottom instead of vertical center (better for ground enemies)
            offset_y = (target_size[1] - new_size[1])
            
            final_f.paste(frame, (offset_x, offset_y), frame)
            final_e.paste(e_frame, (offset_x, offset_y), e_frame)
            
            processed_frames.append(final_f)
            emissive_frames.append(final_e)
        else:
            processed_frames.append(Image.new("RGBA", target_size, (0, 0, 0, 0)))
            emissive_frames.append(Image.new("RGBA", target_size, (0, 0, 0, 0)))

    # Construct the 8-frame sheet
    # 0: Idle, 1: Walk, 2-5: Attack, 6: Hurt, 7: Death
    
    sheet = Image.new("RGBA", (target_size[0] * 8, target_size[1]), (0, 0, 0, 0))
    sheet_e = Image.new("RGBA", (target_size[0] * 8, target_size[1]), (0, 0, 0, 0))
    
    # 0: Idle
    sheet.paste(processed_frames[0], (0, 0))
    sheet_e.paste(emissive_frames[0], (0, 0))
    
    # 1: Walk (We will use walk but also add 0 and 1 alternating if we had more frames)
    sheet.paste(processed_frames[1], (target_size[0], 0))
    sheet_e.paste(emissive_frames[1], (target_size[0], 0))
    
    # 2-5: Attack (Arms raised)
    for i in range(4):
        f = processed_frames[2].copy()
        fe = emissive_frames[2].copy()
        # Subtle breathing/pulsing for attack animation
        scale_mod = 1.0 + (0.02 * (i % 2))
        nw, nh = int(target_size[0] * scale_mod), int(target_size[1] * scale_mod)
        # Just simple paste for now
        sheet.paste(f, (target_size[0] * (2 + i), 0))
        sheet_e.paste(fe, (target_size[0] * (2 + i), 0))
        
    # 6: Hurt (Idle but red tinted)
    hurt = processed_frames[0].copy()
    hurt_e = emissive_frames[0].copy()
    red = Image.new("RGBA", target_size, (255, 0, 0, 100))
    hurt = Image.alpha_composite(hurt, red)
    hurt.putalpha(processed_frames[0].split()[3])
    sheet.paste(hurt, (target_size[0] * 6, 0))
    sheet_e.paste(hurt_e, (target_size[0] * 6, 0))
    
    # 7: Death
    sheet.paste(processed_frames[3], (target_size[0] * 7, 0))
    sheet_e.paste(emissive_frames[3], (target_size[0] * 7, 0))
    
    # Save results
    os.makedirs(output_dir, exist_ok=True)
    sheet.save(os.path.join(output_dir, "sporecaster_spritesheet.png"))
    sheet_e.save(os.path.join(output_dir, "sporecaster_spritesheet_e.png"))
    
    # Also save individual idle for references
    processed_frames[0].save(os.path.join(output_dir, "sporecaster_idle.png"))
    
    print(f"Successfully processed Sporecaster V2 into {output_dir}")

if __name__ == "__main__":
    input_img = r"C:\Users\18136\.gemini\antigravity\brain\625a6ea0-c965-4c5c-b6eb-09a2c9377041\sporecaster_v2_grid_1772943391077.png"
    out_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\Sporecaster"
    process_sporecaster(input_img, out_dir)

