import sys
import os
import json
from PIL import Image

def generate_thumbnail():
    try:
        # ✅ Bug #2 Fix: รับ JSON Array แทน comma-separated string
        # เพื่อรองรับ path ที่มี comma ใน filename หรือ folder name
        input_paths = json.loads(sys.argv[1])
        output_path = sys.argv[2]
        
        if not input_paths:
            print(json.dumps({"success": False, "error": "No input images provided"}))
            sys.exit(1)
            
        images = []
        valid_paths = []
        from PIL import ImageOps
        
        for path in input_paths:
            if os.path.exists(path):
                try:
                    # Open image
                    img = Image.open(path)
                    # Convert to RGB to ensure compatibility
                    if img.mode != 'RGB':
                        img = img.convert('RGB')
                    images.append(img)
                    valid_paths.append(path)
                except Exception as e:
                    pass # Ignore unreadable images
                    
        if not images:
            print(json.dumps({"success": False, "error": "No valid images could be read"}))
            sys.exit(1)
            
        if len(images) == 1:
            # Single image: just resize and save (width 400px)
            img = images[0]
            basewidth = 400
            wpercent = (basewidth / float(img.size[0]))
            hsize = int((float(img.size[1]) * float(wpercent)))
            img = img.resize((basewidth, hsize), Image.Resampling.LANCZOS)
            img.save(output_path, format='WEBP', quality=80)
            print(json.dumps({"success": True, "output": output_path, "frames": 1}))
        else:
            # Multiple images: Blurred Background + Stack
            from PIL import ImageFilter, ImageEnhance
            
            canvas_w, canvas_h = 400, 300
            
            # 1. Background (using newest image which is images[0] because input is newest-first)
            # ✅ ใช้ ImageOps.fit เพื่อ crop ให้พอดีกับ canvas เสมอ ไม่ว่า aspect ratio จะเป็นอะไร
            bg = ImageOps.fit(images[0], (canvas_w, canvas_h), Image.Resampling.LANCZOS)
            bg = bg.filter(ImageFilter.GaussianBlur(15))
            bg = ImageEnhance.Brightness(bg).enhance(0.5) # Darken slightly for contrast
            
            # 2. Draw images from oldest to newest (reversed)
            draw_list = images[::-1]
            
            # Predefined angles to look like a highly scattered photo album
            angles = [-20, 15, -15, 10, 0]
            # Use only the angles we need, ensuring the last one (newest) is always 0 degrees (straight)
            used_angles = angles[-len(draw_list):] if len(draw_list) <= 5 else angles
            
            for i, img in enumerate(draw_list):
                if i >= 5: break
                
                # ✅ ใช้ ImageOps.fit สำหรับ thumbnail ด้วย เพื่อป้องกัน aspect ratio issues
                thumb_w = int(canvas_w * 0.55)
                thumb_h = int(canvas_h * 0.55)
                # Cap ขนาดให้ไม่เกิน canvas ขนาดใหญ่เกินไป
                if thumb_h > int(canvas_h * 0.75):
                    thumb_h = int(canvas_h * 0.75)
                    thumb_w = int(canvas_w * 0.55)
                    
                # ใช้ resize ปกติเพื่อรักษา aspect ratio ของภาพต้นฉบับ (ดีกว่า fit สำหรับ album stack)
                img_aspect = img.size[0] / float(img.size[1])
                if img_aspect >= 1:
                    # landscape or square
                    actual_w = thumb_w
                    actual_h = int(thumb_w / img_aspect)
                else:
                    # portrait
                    actual_h = thumb_h
                    actual_w = int(thumb_h * img_aspect)
                    
                # Cap ความสูงไม่ให้เกิน
                if actual_h > int(canvas_h * 0.75):
                    actual_h = int(canvas_h * 0.75)
                    actual_w = int(actual_h * img_aspect)
                    
                thumb = img.resize((actual_w, actual_h), Image.Resampling.LANCZOS)
                
                # Add white border
                border_size = 4
                thumb_with_border = ImageOps.expand(thumb, border=border_size, fill='white')
                
                # Rotate with alpha channel to preserve transparent corners
                angle = used_angles[i]
                rotated = thumb_with_border.convert('RGBA').rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
                
                # Calculate center coordinates
                paste_x = (canvas_w - rotated.width) // 2
                paste_y = (canvas_h - rotated.height) // 2
                
                # Paste onto background using alpha channel as mask
                bg.paste(rotated, (paste_x, paste_y), rotated)
                
            bg.save(output_path, format='WEBP', quality=80)
            print(json.dumps({"success": True, "output": output_path, "frames": len(images), "type": "stack"}))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    generate_thumbnail()
