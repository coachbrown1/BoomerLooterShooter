import os
from PIL import Image

def flood_fill_bbox(img, start_x, start_y):
    w, h = img.size
    pixels = img.load()
    
    # If starting pixel is transparent, we have an issue. Try to search nearby for a solid pixel.
    if pixels[start_x, start_y][3] == 0:
        found = False
        for r in range(1, 100):
            for dx in range(-r, r+1):
                for dy in range(-r, r+1):
                    nx, ny = start_x + dx, start_y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        if pixels[nx, ny][3] > 0:
                            start_x, start_y = nx, ny
                            found = True
                            break
                if found: break
            if found: break
            
        if not found:
            return None # Couldn't find a sprite
            
    # BFS to find all connected non-transparent pixels
    queue = [(start_x, start_y)]
    visited = set([(start_x, start_y)])
    
    min_x, min_y = start_x, start_y
    max_x, max_y = start_x, start_y
    
    while queue:
        cx, cy = queue.pop(0)
        
        min_x = min(min_x, cx)
        max_x = max(max_x, cx)
        min_y = min(min_y, cy)
        max_y = max(max_y, cy)
        
        # Check neighbors
        for dx, dy in [(0,1), (1,0), (0,-1), (-1,0), (1,1), (-1,-1), (1,-1), (-1,1)]:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h:
                if (nx, ny) not in visited:
                    visited.add((nx, ny))
                    # Allow a bit of a gap jump if needed, but let's just stick to strictly touching
                    if pixels[nx, ny][3] > 0:
                        queue.append((nx, ny))
                        
    return (min_x, min_y, max_x + 1, max_y + 1)

def make_transparent(img):
    img = img.convert("RGBA")
    new_data = []
    w, h = img.size
    bg_color = img.getpixel((0, 0))
    def is_bg(pix):
        if pix[0] > 220 and pix[1] > 220 and pix[2] > 220: return True
        return abs(pix[0]-bg_color[0]) < 40 and abs(pix[1]-bg_color[1]) < 40 and abs(pix[2]-bg_color[2]) < 40

    data = list(img.getdata())
    for item in data:
        if is_bg(item):
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append((item[0], item[1], item[2], 255))
    img.putdata(new_data)
    return img

def process_attack_grid(grid_path, target_size=(128, 128)):
    img = Image.open(grid_path).convert("RGBA")
    img = make_transparent(img)
    w, h = img.size
    cell_w, cell_h = w // 2, h // 2
    
    positions = [(0, 0), (cell_w, 0), (0, cell_h), (cell_w, cell_h)]
    attack_frames = []
    
    # We will search from the center of each cell.
    # To account for disconnected parts (like a floating arrow or drop of blood),
    # we might lose them, but this is a much safer bet to fix the massive shrinking issue.
    for (x, y) in positions:
        frame = img.crop((x, y, x + cell_w, y + cell_h))
        
        # Find flood fill bbox starting from center
        fcx, fcy = cell_w // 2, cell_h // 2
        
        bbox = flood_fill_bbox(frame, fcx, fcy)
        print(f"Cell {(x,y)}: bbox {bbox}")
        
        if bbox:
            sprite = frame.crop(bbox)
            sw, sh = sprite.size
            ratio = min(120 / sw, 120 / sh)
            new_size = (int(sw * ratio), int(sh * ratio))
            sprite = sprite.resize(new_size, Image.BILINEAR)
            
            final_frame = Image.new("RGBA", target_size, (0, 0, 0, 0))
            offset_x = (target_size[0] - new_size[0]) // 2
            offset_y = (target_size[1] - new_size[1]) // 2
            
            # To preserve drop shadows/clean edges, we can apply an alpha mask or just let it be.
            final_frame.paste(sprite, (offset_x, offset_y), sprite)
            attack_frames.append(final_frame)
        else:
            attack_frames.append(Image.new("RGBA", target_size, (0, 0, 0, 0)))
            
    return attack_frames

def build_8_frame_sheet(old_sheet_path, attack_grid_path, new_sheet_path):
    old_sheet = Image.open(old_sheet_path).convert("RGBA")
    # Hardcode dimensions to prevent corruption if run over an already 8-frame sheet
    frame_w = 128
    frame_h = 128
    
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
    img = Image.open(sheet_path).convert("RGBA")
    emissive = Image.new("RGBA", img.size, (0, 0, 0, 0))
    
    data = img.getdata()
    e_data = []
    for item in data:
        r, g, b, a = item
        if r > 150 and g > 150 and b < 100 and a > 0:
            e_data.append((r, g, b, 255))
        else:
            e_data.append((0, 0, 0, 0))
    emissive.putdata(e_data)
    emissive.save(target_path)
    print(f"Saved emissive {target_path}")

if __name__ == "__main__":
    assets = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies"
    previews = r"j:\BoomerShooter\sprite_previews"
    
    melee_grid = os.path.join(previews, "Newgoblinmelee.png")
    melee_sheet = os.path.join(assets, "GoblinForward", "goblin_forward_spritesheet.png")
    melee_e_sheet = os.path.join(assets, "GoblinForward", "goblin_forward_spritesheet_e.png")
    
    ranged_grid = os.path.join(previews, "newgoblinranged.png")
    ranged_sheet = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_spritesheet.png")
    ranged_e_sheet = os.path.join(assets, "GoblinArcherForward", "goblin_archer_forward_spritesheet_e.png")
    
    build_8_frame_sheet(melee_sheet, melee_grid, melee_sheet)
    generate_emissive(melee_sheet, melee_e_sheet)
    
    build_8_frame_sheet(ranged_sheet, ranged_grid, ranged_sheet)
    generate_emissive(ranged_sheet, ranged_e_sheet)
