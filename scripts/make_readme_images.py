#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Dungeon Route Guide (docs/images/ui_*.png, settings_*.png).

The next-objective bar, the route window (map, markers, route list, loot), the detail
card, the World Map entrance pin and the settings window are rebuilt from the sizes,
coordinates, colours and strings in the addon code (UI/DungeonMapWindow.lua, UI/HUD.lua,
UI/WorldMapPins.lua, UI/OptionsWindow.lua, Modules/ProgressTracker.lua, Core/Locales.lua)
and the bundled data (Data/DungeonData.lua, Data/MinimapData.lua), in game pixels x scale.
The Wailing Caverns map is put together from the minimap tiles in MinimapTiles_v12.
A drawing stands in for the 3D model and item icons.

usage: python scripts/make_readme_images.py .
Needs Pillow (to read the .tga tiles). Renders with a local headless Chrome
(set CHROME=<path> if it is not found).
"""
import base64
import html
import io
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

PAGE_W = 1600
CALL = "#ea837e"
S = 1.25  # game px -> page px

# ---------------------------------------------------------------------------
# A small reader for Lua table literals
# ---------------------------------------------------------------------------
TOK = re.compile(r'\s*(?:(--\[\[.*?\]\])|(--[^\n]*)|("(?:[^"\\]|\\.)*")|(\'(?:[^\'\\]|\\.)*\')|(\d+\.?\d*(?:[eE][-+]?\d+)?)|([A-Za-z_][\w.]*)|(\[\[.*?\]\])|(.))', re.S)


def _tokens(s):
    for m in TOK.finditer(s):
        c, lc, ds, ss, num, name, ls, ch = m.groups()
        if c or lc:
            continue
        if ds or ss:
            t = (ds or ss)[1:-1]
            yield ("s", re.sub(r"\\(.)", lambda mm: {"n": "\n", "t": "\t"}.get(mm.group(1), mm.group(1)), t))
        elif ls:
            yield ("s", ls[2:-2])
        elif num:
            yield ("n", float(num) if ("." in num or "e" in num.lower()) else int(num))
        elif name:
            yield ("id", name)
        elif ch and not ch.isspace():
            yield ("p", ch)


def _balanced(it):
    depth = 0
    for t in it:
        yield t
        if t == ("p", "{"):
            depth += 1
        elif t == ("p", "}"):
            depth -= 1
            if depth == 0:
                return


def lua_table(src, start):
    """Python value of the Lua table literal that starts at src[start] == '{'."""
    toks = list(_balanced(_tokens(src[start:])))
    pos = [0]

    def peek(k=0):
        return toks[pos[0] + k]

    def nxt():
        pos[0] += 1
        return toks[pos[0] - 1]

    def val():
        t = nxt()
        if t == ("p", "{"):
            return tab()
        if t[0] in ("s", "n"):
            return t[1]
        if t == ("p", "-"):
            return -nxt()[1]
        if t[0] == "id":
            return {"true": True, "false": False, "nil": None}.get(t[1], ("ref", t[1]))
        raise ValueError(t)

    def tab():
        arr, d = [], {}
        while True:
            t = peek()
            if t == ("p", "}"):
                nxt()
                break
            if t == ("p", "["):
                nxt()
                k = val()
                nxt()
                nxt()
                d[k] = val()
            elif t[0] == "id" and peek(1) == ("p", "="):
                nxt()
                nxt()
                d[t[1]] = val()
            else:
                arr.append(val())
            if peek() in (("p", ","), ("p", ";")):
                nxt()
        if d and arr:
            d.update({i: v for i, v in enumerate(arr, 1)})
            return d
        return d if d else arr

    nxt()
    return tab()


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# Values read from the Lua code and the bundled data
# ---------------------------------------------------------------------------
def parse_locales(src):
    block = src[src.index("local StyleService = {"):]
    block = block[:block.index("\n}")]
    ko, en = {}, {}
    for k, a, b in re.findall(r'^\s*(\w+)\s*=\s*\{\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\s*\}', block, re.M):
        ko[k], en[k] = a.replace('\\"', '"'), b.replace('\\"', '"')
    return {"ko": ko, "en": en}


def parse_defaults(src):
    block = src[src.index("local DEFAULTS = {"):]
    block = block[:block.index("\n}")]
    out = {}
    for k, v in re.findall(r"(\w+)\s*=\s*(true|false|[\d.]+)", block):
        out[k] = True if v == "true" else False if v == "false" else float(v)
    return out


def parse_options(src):
    """Settings window rows of UI/OptionsWindow.lua buildConfigWindow."""
    src = src[src.index("function SettingsDialog.buildConfigWindow"):]
    w, h = map(int, re.search(r"windowFrame:SetSize\((\d+), (\d+)\)", src).groups())
    checks = []
    for x, y, lw, label, value in re.findall(
            r"createStyledCheckbox\((\d+), (-?\d+), (\d+), function\(\) return (.*?) end,\s*function\(\) return (.*?) end", src):
        key = re.search(r"L\.(\w+)", label).group(1)
        field = re.search(r"ns\.db\.(\w+)", value)
        checks.append({"x": int(x), "y": -int(y), "w": int(lw), "label": key,
                       "field": field.group(1) if field else None, "notFalse": "~= false" in value})

    def button(var):
        m = re.search(var + r" = createStyledButton\((\d+), (-?\d+), (\d+), (\d+), (true|false)", src)
        return int(m.group(1)), -int(m.group(2)), int(m.group(3)), int(m.group(4)), m.group(5) == "true"

    sections = [-int(v) for v in re.findall(r"createSectionDivider\((-?\d+)\)", src)]
    alpha_y = -int(re.search(r'alphaLbl:SetPoint\("TOPLEFT", 20, (-?\d+)\)', src).group(1))
    size_x = int(re.search(r'sizeLbl:SetPoint\("TOPLEFT", (\d+), (-?\d+)\)', src).group(1))
    return {"size": (w, h), "checks": checks, "sections": sections, "alphaY": alpha_y, "sizeX": size_x,
            "lang": button("local langBtn"), "close": button("local close"),
            "alphaMinus": button("local alphaMinus"), "alphaPlus": button("local alphaPlus"),
            "sizeMinus": button("local sizeMinus"), "sizePlus": button("local sizePlus"),
            "launch": button("local launchMapBtn"), "go": button("local goBtn"),
            "resetProg": button("local resetProgBtn"), "export": button("local exportBtn"),
            "resetPos": button("local bottomResetBtn"), "donate": button("local donateBtn")}


def parse_window(src):
    head = re.search(r"local HEADER, PAD, LISTW = (\d+), (\d+), (\d+)", src).groups()
    leg = re.search(r"local LEGEND_H, FOOT_H = (\d+), (\d+)", src).groups()
    cat_block = src[src.index("local CAT = {"):]
    cat_block = cat_block[:cat_block.index("\n}")]
    cat = {k: [float(v) for v in b.split(",")] for k, b in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", cat_block)}
    return {"HEADER": int(head[0]), "PAD": int(head[1]), "LISTW": int(head[2]),
            "LEGEND_H": int(leg[0]), "FOOT_H": int(leg[1]), "CAT": cat,
            "CARD_W": int(re.search(r"local CARD_W = (\d+)", src).group(1)),
            "MODEL_H": int(re.search(r"local MODEL_H = (\d+)", src).group(1))}


def parse_dungeon(src, key):
    i = src.index(f'key = "{key}"')
    return lua_table(src, src.rindex("{", 0, i))


def parse_minimap(src, key):
    maps = lua_table(src, src.index("local maps=") + len("local maps="))
    return maps[key]


def css(c, alpha=None):
    r, g, b = (round(min(1, v) * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


def strip_codes(s):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", s)


# ---------------------------------------------------------------------------
# Scene: inside Wailing Caverns, four Fanglords down, Verdan next and selected
# ---------------------------------------------------------------------------
DUNGEON = "wc"
DONE = {"s2", "s3", "s4", "s5", "s8"}
SELECTED = "s9"
PIN_LEVEL_EXAMPLE = True
LOOT_NAMES = {  # item names for the mock-up (the addon reads them from the game)
    6630: ("괴물씨앗 버클러", "Seedcloak Buckler", "🛡️"),
    6631: ("살아있는 뿌리", "Living Root", "🌿"),
    6629: ("곰팡이 단망토", "Sporid Cape", "🧣"),
}
RARE_BLUE = "#0070dd"

T = {
    "ko": {
        "lead": "18개 던전의 실제 미니맵 지도 위에 공략 순서 · 우두머리 · 희귀 몹 · 퀘스트 장소를 표시하고, 처치하면 자동으로 체크합니다",
        "zone": "불모의 땅",
        "notes": [
            ("다음 목표 바", "던전 안에서 다음 목표와 진행도(처치한 우두머리/전체), 짧은 공략 메모. ‘지도’는 공략 창을 열고 ‘파티 알림’은 현재 단계를 파티 채팅에 알립니다."),
            ("던전 선택", "제목을 누르면 18개 던전 목록(권장 레벨, 지금 있는 던전 표시). ‘현재 던전’은 지금 있는 던전으로 돌아오고, ‘목록’은 오른쪽 목록을 접고 펼치며, ‘설정’은 설정창을 엽니다."),
            ("지도", "번호 = 우두머리 순서, 색 = 종류. 희귀 몹·할 일은 아이콘, 노란 ! = 퀘스트 대상, ✓ = 완료, 빛나는 표식 = 다음 목표. 휠로 확대, 확대 후 끌어서 이동, ‘전체’로 다시 맞춤."),
            ("경로 / 퀘스트 / 준비", "경로: 단계 목록(좌클릭 선택, 우클릭 완료 전환)과 일반 몹 드랍 목록. 퀘스트: 최소 수락 레벨·보상·진행 상태. 준비: 열쇠·진영 주의사항·준비물."),
            ("자동 체크", "우두머리를 처치하면 ✓로 바뀌고 다음 목표가 노란색으로 강조됩니다. 아래에 공략 메모와 전리품 아이콘(Shift+클릭: 채팅 링크)."),
            ("상세 카드", "표식이나 단계를 누르면 3D 모델(끌기 회전 · 휠 확대 · 우클릭 처음 각도)과 전리품 목록이 창 옆에 열립니다."),
            ("세계지도 입구", "대륙·지역 지도의 던전 입구 표식. 클릭하면 그 던전의 공략 창, Shift+클릭하면 입구 방향 화살표 안내와 지도 목적지 표시."),
        ],
        "foot": "애드온 코드의 창 크기·좌표·색상·문구와 내장 데이터로 재현한 예시 화면입니다. 지도는 애드온에 들어 있는 미니맵 타일로 그린 통곡의 동굴이고, 3D 모델과 아이템 아이콘 자리에는 그림을 넣었습니다.",
        "sTitle": "설정창",
        "sLead": "/ezdg config · 언어, 던전 안 동작, 세계지도 표시, 창 투명도와 지도 크기, 도구",
        "sNotes": [
            ("언어", "상자를 누르고 목록(자동 · 한국어 · English · Deutsch · Français · Español · Русский · 简体中文 · 繁體中文)에서 고릅니다."),
            ("던전 안 동작", "입장 시 공략 창 자동 열기, 다음 목표 바, 희귀 몹 발견 알림, 전투 중 반투명, 창 위치 잠금, 화면 바로가기 아이콘."),
            ("세계지도", "던전 입구·이름·권장 레벨 표시(이름은 처음엔 꺼짐), 지도 버튼 좌하단 자동 정렬, 지도 표식 위치 수동 편집 모드."),
            ("창 투명도 · 지도 크기", "배경 30~100%, 던전 지도 260~620px."),
            ("도구", "공략 창 열기, 입구 방향 화살표 안내, 현재 던전 진행도 초기화, 편집한 표식 위치 내보내기."),
            ("위치 초기화 · 후원", "공략 창, 화면 아이콘, 다음 목표 바, 입구 화살표, 세계지도 버튼을 처음 위치로 되돌리고 숨긴 아이콘을 다시 표시합니다."),
        ],
        "sFoot": "애드온 코드의 창 크기·좌표·색상·문구로 재현한 예시 화면입니다. 체크 상태는 기본값입니다.",
    },
    "en": {
        "lead": "Route order, bosses, rares and quest spots on real minimap maps of 18 dungeons, ticked off automatically as bosses die",
        "zone": "The Barrens",
        "notes": [
            ("Next-objective bar", "Inside a dungeon: next objective, progress (bosses killed / total) and a short tip. ‘Map’ opens the guide, ‘Tell party’ posts the current step to party chat."),
            ("Pick a dungeon", "Click the title for the list of 18 dungeons with their levels. ‘Current’ returns to the dungeon you are in, ‘List’ folds the side list, ‘Options’ opens the settings."),
            ("Map", "Number = boss order, colour = type. Rares and tasks get an icon, yellow ! = quest target, ✓ = done, glowing marker = next objective. Wheel to zoom, drag to pan when zoomed, ‘Fit’ resets."),
            ("Route / Quests / Prep", "Route: the step list (left-click select, right-click toggle done) and trash drops. Quests: minimum level, rewards and status. Prep: keys, faction warnings, supplies."),
            ("Auto check", "A killed boss gets a ✓ and the next objective turns yellow. Below: the tip and loot icons (Shift+click: chat link)."),
            ("Detail card", "Click a marker or step to open the 3D model (drag to rotate · wheel to zoom · right-click to reset) and the loot list next to the window."),
            ("World Map entrances", "Dungeon entrance pins on continent and zone maps. Click: that dungeon's guide window. Shift+click: entrance arrow and a map waypoint."),
        ],
        "foot": "Mock-up rebuilt from the window sizes, coordinates, colours and strings in the addon code and its bundled data. The map is Wailing Caverns drawn from the minimap tiles shipped with the addon; pictures stand in for the 3D model and item icons.",
        "sTitle": "Settings",
        "sLead": "/ezdg config · language, in-dungeon behaviour, World Map pins, window opacity and map size, tools",
        "sNotes": [
            ("Language", "Click the box and pick from the list (Auto · 한국어 · English · Deutsch · Français · Español · Русский · 简体中文 · 繁體中文)."),
            ("In the dungeon", "Auto-open on entry, next-objective bar, rare mob alert, fade in combat, lock the window, floating launcher icon."),
            ("World Map", "Dungeon entrances, names and recommended levels (names off by default), auto-align the map button, marker position edit mode."),
            ("Opacity · map size", "Background 30–100%, dungeon map 260–620 px."),
            ("Tools", "Open the guide, start the entrance arrow, reset current dungeon progress, export marker edits."),
            ("Reset positions · support", "Moves the guide, launcher icon, objective bar, entrance arrow and World Map button back to their defaults and shows a hidden icon again."),
        ],
        "sFoot": "Mock-up rebuilt from the window size, coordinates, colours and strings in the addon code. Check boxes show the defaults.",
    },
}


def px(v):
    return f"{v * S:.2f}px"


def esc(s):
    return html.escape(s, quote=False)


SHADOW = "text-shadow:1px 1px 0 #000,0 0 2px rgba(0,0,0,.8);"
OUTLINE = "text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000,0 0 3px #000;"
GOLD = "#ffd100"
FS = {"small": 10, "normal": 12, "large": 15, "hl": 12}

CSS = f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ width: {PAGE_W}px; overflow: hidden; background: radial-gradient(ellipse at 30% 0%, #1f2a3d 0%, #121922 55%, #0b1014 100%);
  font-family: 'Noto Sans KR', 'Malgun Gothic', sans-serif; color: #edf4f7; }}
.page {{ position: relative; padding: 34px 50px 40px; }}
h1 {{ color: {CALL}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {CALL}; color: #2a0f0d; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #d5dde2; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.t {{ position: absolute; white-space: nowrap; line-height: 1.15; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {CALL}; color: #2a0f0d; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #2a0f0d; box-shadow: 0 0 0 2px {CALL}55; z-index: 50; }}
.notes {{ position: absolute; }}
.note {{ display: flex; gap: 12px; margin-bottom: 10px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {CALL}; color: #2a0f0d; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; }}
.note b {{ color: #fff; }}
.foot {{ color: #7d8d98; font-size: 13.5px; line-height: 1.5; }}
.fit {{ display: inline-block; }}
.tip {{ position: absolute; background: rgba(6,10,16,.94); border: 2px solid #5d6d7a; border-radius: 4px; padding: 7px 11px;
  font-size: 14px; line-height: 1.5; white-space: nowrap; z-index: 20; }}
.row {{ position: relative; display: flex; align-items: flex-start; }}
"""

