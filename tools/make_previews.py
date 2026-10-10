"""Render every sliced piece as its own PNG, named by its engine id, plus labelled index sheets.

    python3 tools/make_previews.py        # needs Pillow

Writes into docs/previews/. Reference only -- nothing in the game reads it. See the README there.

The id is what you type and what the manifest keys on, so it is the name on every image.
"""
import os
import re
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = "/home/user/Project-Juice/"
SINGLES = ROOT + "docs/previews/"
SHEETS = ROOT + "docs/previews/"
Image.MAX_IMAGE_PIXELS = None

SOURCES = {
    "blob_sheet_1": ("terrain", "terrain/Blob Sheet 1.png"),
    "blob_sheet_2": ("terrain", "terrain/Blob Sheet 2.png"),
    "blob_sheet_3": ("terrain", "terrain/Blob Sheet 3.png"),
    "prop_sheet_1": ("props", "props/Prop Sheet 1.png"),
    "prop_sheet_2": ("props", "props/Prop Sheet 2.png"),
}

SINGLE_MAX = 256
CELL = 230
LABEL = 34
COLS = 6
BG = (168, 170, 174)


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def pieces_of(stem):
    text = open(ROOT + f"art/manifest/{stem}.tres").read()
    out = []
    for block in text.split("[sub_resource")[1:]:
        m_id = re.search(r'^id = "([^"]+)"', block, re.M)
        m_rg = re.search(r"^region = Rect2i\(([-\d]+), ([-\d]+), ([-\d]+), ([-\d]+)\)", block, re.M)
        m_kd = re.search(r"^kind = (\d+)", block, re.M)
        if m_id and m_rg:
            out.append({
                "id": m_id.group(1),
                "region": tuple(int(g) for g in m_rg.groups()),
                "kind": int(m_kd.group(1)) if m_kd else 0,
            })
    return out


KINDS = {0: "polygon", 1: "circle", 2: "rect", 3: "annulus", 4: "none"}

os.makedirs(SINGLES, exist_ok=True)
small = font(15)
tiny = font(13)
total = 0

for stem, (family, rel) in SOURCES.items():
    sheet = Image.open(ROOT + "art/source/" + rel).convert("RGBA")
    entries = pieces_of(stem)
    cells = []

    for e in entries:
        x, y, w, h = e["region"]
        crop = sheet.crop((x, y, x + w, y + h))

        # --- the individual file, on a mid grey so black art reads -------------
        scale = min(SINGLE_MAX / max(1, w), SINGLE_MAX / max(1, h), 1.0)
        thumb = crop.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
        plate = Image.new("RGBA", (SINGLE_MAX, SINGLE_MAX), BG + (255,))
        plate.alpha_composite(thumb, ((SINGLE_MAX - thumb.width) // 2, (SINGLE_MAX - thumb.height) // 2))
        plate.convert("RGB").save(f"{SINGLES}{e['id']}.png", optimize=True)
        total += 1

        # --- the cell for the index sheet -------------------------------------
        s2 = min((CELL - 16) / max(1, w), (CELL - 16) / max(1, h))
        cells.append((e, crop.resize((max(1, int(w * s2)), max(1, int(h * s2))), Image.LANCZOS)))

    rows = (len(cells) + COLS - 1) // COLS
    canvas = Image.new("RGB", (COLS * CELL, rows * (CELL + LABEL)), (250, 250, 250))
    d = ImageDraw.Draw(canvas)
    for i, (e, img) in enumerate(cells):
        cx, cy = (i % COLS) * CELL, (i // COLS) * (CELL + LABEL)
        d.rectangle([cx + 2, cy + 2, cx + CELL - 3, cy + CELL - 3], fill=BG)
        canvas.paste(img.convert("RGB"), (cx + (CELL - img.width) // 2, cy + (CELL - img.height) // 2), img)
        d.text((cx + 6, cy + CELL + 2), e["id"], fill=(10, 10, 10), font=small)
        w, h = e["region"][2], e["region"][3]
        d.text((cx + 6, cy + CELL + 18), f"{KINDS.get(e['kind'], '?')}   {w}x{h}", fill=(90, 90, 95), font=tiny)
    canvas.save(f"{SHEETS}index_{stem}.jpg", quality=90)
    print(f"index_{stem}.jpg  {len(cells)} pieces  {canvas.size}")

print(f"{total} individual previews in docs/previews/")
