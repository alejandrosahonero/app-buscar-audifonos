"""Composes the Play Store listing images from the raw app screens.

    STORE=1 flutter test test/store --update-goldens   # raw screens
    python tool/store/compose_listing.py               # -> store/

Output: store/feature-graphic-<lang>.png (1024x500) and
store/<lang>/0N-*.png phone screenshots (1080x1920), Faro palette.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "test/store/raw"
OUT = ROOT / "store"
FONTS = ROOT / "assets/fonts"

MAREA = (7, 24, 32)
CASCO = (15, 42, 51)
LINEA = (30, 60, 71)
FARO = (242, 180, 85)
ESPUMA = (228, 237, 239)
BRUMA = (143, 166, 172)

SHOTS = {
    "es": [
        ("radar_near", "Encuéntralos", "siguiendo la luz",
         "El radar se ilumina cuanto más cerca estás"),
        ("list_dark", "Todo lo que hay", "a tu alrededor",
         "Marca, modelo y batería de un vistazo"),
        ("radar_far", "Más cerca,", "más rápido suena",
         "Sonido tipo detector para buscar sin mirar"),
        ("list_light", "Tus favoritos,", "siempre arriba",
         "Aunque estén apagados o fuera de alcance"),
        ("howto", "Listo en", "cuatro pasos",
         "Sin configurar nada ni saber de Bluetooth"),
    ],
    "en": [
        ("radar_near", "Find them by", "following the light",
         "The radar glows brighter as you get closer"),
        ("list_dark", "Everything", "around you",
         "Brand, model and battery at a glance"),
        ("radar_far", "The closer you get,", "the faster it clicks",
         "Detector-style sound to search hands-free"),
        ("list_light", "Your favourites,", "always on top",
         "Even when they're off or out of range"),
        ("howto", "Ready in", "four steps",
         "No setup, no Bluetooth know-how needed"),
    ],
}

FEATURE = {
    "es": ("Buscar Audífonos", "Encuentra tus auriculares perdidos", "siguiendo la luz del radar"),
    "en": ("Buscar Audífonos", "Find your lost earbuds", "by following the radar's light"),
}


def font(name, size):
    return ImageFont.truetype(str(FONTS / f"{name}.ttf"), size)


def glow(size, center, radius, color, alpha):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = center
    d.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def arcs(img, center, radii, width, color):
    d = ImageDraw.Draw(img)
    x, y = center
    for r in radii:
        d.ellipse((x - r, y - r, x + r, y + r), outline=color, width=width)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def phone(screen, width):
    """The raw screen inside a thin Casco bezel, with rounded corners."""
    s = screen.resize((width, round(screen.height * width / screen.width)), Image.LANCZOS)
    bezel = 16
    w, h = s.width + 2 * bezel, s.height + 2 * bezel
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, w - 1, h - 1), 70, fill=CASCO, outline=LINEA, width=3)
    body.paste(s, (bezel, bezel), rounded_mask(s.size, 56))
    return body


def screenshot(lang, index, raw, line1, line2, sub):
    W, H = 1080, 1920
    img = Image.new("RGBA", (W, H), MAREA + (255,))
    img.alpha_composite(glow((W, H), (W // 2, 1250), 520, FARO, 70))
    arcs(img, (W // 2, 1250), (380, 560, 740), 2, LINEA)

    d = ImageDraw.Draw(img)
    title = font("Sora-600", 82)
    accent = font("Sora-300", 82)
    body = font("Manrope-500", 40)
    d.text((W // 2, 120), line1, font=title, fill=ESPUMA, anchor="mt")
    d.text((W // 2, 218), line2, font=accent, fill=FARO, anchor="mt")
    d.text((W // 2, 340), sub, font=body, fill=BRUMA, anchor="mt")

    device = phone(Image.open(RAW / f"{lang}_{raw}.png").convert("RGBA"), 640)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = (W - device.width) // 2
    y = 440
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, y + 20, x + device.width, y + device.height + 20), 70, fill=(0, 0, 0, 150))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)))
    img.alpha_composite(device, (x, y))

    path = OUT / lang / f"0{index}-{raw}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(path, optimize=True)
    return path


def logo(size):
    """brand/logo.svg redrawn at 4x and downsampled: headphones over radar waves."""
    k = size * 4 / 108
    big = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)

    def p(v):
        return v * k

    def arc(r, w, color):
        cx, cy = 54, 64
        o = r + w / 2  # Pillow draws the stroke inwards from the box
        d.arc((p(cx - o), p(cy - o), p(cx + o), p(cy + o)), 180, 360, fill=color, width=round(p(w)))
        for sx in (cx - r, cx + r):  # round caps
            d.ellipse((p(sx - w / 2), p(cy - w / 2), p(sx + w / 2), p(cy + w / 2)), fill=color)

    arc(28, 5.5, ESPUMA + (255,))
    arc(18, 4.5, ESPUMA + (140,))
    arc(9, 4.5, FARO + (255,))
    d.rounded_rectangle((p(20), p(60), p(32), p(78)), p(5), fill=ESPUMA)
    d.rounded_rectangle((p(76), p(60), p(88), p(78)), p(5), fill=ESPUMA)
    d.ellipse((p(49.5), p(61.5), p(58.5), p(70.5)), fill=FARO)
    return big.resize((size, size), Image.LANCZOS)


def feature_graphic(lang):
    W, H = 1024, 500
    img = Image.new("RGBA", (W, H), MAREA + (255,))
    c = (220, 262)
    img.alpha_composite(glow((W, H), c, 200, FARO, 80))
    arcs(img, c, (170, 260, 350, 440), 2, LINEA)
    img.alpha_composite(logo(300), (c[0] - 150, c[1] - 162))

    name, line1, line2 = FEATURE[lang]
    d = ImageDraw.Draw(img)
    d.text((448, 150), name, font=font("Sora-600", 50), fill=ESPUMA)
    d.text((450, 236), line1, font=font("Manrope-500", 29), fill=BRUMA)
    d.text((450, 276), line2, font=font("Manrope-500", 29), fill=BRUMA)
    d.rounded_rectangle((450, 340, 518, 346), 3, fill=FARO)

    path = OUT / f"feature-graphic-{lang}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(path, optimize=True)
    return path


if __name__ == "__main__":
    for lang, shots in SHOTS.items():
        print(feature_graphic(lang))
        for i, shot in enumerate(shots, 1):
            print(screenshot(lang, i, *shot))
