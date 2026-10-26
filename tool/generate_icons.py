"""Genera todos los iconos de Simple Music a partir de la imagen de marca.

Uso:
    python tool/generate_icons.py

La imagen original está en assets/branding/app_icon_source.jpg. El script
recorta el cuadrado azul, crea la versión con esquinas transparentes, extrae
el glifo blanco para el icono adaptativo de Android y exporta los tamaños de
Android, iOS, macOS, web y Windows.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "branding" / "app_icon_source.jpg"
MASTER = ROOT / "assets" / "images" / "app_icon.png"
OPAQUE = ROOT / "assets" / "images" / "app_icon_opaque.png"

# Recorte exacto del cuadrado azul dentro de la imagen original (784x1168).
CROP = (137, 302, 646, 836)
SIZE = 1024
RADIUS = 238
TOP_COLOR = (27, 116, 234)
BOTTOM_COLOR = (8, 67, 171)


def rounded_mask(size: int, radius: int, supersample: int = 4) -> Image.Image:
    big = size * supersample
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (0, 0, big - 1, big - 1),
        radius=radius * supersample,
        fill=255,
    )
    return mask.resize((size, size), Image.Resampling.LANCZOS)


def circle_mask(size: int, supersample: int = 4) -> Image.Image:
    big = size * supersample
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, big - 1, big - 1), fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)


def gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    column = Image.new("RGB", (1, size))
    pixels = column.load()
    for y in range(size):
        t = y / max(1, size - 1)
        pixels[0, y] = tuple(
            round(top[i] * (1 - t) + bottom[i] * t) for i in range(3)
        )
    return column.resize((size, size), Image.Resampling.BILINEAR)


def build_master() -> Image.Image:
    source = Image.open(SOURCE).convert("RGB")
    crop = source.crop(CROP).resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    crop.putalpha(rounded_mask(SIZE, RADIUS))
    return crop


def build_opaque(master: Image.Image) -> Image.Image:
    background = gradient(SIZE, TOP_COLOR, BOTTOM_COLOR).convert("RGBA")
    background.alpha_composite(master)
    return background.convert("RGB")


def build_glyph(master: Image.Image, canvas: int = 432) -> Image.Image:
    rgba = np.asarray(master).astype(np.int16)
    red, green, blue = rgba[:, :, 0], rgba[:, :, 1], rgba[:, :, 2]
    whiteness = np.minimum(np.minimum(red, green), blue)
    saturation = np.maximum(np.maximum(red, green), blue) - whiteness
    alpha = np.clip((whiteness - 150) / 80.0, 0.0, 1.0)
    alpha *= np.clip((70.0 - saturation) / 50.0, 0.0, 1.0)
    alpha = (alpha * 255).astype(np.uint8)

    glyph = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    glyph.putalpha(Image.fromarray(alpha, "L"))
    bbox = glyph.getbbox()
    if bbox is None:
        raise RuntimeError("No se pudo extraer el glifo blanco del icono.")
    glyph = glyph.crop(bbox)

    max_side = int(canvas * 0.60)
    scale = min(max_side / glyph.width, max_side / glyph.height)
    glyph = glyph.resize(
        (max(1, round(glyph.width * scale)), max(1, round(glyph.height * scale))),
        Image.Resampling.LANCZOS,
    )

    # Sombra suave para conservar la profundidad del icono original.
    shadow = Image.new("RGBA", glyph.size, (0, 0, 0, 0))
    shadow.putalpha(glyph.getchannel("A").filter(ImageFilter.GaussianBlur(5)))
    shadow = shadow.point(lambda value: int(value * 0.35))
    shadow_color = Image.new("RGBA", glyph.size, (2, 12, 38, 255))
    shadow_color.putalpha(shadow.getchannel("A"))

    result = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    offset = (canvas - glyph.width) // 2
    top = (canvas - glyph.height) // 2
    result.alpha_composite(shadow_color, (offset + 3, top + 6))
    result.alpha_composite(glyph, (offset, top))
    return result


def resize(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)


def save_opaque(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resize(image.convert("RGB"), size).save(path, "PNG", optimize=True)


def generate_android(master: Image.Image, opaque: Image.Image, glyph: Image.Image) -> None:
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    legacy = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in legacy.items():
        save_png(resize(master, size), res / folder / "ic_launcher.png")
        round_icon = opaque.convert("RGBA")
        round_icon.putalpha(circle_mask(SIZE))
        save_png(resize(round_icon, size), res / folder / "ic_launcher_round.png")

    adaptive = {
        "mipmap-mdpi": 108,
        "mipmap-hdpi": 162,
        "mipmap-xhdpi": 216,
        "mipmap-xxhdpi": 324,
        "mipmap-xxxhdpi": 432,
    }
    for folder, size in adaptive.items():
        save_png(resize(glyph, size), res / folder / "ic_launcher_foreground.png")

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (anydpi / name).write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '</adaptive-icon>\n',
            encoding="utf-8",
        )

    drawable = res / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    (drawable / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android" '
        'android:shape="rectangle">\n'
        '    <gradient\n'
        '        android:angle="270"\n'
        f'        android:startColor="#{TOP_COLOR[0]:02X}{TOP_COLOR[1]:02X}{TOP_COLOR[2]:02X}"\n'
        f'        android:endColor="#{BOTTOM_COLOR[0]:02X}{BOTTOM_COLOR[1]:02X}{BOTTOM_COLOR[2]:02X}" />\n'
        '</shape>\n',
        encoding="utf-8",
    )

    nodpi = res / "drawable-nodpi"
    nodpi.mkdir(parents=True, exist_ok=True)
    save_png(resize(master, 288), nodpi / "launch_icon.png")


def generate_ios(opaque: Image.Image) -> None:
    iconset = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((iconset / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents.get("images", []):
        filename = entry.get("filename")
        if not filename:
            continue
        size_text = entry.get("size", "1024x1024")
        base = float(size_text.split("x")[0])
        scale = int(entry.get("scale", "1x").rstrip("x"))
        pixels = round(base * scale)
        save_opaque(opaque, iconset / filename, pixels)


def generate_macos(opaque: Image.Image) -> None:
    iconset = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((iconset / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents.get("images", []):
        filename = entry.get("filename")
        if not filename:
            continue
        size_text = entry.get("size", "1024x1024")
        base = float(size_text.split("x")[0])
        scale = int(entry.get("scale", "1x").rstrip("x"))
        pixels = round(base * scale)
        save_opaque(opaque, iconset / filename, pixels)


def generate_web(master: Image.Image, opaque: Image.Image) -> None:
    web = ROOT / "web"
    save_opaque(opaque, web / "icons" / "Icon-192.png", 192)
    save_opaque(opaque, web / "icons" / "Icon-512.png", 512)
    save_opaque(opaque, web / "favicon.png", 64)

    for size in (192, 512):
        canvas = gradient(size, TOP_COLOR, BOTTOM_COLOR).convert("RGBA")
        icon_size = round(size * 0.80)
        icon = resize(master, icon_size)
        canvas.alpha_composite(icon, ((size - icon_size) // 2, (size - icon_size) // 2))
        save_png(canvas, web / "icons" / f"Icon-maskable-{size}.png")


def generate_windows(opaque: Image.Image) -> None:
    ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    images = [resize(opaque.convert("RGB"), size[0]) for size in sizes]
    images[-1].save(ico, format="ICO", sizes=sizes)


def main() -> None:
    master = build_master()
    opaque = build_opaque(master)
    glyph = build_glyph(master)

    save_png(master, MASTER)
    opaque.save(OPAQUE, "PNG", optimize=True)

    generate_android(master, opaque, glyph)
    generate_ios(opaque)
    generate_macos(opaque)
    generate_web(master, opaque)
    generate_windows(opaque)

    print(f"Master: {MASTER}")
    print(f"Opaque: {OPAQUE}")
    print("Iconos generados correctamente.")


if __name__ == "__main__":
    main()
