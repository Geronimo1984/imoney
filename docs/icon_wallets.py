import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

S = 2048
OUT = 1024
C = S / 2
FONT = '/System/Library/Fonts/SFNSRounded.ttf'
FONT_PLAIN = '/System/Library/Fonts/SFNS.ttf'

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def grad(stops, angle=110):
    small = 128
    img = Image.new('RGB', (small, small))
    px = img.load()
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    corners = [x * dx + y * dy for x, y in [(0, 0), (1, 0), (0, 1), (1, 1)]]
    lo, hi = min(corners), max(corners)
    for y in range(small):
        for x in range(small):
            t = ((x / (small - 1)) * dx + (y / (small - 1)) * dy - lo) / (hi - lo)
            for k in range(len(stops) - 1):
                t0, c0 = stops[k]; t1, c1 = stops[k + 1]
                if t <= t1 or k == len(stops) - 2:
                    px[x, y] = lerp(c0, c1, min(max((t - t0) / max(t1 - t0, 1e-6), 0), 1))
                    break
    return img.resize((S, S), Image.BICUBIC)

def font(size, path=FONT, weight='Bold'):
    f = ImageFont.truetype(path, int(size))
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f

def mask(fn):
    m = Image.new('L', (S, S), 0)
    fn(ImageDraw.Draw(m))
    return m

def rotated(m, angle, cx=C, cy=C):
    return m.rotate(angle, resample=Image.BICUBIC, center=(cx, cy))

def shadow(img, m, dy=30, blur=40, alpha=0.45):
    sh = Image.new('L', (S, S), 0)
    sh.paste(m, (0, int(dy)))
    sh = sh.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * alpha))
    return Image.composite(Image.new('RGB', (S, S), (0, 0, 0)), img, sh)

def put(img, m, src):
    if isinstance(src, tuple):
        src = Image.new('RGB', (S, S), src)
    return Image.composite(src, img, m)

def glyph(s, size, cx, cy, angle=0):
    m = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(m)
    f = font(size)
    b = d.textbbox((0, 0), s, font=f)
    d.text((cx - (b[2] - b[0]) / 2 - b[0], cy - (b[3] - b[1]) / 2 - b[1]), s, font=f, fill=255)
    return rotated(m, angle, cx, cy) if angle else m

