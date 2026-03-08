from PIL import Image
import os

gen_path = r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_archer_spritesheet_gemini_1772893205035.png"
output_path = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcher\goblin_archer_spritesheet.png"
idle_path = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcher\goblin_archer_idle.png"

def make_transparent(img):
    img = img.convert("RGBA")
    datas = img.getdata()
    new_data = []
    threshold = 240
    for item in img.getdata():
        if item[0] > threshold and item[1] > threshold and item[2] > threshold:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append(item)
    img.putdata(new_data)
    return img

if os.path.exists(gen_path):
    img = Image.open(gen_path).convert("RGBA")
    img = make_transparent(img)
    
    # 2x2 grid (320x320 each if 640x640)
    sheet = Image.new("RGBA", (128 * 4, 128))
    
    # Extract frames from 2x2 grid
    positions = [(0,0), (320,0), (0,320), (320,320)]
    for i, (x, y) in enumerate(positions):
        frame = img.crop((x, y, x + 320, y + 320))
        # Find local bbox of the sprite in this frame to center it
        bbox = frame.getbbox()
        if bbox:
            sprite = frame.crop(bbox)
            # Resize sprite proportionally to fit 128x128
            sw, sh = sprite.size
            ratio = min(120/sw, 120/sh)
            new_size = (int(sw*ratio), int(sh*ratio))
            sprite = sprite.resize(new_size, Image.BILINEAR)
            
            # Place in center of 128x128 frame
            offset_x = (128 - new_size[0]) // 2
            offset_y = (128 - new_size[1]) // 2
            sheet.paste(sprite, (i * 128 + offset_x, offset_y), sprite)
    
    sheet.save(output_path)
    print(f"Saved spritesheet to {output_path}")
    
    # Save idle frame separately
    idle = sheet.crop((0, 0, 128, 128))
    idle.save(idle_path)
    print(f"Saved idle to {idle_path}")
else:
    print("Source not found")
