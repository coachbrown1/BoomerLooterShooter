import os
from PIL import Image

# Try importing rembg, fallback if missing
try:
    from rembg import remove, new_session
except ImportError:
    print("Warning: rembg not installed. Run 'pip install rembg' to use this script.")
    exit(1)

def process_goblins(sources, output_path, idle_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    sheet = Image.new("RGBA", (128 * 5, 128), (0,0,0,0))
    filled = [False] * 5
    
    # Initialize a rembg session
    session = new_session("u2net")
    
    for gen_path, positions, target_indices in sources:
        if not os.path.exists(gen_path): 
            print("Missing:", gen_path)
            continue
            
        print("Processing with rembg:", gen_path)
        img = Image.open(gen_path).convert("RGBA")
        
        # Determine the individual quadrant size from original full size
        w, h = img.size
        # The prompt generated 2x2 grids, so quadrant size is w//2, h//2
        fw, fh = w // 2, h // 2
        
        for i, (sx, sy) in enumerate(positions):
            # Crop the quadrant BEFORE rembg to ensure it treats it as a single distinct subject
            quadrant = img.crop((sx, sy, sx + fw, sy + fh))
            
            # Use rembg!
            sprite_bg_removed = remove(quadrant, session=session)
            
            # Now proceed with the rest of the normal processing
            bbox = sprite_bg_removed.getbbox()
            if bbox:
                sprite = sprite_bg_removed.crop(bbox)
                
                # We need to completely harden the alpha channel:
                # rembg uses soft alpha edges (anti-aliasing). Godot's crisp outline shader
                # looks better when edges are completely hard. We can do a threshold cut
                hard_data = []
                for p in sprite.getdata():
                    if p[3] > 64:  # Threshold to treat as fully solid
                        hard_data.append((p[0], p[1], p[2], 255))
                    else:
                        hard_data.append((0, 0, 0, 0))
                sprite.putdata(hard_data)
                
                # Resize
                sw, sh = sprite.size
                ratio = min(120/sw, 120/sh)
                new_size = (int(sw*ratio), int(sh*ratio))
                sprite = sprite.resize(new_size, Image.NEAREST)
                
                target_idx = target_indices[i]
                offset_x = (128 - new_size[0]) // 2
                offset_y = (128 - new_size[1]) // 2
                sheet.paste(sprite, (target_idx * 128 + offset_x, offset_y), sprite)
                filled[target_idx] = True

    if not filled[3] and filled[0]:
        idle = sheet.crop((0, 0, 128, 128))
        hurt = idle.rotate(15, expand=False, resample=Image.NEAREST)
        hw, hh = hurt.size
        hurt = hurt.resize((hw, int(hh * 0.85)), Image.NEAREST)
        hurt_frame = Image.new("RGBA", (128, 128), (0,0,0,0))
        hurt_frame.paste(hurt, (0, 128 - hurt.size[1]), hurt)
        sheet.paste(hurt_frame, (3 * 128, 0), hurt_frame)

    sheet.save(output_path)
    idle_img = sheet.crop((0, 0, 128, 128))
    idle_img.save(idle_path)
    print(f"Saved: {output_path}")

if __name__ == "__main__":
    goblin_f1 = r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_facing_forward_gemini_1772893490735.png"
    process_goblins([
        (goblin_f1, [(0,0), (320,0), (0,320), (320,320)], [0, 1, 2, 4]) 
    ], r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_spritesheet.png",
       r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_idle.png")
       
    archer_f1 = r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_archer_facing_forward_gemini_1772893547748.png"
    process_goblins([
        (archer_f1, [(0,0), (320,0), (0,320), (320,320)], [0, 1, 2, 4]) 
    ], r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_spritesheet.png",
       r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_idle.png")
