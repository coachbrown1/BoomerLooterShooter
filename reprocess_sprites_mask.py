from PIL import Image
import os

def process_goblins(sources, output_path, idle_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    sheet = Image.new("RGBA", (128 * 5, 128), (0,0,0,0))
    filled = [False] * 5
    
    for gen_path, positions, target_indices in sources:
        if not os.path.exists(gen_path): continue
        img = Image.open(gen_path).convert("RGBA")
        
        bg_c = img.getpixel((0,0))
        w, h = img.size
        mask = [[0 for _ in range(h)] for _ in range(w)]
        for x in range(w):
            for y in range(h):
                c = img.getpixel((x,y))
                dist = abs(c[0]-bg_c[0]) + abs(c[1]-bg_c[1]) + abs(c[2]-bg_c[2])
                if dist < 45 or (c[0]>235 and c[1]>235 and c[2]>235) or (c[0]<25 and c[1]<25 and c[2]<25):
                    mask[x][y] = 1

        queue = []
        for x in range(w):
            if mask[x][0] == 1: queue.append((x, 0))
            if mask[x][h-1] == 1: queue.append((x, h-1))
        for y in range(h):
            if mask[0][y] == 1: queue.append((0, y))
            if mask[w-1][y] == 1: queue.append((w-1, y))
            
        visited = set(queue)
        actual_bg = set()
        
        while queue:
            x, y = queue.pop()
            actual_bg.add((x,y))
            for nx, ny in [(x+1,y), (x-1,y), (x,y+1), (x,y-1)]:
                if 0 <= nx < w and 0 <= ny < h:
                    if mask[nx][ny] == 1 and (nx, ny) not in visited:
                        visited.add((nx,ny))
                        queue.append((nx,ny))
                        
        new_data = []
        for y in range(h):
            for x in range(w):
                if (x,y) in actual_bg:
                    new_data.append((0,0,0,0))
                else:
                    c = img.getpixel((x,y))
                    new_data.append((c[0], c[1], c[2], 255))
        
        img.putdata(new_data)
        
        for i, (sx, sy) in enumerate(positions):
            fw, fh = w // 2, h // 2
            frame = img.crop((sx, sy, sx + fw, sy + fh))
            bbox = frame.getbbox()
            if bbox:
                sprite = frame.crop(bbox)
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
