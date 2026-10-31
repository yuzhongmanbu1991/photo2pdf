#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 App 图标（1024x1024，无文字、无透明通道）。

设计：蓝绿对角渐变底 + 白色文档页（右上折角）+ 页内照片图形（山 + 太阳）。
iOS 会自动给图标加圆角，所以这里画的是满幅方形、四角不透明的图。

用法（Windows）：
    "C:\\Program Files\\Python312\\python.exe" scripts\\generate_app_icon.py

依赖：Pillow
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFilter

# 输出尺寸（App Store / iOS 只需 1024 单尺寸）
SIZE = 1024
# 超采样倍数：先画大图再缩小，边缘更平滑
SS = 2

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(BASE_DIR, "Resources", "Assets.xcassets", "AppIcon.appiconset")
PREVIEW_PATH = os.path.join(BASE_DIR, "docs", "icon-preview.png")


def gradient(size: int) -> Image.Image:
    """四角渐变的蓝色 -> 蓝绿 -> 青色底图（先画 2x2 再放大，天然平滑）"""
    corners = Image.new("RGB", (2, 2))
    corners.putpixel((0, 0), (56, 189, 248))    # #38BDF8 亮蓝
    corners.putpixel((1, 0), (14, 165, 233))    # #0EA5E9 天蓝
    corners.putpixel((0, 1), (20, 184, 166))    # #14B8A6 teal
    corners.putpixel((1, 1), (13, 148, 136))    # #0D9488 深 teal
    return corners.resize((size, size), Image.BICUBIC).convert("RGBA")


