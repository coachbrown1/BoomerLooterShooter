from PIL import Image, ImageDraw
import os

def fix_goblin():
    path = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinForward\goblin_forward_spritesheet.png"
    img = Image.open(path).convert("RGBA")
    idle = img.crop((0, 0, 128, 128))
    
    # Lunge effect: Scale up slightly and center to make it seem like it's coming forward
    attack = idle.resize((int(128 * 1.1), int(128 * 1.1)), Image.BILINEAR)
    offset = int(128 * 0.05)
    attack = attack.crop((offset, offset, offset + 128, offset + 128))
    
    draw = ImageDraw.Draw(attack)
    # Sword swipe arc over the character
    draw.arc([10, 30, 118, 100], start=180, end=360, fill=(200, 200, 220, 255), width=8)
    draw.arc([15, 30, 113, 100], start=200, end=340, fill=(255, 255, 255, 200), width=4)
    # simple hilt
    draw.line([(5, 65), (20, 75)], fill=(101, 67, 33, 255), width=6)
    
    # clear frame 2 (Attack)
    draw_img = ImageDraw.Draw(img)
    draw_img.rectangle([256, 0, 384, 128], fill=(0,0,0,0))
    img.paste(attack, (256, 0), attack)
    img.save(path)
    print("Fixed goblin attack")

def fix_archer():
    path = r"j:\BoomerShooter\boomer-shooter\Assets\Enemies\GoblinArcherForward\goblin_archer_forward_spritesheet.png"
    img = Image.open(path).convert("RGBA")
    idle = img.crop((0, 0, 128, 128))
    
    # Simple tension: body moves slightly up/down or mostly remains same
    attack = idle.copy()
    draw = ImageDraw.Draw(attack)
    
    # Horizontal bow
    # Wooden bow arc (curved up)
    draw.arc([20, 50, 108, 90], start=180, end=360, fill=(120, 80, 40, 255), width=5)
    
    # Drawn string (V-shape)
    draw.line([(20, 70), (64, 85), (108, 70)], fill=(220, 220, 220, 180), width=2)
    
    # Arrow tip (pointing toward camera)
    draw.ellipse([60, 56, 68, 64], fill=(180, 180, 200, 255))
    draw.polygon([(64, 52), (60, 60), (68, 60)], fill=(200, 200, 220, 255))
    # Arrow shaft (going back to the hand/string at 64,85)
    draw.line([(64, 60), (64, 85)], fill=(139, 69, 19, 255), width=3)
    
    # clear frame 2
    draw_img = ImageDraw.Draw(img)
    draw_img.rectangle([256, 0, 384, 128], fill=(0,0,0,0))
    img.paste(attack, (256, 0), attack)
    img.save(path)
    print("Fixed archer attack")

if __name__ == "__main__":
    fix_goblin()
    fix_archer()