FIT_JS = """
<script>
document.querySelectorAll('[data-fit]').forEach(function (e) {
  var max = parseFloat(e.dataset.fit), min = parseFloat(e.dataset.min || 8);
  var fs = parseFloat(getComputedStyle(e).fontSize);
  while (e.scrollWidth > max && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
});
</script>
"""


def box(x, y, w, h, style="", inner=""):
    return f'<div class="abs" style="left:{px(x)};top:{px(y)};width:{px(w)};height:{px(h)};{style}">{inner}</div>'


def text(x, y, s, size, color, extra=""):
    return f'<div class="t" style="left:{px(x)};top:{px(y)};font-size:{px(size)};color:{color};{SHADOW}{extra}">{s}</div>'


def disc(cx, cy, d, color, extra=""):
    """circle of diameter d (game px) centred on cx, cy (game px)"""
    return (f'<div class="abs" style="left:{px(cx - d / 2)};top:{px(cy - d / 2)};width:{px(d)};height:{px(d)};'
            f'border-radius:50%;background:{color};{extra}"></div>')


def note_html(start, lst):
    return "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{esc(a)}</b> — {esc(b)}</div></div>'
                   for i, (a, b) in enumerate(lst))


def notes_height(notes, width):
    h = 0
    for a, b in notes:
        chars = len(a) + len(b) + 3
        wide = sum(1 for ch in a + b if ord(ch) > 0x2e80)
        per_line = width / (8.4 + 7.4 * wide / chars)
        h += max(1, math.ceil(chars / per_line)) * 24 + 10
    return h


