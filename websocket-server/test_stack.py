import sys
import os
import json
from PIL import Image, ImageFilter, ImageOps, ImageEnhance

def create_stack():
    try:
        # Create dummy images
        img1 = Image.new('RGB', (800, 600), color='red')
        img1.save('t1.jpg')
        img2 = Image.new('RGB', (600, 800), color='blue')
        img2.save('t2.jpg')
        img3 = Image.new('RGB', (800, 800), color='green')
        img3.save('t3.jpg')
        
        input_paths = ['t1.jpg', 't2.jpg', 't3.jpg']
        
        images = []
        for path in input_paths:
            img = Image.open(path).convert('RGB')
            images.append(img)
            
        canvas_w, canvas_h = 400, 300
        
        # 1. Background (using newest image which is images[0] because list is sorted newest first)
        bg = ImageOps.fit(images[0], (canvas_w, canvas_h), Image.Resampling.LANCZOS)
        bg = bg.filter(ImageFilter.GaussianBlur(15))
        bg = ImageEnhance.Brightness(bg).enhance(0.5) # Darken slightly
        
        # 2. Draw images from oldest to newest (reversed)
        # Assuming input is [newest, older, oldest]
        draw_list = images[::-1]
        
        # Predefined angles for up to 5 images
        angles = [-12, 10, -6, 8, 0]
        # Start using angles from the end so the last one is always 0
        used_angles = angles[-len(draw_list):] if len(draw_list) <= 5 else angles
        
        for i, img in enumerate(draw_list):
            if i >= 5: break
            
            # Create a thumbnail with a white border
            thumb_w = int(canvas_w * 0.5)
            # preserve aspect ratio
            ratio = thumb_w / float(img.size[0])
            thumb_h = int(img.size[1] * ratio)
            
            # Cap height to avoid being too tall
            if thumb_h > int(canvas_h * 0.75):
                thumb_h = int(canvas_h * 0.75)
                thumb_w = int(img.size[0] * (thumb_h / float(img.size[1])))
                
            thumb = img.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            
            # Add white border
            border_size = 6
            thumb_with_border = ImageOps.expand(thumb, border=border_size, fill='white')
            
            # Rotate
            angle = used_angles[i]
            # expand=True to keep corners
            rotated = thumb_with_border.convert('RGBA').rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
            
            # Center coordinates
            paste_x = (canvas_w - rotated.width) // 2
            paste_y = (canvas_h - rotated.height) // 2
            
            # Paste with alpha channel
            bg.paste(rotated, (paste_x, paste_y), rotated)
            
        bg.save('stack_out.webp', format='WEBP', quality=80)
        print("Done")
    except Exception as e:
        print(f"Error: {e}")

create_stack()
