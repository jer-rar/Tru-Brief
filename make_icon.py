from PIL import Image, ImageFilter
import numpy as np

src = r"d:\Tru-Developer\trubrief_app\assets\images\Test 1.jpg"
out_fg = r"d:\Tru-Developer\trubrief_app\assets\images\trubrief_icon_fg.png"
out_main = r"d:\Tru-Developer\trubrief_app\assets\images\trubrief_icon_new.png"

img = Image.open(src).convert("RGB")
w, h = img.size

side = max(w, h)
square = Image.new("RGB", (side, side), (0, 0, 0))
square.paste(img, ((side - w) // 2, (side - h) // 2))

canvas_size = 1024

def make_icon(fill_pct, outpath):
    logo_size = int(canvas_size * fill_pct)
    logo = square.resize((logo_size, logo_size), Image.LANCZOS)
    canvas = Image.new("RGB", (canvas_size, canvas_size), (0, 0, 0))
    offset = (canvas_size - logo_size) // 2
    canvas.paste(logo, (offset, offset))
    arr = np.array(canvas, dtype=np.float32)
    edge = int(canvas_size * 0.015)
    for i in range(edge):
        alpha = i / edge
        arr[i, :] = arr[i, :] * alpha
        arr[-(i+1), :] = arr[-(i+1), :] * alpha
        arr[:, i] = arr[:, i] * alpha
        arr[:, -(i+1)] = arr[:, -(i+1)] * alpha
    result = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    result.save(outpath, "PNG")
    print(f"Saved {outpath} ({round(fill_pct*100)}% fill)")

make_icon(0.92, out_main)
make_icon(0.98, out_fg)