def button(x, y, w, h, label, size=10, color="#edf4f7", alpha=1.0, accent=False):
    bg = "rgba(61,36,38,.96)" if accent else "rgba(29,40,49,.96)"
    bd = CALL if accent else "rgba(52,76,91,1)"
    return box(x, y, w, h, f"background:{bg};border:1px solid {bd};display:flex;align-items:center;justify-content:center;opacity:{alpha}",
               f'<span class="fit" data-fit="{(w - 8) * S:.1f}" data-min="{size * 0.7 * S:.1f}" style="font-size:{px(size)};color:{color};white-space:nowrap;{SHADOW}">{esc(label)}</span>')


# ---------------------------------------------------------------------------
# Map art: the minimap tiles put together on the raster of Data/MinimapData.lua
# ---------------------------------------------------------------------------
def map_image(root, page, out_px):
    rw, rh = page["rasterSize"]
    raster = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    for tile in page["grid"]["tiles"]:
        path, tx, ty, tw, th = tile[0], tile[1], tile[2], tile[3], tile[4]
        border = tile[6] if len(tile) > 6 else 0
        name = path.split("\\")[-1]
        img = Image.open(root / "MinimapTiles_v12" / name).convert("RGBA")
        img = img.crop((border, border, border + tw, border + th))
        raster.alpha_composite(img, (int(tx), int(ty)))
    vx, vy, vw, vh = page["view"]
    canvas = Image.new("RGBA", (int(round(vw)), int(round(vh))), (0, 0, 0, 0))
    canvas.alpha_composite(raster, (int(round(-vx)), int(round(-vy))))
    canvas = canvas.resize((out_px, out_px), Image.LANCZOS)
    buf = io.BytesIO()
    canvas.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def boss_index(steps, i):
    if steps[i]["kind"] != "boss":
        return None
    return sum(1 for s in steps[:i + 1] if s["kind"] == "boss")


def category(step):
    if step["kind"] in ("object", "task"):
        return "quest"
    return step["kind"] if step["kind"] in ("entrance", "boss", "rare", "npc", "quest") else "boss"


