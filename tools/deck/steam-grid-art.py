import glob, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter
thumbs = sorted(glob.glob("/home/deck/GodotProjects/.duo-arena-stage/arcade/thumbs/*.jpg"))
random.seed(7)
def font(sz):
    for f in ("/usr/share/fonts/TTF/DejaVuSans-Bold.ttf", "/usr/share/fonts/noto/NotoSans-Bold.ttf"):
        try: return ImageFont.truetype(f, sz)
        except OSError: pass
    return ImageFont.load_default()
def collage(w, h, cols):
    img = Image.new("RGB", (w, h), (14, 12, 30))
    tw = w // cols + 2; th = int(tw * 9 / 16)
    pics = thumbs[:] ; random.shuffle(pics)
    k = 0
    for y in range(0, h, th):
        for x in range(0, w, tw):
            t = Image.open(pics[k % len(pics)]).convert("RGB").resize((tw, th)); k += 1
            img.paste(t, (x, y))
    return img
def title(img, lines, sub=None, color=(255, 214, 90)):
    w, h = img.size
    dark = Image.new("RGBA", (w, h), (10, 8, 28, 150)); img = Image.alpha_composite(img.convert("RGBA"), dark)
    d = ImageDraw.Draw(img)
    sz = int(min(w / (max(len(l) for l in lines) * 0.62), h / (len(lines) * 1.6)))
    f = font(sz); y = h // 2 - (len(lines) * sz * 1.15) / 2 - (sz * 0.3 if sub else 0)
    for l in lines:
        tw = d.textlength(l, font=f); d.text(((w - tw) / 2, y), l, font=f, fill=color, stroke_width=max(3, sz // 12), stroke_fill=(20, 10, 40)); y += sz * 1.15
    if sub:
        fs = font(max(18, sz // 3)); tw = d.textlength(sub, font=fs); d.text(((w - tw) / 2, y + sz * 0.15), sub, font=fs, fill=(150, 230, 255), stroke_width=3, stroke_fill=(20, 10, 40))
    return img.convert("RGB")
def term(w, h, lines):
    img = Image.new("RGB", (w, h), (24, 22, 30)); d = ImageDraw.Draw(img)
    sz = int(min(w / 9, h / 5)); f = font(sz); fm = font(max(16, sz // 3))
    d.text((w * 0.08, h * 0.12), ">_", font=fm, fill=(120, 230, 160))
    y = h / 2 - sz * len(lines) * 0.6
    for l in lines:
        tw = d.textlength(l, font=f); d.text(((w - tw) / 2, y), l, font=f, fill=(217, 119, 87)); y += sz * 1.15
    return img
sets = {
  "4241830559": (["LIVING", "ROOM", "ARCADE"], "play with the family"),
  "3597271914": (["ARCADE"], "on this Deck"),
}
for appid, (lines, sub) in sets.items():
    title(collage(600, 900, 2), lines, sub).save(f"{appid}p.png")
    title(collage(920, 430, 4), [" ".join(lines)] if len(lines) > 1 else lines, sub).save(f"{appid}.png")
    title(collage(1920, 620, 6), [" ".join(lines)] if len(lines) > 1 else lines, sub).save(f"{appid}_hero.png")
term(600, 900, ["Claude", "Code"]).save("3658794815p.png")
term(920, 430, ["Claude Code"]).save("3658794815.png")
term(1920, 620, ["Claude Code"]).save("3658794815_hero.png")
print("ok")
