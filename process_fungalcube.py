from PIL import Image
import os

def process_ready_sheet(input_path, output_dir, enemy_name):
    print(f"Processing sheet for {enemy_name}...")
    img = Image.open(input_path).convert("RGBA")
    w, h = img.size
    
    # We expect 8 frames. Assuming the frames are equally spaced.
    # The image is 1344x896. This looks like a single strip or something?
    # Wait, 1344 / 8 = 168.
    
    # Let's detect the actual content frames.
    # The image provided in the preview was a single row of 8 sprites.
    
    frame_w = w // 8
    frame_h = h
    
    final_sheet = Image.new("RGBA", (128 * 8, 128), (0, 0, 0, 0))
    
    for i in range(8):
        frame = img.crop((i * frame_w, 0, (i + 1) * frame_w, frame_h))
        # Remove black background
        data = frame.getdata()
        new_data = []
        for p in data:
            if p[0] < 20 and p[1] < 20 and p[2] < 20:
                new_data.append((0, 0, 0, 0))
            else:
                new_data.append(p)
        frame.putdata(new_data)
        
        # Crop to content
        bbox = frame.getbbox()
        if bbox:
            sprite = frame.crop(bbox)
            sw, sh = sprite.size
            # Fit into 120x120 to leave margin
            ratio = min(120/sw, 120/sh)
            new_size = (int(sw * ratio), int(sh * ratio))
            sprite = sprite.resize(new_size, Image.BILINEAR)
            
            # Paste centered
            offset_x = (128 - new_size[0]) // 2
            offset_y = (128 - new_size[1]) // 2
            final_sheet.paste(sprite, (i * 128 + offset_x, offset_y), sprite)
            
    # Save results
    os.makedirs(output_dir, exist_ok=True)
    sheet_path = os.path.join(output_dir, f"{enemy_name.lower()}_spritesheet.png")
    idle_path = os.path.join(output_dir, f"{enemy_name.lower()}_idle.png")
    
    final_sheet.save(sheet_path)
    final_sheet.crop((0, 0, 128, 128)).save(idle_path)
    print(f"Saved: {sheet_path}")
    
    # Generate emissive (glowing mushrooms)
    emissive = Image.new("RGBA", final_sheet.size, (0, 0, 0, 0))
    e_data = []
    for p in final_sheet.getdata():
        # Light green/yellow mushrooms or bits
        if p[1] > 180 and p[3] > 0:
            e_data.append((p[0], p[1], p[2], p[3]))
        else:
            e_data.append((0, 0, 0, 0))
    emissive.putdata(e_data)
    e_path = os.path.join(output_dir, f"{enemy_name.lower()}_spritesheet_e.png")
    emissive.save(e_path)
    print(f"Saved Emissive: {e_path}")

if __name__ == "__main__":
    process_ready_sheet(
        r"j:\BoomerShooter\sprite_previews\FungalCube.png",
        r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\FungalCube",
        "FungalCube"
    )
