from PIL import Image

def process_full_sheet(grid_path, out_path, emissive_path):
    from fix_goblin_attack_anims_floodfill import make_transparent, flood_fill_bbox
    img = Image.open(grid_path).convert("RGBA")
    img = make_transparent(img)
    w, h = img.size
    cell_w, cell_h = w // 2, h // 2
    
    positions = [(0, 0), (cell_w, 0), (0, cell_h), (cell_w, cell_h)]
    cells = []
    
    for (x, y) in positions:
        frame = img.crop((x, y, x + cell_w, y + cell_h))
        fcx, fcy = cell_w // 2, cell_h // 2
        bbox = flood_fill_bbox(frame, fcx, fcy)
        
        if not bbox:
            bbox = frame.getbbox()
            
        if bbox:
            sprite = frame.crop(bbox)
            sw, sh = sprite.size
            ratio = min(120 / sw, 120 / sh)
            new_size = (int(sw * ratio), int(sh * ratio))
            sprite = sprite.resize(new_size, Image.BILINEAR)
            
            final_frame = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
            offset_x = (128 - new_size[0]) // 2
            offset_y = 127 - new_size[1]
            final_frame.paste(sprite, (offset_x, offset_y), sprite)
            cells.append(final_frame)
        else:
            cells.append(Image.new("RGBA", (128, 128), (0, 0, 0, 0)))
            
    eight_sheet = Image.new("RGBA", (128 * 8, 128), (0,0,0,0))
    
    eight_sheet.paste(cells[0], (0, 0))
    eight_sheet.paste(cells[1], (128, 0))
    
    eight_sheet.paste(cells[2], (128 * 2, 0))
    eight_sheet.paste(cells[3], (128 * 3, 0))
    eight_sheet.paste(cells[3], (128 * 4, 0))
    eight_sheet.paste(cells[2], (128 * 5, 0))
    
    idle_orig = cells[0]
    hurt = idle_orig.rotate(15, expand=False, resample=Image.BILINEAR)
    hw, hh = hurt.size
    hurt = hurt.resize((hw, int(hh * 0.85)), Image.BILINEAR)
    hurt_frame = Image.new("RGBA", (128, 128), (0,0,0,0))
    hurt_frame.paste(hurt, (0, 128 - hurt.size[1]), hurt)
    eight_sheet.paste(hurt_frame, (128 * 6, 0))
    
    idle_orig_sq = cells[0].copy()
    death = idle_orig_sq.rotate(90, expand=True, resample=Image.BILINEAR)
    dw, dh = death.size
    death = death.resize((dw, int(dh * 0.5)), Image.BILINEAR)
    death_frame = Image.new("RGBA", (128, 128), (0,0,0,0))
    death_frame.paste(death, (0, 128 - death.size[1]), death)
    eight_sheet.paste(death_frame, (128 * 7, 0))
    
    eight_sheet.save(out_path)
    print(f"Saved {out_path}")
    
    emissive = Image.new("RGBA", eight_sheet.size, (0,0,0,0))
    data = eight_sheet.getdata()
    e_data = []
    for p in data:
        r, g, b, a = p
        if r > 150 and g > 150 and b < 100 and a > 0:
            e_data.append((r, g, b, 255))
        else:
            e_data.append((0,0,0,0))
    emissive.putdata(e_data)
    emissive.save(emissive_path)
    print(f"Saved emissive {emissive_path}")

m_grid = r"j:\BoomerShooter\sprite_previews\Newgoblinmelee.png"
m_out = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_spritesheet.png"
m_e = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_spritesheet_e.png"

r_grid = r"j:\BoomerShooter\sprite_previews\newgoblinranged.png"
r_out = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_spritesheet.png"
r_e = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_spritesheet_e.png"

process_full_sheet(m_grid, m_out, m_e)
process_full_sheet(r_grid, r_out, r_e)
