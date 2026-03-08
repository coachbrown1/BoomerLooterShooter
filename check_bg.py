from PIL import Image
img1 = Image.open(r'C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_facing_forward_gemini_1772893490735.png')
img2 = Image.open(r'C:\Users\18136\.gemini\antigravity\brain\f8adc7ff-b554-40f6-bd98-b9946fe22daa\goblin_archer_facing_forward_gemini_1772893547748.png')
print('Normal:', img1.getpixel((0,0)), img1.getpixel((320,320)))
print('Archer:', img2.getpixel((0,0)), img2.getpixel((320,320)))
