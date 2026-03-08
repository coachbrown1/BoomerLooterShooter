from PIL import Image
import os

def make_transparent(img):
    img = img.convert("RGBA")
    new_data = []
    # Identify the background color by looking at the top-left pixel
    bg_color = img.getpixel((0, 0))
    # Threshold for matching background
    def is_bg(pix):
        # Match near-white (if white background) or near the specific bg_color (if black/dark)
        if pix[0] > 220 and pix[1] > 220 and pix[2] > 220: return True
        return abs(pix[0]-bg_color[0]) < 45 and abs(pix[1]-bg_color[1]) < 45 and abs(pix[2]-bg_color[2]) < 45

    for item in img.getdata():
        if is_bg(item):
            new_data.append((0, 0, 0, 0))
        else:
            # Force opaque to prevent lightbleed/see-through issues
            new_data.append((item[0], item[1], item[2], 255))
    img.putdata(new_data)
    return img

def process_goblins_to_5_frame(sources, output_path, idle_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    sheet = Image.new("RGBA", (128 * 5, 128))
    
    # Track which frames were filled
    filled = [False] * 5
    
    for gen_path, positions, target_indices in sources:
        if not os.path.exists(gen_path): continue
        img = Image.open(gen_path).convert("RGBA")
        img = make_transparent(img)
        w, h = img.size
        fw, fh = w // 2, h // 2
        
        for i, (sx, sy) in enumerate(positions):
            frame = img.crop((sx, sy, sx + fw, sy + fh))
            bbox = frame.getbbox()
            if bbox:
                sprite = frame.crop(bbox)
                sw, sh = sprite.size
                ratio = min(120/sw, 120/sh)
                new_size = (int(sw*ratio), int(sh*ratio))
                sprite = sprite.resize(new_size, Image.BILINEAR)
                
                target_idx = target_indices[i]
                offset_x = (128 - new_size[0]) // 2
                offset_y = (128 - new_size[1]) // 2
                sheet.paste(sprite, (target_idx * 128 + offset_x, offset_y), sprite)
                filled[target_idx] = True

    # Procedural Hurt Frame (index 3) if missing
    if not filled[3] and filled[0]:
        idle = sheet.crop((0, 0, 128, 128))
        # Rotate and squash for a hurt effect
        hurt = idle.rotate(15, expand=False, resample=Image.BILINEAR)
        # Squash Y
        hw, hh = hurt.size
        hurt = hurt.resize((hw, int(hh * 0.85)), Image.BILINEAR)
        # Repaste into a clean 128x128
        hurt_frame = Image.new("RGBA", (128, 128), (0,0,0,0))
        hurt_frame.paste(hurt, (0, 128 - hurt.size[1]), hurt)
        sheet.paste(hurt_frame, (3 * 128, 0), hurt_frame)

    sheet.save(output_path)
    print(f"Saved 5-frame sheet to {output_path}")
    idle_img = sheet.crop((0, 0, 128, 128))
    idle_img.save(idle_path)

if __name__ == "__main__":
    goblin_f1 = r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_facing_forward_gemini_1772893490735.png"
    
    # Normal Goblin - ONLY use f1 for consistency
    process_goblins_to_5_frame([
        (goblin_f1, [(0,0), (320,0), (0,320), (320,320)], [0, 1, 2, 4]) 
    ], r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_spritesheet.png",
       r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_idle.png")
       
    # Archer Forward (Gen 1 is already consistent)
    archer_f1 = r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_archer_facing_forward_gemini_1772893547748.png"
    process_goblins_to_5_frame([
        (archer_f1, [(0,0), (320,0), (0,320), (320,320)], [0, 1, 2, 4]) 
    ], r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_spritesheet.png",
       r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_idle.png")
