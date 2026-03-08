import os
from PIL import Image, ImageDraw

def create_grate_cookie(output_path):
    # 256x256 monochrome image
    size = 256
    img = Image.new("L", (size, size), 255) # White background (light passes through)
    draw = ImageDraw.Draw(img)
    
    # Draw thick black grid lines
    line_thickness = 16
    spacing = 64
    
    for i in range(0, size + 1, spacing):
        # Vertical lines
        draw.rectangle([i - line_thickness//2, 0, i + line_thickness//2, size], fill=0)
        # Horizontal lines
        draw.rectangle([0, i - line_thickness//2, size, i + line_thickness//2], fill=0)
        
    # Soften the edges so it looks more like a shadow
    img = img.resize((128, 128), Image.Resampling.LANCZOS).resize((256, 256), Image.Resampling.LANCZOS)
        
    img.save(output_path)
    print(f"Saved: {output_path}")

if __name__ == "__main__":
    os.makedirs(r"j:\BoomerShooter\boomer-shooter\Assets\Effects", exist_ok=True)
    create_grate_cookie(r"j:\BoomerShooter\boomer-shooter\Assets\Effects\cookie_grate.png")
