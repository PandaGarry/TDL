#!/usr/bin/env python3
"""Render pixel-accurate 1920x1080 stage previews of GreyboxStage + SevaraVisualTheme.

Composes the baked 2.5D PBR+Painterly chunk layers in `assets/textures/sevara_p1/`
(`chunk_nivara_clean.png` and `chunk_nivara_silted_dusk.png`) with the authoritative
P1 entity tags, slate HUD bar, P1 ecological & body diagnostic panel, and the
diegetic leather Field Journal overlay using Cyrillic TrueType fonts.
"""

import os
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
TEX_DIR = "assets/textures/sevara_p1"
OUT_DIR = "docs/art/concepts"

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_SERIF_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def get_font(path, size):
    return ImageFont.truetype(path, size)


def draw_tag_pill(draw, cx, cy, title, subtitle, border_rgb, is_local=False):
    f_title = get_font(FONT_BOLD, 14)
    f_sub = get_font(FONT_REG, 12)
    full_text = f"{'★ ' if is_local else ''}{title}"
    b1 = draw.textbbox((0, 0), full_text, font=f_title)
    b2 = draw.textbbox((0, 0), subtitle, font=f_sub)
    w = max(b1[2] - b1[0], b2[2] - b2[0]) + 22
    h = 38
    x0, y0 = cx - w // 2, cy - h
    draw.rounded_rectangle(
        [x0, y0, x0 + w, y0 + h],
        radius=6,
        fill=(14, 18, 20, 212),
        outline=(*border_rgb, 230),
        width=2 if is_local else 1,
    )
    draw.text((cx - (b1[2] - b1[0]) // 2, y0 + 4), full_text, font=f_title, fill=(246, 240, 224, 255))
    draw.text((cx - (b2[2] - b2[0]) // 2, y0 + 21), subtitle, font=f_sub, fill=(196, 212, 198, 240))


def render_frame(output_path, mode="morning_clean"):
    is_dusk = mode == "dusk_silt_journal"
    src_name = "chunk_nivara_clean.png" if not is_dusk else "chunk_nivara_silted_dusk.png"
    bg = Image.open(os.path.join(TEX_DIR, src_name)).convert("RGBA").resize((W, H), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(bg, "RGBA")

    f_hud_title = get_font(FONT_SERIF_BOLD, 17)
    f_hud = get_font(FONT_REG, 14)
    f_hud_bold = get_font(FONT_BOLD, 14)

    # 1. World-space subtle diegetic labels on key P1 nodes & Anchor NPCs
    labels = [
        (335, 395, "Дом Селимы", "Стена материальной хроники", (218, 162, 102), False),
        (435, 705, "Мавена (Травница)", "Стол карантина Кевалу [E]", (158, 196, 104), False),
        (640, 560, "Сарела", "Вождь Нивары · Доверие 64", (214, 184, 96), False),
        (745, 450, "Путник (Вы) · Тован", "Шлюз канала Ниварела [F]", (248, 224, 128), True),
        (1325, 205, "Тобрен (Дозор)", "Тропа к якорю Кевара", (176, 194, 208), False),
        (1585, 165, "Якорь разлома Кевар", "Плёнка воды и споры Кевалу" if not is_dusk else "ДИКИЙ ВЫБРОС КЕВАЛУ!", (212, 126, 108) if is_dusk else (148, 186, 194), False),
        (1560, 675, "Луг Хераво", "Селаве и стадо Кораме", (154, 188, 112), False),
    ]
    for lx, ly, ltitle, lsub, lcol, loc in labels:
        draw_tag_pill(draw, lx, ly, ltitle, lsub, lcol, is_local=loc)

    # 2. Top Slate HUD Bar (GreyboxStage)
    draw.rounded_rectangle(
        [16, 12, W - 16, 56],
        radius=8,
        fill=(14, 18, 20, 226),
        outline=(122, 146, 116, 220),
        width=2,
    )
    clock_str = (
        "Весна, День 1 (01/30) · 08:00 Утро"
        if not is_dusk
        else "Весна, День 2 (02/30) · 18:30 Сумерки"
    )
    draw.text(
        (32, 22),
        f"СЕВАРА P1 · Долина Нивары   |   {clock_str}   |   Камера: 3/4 Орто (58°) · Зум 1.0x [Z]   |   Текстуры: HIGH (PBR+Painterly) [T]",
        font=f_hud_title,
        fill=(240, 214, 138, 255),
    )

    # 3. Compact P1 Ecological & Body Diagnostics Panel (top-left)
    silt_val = 0.22 if not is_dusk else 0.64
    draw.rounded_rectangle(
        [16, 68, 608, 316],
        radius=8,
        fill=(14, 18, 20, 224),
        outline=(104, 128, 104, 210),
        width=2,
    )
    panel_lines = [
        (True, "ЭКО-ЦЕПОЧКА ДОЛИНЫ СЕВАРЫ (SevaraEcoChain):"),
        (False, f" • Канал Ниварела: ил {silt_val:.2f} | Береговая Талина: {'78.0 (держит берег)' if not is_dusk else '41.0 (эрозия русла!)'}"),
        (False, f" • Заводь Мулане: рыба Навелу {'82.0 (чистый нерест)' if not is_dusk else '26.0 (угроза refugium!)'}"),
        (False, f" • Образец Кевалу: {'в закрытом сосуде у Мавены (карантин)' if not is_dusk else 'ДИКИЙ ВЫБРОС В КАНАЛЕ!'}"),
        (True, "ТЕЛО И ПРАКТИКА ПЕРСОНАЖА (BodyVitals):"),
        (False, f" • Сытость: 84 | Вода: 88 | Бодрость: {'86' if not is_dusk else '61'} | Тепло: {'76' if not is_dusk else '44 (холодно)'}"),
        (False, f" • Сырость плаща: {'28%' if not is_dusk else '68%'} | Болотная лихорадка: {'0.0 (здоров)' if not is_dusk else '24.5 (нужен отвар Селаве!)'}"),
        (False, " • Практика: Экология 18.5 | Выживание 14.0 | Доверие Нивары: 62"),
    ]
    y_cursor = 80
    for is_hdr, text_line in panel_lines:
        if is_hdr and y_cursor > 85:
            y_cursor += 6
        draw.text(
            (30, y_cursor),
            text_line,
            font=f_hud_bold if is_hdr else f_hud,
            fill=(238, 206, 124, 255) if is_hdr else (218, 228, 218, 248),
        )
        y_cursor += 27

    # 4. In Dusk mode, composite the diegetic Leather Field Journal & Hypothesis Ladder card in bottom-right
    if is_dusk:
        j_img_path = os.path.join(OUT_DIR, "step5_diegetic_field_journal_ui.png")
        if os.path.exists(j_img_path):
            j_card = Image.open(j_img_path).convert("RGBA").resize((660, 520), Image.Resampling.LANCZOS)
            jx, jy = W - 684, H - 544
            draw.rounded_rectangle(
                [jx - 6, jy - 36, jx + 666, jy + 526],
                radius=10,
                fill=(18, 14, 12, 232),
                outline=(186, 148, 92, 235),
                width=2,
            )
            draw.text(
                (jx + 12, jy - 28),
                "ПОЛЕВОЙ ЖУРНАЛ И ЛЕСТНИЦА ГИПОТЕЗ [J] · Зацепки: 4/5 · Хроника: 6",
                font=f_hud_bold,
                fill=(242, 218, 152, 255),
            )
            bg.paste(j_card, (jx, jy))

    out_rgb = bg.convert("RGB")
    out_rgb.save(output_path, quality=95, optimize=True)
    print("Saved", output_path, os.path.getsize(output_path))


if __name__ == "__main__":
    render_frame(os.path.join(OUT_DIR, "ingame_stage_p1_morning_clean.png"), mode="morning_clean")
    render_frame(os.path.join(OUT_DIR, "ingame_stage_p1_dusk_silt_and_journal.png"), mode="dusk_silt_journal")
