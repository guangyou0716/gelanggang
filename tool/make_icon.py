"""Draws the gelanggang app icon (a white shuttlecock on teal) and writes
every size the platforms need. Run from the repo root (needs Pillow): python3 tool/make_icon.py"""
import json, os
from PIL import Image, ImageDraw

TEAL = (15, 118, 110)
TEAL_DARK = (17, 94, 89)
WHITE = (255, 255, 255)
CORK = (253, 230, 138)
S = 2048  # drawn large, scaled down for smooth edges


def draw(scale: float, rounded: bool) -> Image.Image:
    """scale: share of the canvas the shuttlecock may use (maskable icons keep
    it inside the 80% safe circle); rounded: transparent rounded corners."""
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=TEAL)
    else:
        d.rectangle([0, 0, S, S], fill=TEAL)
    # A faint court line behind the shuttle.
    lw = int(S * 0.018)
    ly = S / 2 + 0.36 * S * scale
    d.line([(S * 0.5 - 0.42 * S * scale, ly), (S * 0.5 + 0.42 * S * scale, ly)], fill=TEAL_DARK, width=lw)

    def p(x, y):  # unit coords (-0.5..0.5 around centre) to pixels
        return (S / 2 + x * S * scale, S / 2 + y * S * scale)

    # Feather skirt: a trapezoid opening upwards, slightly tilted feel by
    # scalloped top edge.
    top_y, base_y = -0.36, 0.17
    top_w, base_w = 0.36, 0.12
    d.polygon([p(-top_w, top_y), p(top_w, top_y), p(base_w, base_y), p(-base_w, base_y)], fill=WHITE)
    # Scallops along the top.
    n = 6
    r = top_w / n
    for i in range(n):
        cx = -top_w + r + i * 2 * r
        x0, y0 = p(cx - r, top_y - r * 0.9)
        x1, y1 = p(cx + r, top_y + r * 0.9)
        d.ellipse([x0, y0, x1, y1], fill=WHITE)
    # Feather shafts.
    shaft = int(S * 0.012 * scale / 0.8)
    for i in range(n + 1):
        fx = -top_w + i * (2 * top_w / n)
        bx = -base_w + i * (2 * base_w / n)
        d.line([p(fx * 0.92, top_y + 0.02), p(bx, base_y)], fill=TEAL, width=shaft)
    # Band where feathers meet the cork.
    d.rectangle([*p(-base_w - 0.01, base_y - 0.035), *p(base_w + 0.01, base_y + 0.01)], fill=TEAL_DARK)
    # Cork: a half-dome.
    x0, y0 = p(-base_w - 0.01, base_y + 0.01 - 0.13)
    x1, y1 = p(base_w + 0.01, base_y + 0.01 + 0.13)
    d.chord([x0, y0, x1, y1], start=0, end=180, fill=CORK)
    return img


def save(img: Image.Image, path: str, size: int, alpha: bool) -> None:
    out = img.resize((size, size), Image.LANCZOS)
    if not alpha:
        bg = Image.new('RGB', out.size, TEAL)
        bg.paste(out, mask=out.split()[3])
        out = bg
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path, optimize=True)


square = draw(0.8, rounded=False)
rounded = draw(0.8, rounded=True)
maskable = draw(0.62, rounded=False)

save(rounded, 'web/favicon.png', 32, True)
save(rounded, 'web/icons/Icon-192.png', 192, True)
save(rounded, 'web/icons/Icon-512.png', 512, True)
save(maskable, 'web/icons/Icon-maskable-192.png', 192, False)
save(maskable, 'web/icons/Icon-maskable-512.png', 512, False)
for folder, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save(rounded, f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png', size, True)
ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.load(open(f'{ios}/Contents.json'))['images']:
    pts = float(entry['size'].split('x')[0])
    px = round(pts * int(entry['scale'][0]))
    save(square, f"{ios}/{entry['filename']}", px, False)  # iOS: no alpha
save(rounded, 'docs/icon.png', 256, True)
