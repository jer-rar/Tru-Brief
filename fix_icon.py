from PIL import Image, ImageChops
import numpy as np

src = r"d:\Tru-Developer\trubrief_app\assets\images\Playstore_white.jpg"
out = r"d:\Tru-Developer\trubrief_app\assets\images\trubrief_icon_new.png"

img = Image.open(src).convert("RGBA")
print(f"Original size: {img.size}")

# Convert to RGB to find non-white content bounds
rgb = img.convert("RGB")
arr = np.array(rgb)

# Find pixels that are NOT near-white (threshold: any channel < 240)
mask = np.any(arr < 240, axis=2)
rows = np.any(mask, axis=1)
cols = np.any(mask, axis=0)

if rows.any() and cols.any():
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    print(f"Content bounds: rows {rmin}-{rmax}, cols {cmin}-{cmax}")
    content = img.crop((cmin, rmin, cmax + 1, rmax + 1))
else:
    content = img
    print("No non-white content found, using full image")

# Make the content square
cw, ch = content.size
side = max(cw, ch)
square_content = Image.new("RGBA", (side, side), (255, 255, 255, 255))
square_content.paste(content, ((side - cw) // 2, (side - ch) // 2))

# Build final 1024x1024 canvas with white background
# Logo fills 82% of canvas — matches YouTube/YT Music proportions
canvas_size = 1024
fill_pct = 0.82
logo_size = int(canvas_size * fill_pct)
logo = square_content.resize((logo_size, logo_size), Image.LANCZOS)

canvas = Image.new("RGBA", (canvas_size, canvas_size), (255, 255, 255, 255))
offset = (canvas_size - logo_size) // 2
canvas.paste(logo, (offset, offset), logo)

canvas.save(out, "PNG")
print(f"Saved {out} — logo at {round(fill_pct*100)}% fill ({logo_size}px in {canvas_size}px canvas)")
