#!/usr/bin/env python3
"""Generates the Prompt Forge launcher icons into android/ and ios/ from assets/icon/*.png.

  python3 tool/make_icons.py        (needs Pillow: pip install pillow)

Idempotent and safe to re-run. Android: legacy square icons plus an adaptive icon (background colour +
foreground). iOS: every size listed in AppIcon.appiconset/Contents.json, without an alpha channel (App Store rule).
"""
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "assets/icon/icon.png"        # full-bleed 1024x1024, opaque
FOREGROUND = ROOT / "assets/icon/icon_fg.png"  # transparent, artwork inside the adaptive-icon safe zone
BACKGROUND_HEX = "#0B0D10"


def resized(img, px):
    return img.resize((px, px), Image.LANCZOS)


def android():
    res = ROOT / "android/app/src/main/res"
    if not (ROOT / "android").exists():
        print("android/ not generated yet - skipping Android icons")
        return
    icon = Image.open(ICON).convert("RGBA")
    fg = Image.open(FOREGROUND).convert("RGBA")
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for density, px in legacy.items():
        d = res / f"mipmap-{density}"
        d.mkdir(parents=True, exist_ok=True)
        resized(icon, px).save(d / "ic_launcher.png")
        resized(fg, adaptive[density]).save(d / "ic_launcher_foreground.png")
    any_v26 = res / "mipmap-anydpi-v26"
    any_v26.mkdir(parents=True, exist_ok=True)
    (any_v26 / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{BACKGROUND_HEX}</color>\n</resources>\n',
        encoding="utf-8",
    )
    print("android launcher icons written")


def ios():
    iconset = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = iconset / "Contents.json"
    if not contents.exists():
        print("ios/ not generated yet - skipping iOS icons")
        return
    icon = Image.open(ICON).convert("RGB")  # App Store rejects icons with an alpha channel
    data = json.loads(contents.read_text(encoding="utf-8"))
    written = 0
    for img in data.get("images", []):
        name = img.get("filename")
        if not name:
            continue
        size = float(img["size"].split("x")[0])
        scale = int(img.get("scale", "1x").rstrip("x"))
        px = int(round(size * scale))
        resized(icon, px).save(iconset / name)
        written += 1
    print(f"ios app icons written ({written} files)")


if __name__ == "__main__":
    android()
    ios()
