
import os
from PIL import Image, ImageOps

def process_sprite(input_path, output_path, emissive_path=None):
    img = Image.open(input_path).convert("RGBA")
    datas = img.getdata()

    new_data = []
    for item in datas:
        # If the pixel is very dark (black background), make it transparent
        # Using a small threshold to handle slight compression artifacts
        brightness = (item[0] + item[1] + item[2]) / 3
        if brightness < 15: # Threshold for black background
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append(item)

    img.putdata(new_data)
    
    # Crop to content
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    
    # Resize to a consistent size? 
    # The originals were 128x128. Let's go with 512x512 for high quality "boomer shooter" look.
    # Actually, keep the aspect ratio but limit max dimension to 512.
    max_size = 512
    w, h = img.size
    if w > h:
        new_w = max_size
        new_h = int(h * (max_size / w))
    else:
        new_h = max_size
        new_w = int(w * (max_size / h))
    
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    img.save(output_path)
    print(f"Saved processed sprite to {output_path}")

    if emissive_path:
        # Create emissive mask: essentially the sprite but with black background instead of transparent
        # and potentially boosted brightness on glowing areas.
        emissive = Image.new("RGB", (new_w, new_h), (0, 0, 0))
        # Paste the sprite on top of black
        emissive.paste(img, (0, 0), img)
        # Maybe boost contrast/brightness for emission?
        # Actually, for sprites that are already glowing, the image itself works well.
        emissive.save(emissive_path)
        print(f"Saved emissive mask to {emissive_path}")

if __name__ == "__main__":
    crystal_in = r"C:\Users\18136\.gemini\antigravity\brain\318d928d-e730-4b3b-9229-eab440e4e948\new_fungal_crystal_sprite_1772940409318.png"
    mushroom_in = r"C:\Users\18136\.gemini\antigravity\brain\318d928d-e730-4b3b-9229-eab440e4e948\new_fungal_mushroom_sprite_1772940420218.png"
    
    base_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Environment\Fungal"
    
    crystal_out = os.path.join(base_dir, "prop_fungal_crystal.png")
    mushroom_out = os.path.join(base_dir, "prop_fungal_mushroom.png")
    
    # Back up originals
    old_crystal = os.path.join(base_dir, "prop_fungal_crystal_old.png")
    old_mushroom = os.path.join(base_dir, "prop_fungal_mushroom_old.png")
    
    if os.path.exists(crystal_out) and not os.path.exists(old_crystal):
        os.rename(crystal_out, old_crystal)
    if os.path.exists(mushroom_out) and not os.path.exists(old_mushroom):
        os.rename(mushroom_out, old_mushroom)
        
    process_sprite(crystal_in, crystal_out)
    process_sprite(mushroom_in, mushroom_out)