def kind_icon(kind, size):
    """stand-ins for the KIND_ICON textures of Modules/ProgressTracker.lua"""
    if kind == "rare":  # raid target star
        return (f'<svg width="{size}" height="{size}" viewBox="0 0 20 20"><path d="M10 1.5 L12.6 7.3 L18.8 7.8 L14 11.9 L15.5 18 L10 14.7 L4.5 18 L6 11.9 L1.2 7.8 L7.4 7.3 Z" '
                'fill="#ffd84a" stroke="#6b4b00" stroke-width="1.2"/></svg>')
    if kind in ("object", "task"):  # available quest "!"
        return (f'<svg width="{size}" height="{size}" viewBox="0 0 20 20"><path d="M7.5 2 H12.5 L11.4 13 H8.6 Z" fill="#ffd100" stroke="#3a2a00" stroke-width="1"/>'
                '<circle cx="10" cy="16.6" r="2.2" fill="#ffd100" stroke="#3a2a00" stroke-width="1"/></svg>')
    if kind == "npc":
        return (f'<svg width="{size}" height="{size}" viewBox="0 0 20 20"><path d="M3 4 H17 V13 H9 L5 17 V13 H3 Z" fill="#f2f2f2" stroke="#333" stroke-width="1"/></svg>')
    if kind == "trash":  # bag
        return (f'<svg width="{size}" height="{size}" viewBox="0 0 20 20"><rect x="1" y="1" width="18" height="18" rx="2" fill="#3b2c1c"/>'
                '<path d="M6 7 Q10 3 14 7 L15.5 16 H4.5 Z" fill="#a07a48" stroke="#2a1d10" stroke-width="1"/></svg>')
    return ""


CHECK_SVG = ('<svg width="100%" height="100%" viewBox="0 0 20 20"><path d="M3.5 10.5 L8 15 L16.5 4.5" fill="none" stroke="#1f3d0c" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'
             '<path d="M3.5 10.5 L8 15 L16.5 4.5" fill="none" stroke="#5fe03a" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/></svg>')


def marker(cx, cy, step, num, done, selected, nxt, cat):
    """UI/DungeonMapWindow.lua resolveMarker: glow 26, ring 17, circle 14, check 12, quest badge 8"""
    p = []
    col = cat["done"] if done else cat[category(step)]
    if nxt:
        p.append(disc(cx, cy, 26, "radial-gradient(circle, rgba(255,209,0,.85) 0%, rgba(255,209,0,.35) 55%, rgba(255,209,0,0) 72%)"))
    p.append(disc(cx, cy, 17, "rgba(255,255,255,.9)" if selected else "rgba(0,0,0,.5)"))
    p.append(disc(cx, cy, 14, css(col, 0.45 if step.get("optional") else 0.6), "box-shadow:inset 0 0 0 1px rgba(0,0,0,.25)"))
    # the circle sits on the map; draw an opaque base under it so the 60 % colour reads as in game
    p.insert(-1, disc(cx, cy, 14, "rgba(20,16,12,.55)"))
    if num:
        p.append(f'<div class="t" style="left:{px(cx)};top:{px(cy)};transform:translate(-50%,-52%);font-size:{px(10)};color:#fff;font-weight:700;{SHADOW}">{num}</div>')
    else:
        p.append(f'<div class="abs" style="left:{px(cx - 5.5)};top:{px(cy - 5.5)};width:{px(11)};height:{px(11)}">{kind_icon(step["kind"], 11 * S)}</div>')
    if done:
        p.append(f'<div class="abs" style="left:{px(cx + 8 + 5 - 12)};top:{px(cy + 8 + 4 - 12)};width:{px(12)};height:{px(12)}">{CHECK_SVG}</div>')
    if step.get("quest") and not done and step["kind"] not in ("object", "task"):
        bx, by = cx + 8 + 3 - 4, cy - 8 - 3 + 4
        p.append(disc(bx, by, 8, "rgb(255,209,0)"))
        p.append(f'<div class="t" style="left:{px(bx)};top:{px(by)};transform:translate(-50%,-52%);font-size:{px(7.5)};color:#000;font-weight:800">!</div>')
    return "".join(p)


