from PIL import Image

def test(grid_path):
    img = Image.open(grid_path).convert('RGBA')
    w, h = img.size
    print(f'Original size: {w}x{h}')

    # Try background removal
    bg_color = img.getpixel((0,0))
    print(f'BG color top-left: {bg_color}')
    data = img.getdata()
    new_data = []

    def is_bg(pix):
        if pix[0] > 220 and pix[1] > 220 and pix[2] > 220: return True
        return abs(pix[0]-bg_color[0]) < 40 and abs(pix[1]-bg_color[1]) < 40 and abs(pix[2]-bg_color[2]) < 40

    for item in data:
        if is_bg(item):
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append((item[0], item[1], item[2], 255))
    
    img.putdata(new_data)
    
    cell_w, cell_h = w // 2, h // 2
    for (x, y) in [(0, 0), (cell_w, 0), (0, cell_h), (cell_w, cell_h)]:
        frame = img.crop((x, y, x + cell_w, y + cell_h))
        bbox = frame.getbbox()
        print(f'Cell pos {(x,y)}: bbox {bbox}, full_size {frame.size}')
        if bbox:
            print(f'   bbox size: {bbox[2]-bbox[0]} x {bbox[3]-bbox[1]}')

print('--- MELEE ---')
test(r'j:\BoomerShooter\sprite_previews\Newgoblinmelee.png')
print('--- RANGED ---')
test(r'j:\BoomerShooter\sprite_previews\newgoblinranged.png')
