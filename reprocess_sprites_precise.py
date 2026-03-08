from PIL import Image, ImageDraw
import os

def floodfill_transparent(img, xy, threshold=20):
    img = img.convert("RGBA")
    width, height = img.size
    pixels = img.load()
    
    bg_color = pixels[xy]
    
    # Use BFS for flood fill
    visited = set()
    queue = [xy]
    
    def color_dist(c1, c2):
        # Manhattan distance for simplicity
        return abs(c1[0] - c2[0]) + abs(c1[1] - c2[1]) + abs(c1[2] - c2[2])
        
    while queue:
        x, y = queue.pop()
        if (x, y) in visited:
            continue
        visited.add((x, y))
        
        c = pixels[x, y]
        # Same check as previous, but only connected pixels
        # 60 manhattan distance = 20 per channel on average
        if color_dist(c, bg_color) < 75 or (c[0] > 230 and c[1] > 230 and c[2] > 230) or (c[0] < 25 and c[1] < 25 and c[2] < 25):
            pixels[x, y] = (0, 0, 0, 0)
            
            # Add neighbors
            if x > 0: queue.append((x - 1, y))
            if x < width - 1: queue.append((x + 1, y))
            if y > 0: queue.append((x, y - 1))
            if y < height - 1: queue.append((x, y + 1))

    # Also clean up edges using a simple heuristic
    return img

def make_transparent(img):
    # Use floodfill to remove background starting from multiple corners to ensure all parts of the grid background are caught
    w, h = img.size
    processed_img = floodfill_transparent(img, (0, 0), threshold=10)
    processed_img = floodfill_transparent(processed_img, (w-1, 0), threshold=10)
    processed_img = floodfill_transparent(processed_img, (0, h-1), threshold=10)
    processed_img = floodfill_transparent(processed_img, (w-1, h-1), threshold=10)
    
    # Force all non-transparent pixels to 255 alpha to prevent any semi-transparent lightbleed issues
    new_data = []
    for item in processed_img.getdata():
        if item[3] > 0:
            new_data.append((item[0], item[1], item[2], 255))
        else:
            new_data.append((0, 0, 0, 0))
    processed_img.putdata(new_data)
    
    return processed_img

def process_goblins_to_5_frame(sources, output_path, idle_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    sheet = Image.new("RGBA", (128 * 5, 128))
    
    filled = [False] * 5
    
    for gen_path, positions, target_indices in sources:
        if not os.path.exists(gen_path): continue
        img = Image.open(gen_path).convert("RGBA")
        img = make_transparent(img)
        w, h = img.size
        
        for i, (sx, sy) in enumerate(positions):
            # The original images are likely 640x640 or something. The earlier script hardcoded crop sizes.
            # Usually 4-grid generation is 2x2.
            fw, fh = w // 2, h // 2
            frame = img.crop((sx, sy, sx + fw, sy + fh))
            bbox = frame.getbbox()
            if bbox:
                sprite = frame.crop(bbox)
                sw, sh = sprite.size
                ratio = min(120/sw, 120/sh)
                new_size = (int(sw*ratio), int(sh*ratio))
                # Use NEAREST to maintain sharp pixels if it's pixel art, else BILINEAR
                sprite = sprite.resize(new_size, Image.BILINEAR)
                
                target_idx = target_indices[i]
                offset_x = (128 - new_size[0]) // 2
                offset_y = (128 - new_size[1]) // 2
                sheet.paste(sprite, (target_idx * 128 + offset_x, offset_y), sprite)
                filled[target_idx] = True

    if not filled[3] and filled[0]:
        idle = sheet.crop((0, 0, 128, 128))
        hurt = idle.rotate(15, expand=False, resample=Image.BILINEAR)
        hw, hh = hurt.size
        hurt = hurt.resize((hw, int(hh * 0.85)), Image.BILINEAR)
        hurt_frame = Image.new("RGBA", (128, 128), (0,0,0,0))
        hurt_frame.paste(hurt, (0, 128 - hurt.size[1]), hurt)
        sheet.paste(hurt_frame, (3 * 128, 0), hurt_frame)

    sheet.save(output_path)
    idle_img = sheet.crop((0, 0, 128, 128))
    idle_img.save(idle_path)
    print(f"Saved: {output_path}")

if __name__ == "__main__":
    goblin_f1 = r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_facing_forward_gemini_1772893490735.png"
    process_goblins_to_5_frame([
        (goblin_f1, [(0,0), (320,0), (0,320), (320,320)], [0, 1, 2, 4]) 
    ], r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_spritesheet.png",
       r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_idle.png")
       
    archer_f1 = r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_archer_facing_forward_gemini_1772893547748.png"
    process_goblins_to_5_frame([
        (archer_f1, [(0,0), (320,0), (0,320), (320,320)], [0, 1, 2, 4]) 
    ], r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_spritesheet.png",
       r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_idle.png")