# ---------------------------------------------------------------------------
# Route window, HUD, detail card, World Map pin (UI/DungeonMapWindow.lua, UI/HUD.lua, UI/WorldMapPins.lua)
# ---------------------------------------------------------------------------
def route_window(ctx, lang, x0, y0):
    L, W_, d, mm = ctx["L"][lang], ctx["win"], ctx["dungeon"], ctx["minimap"]
    cat = W_["CAT"]
    HEADER, PAD, LISTW = W_["HEADER"], W_["PAD"], W_["LISTW"]
    size = int(ctx["defaults"]["mapSize"])
    page = mm["pages"][0]
    vx, vy, vw, vh = page["view"]
    CW = int(math.floor(size * vw / vh + 0.5))
    W = max(360, PAD + CW + PAD + LISTW)
    H = HEADER + size + W_["LEGEND_H"] + W_["FOOT_H"] + 8
    sc = size / vh
    steps = d["steps"]
    p = []
    # header: close 22, Options 44, List 40, Current 64, title dropdown
    bx = W - PAD - 22
    p.append(button(bx, 4, 22, 20, "X"))
    for key, w, gap in (("BTN_MENU", 44, 2), ("BTN_LIST", 40, 2), ("BTN_CURRENT", 64, 6)):
        bx -= gap + w
        p.append(button(bx, 4, w, 20, L[key], alpha=0.45 if key == "BTN_CURRENT" else 1))
    tw = bx - 6 - PAD
    title = f'{esc(d["name"][lang])} <span style="color:#aaaaaa">{esc(d["levels"])}</span>'
    p.append(box(PAD, 4, tw, 20, f"background:rgba(29,40,49,.94);border:1px solid rgba(234,131,126,.9)",
                 text(6, 3, f'<span class="fit" data-fit="{(tw - 30) * S:.1f}">{title}</span>', FS["normal"], GOLD)
                 + f'<div class="t" style="right:{px(5)};top:{px(2)};font-size:{px(11)};color:{GOLD}">▼</div>'))
    anchors = {"title": (x0 + (PAD + tw / 2) * S, y0 + 4 * S)}
    # map canvas
    cx0, cy0 = PAD, HEADER
    p.append(box(cx0, cy0, CW, size, "background:rgba(0,0,0,.5);overflow:hidden",
                 f'<img src="{ctx["mapImg"]}" style="position:absolute;left:0;top:0;width:{px(CW)};height:{px(size)}">'))

    def M(pos):
        return cx0 + (pos[0] - vx) * sc, cy0 + (pos[1] - vy) * sc

    # orientation badge, fit button
    p.append(f'<div class="t" style="right:{px(W - (cx0 + CW) + 6)};top:{px(cy0 + 27)};font-size:{px(FS["small"])};color:{GOLD};{SHADOW}">{esc(L["MAP_NORTH_UP"])}</div>')
    p.append(button(cx0 + CW - 4 - 46, cy0 + size - 4 - 20, 46, 20, L["MAP_FIT"]))
    # entrance
    ex, ey = M(mm["start"]["pos"])
    p.append(disc(ex, ey, 15, css(cat["entrance"])) + disc(ex, ey, 9, "rgba(13,38,13,.5)"))
    p.append(f'<div class="t" style="left:{px(ex)};top:{px(ey + 8.5)};transform:translate(-50%,0);font-size:{px(FS["small"])};color:{css(cat["entrance"])};{SHADOW}">{esc(L["LEG_ENTRANCE"])}</div>')
    # markers
    next_idx = next(i for i, s in enumerate(steps) if s["id"] not in DONE and not s.get("optional") and s["kind"] != "fork")
    marks = []
    for i, s in enumerate(steps):
        geo = mm["steps"].get(s["id"])
        if not geo or not geo.get("pos"):
            continue
        mx, my = M(geo["pos"])
        marks.append((i, mx, my))
        p.append(marker(mx, my, s, boss_index(steps, i), s["id"] in DONE, s["id"] == SELECTED, i == next_idx, cat))
        if s["id"] == SELECTED:
            anchors["marker"] = (x0 + mx * S, y0 + my * S)
    # legend
    lx = cx0
    ly = cy0 + size + 3 + W_["LEGEND_H"] / 2
    for k in ("entrance", "boss", "rare", "npc", "quest"):
        p.append(disc(lx + 4.5, ly, 9, css(cat[k])))
        label = L["LEG_" + k.upper()]
        p.append(f'<div class="t" style="left:{px(lx + 12)};top:{px(ly)};transform:translate(0,-50%);font-size:{px(FS["small"])};color:#fff;{SHADOW}">{esc(label)}</div>')
        lx += 16 + len(label) * (9.5 if lang == "ko" else 5.6) + 10
    # side list
    lx0 = cx0 + CW + PAD
    tabs = (("TAB_ROUTE", 54), ("TAB_QUEST", 58), ("TAB_NOTES", 50))
    tx = lx0
    for i, (k, w) in enumerate(tabs):
        p.append(button(tx, cy0, w, 20, L[k], alpha=1 if i == 0 else 0.55))
        tx += w + 2
    anchors["tabs"] = (x0 + tx * S, y0 + (cy0 + 10) * S)
    done_n = sum(1 for s in steps if s["kind"] == "boss" and not s.get("optional") and s["id"] in DONE)
    total = sum(1 for s in steps if s["kind"] == "boss" and not s.get("optional"))
    skull = ('<svg width="12" height="12" viewBox="0 0 20 20" style="vertical-align:-1px"><path d="M10 2 C4.5 2 3 6 3 9 C3 11.5 4.5 12.5 5.5 13 V16 H14.5 V13 C15.5 12.5 17 11.5 17 9 C17 6 15.5 2 10 2 Z" fill="#f0e8d8" stroke="#222" stroke-width="1"/>'
             '<circle cx="7.3" cy="9.3" r="2" fill="#222"/><circle cx="12.7" cy="9.3" r="2" fill="#222"/></svg>')
    p.append(f'<div class="t" style="right:{px(W - (lx0 + LISTW - PAD) + 4)};top:{px(cy0 + 4)};font-size:{px(FS["small"])};color:{GOLD};{SHADOW}">{skull} {done_n}/{total}</div>')
    list_w = LISTW - PAD - 24
    rows = []
    for i, s in enumerate(steps):
        done = s["id"] in DONE
        num = boss_index(steps, i)
        if done:
            color = "#8c8c8c"
        elif i == next_idx:
            color = GOLD
        elif s.get("optional"):
            color = "rgb(209,179,255)"
        else:
            color = "#fff"
        if s.get("outside"):
            tag = L["OUTSIDE"]
        elif s["kind"] == "rare":
            tag = L["KIND_rare"]
        elif s.get("optional"):
            tag = L["OPTIONAL"]
        elif s["kind"] != "boss":
            tag = L.get("KIND_" + s["kind"], "")
        else:
            tag = ""
        lead = ""
        if done:
            lead += f'<div class="abs" style="left:{px(1)};top:{px(1)};width:{px(14)};height:{px(14)}">{CHECK_SVG}</div>'
        elif s["kind"] != "fork":
            lead += f'<div class="abs" style="left:{px(4)};top:{px(4)};width:{px(8)};height:{px(8)};border-radius:50%;background:{css(cat[category(s)])}"></div>'
        if num:
            lead += f'<div class="abs" style="left:{px(14)};top:{px(2)};width:{px(18)};text-align:right;font-size:{px(FS["small"])};color:{GOLD};{SHADOW}">{num}</div>'
        else:
            lead += f'<div class="abs" style="left:{px(20)};top:{px(1.5)};width:{px(13)};height:{px(13)}">{kind_icon(s["kind"], 13 * S)}</div>'
        bg = "background:rgba(255,209,0,.12);" if s["id"] == SELECTED else ""
        rows.append(f'<div class="row" style="width:{px(list_w)};min-height:{px(17)};{bg}">{lead}'
                    f'<div style="margin-left:{px(37)};padding-top:{px(2)};flex:1;font-size:{px(FS["small"])};line-height:1.2;color:{color};{SHADOW}">{esc(s["name"][lang])}</div>'
                    f'<div style="padding:{px(2)} {px(2)} 0 {px(4)};font-size:{px(FS["small"])};line-height:1.2;color:#9a9a9a;white-space:nowrap;{SHADOW}">{esc(tag)}</div></div>')
    for g in d.get("trashGroups", []):
        lead = (f'<div class="abs" style="left:{px(4)};top:{px(4)};width:{px(8)};height:{px(8)};border-radius:50%;background:rgb(153,153,153)"></div>'
                f'<div class="abs" style="left:{px(20)};top:{px(1.5)};width:{px(13)};height:{px(13)}">{kind_icon("trash", 13 * S)}</div>')
        rows.append(f'<div class="row" style="width:{px(list_w)};min-height:{px(17)}">{lead}'
                    f'<div style="margin-left:{px(37)};padding-top:{px(2)};flex:1;font-size:{px(FS["small"])};line-height:1.2;color:#ccc;{SHADOW}">{esc(g["name"][lang])}</div>'
                    f'<div style="padding:{px(2)} {px(2)} 0 {px(4)};font-size:{px(FS["small"])};color:#9a9a9a;white-space:nowrap;{SHADOW}">{esc(L["LOOT"])} {len(g["loot"])}</div></div>')
    sel_i = next(i for i, s in enumerate(steps) if s["id"] == SELECTED)
    sel = steps[sel_i]
    sel_title = f'{boss_index(steps, sel_i)}. {sel["name"][lang]}'
    tip = (f'<div style="margin:{px(6)} {px(4)} {px(8)};width:{px(list_w - 8)};font-size:{px(FS["small"])};line-height:1.3;white-space:normal;{SHADOW}">'
           f'<span style="color:{GOLD}">{esc(sel_title)}</span><br>{esc(sel["tip"][lang])}</div>')
    icons = "".join(f'<div style="display:inline-block;width:{px(22)};height:{px(22)};margin-right:{px(2)};box-shadow:0 0 0 {px(1)} {RARE_BLUE};'
                    f'background:linear-gradient(#2d3a2a,#141a12);font-size:{px(14)};line-height:{px(22)};text-align:center">{LOOT_NAMES[i][2]}</div>'
                    for i in sel.get("loot", []))
    loot = (f'<div style="margin-left:{px(4)};font-size:{px(FS["small"])};color:{GOLD};{SHADOW}">{esc(L["LOOT"])} · {esc(sel["name"][lang])}</div>'
            f'<div style="margin:{px(3)} 0 0 {px(3)}">{icons}</div>')
    p.append(f'<div class="abs" style="left:{px(lx0)};top:{px(cy0 + 26)};width:{px(list_w)};height:{px(size + W_["LEGEND_H"] - 26)};overflow:hidden">'
             + "".join(rows) + tip + loot + "</div>")
    # scroll bar of the list (UIPanelScrollFrameTemplate)
    p.append(box(lx0 + list_w + 4, cy0 + 26 + 16, 12, size + W_["LEGEND_H"] - 26 - 32, "background:rgba(0,0,0,.35);border-radius:3px"))
    p.append(box(lx0 + list_w + 5, cy0 + 26 + 18, 10, 70, "background:linear-gradient(90deg,#6c5a3a,#a88a52,#6c5a3a);border-radius:3px"))
    row_y = cy0 + 26 + (sel_i + 0.5) * 17
    anchors["selRow"] = (x0 + (lx0 + list_w) * S, y0 + row_y * S)
    anchors["map"] = (x0 + (cx0 + 30) * S, y0 + (cy0 + 30) * S)
    win = (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{px(W)};height:{px(H)};background:rgba(18,24,31,{ctx["defaults"]["alpha"]:.2f});'
           f'border:1px solid rgba(234,131,126,.9)">' + "".join(p) + "</div>")
    return win, anchors, (W, H), sel_title


