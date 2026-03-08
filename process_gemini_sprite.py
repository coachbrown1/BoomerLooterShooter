from PIL import Image
import os

# Path to the generated image (this will be updated based on the actual path)
gen_path = r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_spritesheet_gemini_1772893095453.png"
output_path = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\Goblin\goblin_spritesheet.png"

def make_transparent(img):
    img = img.convert("RGBA")
    new_data = []
    # Mask both white and very dark (the black grid lines)
    for item in img.getdata():
        r, g, b, a = item
        # Remove white
        if r > 240 and g > 240 and b > 240:
            new_data.append((0, 0, 0, 0))
        # Remove black/dark-gray grid lines
        elif r < 20 and g < 20 and b < 20:
             new_data.append((0, 0, 0, 0))
        else:
            # Force opaque
            new_data.append((r, g, b, 255))
    img.putdata(new_data)
    return img

if os.path.exists(gen_path):
    img = Image.open(gen_path).convert("RGBA")
    w, h = img.size
    print(f"Original size: {w}x{h}")
    
    # Process transparency
    img = make_transparent(img)
    
    # 1. Detect the sprite strip (where it's not all white/transparent)
    # The goblin sprites seem to be in the middle vertically.
    # Let's crop manually for now or use bbox.
    
    # Based on the image, the frames are in a strip.
    # We can probably use alpha to find content.
    bbox = img.getbbox()
    if bbox:
        # Crop to the content-containing area
        img_cropped = img.crop(bbox)
        cw, ch = img_cropped.size
        print(f"Cropped content size: {cw}x{ch}")
        
        # Now we want to split into 4 frames and pad/resize to 128x128 each.
        # However, the frames in the image seem fairly evenly spaced.
        # Let's try to just resize the cropped strip to 512x128.
        final_sheet = img_cropped.resize((512, 128), Image.BILINEAR)
        
        # Backup old one first?
        if os.path.exists(output_path):
            old_path = output_path + ".bak"
            if os.path.exists(old_path): os.remove(old_path)
            os.rename(output_path, old_path)
            
        final_sheet.save(output_path)
        print(f"Processed and saved to {output_path}")
        
        # Extract first frame as idle
        idle_path = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\Goblin\goblin_idle.png"
        idle_img = final_sheet.crop((0, 0, 128, 128))
        
        # Backup old idle
        if os.path.exists(idle_path):
            old_idle_path = idle_path + ".bak"
            if os.path.exists(old_idle_path): os.remove(old_idle_path)
            os.rename(idle_path, old_idle_path)
            
        idle_img.save(idle_path)
        print(f"Extracted and saved idle to {idle_path}")
    else:
        print("Empty image detected after transparency masking.")
else:
    print(f"File not found: {gen_path}")
