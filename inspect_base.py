from PIL import Image
import sys

img = Image.open(r"C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_facing_forward_gemini_1772893490735.png").convert("RGBA")
for (x, y) in [(0,0), (320,0), (0,320), (320,320)]:
    frame = img.crop((x, y, x + 320, y + 320))
    bbox = frame.getbbox()
    if bbox:
        pixels = sum(1 for p in frame.getdata() if p[3] > 100)
        print(f"Cell {(x,y)}: bbox {bbox}, area {pixels}")
