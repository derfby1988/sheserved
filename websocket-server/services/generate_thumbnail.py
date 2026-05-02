import sys
import os
import json
from PIL import Image

def generate_thumbnail():
    try:
        input_paths = sys.argv[1].split(',')
        output_path = sys.argv[2]
        
        if not input_paths or not input_paths[0]:
            print(json.dumps({"success": False, "error": "No input images provided"}))
            sys.exit(1)
            
        images = []
        target_size = None
        
        from PIL import ImageOps
        
        for path in input_paths:
            if os.path.exists(path):
                try:
                    # Open image
                    img = Image.open(path)
                    # Convert to RGB to ensure compatibility
                    if img.mode != 'RGB':
                        img = img.convert('RGB')
                        
                    if target_size is None:
                        # Calculate dimensions based on first image (width 400px)
                        basewidth = 400
                        wpercent = (basewidth / float(img.size[0]))
                        hsize = int((float(img.size[1]) * float(wpercent)))
                        target_size = (basewidth, hsize)
                        
                    # Resize and crop to exactly match target_size
                    img = ImageOps.fit(img, target_size, Image.Resampling.LANCZOS)
                    images.append(img)
                except Exception as e:
                    pass # Ignore unreadable images
                    
        if not images:
            print(json.dumps({"success": False, "error": "No valid images could be read"}))
            sys.exit(1)
            
        if len(images) == 1:
            # Single image thumbnail
            images[0].save(output_path, format='WEBP', quality=60)
        else:
            # Animated WebP for multiple images (2 seconds per frame = 2000ms)
            images[0].save(output_path, format='WEBP', save_all=True, append_images=images[1:], duration=2000, loop=0, quality=60)
            
        print(json.dumps({"success": True, "output": output_path, "frames": len(images)}))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    generate_thumbnail()
