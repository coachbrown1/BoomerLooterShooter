from PIL import Image
import math
import sys

img = Image.open(sys.argv[1]).convert("RGBA")
for i in range(8):
    frame = img.crop((i*128, 0, (i+1)*128, 128))
    bbox = frame.getbbox()
    if bbox:
        pixels = sum(1 for p in frame.getdata() if p[3] > 100)
        print(f"Frame {i}: bbox {bbox}, area {pixels}")
    else:
        print(f"Frame {i}: empty")
