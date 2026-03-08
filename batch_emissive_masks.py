import os, sys
sys.path.insert(0, r'j:\BoomerShooter')
from generate_emissive_masks import create_emissive_mask

enemies_dir = r'j:\BoomerShooter\boomer-shooter\Assets\Enemies'
for root, dirs, files in os.walk(enemies_dir):
    for file in files:
        if file.endswith('.png') and not file.endswith('_e.png'):
            path = os.path.join(root, file)
            out_path = os.path.join(root, file.replace('.png', '_e.png'))
            if not os.path.exists(out_path):
                create_emissive_mask(path, out_path, 'goblin')
                print('Generated:', out_path)
            else:
                print('Already exists:', out_path)
print("Done!")