def hud(ctx, lang, x0, y0, sel_title):
    L, d = ctx["L"][lang], ctx["dungeon"]
    steps = d["steps"]
    done_n = sum(1 for s in steps if s["kind"] == "boss" and not s.get("optional") and s["id"] in DONE)
    total = sum(1 for s in steps if s["kind"] == "boss" and not s.get("optional"))
    sel = next(s for s in steps if s["id"] == SELECTED)
    first = re.split(r"(?<=[.!?。])\s", sel["tip"][lang])[0]
    W, H = 340, 62
    p = [button(W - 4 - 42, 4, 42, 18, L["BTN_MAP"]), button(W - 4 - 42 - 2 - 62, 4, 62, 18, L["BTN_ANNOUNCE"])]
    p.append(text(8, 6, f'<span style="color:{GOLD}">{esc(d["name"][lang])}</span>  {esc(L["PROGRESS"].replace("%d", str(done_n), 1).replace("%d", str(total), 1))}', FS["small"], GOLD))
    p.append(text(8, 22, f'<span style="color:{GOLD}">{esc(L["NEXT"])}:</span> {esc(sel_title)}', FS["hl"], "#fff"))
    p.append(f'<div class="t" style="left:{px(8)};top:{px(41)};width:{px(W - 16)};overflow:hidden;text-overflow:ellipsis;font-size:{px(FS["small"])};color:#d9d9d9;{SHADOW}">{esc(first)}</div>')
    return (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{px(W)};height:{px(H)};background:rgba(18,24,31,.90);border:1px solid rgba(234,131,126,.85)">'
            + "".join(p) + "</div>"), (W, H)


MODEL_ART = ('<svg width="100%" height="100%" viewBox="0 0 200 150" preserveAspectRatio="xMidYMid meet">'
             '<defs><radialGradient id="g" cx="50%" cy="45%" r="60%"><stop offset="0" stop-color="#7fae4a"/><stop offset="1" stop-color="#3d5e22"/></radialGradient></defs>'
             '<ellipse cx="100" cy="138" rx="58" ry="7" fill="rgba(0,0,0,.45)"/>'
             '<path d="M70 135 Q60 100 72 70 Q80 40 100 32 Q120 40 128 70 Q140 100 130 135 Z" fill="url(#g)" stroke="#22350f" stroke-width="2"/>'
             '<path d="M72 80 Q40 70 30 40 Q55 52 76 64 Z M128 80 Q160 70 170 40 Q145 52 124 64 Z" fill="#5d8a32" stroke="#22350f" stroke-width="2"/>'
             '<path d="M84 34 Q78 14 90 6 Q92 22 98 30 Z M116 34 Q122 14 110 6 Q108 22 102 30 Z" fill="#8bbf55" stroke="#22350f" stroke-width="2"/>'
             '<circle cx="90" cy="58" r="5" fill="#ffe36a"/><circle cx="110" cy="58" r="5" fill="#ffe36a"/>'
             '<path d="M88 78 Q100 86 112 78" fill="none" stroke="#22350f" stroke-width="3" stroke-linecap="round"/>'
             '<path d="M78 110 Q70 125 60 132 M122 110 Q130 125 140 132 M100 100 V134" stroke="#4a6d27" stroke-width="5" fill="none" stroke-linecap="round"/></svg>')


def detail_card(ctx, lang, x0, y0, H, sel_title):
    L, W_, d = ctx["L"][lang], ctx["win"], ctx["dungeon"]
    W, MH = W_["CARD_W"], W_["MODEL_H"]
    sel = next(s for s in d["steps"] if s["id"] == SELECTED)
    p = [button(W - 4 - 22, 4, 22, 20, "X"),
         text(8, 8, f'<span class="fit" data-fit="{(W - 40) * S:.1f}">{esc(sel_title)}</span>', FS["normal"], GOLD),
         text(8, 25, esc(L["KIND_" + sel["kind"]]), FS["small"], "#9a9a9a"),
         box(6, 44, W - 12, MH, "background:rgba(0,0,0,.45)", MODEL_ART)]
    loot = sel.get("loot", [])
    p.append(text(8, 44 + MH + 8, f'{esc(L["LOOT"])} ({len(loot)})', FS["small"], GOLD))
    y = 44 + MH + 8 + 16
    for iid in loot:
        ko, en, icon = LOOT_NAMES[iid]
        p.append(box(9, y + 1, 18, 18, f"box-shadow:0 0 0 {px(1)} {RARE_BLUE};background:linear-gradient(#2d3a2a,#141a12);font-size:{px(12)};line-height:{px(18)};text-align:center", icon))
        p.append(text(32, y + 3, esc(ko if lang == "ko" else en), FS["small"], RARE_BLUE))
        y += 21
    return (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{px(W)};height:{px(H)};background:rgba(18,24,31,.92);border:1px solid rgba(234,131,126,.9)">'
            + "".join(p) + "</div>"), W


