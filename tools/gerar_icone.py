"""Gera o ícone do app NaÁrea (pôr-do-sol potiguar + pino de mapa).

Saída (em app/assets/icon/):
  - icon.png             1024x1024, fundo completo (iOS, web, Android legado)
  - icon_foreground.png  1024x1024, só o pino em fundo transparente, dentro da
                         zona segura do ícone adaptativo do Android (66%)
  - icon_background.png  1024x1024, só o fundo (céu + sol + mar)

Uso (da raiz do repositório):
  python tools/gerar_icone.py
  cd app && dart run flutter_launcher_icons

Requer Pillow (testado com Python 3.13 + Pillow 11.3).
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersampling para bordas suaves
W = SIZE * SS

# Paleta (mesma de app/lib/ui/core/theme.dart)
SOL = (255, 200, 87)
LARANJA = (255, 159, 28)
CORAL = (255, 107, 74)
CORAL_ESCURO = (217, 72, 43)
AZUL_MAR = (14, 124, 155)
AZUL_CLARO = (78, 176, 199)
AREIA = (255, 244, 230)
BRANCO = (255, 255, 255)

OUT_DIR = Path(__file__).resolve().parent.parent / "app" / "assets" / "icon"


def lerp(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def vertical_gradient(size: int, stops: list[tuple[float, tuple[int, int, int]]]) -> Image.Image:
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                img.putpixel((0, y), lerp(c0, c1, (t - t0) / (t1 - t0)))
                break
    return img.resize((size, size))


def background() -> Image.Image:
    """Céu de pôr-do-sol, sol no horizonte e o mar com ondas."""
    horizon = int(W * 0.66)
    img = vertical_gradient(W, [(0.0, SOL), (0.35, LARANJA), (0.66, CORAL), (1.0, CORAL)])
    draw = ImageDraw.Draw(img)

    # Sol metade acima do horizonte
    r = int(W * 0.2)
    cx = W // 2
    draw.ellipse((cx - r, horizon - r, cx + r, horizon + r), fill=lerp(SOL, BRANCO, 0.35))

    # Mar
    draw.rectangle((0, horizon, W, W), fill=AZUL_MAR)

    # Ondas: faixas senoidais mais claras
    def wave(y0: int, amp: int, length: int, thickness: int, color: tuple[int, int, int]) -> None:
        pts_top = []
        for x in range(0, W + 1, SS * 4):
            pts_top.append((x, y0 + amp * math.sin(2 * math.pi * x / length)))
        pts = pts_top + [(x, y + thickness) for x, y in reversed(pts_top)]
        draw.polygon(pts, fill=color)

    wave(horizon + int(W * 0.035), int(W * 0.012), int(W * 0.25), int(W * 0.02), AZUL_CLARO)
    wave(horizon + int(W * 0.12), int(W * 0.014), int(W * 0.3), int(W * 0.022), AZUL_CLARO)
    wave(horizon + int(W * 0.22), int(W * 0.016), int(W * 0.35), int(W * 0.024), lerp(AZUL_CLARO, AREIA, 0.3))
    return img


def pin_layer(scale: float = 1.0) -> Image.Image:
    """Pino de mapa branco com um "sol" coral no centro, com sombra suave."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cx = W // 2
    head_r = int(W * 0.2 * scale)
    head_cy = int(W * 0.42 - (1 - scale) * W * 0.02)
    tip_y = head_cy + int(head_r * 2.15)

    def pin_shape(draw: ImageDraw.ImageDraw, dx: int, dy: int, fill: tuple[int, ...]) -> None:
        draw.ellipse((cx - head_r + dx, head_cy - head_r + dy, cx + head_r + dx, head_cy + head_r + dy), fill=fill)
        # Triângulo tangente ao círculo até a ponta
        ang = math.asin(head_r / (tip_y - head_cy))
        tx = head_r * math.cos(ang)
        ty = head_r * math.sin(ang)
        draw.polygon(
            [
                (cx - tx + dx, head_cy + ty + dy),
                (cx + tx + dx, head_cy + ty + dy),
                (cx + dx, tip_y + dy),
            ],
            fill=fill,
        )

    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    pin_shape(ImageDraw.Draw(shadow), 0, int(W * 0.015), (60, 20, 10, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.012))
    layer.alpha_composite(shadow)

    draw = ImageDraw.Draw(layer)
    pin_shape(draw, 0, 0, BRANCO + (255,))
    inner = int(head_r * 0.5)
    draw.ellipse((cx - inner, head_cy - inner, cx + inner, head_cy + inner), fill=CORAL_ESCURO + (255,))
    return layer


def save(img: Image.Image, name: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    out.save(OUT_DIR / name, optimize=True)
    print(f"gerado: {OUT_DIR / name}")


def main() -> None:
    bg = background()
    full = bg.convert("RGBA")
    full.alpha_composite(pin_layer(1.0))
    save(full.convert("RGB"), "icon.png")
    save(bg, "icon_background.png")
    # Adaptativo: o launcher recorta ~1/3 das bordas; pino menor e centrado.
    save(pin_layer(0.72), "icon_foreground.png")


if __name__ == "__main__":
    main()
