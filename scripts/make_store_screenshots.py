"""Compose Clear Air store art, site images, from app captures.

Every capture is a 1080x2400 PNG: real `adb exec-out screencap` frames for the
states the emulator can reach, and `tool/screenshots/store_shots_test.dart`
renders for Connected and Connecting (this build network blocks relay dials).

Usage:
    python3 scripts/make_store_screenshots.py \
        --home docs/design/evidence/phase1/renders/connected-360x800.png \
        --connecting docs/design/evidence/phase1/renders/connecting-360x800.png \
        --standby /tmp/shot_standby.png \
        --servers /tmp/shot_servers.png \
        --speed /tmp/shot_speed.png \
        --results /tmp/shot_results.png \
        --settings /tmp/shot_settings.png
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SANS = str(ROOT / 'assets/fonts/SchibstedGrotesk-VF.ttf')
MONO = str(ROOT / 'assets/fonts/GeistMono-VF.ttf')

# Clear Air, day: air.skyTop -> air.groundBottom, ink text, accent press.
SKY_TOP = (242, 247, 243)
GROUND_BOTTOM = (227, 236, 231)
INK = (14, 27, 29)
ACCENT_INK = (11, 101, 109)
FRAME = (20, 49, 47)
HAIRLINE = (14, 27, 29, 26)
SHADOW = (14, 27, 29, 52)

SOURCE_ASPECT = 1080 / 2400


def sans(size, weight='Medium'):
    font = ImageFont.truetype(SANS, size)
    font.set_variation_by_name(weight)
    return font


def mono(size, weight='Medium'):
    font = ImageFont.truetype(MONO, size)
    font.set_variation_by_name(weight)
    return font


def background(width, height):
    canvas = Image.new('RGB', (width, height), SKY_TOP)
    draw = ImageDraw.Draw(canvas)
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(
            round(SKY_TOP[i] + (GROUND_BOTTOM[i] - SKY_TOP[i]) * t)
            for i in range(3)
        )
        draw.line([(0, y), (width, y)], fill=color)
    # The connect surface's horizon, echoed behind the phone.
    horizon = round(height * 0.38)
    draw.line([(0, horizon), (width, horizon)], fill=HAIRLINE, width=1)
    return canvas


def draw_tracked(draw, xy, text, font, fill, tracking):
    x, y = xy
    for char in text:
        draw.text((x, y), char, font=font, fill=fill)
        x += draw.textlength(char, font=font) + tracking


def wrap(text, font, draw, max_width):
    lines, current = [], ''
    for word in text.split():
        candidate = word if not current else f'{current} {word}'
        if draw.textlength(candidate, font=font) <= max_width:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def compose(src, title, out, width, height):
    s = width / 1080.0
    canvas = background(width, height)
    draw = ImageDraw.Draw(canvas)

    margin_x = round(78 * s)
    kicker = mono(round(25 * s), 'SemiBold')
    draw_tracked(draw, (margin_x, round(80 * s)), 'BULBVPN', kicker,
                 ACCENT_INK, round(5 * s))

    title_font = sans(round(47 * s), 'Medium')
    title_lines = wrap(title, title_font, draw, width - margin_x * 2)
    line_height = round(54 * s)
    title_y = round(122 * s)
    for i, line in enumerate(title_lines):
        draw.text((margin_x, title_y + i * line_height), line,
                  font=title_font, fill=INK)

    header_bottom = title_y + len(title_lines) * line_height
    frame_top = header_bottom + round(50 * s)
    bottom_margin = round(58 * s)
    available = height - frame_top - bottom_margin
    frame_w = min(width - margin_x * 2, int(available * SOURCE_ASPECT))
    frame_h = round(frame_w / SOURCE_ASPECT)
    frame_x = (width - frame_w) // 2
    radius = round(frame_w * 0.06)
    border = max(2, round(3 * s))

    shadow = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [frame_x + 4 * s, frame_top + 18 * s,
         frame_x + frame_w + 4 * s, frame_top + frame_h + 18 * s],
        radius + 8,
        fill=SHADOW,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(round(30 * s)))
    canvas = Image.alpha_composite(canvas.convert('RGBA'), shadow).convert('RGB')
    draw = ImageDraw.Draw(canvas)

    inner_w, inner_h = frame_w - 2 * border, frame_h - 2 * border
    shot = Image.open(src).convert('RGB').resize(
        (inner_w, inner_h), Image.LANCZOS
    )
    mask = Image.new('L', (inner_w, inner_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, inner_w - 1, inner_h - 1], max(0, radius - border), fill=255
    )
    draw.rounded_rectangle(
        [frame_x, frame_top, frame_x + frame_w - 1, frame_top + frame_h - 1],
        radius,
        fill=FRAME,
    )
    canvas.paste(shot, (frame_x + border, frame_top + border), mask)

    out.parent.mkdir(parents=True, exist_ok=True)
    if out.suffix == '.png':
        canvas.save(out, optimize=True)
    else:
        canvas.save(out, quality=92, optimize=True)
    print('wrote', out)


def plain(src, out, size, crop=None):
    image = Image.open(src).convert('RGB').resize(size, Image.LANCZOS)
    if crop:
        image = image.crop(crop)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.suffix == '.webp':
        image.save(out, quality=90, method=6)
    else:
        image.save(out, quality=88, optimize=True)
    print('wrote', out)


def main():
    parser = argparse.ArgumentParser()
    for name in ('home', 'connecting', 'standby', 'servers', 'speed',
                 'results', 'settings'):
        parser.add_argument(f'--{name}', required=True)
    args = parser.parse_args()

    shots = [
        (args.home, 'See where your traffic exits', '01-home'),
        (args.connecting, 'One tap starts the tunnel', '02-connecting'),
        (args.servers, 'Pick a relay, or let Auto choose', '03-servers'),
        (args.speed, "Measure the path you're on", '04-speedtest'),
        (args.results, 'Download, upload, and ping, measured', '05-speed-results'),
    ]
    for src, title, name in shots:
        compose(src, title, ROOT / f'store/screenshots/play-phone/{name}.jpg',
                1080, 1920)
        compose(src, title, ROOT / f'store/screenshots/iphone69/{name}.png',
                1290, 2796)

    site = ROOT / 'site/assets/screenshots'
    plain(args.standby, site / 'standby-v2.webp', (720, 1600))
    plain(args.home, site / 'connected-v2.webp', (720, 1600))
    plain(args.servers, site / 'servers-v2.webp', (720, 1600))
    plain(args.speed, site / 'speed-idle-v2.webp', (720, 1600))
    plain(args.results, site / 'speed-results-v2.webp', (720, 1166),
          crop=(0, 0, 720, 1166))
    plain(args.settings, site / 'settings-v2.webp', (720, 1600))


if __name__ == '__main__':
    main()
