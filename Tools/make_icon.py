"""生成 iAgent 的 App 图标：深色渐变底 + 蓝色小鲸鱼 + 聊天气泡。

用法：python3 Tools/make_icon.py
输出：EAgent/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os

SIZE = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def background():
    top = (13, 22, 48)
    bottom = (24, 52, 104)
    img = Image.new("RGB", (SIZE, SIZE), top)
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        draw.line([(0, y), (SIZE, y)], fill=lerp(top, bottom, y / SIZE))
    # 右上角一点光晕
    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse([520, -220, 1260, 520], fill=(28, 92, 190))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    img = Image.blend(img, Image.blend(img, glow, 0.0), 0.0)
    return img


def whale(draw):
    """一条圆润的蓝色小鲸鱼（DeepSeek 的胖鱼）。"""
    body = [(210, 330), (760, 300), (830, 470), (770, 650), (520, 730), (270, 660), (190, 480)]
    draw.polygon(body, fill=(58, 176, 255))
    # 腹部
    draw.ellipse([250, 470, 760, 730], fill=(120, 210, 255))
    # 尾巴
    draw.polygon([(760, 380), (930, 250), (880, 450)], fill=(58, 176, 255))
    draw.polygon([(760, 560), (940, 650), (800, 640)], fill=(58, 176, 255))
    # 眼睛
    draw.ellipse([330, 430, 395, 495], fill=(12, 26, 52))
    draw.ellipse([348, 444, 372, 468], fill=(255, 255, 255))
    # 腹鳍
    draw.ellipse([470, 600, 620, 700], fill=(40, 140, 220))


def bubble(draw):
    """右上角的聊天气泡。"""
    draw.rounded_rectangle([640, 120, 900, 320], radius=52, fill=(255, 255, 255))
    draw.polygon([(700, 300), (690, 380), (790, 315)], fill=(255, 255, 255))
    for x in (710, 770, 830):
        draw.ellipse([x, 200, x + 30, 230], fill=(58, 150, 230))


def main():
    img = background()
    draw = ImageDraw.Draw(img)
    bubble(draw)
    whale(draw)

    out_dir = os.path.join(os.path.dirname(__file__), "..", "EAgent", "Assets.xcassets", "AppIcon.appiconset")
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "AppIcon-1024.png")
    img.save(out, "PNG")
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
