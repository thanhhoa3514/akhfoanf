#!/usr/bin/env python3
"""Turn raw App Store UI-test screenshots into captioned store images.

Usage:
    python3 scripts/appstore_frames.py --input snapshots/ --output appstore/ --device iphone
    python3 scripts/appstore_frames.py --input snapshots/ --output appstore/ --device ipad --lang de

`--input` is the folder written by `xcrun xcresulttool export attachments` (PNG files plus
manifest.json). Output sizes are the ones App Store Connect accepts:

    iphone → iPhone 6.9"  1320 x 2868  and  iPhone 6.5"  1284 x 2778   (portrait)
    ipad   → iPad 13"     2752 x 2064                                (landscape)
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

BRAND = (63, 117, 104)        # #3F7568, AppTheme.Colors.brandPrimary (light)
BRAND_DEEP = (44, 88, 77)
MINT = (231, 242, 239)        # #E7F2EF, brandPrimarySoft
WHITE = (255, 255, 255)

# Store order. The first three are what people see in App Store search results.
SHOTS = ["appstore-01-home", "appstore-02-review", "appstore-03-history",
         "appstore-04-reminders", "appstore-05-search", "appstore-06-document"]

# (title, subtitle) per language, in store order. Keep titles to two short lines.
CAPTIONS: dict[str, list[tuple[str, str]]] = {
    "en": [
        ("Your pet's health,\nall in one place", "Vaccines, medication, visits and documents."),
        ("Scan a vet document.\nWe do the typing.", "Read on your device. You check every detail."),
        ("Every record links\nto its source", "A timeline you can trust at the vet."),
        ("Never miss\na booster", "Due-soon reminders for vaccines and meds."),
        ("Find anything\nin seconds", "Even words inside scanned documents. Offline."),
        ("Private\nby design", "Everything stays on your device. No account."),
    ],
    "de": [
        ("Die Gesundheit deines\nTieres an einem Ort", "Impfungen, Medikamente, Besuche, Dokumente."),
        ("Dokument scannen.\nWir tippen ab.", "Gelesen auf deinem Gerät. Geprüft von dir."),
        ("Jeder Eintrag mit\nOriginalbeleg", "Eine Akte, auf die du dich verlassen kannst."),
        ("Keine Auffrischung\nmehr verpassen", "Erinnerungen für Impfungen und Medikamente."),
        ("Alles in\nSekunden finden", "Sogar Text in gescannten Dokumenten. Offline."),
        ("Privat von\nAnfang an", "Alles bleibt auf deinem Gerät. Kein Konto."),
    ],
    "fr": [
        ("La santé de votre\nanimal, réunie", "Vaccins, traitements, visites et documents."),
        ("Scannez un document.\nOn fait la saisie.", "Lu sur votre appareil. Vérifié par vous."),
        ("Chaque fiche reliée\nà sa source", "Un historique fiable chez le vétérinaire."),
        ("Ne manquez plus\naucun rappel", "Rappels pour les vaccins et les traitements."),
        ("Tout retrouver\nen quelques secondes", "Même le texte des documents scannés. Hors ligne."),
        ("Privé par\nconception", "Tout reste sur votre appareil. Sans compte."),
    ],
    "ja": [
        ("ペットの健康記録を\nひとつの場所に", "ワクチン・お薬・通院・書類をまとめて管理"),
        ("書類をスキャン。\n入力はおまかせ。", "読み取りは端末内。内容はあなたが確認。"),
        ("すべての記録が\n元の書類とつながる", "獣医さんにも見せられる、確かな記録"),
        ("追加接種を\nもう忘れない", "ワクチンとお薬の予定をリマインド"),
        ("すぐに\n見つかる", "スキャンした書類の文字まで検索。オフライン対応"),
        ("プライバシー\n重視", "データは端末内に。アカウント登録不要"),
    ],
}

TARGETS = {
    "iphone": [("iphone-6.9in", (1320, 2868)), ("iphone-6.5in", (1284, 2778))],
    "ipad": [("ipad-13in", (2752, 2064))],
}

# Latin first; Japanese needs a CJK face (Hiragino ships with macOS).
CJK_FONTS = {
    True: ["/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc", "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
           "/System/Library/Fonts/Hiragino Sans GB.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"],
    False: ["/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc", "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
            "/System/Library/Fonts/Hiragino Sans GB.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"],
}
USE_CJK = False

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/SFNSDisplay.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size: int, bold: bool) -> ImageFont.FreeTypeFont:
    for path in (CJK_FONTS[bold] if USE_CJK else []) + FONT_CANDIDATES:
        if not Path(path).exists():
            continue
        try:
            font = ImageFont.truetype(path, size)
            try:  # SF Pro is a variable font
                font.set_variation_by_name("Bold" if bold else "Regular")
            except (OSError, ValueError, AttributeError):
                pass
            return font
        except OSError:
            continue
    return ImageFont.load_default(size)


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def background(size: tuple[int, int]) -> Image.Image:
    """Vertical brand gradient."""
    w, h = size
    top, bottom = BRAND, BRAND_DEEP
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize(size).convert("RGBA")


def draw_text_block(draw: ImageDraw.ImageDraw, xy: tuple[int, int], width: int, title: str, subtitle: str,
                    title_size: int, align: str) -> int:
    """Draws title + subtitle; returns the y below the block."""
    x, y = xy
    # Shrink until the widest line fits in 88% of the canvas (long localised captions).
    while title_size > 24:
        title_font = load_font(title_size, bold=True)
        sub_font = load_font(int(title_size * 0.46), bold=False)
        widest = max(draw.textlength(line, font=title_font) for line in title.split("\n"))
        if widest <= width * 0.88 and draw.textlength(subtitle, font=sub_font) <= width * 0.92:
            break
        title_size = int(title_size * 0.94)
    spacing = int(title_size * 0.12)
    anchor_x = x + width // 2 if align == "center" else x
    anchor = "ma" if align == "center" else "la"
    draw.multiline_text((anchor_x, y), title, font=title_font, fill=WHITE, anchor=anchor,
                        align=align, spacing=spacing)
    box = draw.multiline_textbbox((anchor_x, y), title, font=title_font, anchor=anchor, align=align, spacing=spacing)
    y = box[3] + int(title_size * 0.35)
    draw.text((anchor_x, y), subtitle, font=sub_font, fill=MINT, anchor=anchor)
    sub_box = draw.textbbox((anchor_x, y), subtitle, font=sub_font, anchor=anchor)
    return sub_box[3]


def compose_portrait(shot: Image.Image, size: tuple[int, int], title: str, subtitle: str) -> Image.Image:
    w, h = size
    canvas = background(size)
    draw = ImageDraw.Draw(canvas)
    text_bottom = draw_text_block(draw, (0, int(h * 0.06)), w, title, subtitle, title_size=int(w * 0.082),
                                  align="center")

    phone_w = int(w * 0.80)
    phone = shot.resize((phone_w, int(shot.height * phone_w / shot.width)), Image.LANCZOS)
    phone = rounded(phone, radius=int(phone_w * 0.085))
    top = text_bottom + int(h * 0.045)
    left = (w - phone_w) // 2
    paste_with_shadow(canvas, phone, (left, top), blur=int(w * 0.02))
    return canvas.convert("RGB")


def compose_landscape(shot: Image.Image, size: tuple[int, int], title: str, subtitle: str) -> Image.Image:
    w, h = size
    canvas = background(size)
    draw = ImageDraw.Draw(canvas)
    text_bottom = draw_text_block(draw, (0, int(h * 0.06)), w, title.replace("\n", " "), subtitle,
                                  title_size=int(h * 0.062), align="center")

    tablet_w = int(w * 0.84)
    tablet = shot.resize((tablet_w, int(shot.height * tablet_w / shot.width)), Image.LANCZOS)
    tablet = rounded(tablet, radius=int(tablet_w * 0.025))
    top = text_bottom + int(h * 0.05)
    paste_with_shadow(canvas, tablet, ((w - tablet_w) // 2, top), blur=int(w * 0.012))
    return canvas.convert("RGB")


def paste_with_shadow(canvas: Image.Image, image: Image.Image, origin: tuple[int, int], blur: int) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = image.split()[-1].point(lambda a: int(a * 0.35))
    shadow.paste((0, 0, 0, 255), (origin[0], origin[1] + blur // 2), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(image, origin)


def load_shots(folder: Path) -> dict[str, Path]:
    manifest = json.loads((folder / "manifest.json").read_text())
    shots: dict[str, Path] = {}
    for test in manifest:
        for attachment in test.get("attachments", []):
            name = attachment.get("suggestedHumanReadableName", "").split("_0_")[0]
            file = folder / attachment.get("exportedFileName", "")
            if name in SHOTS and file.suffix == ".png":
                shots[name] = file
    return shots


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device", choices=sorted(TARGETS), required=True)
    parser.add_argument("--lang", choices=sorted(CAPTIONS), default="en")
    args = parser.parse_args()
    global USE_CJK
    USE_CJK = args.lang == "ja"
    captions = dict(zip(SHOTS, CAPTIONS[args.lang]))

    shots = load_shots(args.input)
    missing = [name for name in SHOTS if name not in shots]
    if missing:
        print("warning: missing screenshots:", ", ".join(missing))

    for folder_name, size in TARGETS[args.device]:
        out_dir = args.output / folder_name
        out_dir.mkdir(parents=True, exist_ok=True)
        for index, name in enumerate(n for n in SHOTS if n in shots):
            shot = Image.open(shots[name]).convert("RGB")
            # Simulator screenshots stay in portrait pixels when the device is rotated;
            # turn landscape-device shots back upright (content is rotated clockwise).
            if size[0] > size[1] and shot.height > shot.width:
                shot = shot.rotate(90, expand=True)
            title, subtitle = captions[name]
            compose = compose_landscape if size[0] > size[1] else compose_portrait
            image = compose(shot, size, title, subtitle)
            assert image.size == size, (image.size, size)
            path = out_dir / f"{index + 1:02d}-{name.removeprefix('appstore-')[3:]}.png"
            image.save(path, optimize=True)
            print("wrote", path, image.size)
            # The raw screenshot is useful too (e.g. for App Previews or the website).
            raw_dir = args.output / f"{folder_name}-raw"
            raw_dir.mkdir(exist_ok=True)
            shot.save(raw_dir / path.name)


if __name__ == "__main__":
    main()