def card(img, box, colors, radius=110, angle=0, sheen=True, shadow_dy=-30):
    m = mask(lambda d: d.rounded_rectangle(box, radius=radius, fill=255))
    if angle:
        m = rotated(m, angle, (box[0] + box[2]) / 2, (box[1] + box[3]) / 2)
    img = shadow(img, m, shadow_dy, 40, 0.45)
    img = put(img, m, grad(colors, 110))
    if sheen:
        hl = grad([(0, (255, 255, 255)), (0.45, (0, 0, 0)), (1, (0, 0, 0))], 100).convert('L').point(lambda v: v * 60 // 255)
        img = Image.composite(Image.new('RGB', (S, S), (255, 255, 255)), img, ImageChops.multiply(hl, m))
    return img, m

YELLOW = [(0, (255, 214, 10)), (1, (255, 159, 10))]
GREEN = [(0, (52, 209, 99)), (1, (20, 150, 70))]
BLUE = [(0, (10, 145, 255)), (1, (50, 80, 230))]
RED = [(0, (255, 95, 90)), (1, (230, 40, 80))]
PURPLE = [(0, (175, 100, 255)), (1, (110, 60, 220))]
DARK_BG = [(0, (46, 46, 50)), (1, (10, 10, 12))]

def stack(img, palettes, top=-520, step=230, w=1300, h=820, front_mark=True, mark_color=(255, 255, 255)):
    for i, pal in enumerate(palettes):
        y = C + top + i * step
        img, _ = card(img, [C - w / 2, y, C + w / 2, y + h], pal)
    if front_mark:
        y = C + top + (len(palettes) - 1) * step
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([C - w / 2 + 130, y + h - 220, C - w / 2 + 530, y + h - 160], radius=30, fill=mark_color)
        img = put(img, glyph('₽', 330, C + w / 2 - 230, y + h - 230), mark_color)
    return img

# 1. Исходный: тёмный фон, жёлтая/зелёная/синяя
def w1():
    return stack(grad(DARK_BG, 90), [YELLOW, GREEN, BLUE])

# 2. Светлый фон
def w2():
    return stack(grad([(0, (255, 255, 255)), (1, (226, 230, 238))], 90), [YELLOW, GREEN, BLUE])

# 3. Веер карт на тёмном
def w3():
    img = grad(DARK_BG, 90)
    w, h = 1150, 730
    for pal, ang, dx, dy in [(YELLOW, 16, -150, -60), (GREEN, 4, -30, 30), (BLUE, -8, 90, 120)]:
        box = [C - w / 2 + dx, C - h / 2 + dy, C + w / 2 + dx, C + h / 2 + dy]
        img, _ = card(img, box, pal, angle=ang)
    img = put(img, glyph('₽', 340, C + 380, C + 330, -8), (255, 255, 255))
    return img

# 4. Синий градиент, белые матовые карты
def w4():
    img = grad([(0, (60, 140, 255)), (1, (60, 40, 200))])
    for i, alpha in enumerate([0.55, 0.75, 1.0]):
        y = C - 520 + i * 230
        m = mask(lambda d, y=y: d.rounded_rectangle([C - 650, y, C + 650, y + 820], radius=110, fill=255))
        img = shadow(img, m, -30, 40, 0.35)
        white = Image.blend(img, Image.new('RGB', (S, S), (255, 255, 255)), alpha)
        img = put(img, m, white)
    y = C - 520 + 460
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([C - 520, y + 600, C - 120, y + 660], radius=30, fill=(80, 90, 220))
    img = put(img, glyph('₽', 330, C + 420, y + 590), (80, 90, 220))
    return img

# 5. Две карты и монета, выглядывающая сверху
def w5():
    img = grad(DARK_BG, 90)
    coin = mask(lambda d: d.ellipse([C + 150, C - 760, C + 650, C - 260], fill=255))
    img = shadow(img, coin, 20, 30, 0.4)
    img = put(img, coin, grad([(0, (255, 226, 120)), (1, (230, 150, 20))], 90))
    img = put(img, glyph('₽', 300, C + 400, C - 510), (160, 95, 0))
    return stack(img, [GREEN, BLUE], top=-380, step=260)

# 6. Пять тонких полос-карт системных цветов
def w6():
    img = grad(DARK_BG, 90)
    pals = [RED, YELLOW, GREEN, BLUE, PURPLE]
    for i, pal in enumerate(pals):
        y = C - 640 + i * 150
        img, _ = card(img, [C - 650, y, C + 650, y + 820 if i == 4 else y + 400], pal, radius=100)
    img = put(img, glyph('₽', 330, C + 420, C + 420), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([C - 520, C + 380, C - 120, C + 440], radius=30, fill=(255, 255, 255))
    return img

# 7. Одна большая карта с чипом на ярком градиенте
def w7():
    img = grad([(0, (255, 120, 80)), (0.5, (255, 60, 120)), (1, (150, 60, 230))])
    m = mask(lambda d: d.rounded_rectangle([C - 700, C - 440, C + 700, C + 440], radius=120, fill=255))
    img = shadow(img, m, 40, 60, 0.35)
    img = put(img, m, grad([(0, (255, 255, 255)), (1, (235, 238, 245))], 90))
    chip = mask(lambda d: d.rounded_rectangle([C - 560, C - 260, C - 300, C - 60], radius=40, fill=255))
    img = put(img, chip, grad([(0, (255, 214, 110)), (1, (220, 160, 40))], 90))
    img = put(img, glyph('₽', 420, C + 430, C + 180), (230, 60, 120))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([C - 560, C + 160, C - 100, C + 220], radius=30, fill=(200, 205, 220))
    return img

# 8. Тёмный карман: карты выглядывают из кошелька
def w8():
    img = grad([(0, (0, 170, 150)), (1, (0, 100, 130))])
    img = stack(img, [YELLOW, BLUE], top=-640, step=200, front_mark=False)
    pocket = mask(lambda d: d.rounded_rectangle([C - 700, C - 160, C + 700, C + 640], radius=150, fill=255))
    img = shadow(img, pocket, -30, 50, 0.45)
    img = put(img, pocket, grad([(0, (44, 44, 48)), (1, (14, 14, 16))], 90))
    stitch = mask(lambda d: d.arc([C - 600, C - 560, C + 600, C + 40], 20, 160, fill=255, width=26))
    img = put(img, ImageChops.multiply(stitch, pocket), (90, 90, 96))
    img = put(img, glyph('₽', 330, C, C + 330), (255, 255, 255))
    return img

def rounded(img, size):
    im = img.resize((size, size), Image.LANCZOS)
    m = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4, size * 4], radius=size * 4 * 0.2237, fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out

# Пять карт: финальная иконка в трёх версиях
GRAYS = [[(0, (g, g, g)), (1, (g - 40, g - 40, g - 40))] for g in (235, 205, 175, 145, 115)]

def five_cards(bg, palettes=None, mark=(255, 255, 255)):
    img = grad(bg, 90)
    pals = palettes or [RED, YELLOW, GREEN, BLUE, PURPLE]
    for i, pal in enumerate(pals):
        y = C - 640 + i * 150
        img, _ = card(img, [C - 650, y, C + 650, y + 820 if i == 4 else y + 400], pal, radius=100)
    img = put(img, glyph('₽', 330, C + 420, C + 420), mark)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([C - 520, C + 380, C - 120, C + 440], radius=30, fill=mark)
    return img

def final(out):
    five_cards([(0, (255, 255, 255)), (1, (228, 231, 238))]).resize((OUT, OUT), Image.LANCZOS).save(f'{out}/icon-light.png')
    five_cards(DARK_BG).resize((OUT, OUT), Image.LANCZOS).save(f'{out}/icon-dark.png')
    five_cards([(0, (30, 30, 32)), (1, (0, 0, 0))], GRAYS, (40, 40, 40)).resize((OUT, OUT), Image.LANCZOS).save(f'{out}/icon-tinted.png')

if len(sys.argv) > 2 and sys.argv[2] == 'final':
    final(sys.argv[1])
    sys.exit(0)

out_dir = sys.argv[1]
options = [('W1', 'Как было', w1), ('W2', 'Светлый', w2), ('W3', 'Веер', w3), ('W4', 'Синий матовый', w4),
           ('W5', 'С монетой', w5), ('W6', 'Пять карт', w6), ('W7', 'Одна карта', w7), ('W8', 'Карман', w8)]
icons = []
for key, name, fn in options:
    im = fn().resize((OUT, OUT), Image.LANCZOS)
    im.save(f'{out_dir}/{key}.png')
    icons.append((key, name, im))

cell, pad, cols = 220, 56, 4
rows = math.ceil(len(icons) / cols)
W = cols * (cell + pad) + pad
block = rows * (cell + 90) + 40
sheet = Image.new('RGB', (W, 2 * block), (255, 255, 255))
d = ImageDraw.Draw(sheet)
label = font(28, FONT_PLAIN, 'Semibold')
for b_i, (bg, fg) in enumerate([((242, 242, 247), (28, 28, 30)), ((28, 28, 30), (235, 235, 245))]):
    yb = b_i * block
    d.rectangle([0, yb, W, yb + block], fill=bg)
    for i, (key, name, im) in enumerate(icons):
        x = pad + (i % cols) * (cell + pad)
        y = yb + 30 + (i // cols) * (cell + 90)
        r = rounded(im, cell)
        sheet.paste(r, (x, y), r)
        t = f'{key}. {name}'
        bb = d.textbbox((0, 0), t, font=label)
        d.text((x + (cell - (bb[2] - bb[0])) / 2, y + cell + 18), t, font=label, fill=fg)
sheet.save(f'{out_dir}/wallets.png')
