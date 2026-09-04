r"""Build a faction ensign texture for each banner.

    python tools\make_flags.py

The flag on a Command Post used to be a single flat colour on a waving quad —
the same three numbers already carried by the minimap blip, the health bar and
the selection ring, so the flag added no information and read as a scrap of
coloured cloth. Meanwhile the game already owned four properly designed faction
roundels (textures\insignia_f*.png), used on aircraft and armour and nowhere
else. This composites them into real ensigns: a field in the banner colour, a
darker hoist band against the pole, and the roundel on the fly.

Output: godot\textures\flag_f<N>.png at 512x226 (the flag quad is 1.25 x 0.55).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 512, 226
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot")
TEX = os.path.join(ROOT, "textures")

# field, hoist band, and a thin dividing stripe — pulled toward each banner's
# ARMOUR colours rather than the bright UI colour, so a flag at the top of a
# pole reads as the same army as the vehicles beneath it
BANNERS = {
    1: dict(field=(150, 44, 34), hoist=(74, 26, 22), stripe=(196, 168, 118)),
    2: dict(field=(112, 118, 62), hoist=(58, 60, 34), stripe=(176, 122, 60)),
    3: dict(field=(46, 62, 96), hoist=(24, 32, 52), stripe=(204, 168, 86)),
    4: dict(field=(96, 54, 126), hoist=(48, 26, 66), stripe=(214, 208, 232)),
}


def build(fac, spec):
    img = Image.new("RGBA", (W, H), spec["field"] + (255,))
    d = ImageDraw.Draw(img)

    # hoist band: the third nearest the pole, where a real ensign carries its
    # canton. Also gives the eye something to read when the fly is waving.
    band = int(W * 0.30)
    d.rectangle([0, 0, band, H], fill=spec["hoist"] + (255,))
    d.rectangle([band, 0, band + 7, H], fill=spec["stripe"] + (255,))

    # subtle woven variation so the cloth is not a flat plate of colour
    noise = Image.effect_noise((W, H), 14).convert("L").filter(
        ImageFilter.GaussianBlur(0.6))
    img = Image.composite(
        Image.blend(img, Image.new("RGBA", (W, H), (255, 255, 255, 255)), 0.06),
        img, noise.point(lambda v: 255 if v > 150 else 0))

    # the roundel, on the fly half
    ins_path = os.path.join(TEX, "insignia_f%d.png" % fac)
    if os.path.exists(ins_path):
        ins = Image.open(ins_path).convert("RGBA")
        s = int(H * 0.78)
        ins = ins.resize((s, s), Image.LANCZOS)
        cx = band + (W - band) // 2 - s // 2
        img.alpha_composite(ins, (cx, (H - s) // 2))

    # frayed fly edge: a flag that ends in a perfect rectangle reads as plastic
    d2 = ImageDraw.Draw(img)
    for y in range(0, H, 9):
        bite = 4 + (y * 7 % 11)
        d2.rectangle([W - bite, y, W, y + 4], fill=(0, 0, 0, 0))

    out = os.path.join(TEX, "flag_f%d.png" % fac)
    img.save(out)
    return out


if __name__ == "__main__":
    if not os.path.isdir(TEX):
        print("no textures dir at %s" % TEX)
        sys.exit(1)
    for fac, spec in BANNERS.items():
        print("wrote %s" % build(fac, spec))