def add_glow(base: Image.Image) -> Image.Image:
    """左上角加一团柔和高光，避免整块渐变太死板"""
    size = base.size[0]
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    radius = int(size * 0.55)
    draw.ellipse(
        [-int(size * 0.25), -int(size * 0.35), -int(size * 0.25) + radius * 2, -int(size * 0.35) + radius * 2],
        fill=(255, 255, 255, 46),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.09))
    return Image.alpha_composite(base, glow)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    """圆角矩形遮罩"""
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def draw_document(canvas: Image.Image, s: int) -> None:
    """在画布上画「一叠纸 + 照片图形」"""
    draw = ImageDraw.Draw(canvas, "RGBA")

    # ---- 后面那张纸（稍微偏右上，做出层叠感）----
    back_w, back_h = int(0.50 * s), int(0.62 * s)
    back_x = int(0.30 * s)
    back_y = int(0.155 * s)
    back_rect = Image.new("RGBA", (back_w, back_h), (0, 0, 0, 0))
    ImageDraw.Draw(back_rect).rounded_rectangle(
        [0, 0, back_w - 1, back_h - 1], radius=int(0.06 * s), fill=(255, 255, 255, 120)
    )
    canvas.alpha_composite(back_rect, (back_x, back_y))

    # ---- 前面那张纸的阴影 ----
    front_w, front_h = int(0.52 * s), int(0.64 * s)
    front_x = int(0.19 * s)
    front_y = int(0.20 * s)

    shadow = Image.new("RGBA", (front_w + int(0.16 * s), front_h + int(0.16 * s)), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        [int(0.08 * s), int(0.10 * s), int(0.08 * s) + front_w, int(0.10 * s) + front_h],
        radius=int(0.06 * s),
        fill=(6, 40, 60, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(0.022 * s)))
    canvas.alpha_composite(shadow, (front_x - int(0.08 * s), front_y - int(0.05 * s)))

    # ---- 前面的纸 ----
    page = Image.new("RGBA", (front_w, front_h), (0, 0, 0, 0))
    page_draw = ImageDraw.Draw(page)
    page_draw.rounded_rectangle(
        [0, 0, front_w - 1, front_h - 1], radius=int(0.065 * s), fill=(255, 255, 255, 255)
    )
    # 右上折角（浅灰三角）
    fold = int(0.15 * front_w)
    page_draw.polygon(
        [(front_w - fold, 0), (front_w, 0), (front_w, fold)],
        fill=(214, 226, 236, 255),
    )
    page_draw.line([(front_w - fold, 0), (front_w - fold, fold), (front_w, fold)],
                   fill=(186, 205, 219, 255), width=max(2, int(0.003 * s)))
    canvas.alpha_composite(page, (front_x, front_y))

    # ---- 页内的照片图形（圆角 + 渐变 + 山 + 太阳）----
    photo_w, photo_h = int(front_w * 0.74), int(front_h * 0.46)
    photo_x = front_x + (front_w - photo_w) // 2
    photo_y = front_y + int(front_h * 0.13)

    photo = Image.new("RGBA", (photo_w, photo_h), (0, 0, 0, 0))
    photo_gradient = Image.new("RGBA", (2, 2))
    photo_gradient.putpixel((0, 0), (125, 211, 252, 255))   # 天蓝
    photo_gradient.putpixel((1, 0), (59, 130, 246, 255))
    photo_gradient.putpixel((0, 1), (45, 212, 191, 255))    # teal
    photo_gradient.putpixel((1, 1), (16, 185, 129, 255))
    photo_gradient = photo_gradient.resize((photo_w, photo_h), Image.BICUBIC)
    photo.alpha_composite(photo_gradient)

    photo_draw = ImageDraw.Draw(photo, "RGBA")
    # 太阳
    sun_r = int(photo_h * 0.15)
    photo_draw.ellipse(
        [int(photo_w * 0.66) - sun_r, int(photo_h * 0.20) - sun_r,
         int(photo_w * 0.66) + sun_r, int(photo_h * 0.20) + sun_r],
        fill=(255, 255, 255, 235),
    )
    # 远山
    photo_draw.polygon(
        [(0, photo_h), (int(photo_w * 0.30), int(photo_h * 0.42)),
         (int(photo_w * 0.58), photo_h)],
        fill=(13, 148, 136, 210),
    )
    # 近山
    photo_draw.polygon(
        [(int(photo_w * 0.34), photo_h), (int(photo_w * 0.63), int(photo_h * 0.55)),
         (photo_w, int(photo_h * 0.74)), (photo_w, photo_h)],
        fill=(15, 118, 110, 235),
    )
    # 圆角裁切
    photo.putalpha(rounded_mask((photo_w, photo_h), int(photo_h * 0.09)))
    canvas.alpha_composite(photo, (photo_x, photo_y))

    # ---- 页内文字占位线（不含真实文字，纯装饰）----
    line_color = (203, 213, 225, 255)
    line_h = max(3, int(0.012 * s))
    line_x = photo_x
    line_w = int(photo_w * 0.86)
    line_y = photo_y + photo_h + int(front_h * 0.09)
    for i, ratio in enumerate((1.0, 0.78, 0.55)):
        y = line_y + i * int(front_h * 0.075)
        draw.rounded_rectangle(
            [line_x, y, line_x + int(line_w * ratio), y + line_h],
            radius=line_h // 2,
            fill=line_color,
        )


def main() -> int:
    s = SIZE * SS

    canvas = gradient(s)
    canvas = add_glow(canvas)
    draw_document(canvas, s)

    icon = canvas.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")

    os.makedirs(ICON_DIR, exist_ok=True)
    icon_path = os.path.join(ICON_DIR, "AppIcon-1024.png")
    icon.save(icon_path, format="PNG", optimize=True)

    os.makedirs(os.path.dirname(PREVIEW_PATH), exist_ok=True)
    icon.resize((256, 256), Image.LANCZOS).save(PREVIEW_PATH, format="PNG", optimize=True)

    print(f"icon  -> {icon_path} ({SIZE}x{SIZE}, RGB, 无 alpha)")
    print(f"preview -> {PREVIEW_PATH} (256x256)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
