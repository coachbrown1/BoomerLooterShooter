from PIL import Image, ImageChops
import os

def find_sprites(img_path):
    img = Image.open(img_path).convert("RGBA")
    w, h = img.size
    
    # Remove white background
    data = img.getdata()
    new_data = []
    for p in data:
        if p[0] > 240 and p[1] > 240 and p[2] > 240:
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append((p[0], p[1], p[2], 255))
    img.putdata(new_data)
    
    # Find all disconnected components (simple bounding box search)
    # We'll use a threshold to ignore small things like labels
    
    # Let's just crop the image into a bunch of small boxes and see which ones have pixels
    box_size = 32
    occupied = []
    for y in range(0, h, box_size):
        for x in range(0, w, box_size):
            box = img.crop((x, y, x + box_size, y + box_size))
            if box.getbbox():
                occupied.append((x, y))
    
    # Group neighboring occupied boxes
    visited = set()
    clusters = []
    
    for x, y in occupied:
        if (x, y) in visited: continue
        
        # BFS to find cluster
        cluster = []
        q = [(x, y)]
        visited.add((x, y))
        while q:
            cx, cy = q.pop(0)
            cluster.append((cx, cy))
            for nx, ny in [(cx-box_size, cy), (cx+box_size, cy), (cx, cy-box_size), (cx, cy+box_size)]:
                if (nx, ny) in occupied and (nx, ny) not in visited:
                    visited.add((nx, ny))
                    q.append((nx, ny))
        
        # Find bbox of cluster
        min_x = min(c[0] for c in cluster)
        max_x = max(c[0] for c in cluster) + box_size
        min_y = min(c[1] for c in cluster)
        max_y = max(c[1] for c in cluster) + box_size
        
        # Don't take tiny clusters (likely labels)
        if (max_x - min_x) > 64 and (max_y - min_y) > 64:
            clusters.append((min_x, min_y, max_x, max_y))
            
    # Sort clusters by Y then X
    clusters.sort(key=lambda c: (c[1] // (h//2), c[0]))
    
    print(f"Found {len(clusters)} clusters:")
    for i, (x1, y1, x2, y2) in enumerate(clusters):
        print(f"Cluster {i}: ({x1}, {y1}) to ({x2}, {y2}), size: {x2-x1}x{y2-y1}")
        # Crop and save for debug
        # img.crop((x1, y1, x2, y2)).save(f"debug_cluster_{i}.png")
        
    return img, clusters

if __name__ == "__main__":
    find_sprites(r"j:\BoomerShooter\sprite_previews\SporeHusk.png")