def world_pin(ctx, lang, x0, y0, w, h):
    """Zone map patch with the entrance pin and its tooltip (UI/WorldMapPins.lua OnMouseEnter)."""
    L, d = ctx["L"][lang], ctx["dungeon"]
    e = d["entrance"]
    terrain = (f'<svg class="abs" style="left:0;top:0" width="{w}" height="{h}" viewBox="0 0 100 100" preserveAspectRatio="none">'
               '<defs><radialGradient id="sv" cx="40%" cy="45%" r="75%"><stop offset="0" stop-color="#a98d56"/><stop offset="1" stop-color="#7d6a3e"/></radialGradient></defs>'
               '<rect width="100" height="100" fill="url(#sv)"/>'
               '<path d="M0 22 Q20 18 34 30 Q46 40 40 58 Q34 74 48 100 H0 Z" fill="#8f7745" opacity=".55"/>'
               '<ellipse cx="62" cy="30" rx="13" ry="8" fill="#3f6f8c" stroke="#d8c48e" stroke-width=".6"/>'
               '<path d="M18 0 V100 M0 64 H100" stroke="#c9ad73" stroke-width=".8" fill="none"/>'
               '<g fill="#6c7a3a" opacity=".85"><circle cx="70" cy="70" r="2"/><circle cx="84" cy="52" r="1.6"/><circle cx="30" cy="84" r="1.8"/></g></svg>')
    pin_x, pin_y = w * 0.30, h * 0.30
    pin = (f'<img class="abs" src="{ctx["pinImg"]}" style="left:{pin_x - 10 * S:.1f}px;top:{pin_y - 10 * S:.1f}px;width:{px(20)};height:{px(20)};filter:drop-shadow(0 0 2px #000)">')
    tip = (f'<div class="tip" style="left:8px;top:{pin_y + 18:.0f}px;font-size:13px">'
           f'<div style="color:{GOLD};font-size:14px">EzWoW - Dungeon Route Guide</div>'
           f'<div style="color:{GOLD}">{esc(d["name"][lang])}  <span style="color:#fff">{esc(d["levels"])}</span></div>'
           f'<div style="color:#ccc">{esc(T[lang]["zone"])}  {e["x"]:.1f}, {e["y"]:.1f}</div>'
           f'<div style="color:rgb(128,204,255)">{esc(L["WORLD_PIN_CLICK"])}</div></div>')
    return (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{w}px;height:{h}px;border:2px solid #5d6d7a;border-radius:6px;overflow:visible">'
            f'<div class="abs" style="left:0;top:0;width:{w - 4}px;height:{h - 4}px;overflow:hidden;border-radius:4px">{terrain}</div>{pin}{tip}</div>'), (x0 + pin_x, y0 + pin_y)


