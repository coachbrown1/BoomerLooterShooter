from PIL import Image
import os

def check_grid(grid_path):
    img = Image.open(grid_path).convert("RGBA")
    w, h = img.size
    print(f"=== {os.path.basename(grid_path)} ===: {w}x{h}")
    
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
    
    img_debug = img.copy()
    for x in range(w):
        img_debug.putpixel((x, h//2), (255, 0, 0, 255))
    for y in range(h):
        img_debug.putpixel((w//2, y), (255, 0, 0, 255))
        
    debug_path = grid_path.replace(".png", "_debug.png")
    img_debug.save(debug_path)
    print(f"Saved debug to {debug_path}")

check_grid(r"j:\BoomerShooter\sprite_previews\Newgoblinmelee.png")
check_grid(r"j:\BoomerShooter\sprite_previews\newgoblinranged.png")
