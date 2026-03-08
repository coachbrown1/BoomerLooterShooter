import sys
from PIL import Image

def analyze_alpha(image_path):
    img = Image.open(image_path).convert('RGBA')
    width, height = img.size
    semi_transparent = 0
    opaque = 0
    transparent = 0
    
    for y in range(height):
        for x in range(width):
            _, _, _, a = img.getpixel((x, y))
            if a == 0:
                transparent += 1
            elif a == 255:
                opaque += 1
            else:
                semi_transparent += 1
                
    print(f"File: {image_path}")
    print(f"Size: {width}x{height}")
    print(f"Opaque pixels: {opaque}")
    print(f"Transparent pixels (alpha=0): {transparent}")
    print(f"Semi-transparent pixels (0 < alpha < 255): {semi_transparent}")

analyze_alpha(sys.argv[1])