def ui_page(lang, ctx):
    t = T[lang]
    parts = []
    wx, wy = 50, 150 + 62 * S + 26
    win, an, (W, H), sel_title = route_window(ctx, lang, wx, wy)
    hud_html, _ = hud(ctx, lang, 50, 150, sel_title)
    parts += [hud_html, win]
    card_x = wx + W * S + 2 * S
    card, cw = detail_card(ctx, lang, card_x, wy, H, sel_title)
    parts.append(card)
    pw_x = card_x + cw * S + 30
    pw_w = PAGE_W - 50 - pw_x
    pin_html, pin_at = world_pin(ctx, lang, pw_x, 150, pw_w, 250)
    parts.append(pin_html)
    calls = [
        (50 + 340 * S + 24, 150 + 31 * S),                    # 1 HUD
        (an["title"][0], an["title"][1] - 2),                 # 2 dungeon picker
        an["map"],                                            # 3 map
        (an["tabs"][0] + 20, an["tabs"][1]),                  # 4 tabs
        (an["selRow"][0] + 6, an["selRow"][1]),               # 5 auto check / next
        (card_x + cw * S - 40, wy + 120),                     # 6 detail card
        (pin_at[0] - 34, pin_at[1]),                          # 7 world map pin
    ]
    for i, (x, y) in enumerate(calls, 1):
        parts.append(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>')
    notes_top = wy + H * S + 34
    half = 4
    parts.append(f'<div class="notes" style="left:50px;top:{notes_top:.0f}px;width:720px">{note_html(1, t["notes"][:half])}</div>')
    parts.append(f'<div class="notes" style="left:820px;top:{notes_top:.0f}px;width:730px">{note_html(half + 1, t["notes"][half:])}</div>')
    nh = max(notes_height(t["notes"][:half], 680), notes_height(t["notes"][half:], 690))
    page_h = notes_top + nh + 70
    parts.append(f'<div class="abs foot" style="left:50px;top:{page_h - 58:.0f}px;width:1500px">{esc(t["foot"])}</div>')
    head = f'<div class="page"><h1>EzWoW - Dungeon Route Guide</h1><div class="lead">{esc(t["lead"])}</div></div>'
    return head + "".join(parts), page_h


# ---------------------------------------------------------------------------
# Settings window (UI/OptionsWindow.lua)
# ---------------------------------------------------------------------------
CHECK = ('<svg viewBox="0 0 22 22" width="100%" height="100%"><rect x="3.5" y="3.5" width="15" height="15" rx="1.5" fill="#15130f" stroke="#8a7a50" stroke-width="1.4"/>'
         '{mark}</svg>')
MARK = '<path d="M5.5 11.5 L9.5 15.5 L17.5 5.5" fill="none" stroke="#ffd100" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'


def clean_colon(s):
    return re.sub(r"\s*%.*$", "", re.sub(r"\s*:.*$", "", s))


def settings_window(ctx, lang, x0, y0):
    L, o, dflt = ctx["L"][lang], ctx["options"], ctx["defaults"]
    W, H = o["size"]
    acc, text_c, mut = CALL, "#edf4f7", "#a7b9c5"
    p = []

    def btn(spec, label, color=None):
        x, y, w, h, accent = spec
        return button(x, y, w, h, label, color=color or (acc if accent else text_c), accent=accent)

    p.append(box(1, 1, W - 2, 56, "background:rgba(29,40,49,.96)"))
    p.append(box(1, 55, W - 2, 2, f"background:{acc}"))
    p.append(f'<img class="abs" src="{ctx["icon"]}" style="left:{px(14)};top:{px(14)};width:{px(28)};height:{px(28)}">')
    p.append(text(48, 11, "EzWoW - Dungeon Route Guide", 15, acc))
    p.append(text(48, 32, esc(f'{L["TAB_ROUTE"]} · {L["TAB_QUEST"]} · {L["TAB_NOTES"]}'), FS["small"], mut))
    p.append(btn(o["close"], "X"))
    for y, key in zip(o["sections"], ("BTN_MENU", "SEC_TOOLS")):
        p.append(text(20, y, esc(L[key]), FS["normal"], acc))
        p.append(box(20, y + 18, W - 40, 1, "background:rgba(52,76,91,.85)"))
    p.append(btn(o["lang"], L["OPT_LANG"].replace("%s", L["LANG_auto"]) + " ▼"))
    for c in o["checks"]:
        if c["field"]:
            v = dflt.get(c["field"])
            on = (v is not False) if c["notFalse"] else bool(v)
        else:
            on = False  # edit mode
        label = L[c["label"]]
        label = label if c["label"].startswith("WORLD_") else clean_colon(label)
        p.append(box(c["x"], c["y"], 24, 24, "", CHECK.format(mark=MARK if on else "")))
        p.append(f'<div class="t" style="left:{px(c["x"] + 28)};top:{px(c["y"] + 12)};transform:translate(0,-50%);font-size:{px(FS["small"])};color:{text_c};{SHADOW}">'
                 f'<span class="fit" data-fit="{c["w"] * S:.1f}" data-min="{FS["small"] * 0.7 * S:.1f}">{esc(label)}</span></div>')
    ay = o["alphaY"]
    p.append(text(20, ay, f'<span class="fit" data-fit="{100 * S:.1f}">{esc(clean_colon(L["OPT_ALPHA"]))}</span>', FS["small"], mut))
    p.append(btn(o["alphaMinus"], "-"))
    p.append(btn(o["alphaPlus"], "+"))
    am = o["alphaMinus"]
    p.append(f'<div class="t" style="left:{px(am[0] + am[2] + 2)};top:{px(am[1] + 10)};width:{px(42)};transform:translate(0,-50%);text-align:center;font-size:{px(FS["small"])};color:{text_c};{SHADOW}">{int(dflt["alpha"] * 100 + 0.5)}%</div>')
    p.append(text(o["sizeX"], ay, f'<span class="fit" data-fit="{100 * S:.1f}">{esc(clean_colon(L["OPT_SIZE"]))}</span>', FS["small"], mut))
    p.append(btn(o["sizeMinus"], "-"))
    p.append(btn(o["sizePlus"], "+"))
    sm = o["sizeMinus"]
    p.append(f'<div class="t" style="left:{px(sm[0] + sm[2] + 2)};top:{px(sm[1] + 10)};width:{px(48)};transform:translate(0,-50%);text-align:center;font-size:{px(FS["small"])};color:{text_c};{SHADOW}">{int(dflt["mapSize"])}px</div>')
    p.append(btn(o["launch"], "EzWoW - Dungeon Route Guide (/ezdg)"))
    p.append(btn(o["go"], L["OPT_GO"]))
    p.append(btn(o["resetProg"], L["OPT_RESET"]))
    p.append(btn(o["export"], L["OPT_EXPORT"]))
    p.append(btn(o["resetPos"], L["OPT_RESET_POS"]))
    p.append(btn(o["donate"], strip_codes(L["OPT_DONATE"]), color="#ff7799"))
    p.append(f'<div class="t" style="right:{px(20)};bottom:{px(10)};font-size:{px(FS["small"])};color:{mut};{SHADOW}">EzWoW - Dungeon Route Guide · /ezdg</div>')
    return (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{px(W)};height:{px(H)};background:rgba(18,24,31,.97);border:1px solid rgba(52,76,91,1)">'
            + "".join(p) + "</div>")


def settings_page(lang, ctx):
    t = T[lang]
    o = ctx["options"]
    W, H = o["size"]
    ox, oy = 60, 150
    win = settings_window(ctx, lang, ox, oy)
    ys = [c["y"] for c in o["checks"]]
    world_y = min(c["y"] for c in o["checks"] if c["label"].startswith("WORLD_"))
    spans = [(o["lang"][1], o["lang"][1] + 20), (ys[0], world_y), (world_y, max(ys) + 24),
             (o["alphaY"] - 4, o["alphaY"] + 20), (o["sections"][1], o["export"][1] + 26), (o["resetPos"][1], o["resetPos"][1] + 28)]
    calls = "".join(f'<div class="call" style="left:{ox + W * S + 18:.0f}px;top:{oy + (a + b) / 2 * S - 15:.0f}px">{i}</div>'
                    for i, (a, b) in enumerate(spans, 1))
    nx = ox + W * S + 80
    nw = PAGE_W - nx - 50
    notes_h = notes_height(t["sNotes"], nw - 40)
    page_h = max(oy + H * S, oy + 10 + notes_h) + 80
    body = (f'<div class="page"><h1>EzWoW - Dungeon Route Guide <span class="badge">{esc(t["sTitle"])}</span></h1>'
            f'<div class="lead">{esc(t["sLead"])}</div></div>' + win + calls
            + f'<div class="notes" style="left:{nx:.0f}px;top:{oy + 10}px;width:{nw:.0f}px">{note_html(1, t["sNotes"])}</div>'
            + f'<div class="abs foot" style="left:50px;top:{page_h - 44:.0f}px">{esc(t["sFoot"])}</div>')
    return body, page_h


# ---------------------------------------------------------------------------
def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


def render(chrome, html_text, out_png, height, tmp):
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(html_text, encoding="utf-8")
    subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--user-data-dir={Path(tmp) / 'chrome_profile'}", f"--window-size={PAGE_W},{int(height)}",
                    "--virtual-time-budget=2000", f"--screenshot={out_png}", page.as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)


def png_uri(path, size=None):
    img = Image.open(path).convert("RGBA")
    if size:
        img = img.resize(size, Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def main(root: Path):
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    win_src = read(root, "UI/DungeonMapWindow.lua")
    defaults = parse_defaults(read(root, "Modules/ProgressTracker.lua"))
    minimap = parse_minimap(read(root, "Data/MinimapData.lua"), DUNGEON)
    ctx = {
        "L": parse_locales(read(root, "Core/Locales.lua")),
        "defaults": defaults,
        "options": parse_options(read(root, "UI/OptionsWindow.lua")),
        "win": parse_window(win_src),
        "dungeon": parse_dungeon(read(root, "Data/DungeonData.lua"), DUNGEON),
        "minimap": minimap,
        "mapImg": map_image(root, minimap["pages"][0], int(round(defaults["mapSize"] * S))),
        "icon": png_uri(root / "Media" / "icon.png"),
        "pinImg": png_uri(root / "Media" / "dungeon_pin.tga"),
    }
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezdg_readme_")
    try:
        for lang in ("ko", "en"):
            for name, fn in (("ui", ui_page), ("settings", settings_page)):
                body, h = fn(lang, ctx)
                html_text = (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head>'
                             f'<body style="height:{int(h)}px">{body}{FIT_JS}</body></html>')
                png = out / f"{name}_{lang}.png"
                render(chrome, html_text, png, h, tmp)
                print("wrote", png, int(h))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
