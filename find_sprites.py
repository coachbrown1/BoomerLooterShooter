from PIL import Image

def find_sprites(img_path):
    img = Image.open(img_path).convert('RGBA')
    w, h = img.size
    bg_color = img.getpixel((0,0))
    data = img.getdata()
    
    new_data = []
    def is_bg(pix):
        if pix[0] > 220 and pix[1] > 220 and pix[2] > 220: return True
        return abs(pix[0]-bg_color[0]) < 40 and abs(pix[1]-bg_color[1]) < 40 and abs(pix[2]-bg_color[2]) < 40

    for item in data:
        if is_bg(item):
            new_data.append((0,0,0,0))
        else:
            new_data.append((item[0], item[1], item[2], 255))
    img.putdata(new_data)
    
    # Calculate vertical projection (number of non-alpha pixels per column)
    col_counts = [0] * w
    for x in range(w):
        for y in range(h):
            if img.getpixel((x,y))[3] > 0:
                col_counts[x] += 1
                
    # Find gaps (columns with 0 or very few pixels)
    islands = []
    in_island = False
    start_x = 0
    padding = 10
    
    for x in range(w):
        if col_counts[x] > 5:
            if not in_island:
                in_island = True
                start_x = x
        else:
            if in_island:
                in_island = False
                islands.append((start_x, x))
                
    # if it ends on an island
    if in_island:
        islands.append((start_x, w-1))
                
    print(f'{img_path} - Found {len(islands)} islands: {islands}')
    return img, islands

img_m, islands_m = find_sprites(r'j:\BoomerShooter\sprite_previews\Newgoblinmelee.png')
img_r, islands_r = find_sprites(r'j:\BoomerShooter\sprite_previews\newgoblinranged.png')
