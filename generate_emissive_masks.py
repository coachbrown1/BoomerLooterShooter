import os
from PIL import Image

def create_emissive_mask(image_path, output_path, type="goblin"):
    if not os.path.exists(image_path):
        print(f"File not found: {image_path}")
        return
        
    img = Image.open(image_path).convert("RGBA")
    w, h = img.size
    
    emissive = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    
    for y in range(h):
        for x in range(w):
            r, g, b, a = img.getpixel((x, y))
            if a > 0:
                # Need to identify the glowing parts based on type
                if type == "goblin":
                    # Goblin eyes are usually bright yellow-green
                    # Example: R > 150, G > 180, B < 150
                    # Let's check brightness directly
                    brightness = 0.299*r + 0.587*g + 0.114*b
                    
                    if g > 150 and r > 150 and b < 200:
                        emissive.putpixel((x, y), (255, 255, 255, 255))
                    elif brightness > 220:
                        emissive.putpixel((x, y), (255, 255, 255, 255))
                    else:
                        emissive.putpixel((x, y), (0, 0, 0, 255))
                elif type == "weapon":
                    # For weapons, bright colors like white, cyan, pure red, neon orange are glowing
                    brightness = 0.299*r + 0.587*g + 0.114*b
                    colorfulness = max(abs(r-g), abs(r-b), abs(g-b))
                    
                    if brightness > 180 and colorfulness > 50: # bright colors (neon)
                        emissive.putpixel((x, y), (255, 255, 255, 255))
                    elif brightness > 230: # bright white edges, but sometimes these are just highlights
                        emissive.putpixel((x, y), (255, 255, 255, 255))
                    else:
                        emissive.putpixel((x, y), (0, 0, 0, 255))
            else:
                emissive.putpixel((x, y), (0, 0, 0, 0))
                
    emissive.save(output_path)
    print(f"Saved emissive mask to {output_path}")

if __name__ == "__main__":
    goblin_f_sheet = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_spritesheet.png"
    goblin_f_emissive = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_spritesheet_e.png"
    
    goblin_a_f_sheet = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_spritesheet.png"
    goblin_a_f_emissive = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_spritesheet_e.png"

    create_emissive_mask(goblin_f_sheet, goblin_f_emissive, "goblin")
    create_emissive_mask(goblin_a_f_sheet, goblin_a_f_emissive, "goblin")
    
    # Weapons
    weapons_dir = r"j:\BoomerShooter\boomer-shooter\Assets\Weapons"
    for file in os.listdir(weapons_dir):
        if file.endswith(".png") and not file.endswith("_e.png"):
            path = os.path.join(weapons_dir, file)
            out_path = os.path.join(weapons_dir, file.replace(".png", "_e.png"))
            create_emissive_mask(path, out_path, "weapon")
