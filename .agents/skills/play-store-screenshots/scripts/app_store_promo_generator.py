#!/usr/bin/env python3
"""Store screenshot generator v2 (Script4Me).

Renders localised Google Play / App Store marketing screenshots and a feature
graphic from REAL app screenshots. A JSON config holds the per-app design
system (theme), the storyboard (slides: role, layout, screens) and points at
per-locale copy. Each slide is laid out as HTML/CSS and screenshotted by
headless Chrome (Playwright), then checked automatically: size, alpha, text
overflow, safe area, text/UI overlap, contrast, font coverage (tofu), layout
variety and policy words. Results land in one run folder with contact sheets
and a QA report. Nothing is AI-generated: the generator only typesets and
composes the assets you give it.

Quick mode: pass screenshots instead of a .json config (plus `headers`) to get
a default storyboard. The config reference lives in the
`play-store-screenshots` agent skill (~/.claude/skills).
"""

import argparse
import base64
import copy
import hashlib
import html
import json
import math
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import urlparse


NAME = "App Store Promo Generator"
DESCRIPTION = "Config-driven, localised store screenshots and feature graphic from real app screens: per-app theme, varied layouts, headless-Chrome typesetting, automated QA and contact sheets."
CATEGORY = "Images"
INPUT_TYPES = "Promo config or screenshots (*.json *.png *.jpg *.jpeg *.webp)"

PYTHON_VERSION = "3.12"
DEPENDENCIES = ["pillow", "playwright"]

PARAMETERS = [
    {
        "name": "locales",
        "type": "str",
        "default": "",
        "description": "Comma-separated locales to render (empty = every locale in the config)",
    },
    {
        "name": "slides",
        "type": "str",
        "default": "",
        "description": "Comma-separated slide ids to render (empty = all slides)",
    },
    {
        "name": "devices",
        "type": "str",
        "default": "",
        "description": "Comma-separated canvases: phone, phone_landscape, tablet7, tablet10 (empty = config, else phone)",
    },
    {
        "name": "output_format",
        "type": "str",
        "default": "",
        "description": "png or jpg (empty = config, else png)",
    },
    {
        "name": "skip_feature_graphic",
        "type": "bool",
        "default": False,
        "description": "Do not render the feature graphic",
    },
    {
        "name": "export",
        "type": "bool",
        "default": False,
        "description": "Also copy the final assets into the config's export_dir",
    },
    {
        "name": "strict",
        "type": "bool",
        "default": False,
        "description": "Exit with an error when QA reports warnings (errors always fail)",
    },
    {
        "name": "keep_html",
        "type": "bool",
        "default": False,
        "description": "Keep the generated HTML next to the images for debugging",
    },
    {
        "name": "browser",
        "type": "str",
        "default": "chrome",
        "description": "chrome (installed Google Chrome), chromium (Playwright's own) or a browser executable path",
    },
    {
        "name": "headers",
        "type": "str",
        "default": "",
        "description": "Quick mode only: one headline per screenshot, separated by | or new lines",
    },
    {
        "name": "background_path",
        "type": "file_path",
        "default": "",
        "description": "Quick mode only: background image",
        "allowed_extensions": ["png", "jpg", "jpeg", "webp"],
    },
]


# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

CANVASES = {
    "phone": (1080, 1920),
    "phone_landscape": (1920, 1080),
    "tablet7": (1200, 1920),
    "tablet10": (1600, 2560),
}
FEATURE_SIZE = (1024, 500)
ASSET_HOST = "http://promo.local"
PLAY_LIMITS = {"min_side": 320, "max_side": 3840, "max_ratio": 2.0, "max_bytes": 8 * 1024 * 1024}

# Words Google Play's metadata policy rejects in store graphics (rankings,
# prices, calls to action). Warnings only: a human judges the context.
DEFAULT_BANNED = [
    r"#\s*1\b", r"\bno\.?\s*1\b", r"\bnumber one\b", r"\b(the|world'?s) best\b",
    r"\bbest\s+(app|game|quiz|trivia|puzzle|tool)\b", r"\btop\s+(rated|\d+|app|game)\b",
    r"\bfree\b", r"\bdownload now\b", r"\binstall now\b", r"\bplay now\b", r"\d+\s*%\s*off",
    r"\bsale\b", r"\bdiscount\b", r"\bapp of the year\b",
]

DEFAULT_THEME = {
    "colors": {
        "background": "#0E1016",
        "text": "#F7F5F0",
        "accent": "#FFD166",
        "muted": "#B9BBC6",
        "surface": "#1A1D26",
        "kicker": None,
    },
    "background": {
        "color": None,
        "gradient": None,
        "image": None,
        "image_mode": "cover",
        "image_opacity": 1.0,
        "continuous": False,
        "shift": 0.34,
        "grain": 0.0,
        "vignette": 0.0,
    },
    "fonts": {
        "headline": {
            "family": None,
            "files": [],
            "weight": 700,
            "style": "normal",
            "fallback": ["Avenir Next", "Helvetica Neue", "Arial", "sans-serif"],
            "by_locale": {},
            "letter_spacing": "-0.01em",
            "line_height": 1.06,
            "transform": "none",
        },
        "body": {
            "family": None,
            "files": [],
            "weight": 500,
            "style": "normal",
            "fallback": ["Avenir Next", "Helvetica Neue", "Arial", "sans-serif"],
            "by_locale": {},
            "letter_spacing": "0",
            "line_height": 1.3,
            "transform": "none",
        },
        "kicker": {
            "weight": 700,
            "letter_spacing": "0.16em",
            "transform": "uppercase",
        },
    },
    "text": {
        "position": "top",
        "align": "center",
        "top": 0.055,
        "area": 0.21,
        "width": 0.86,
        "headline_size": 9.4,
        "headline_min": 6.4,
        "sub_size": 3.7,
        "sub_min": 3.0,
        "kicker_size": 2.5,
        "max_lines": 3,
        "sub_max_lines": 2,
        "gap": 1.5,
        "shadow": None,
    },
    "device": {
        "style": "modern",
        "frame": "#0E0F12",
        "edge": "#4A4D56",
        "bezel": 0.012,
        "radius": 0.125,
        "shadow": "soft",
        "camera": True,
        "buttons": True,
        "status_bar": None,
        "halo": None,
    },
    "decor": [],
}

LAYOUTS = (
    "hero", "tilt", "ui_card", "full_bleed", "zoom", "duo", "trio",
    "before_after", "panorama", "custom",
)
FEATURE_LAYOUTS = ("feature_split", "feature_custom")


class PromoError(RuntimeError):
    pass


# --------------------------------------------------------------------------- #
# Small helpers
# --------------------------------------------------------------------------- #

def log(message):
    print(message, flush=True)


def slugify(text):
    value = re.sub(r"[^a-zA-Z0-9]+", "-", str(text or "")).strip("-").lower()
    return value or "app"


def deep_merge(base, override):
    if not isinstance(base, dict) or not isinstance(override, dict):
        return copy.deepcopy(override)
    merged = copy.deepcopy(base)
    for key, value in override.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
    return merged


def parse_color(value):
    """Return (r, g, b, a 0-1) from #hex, rgb()/rgba() or None."""
    if value is None:
        return None
    text = str(value).strip().lower()
    if text.startswith("#"):
        raw = text[1:]
        if len(raw) == 3:
            raw = "".join(ch * 2 for ch in raw)
        if len(raw) in (6, 8):
            channels = [int(raw[i:i + 2], 16) for i in range(0, len(raw), 2)]
            alpha = channels[3] / 255 if len(channels) == 4 else 1.0
            return channels[0], channels[1], channels[2], alpha
    match = re.match(r"rgba?\(([^)]+)\)", text)
    if match:
        parts = [p.strip() for p in match.group(1).replace("/", ",").split(",") if p.strip()]
        if len(parts) >= 3:
            rgb = [float(p) for p in parts[:3]]
            alpha = float(parts[3]) if len(parts) > 3 else 1.0
            return int(rgb[0]), int(rgb[1]), int(rgb[2]), alpha
    return None


def rgba(value, alpha):
    color = parse_color(value) or (0, 0, 0, 1)
    return f"rgba({color[0]},{color[1]},{color[2]},{alpha})"


def relative_luminance(rgb):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb[:3]
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast_ratio(l1, l2):
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def css_family_list(families):
    out = []
    generic = {"serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui"}
    for family in families:
        if not family:
            continue
        out.append(family if family in generic else f'"{family}"')
    return ", ".join(out) or "sans-serif"


def locale_lookup(mapping, locale):
    """Return mapping[locale] or mapping[language] or None."""
    if not mapping:
        return None
    if locale in mapping:
        return mapping[locale]
    language = locale.split("-")[0].split("_")[0]
    return mapping.get(language)


def markup_to_html(text):
    """`*accent*` -> <em>, newline -> <br>; everything else escaped."""
    if text is None:
        return ""
    escaped = html.escape(str(text))
    escaped = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", escaped)
    return escaped.replace("\\n", "<br>").replace("\n", "<br>")


def plain_text(text):
    return re.sub(r"\*", "", str(text or "")).replace("\\n", " ").replace("\n", " ")


def rect_intersection(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x1, y1 = max(ax, bx), max(ay, by)
    x2, y2 = min(ax + aw, bx + bw), min(ay + ah, by + bh)
    if x2 <= x1 or y2 <= y1:
        return 0.0
    return (x2 - x1) * (y2 - y1)


# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #

class Config:
    def __init__(self, data, base_dir, source):
        self.data = data
        self.base = Path(base_dir)
        self.source = source
        app = data.get("app") or {}
        self.app_name = app.get("name") or "App"
        self.slug = app.get("slug") or slugify(self.app_name)
        self.category = (app.get("category") or "").lower()
        self.theme = deep_merge(DEFAULT_THEME, data.get("theme") or {})
        kicker_font = deep_merge(self.theme["fonts"]["body"], self.theme["fonts"].get("kicker") or {})
        self.theme["fonts"]["kicker"] = kicker_font
        self.slides = data.get("slides") or []
        self.feature = data.get("feature_graphic")
        self.output = data.get("output") or {}
        self.qa = data.get("qa") or {}
        self.fallback_locale = data.get("fallback_locale")
        self.screens = data.get("screens") or {}
        self.screens_dir = self.path(data.get("screens_dir") or "screens")
        self.export_dir = self.path(data["export_dir"]) if data.get("export_dir") else None
        self.copy = self._load_copy(data)
        self.locales = list(data.get("locales") or self.copy.keys())
        if not self.locales:
            raise PromoError("No locales: set `locales` or provide copy files.")
        self._validate()

    def path(self, value):
        if value is None:
            return None
        candidate = Path(os.path.expanduser(str(value)))
        return candidate if candidate.is_absolute() else (self.base / candidate)

    def _load_copy(self, data):
        copy_data = {}
        inline = data.get("copy")
        if isinstance(inline, dict):
            for locale, entries in inline.items():
                copy_data[locale] = entries
        copy_dir = data.get("copy_dir")
        if copy_dir:
            folder = self.path(copy_dir)
            if not folder.is_dir():
                raise PromoError(f"copy_dir not found: {folder}")
            for file in sorted(folder.glob("*.json")):
                with open(file, encoding="utf-8") as handle:
                    copy_data[file.stem] = deep_merge(copy_data.get(file.stem, {}), json.load(handle))
        return copy_data

    def _validate(self):
        ids = set()
        for index, slide in enumerate(self.slides):
            slide_id = slide.get("id")
            if not slide_id:
                raise PromoError(f"Slide #{index + 1} has no id.")
            if slide_id in ids:
                raise PromoError(f"Duplicate slide id: {slide_id}")
            ids.add(slide_id)
            layout = slide.get("layout", "hero")
            if layout not in LAYOUTS:
                raise PromoError(f"Slide {slide_id}: unknown layout '{layout}'. Use one of {', '.join(LAYOUTS)}.")
        if self.feature:
            layout = self.feature.get("layout", "feature_split")
            if layout not in FEATURE_LAYOUTS:
                raise PromoError(f"feature_graphic: unknown layout '{layout}'. Use one of {', '.join(FEATURE_LAYOUTS)}.")

    def copy_for(self, locale, key, report):
        entries = self.copy.get(locale) or {}
        value = entries.get(key)
        if value is None and self.fallback_locale and locale != self.fallback_locale:
            value = (self.copy.get(self.fallback_locale) or {}).get(key)
            if value is not None:
                report.warn(locale, key, f"copy missing for {locale}; used {self.fallback_locale}")
        if value is None:
            report.error(locale, key, f"no copy for slide '{key}' in {locale}")
            return {}
        return value

    def screen_entry(self, key):
        entry = self.screens.get(key, key)
        if isinstance(entry, str):
            return {"file": entry, "crop": None}
        return {"file": entry.get("file") or key, "crop": entry.get("crop")}

    def resolve_screen(self, key, locale, report, slide_id):
        entry = self.screen_entry(key)
        file = entry["file"]
        candidates = []
        direct = Path(os.path.expanduser(file))
        if direct.is_absolute():
            candidates.append(("direct", direct))
        else:
            if not Path(file).suffix:
                names = [f"{file}.png", f"{file}.jpg", f"{file}.jpeg", f"{file}.webp"]
            else:
                names = [file]
            for name in names:
                candidates.append(("locale", self.screens_dir / locale / name))
            if self.fallback_locale:
                for name in names:
                    candidates.append(("fallback", self.screens_dir / self.fallback_locale / name))
            for name in names:
                candidates.append(("shared", self.screens_dir / name))
                candidates.append(("shared", self.base / name))
        for kind, candidate in candidates:
            if candidate.is_file():
                if kind == "fallback":
                    report.warn(locale, slide_id, f"screen '{key}' not localised; used {self.fallback_locale}")
                return candidate, entry["crop"]
        report.error(locale, slide_id, f"screen '{key}' not found (looked in {self.screens_dir}/{locale}/)")
        return None, None


def quick_config(image_paths, headers, background_path):
    if not image_paths:
        raise PromoError("Quick mode needs at least one screenshot.")
    items = [part.strip() for part in re.split(r"[\n|]+", headers or "") if part.strip()]
    layouts = ["tilt", "hero", "ui_card", "zoom", "hero", "full_bleed", "hero", "ui_card"]
    slides, copy_entries, screens = [], {}, {}
    for index, path in enumerate(image_paths[:8]):
        key = f"screen{index + 1}"
        screens[key] = str(Path(path).resolve())
        layout = layouts[index % len(layouts)]
        slide = {"id": f"slide{index + 1}", "layout": layout, "screen": key}
        if layout == "zoom":
            slide["region"] = [0.06, 0.18, 0.88, 0.34]
        slides.append(slide)
        headline = items[index] if index < len(items) else (items[-1] if items else f"Slide {index + 1}")
        copy_entries[slide["id"]] = {"headline": headline}
    theme = {}
    if background_path:
        theme["background"] = {"image": str(Path(background_path).resolve()), "continuous": True}
    data = {
        "app": {"name": "Quick promo"},
        "locales": ["default"],
        "screens": screens,
        "slides": slides,
        "copy": {"default": copy_entries},
        "theme": theme,
    }
    return Config(data, Path.cwd(), "quick mode")


def load_config(path):
    with open(path, encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            raise PromoError(f"{path}: invalid JSON ({exc})") from exc
    return Config(data, Path(path).resolve().parent, str(path))


# --------------------------------------------------------------------------- #
# QA report
# --------------------------------------------------------------------------- #

class Report:
    def __init__(self):
        self.items = []
        self.images = []

    def _add(self, level, locale, slide, message, device=None):
        self.items.append({"level": level, "locale": locale, "slide": slide, "device": device, "message": message})

    def error(self, locale, slide, message, device=None):
        self._add("error", locale, slide, message, device)

    def warn(self, locale, slide, message, device=None):
        self._add("warning", locale, slide, message, device)

    def info(self, locale, slide, message, device=None):
        self._add("info", locale, slide, message, device)

    def count(self, level):
        return sum(1 for item in self.items if item["level"] == level)

    def for_image(self, locale, slide, device):
        return [i for i in self.items if i["locale"] == locale and i["slide"] == slide and i["device"] in (device, None)]


# --------------------------------------------------------------------------- #
# Asset preparation (Pillow)
# --------------------------------------------------------------------------- #

class Assets:
    """Prepared files served to the browser through a route handler."""

    def __init__(self, work_dir):
        self.work = Path(work_dir)
        self.work.mkdir(parents=True, exist_ok=True)
        self.routes = {}
        self._cache = {}

    def url_for(self, path):
        path = Path(path)
        digest = hashlib.sha1(str(path.resolve()).encode()).hexdigest()[:12]
        key = f"/a/{digest}/{path.name}"
        self.routes[key] = str(path)
        return ASSET_HOST + key

    def register_bytes(self, name, data, content_type):
        key = f"/b/{name}"
        self.routes[key] = (data, content_type)
        return ASSET_HOST + key

    def screen(self, path, crop):
        """Crop (fractions l,t,r,b) and return (url, width, height)."""
        from PIL import Image

        path = Path(path)
        crop_key = tuple(crop) if crop else None
        cache_key = (str(path.resolve()), path.stat().st_mtime, crop_key)
        if cache_key in self._cache:
            return self._cache[cache_key]
        with Image.open(path) as image:
            image.load()
            if crop:
                left, top, right, bottom = crop
                width, height = image.size
                box = (
                    int(round(left * width)), int(round(top * height)),
                    int(round(right * width)), int(round(bottom * height)),
                )
                image = image.crop(box)
            if image.mode not in ("RGB", "RGBA"):
                image = image.convert("RGBA" if "A" in image.mode else "RGB")
            size = image.size
            if crop:
                digest = hashlib.sha1(repr(cache_key).encode()).hexdigest()[:12]
                out = self.work / f"screen_{digest}.png"
                image.save(out)
                target = out
            else:
                target = path
        result = (self.url_for(target), size[0], size[1])
        self._cache[cache_key] = result
        return result

    def image_size(self, path):
        from PIL import Image

        with Image.open(path) as image:
            return image.size

    def background_strip(self, path, height, width):
        """Mirror-tile a background image into a strip of at least `width`."""
        from PIL import Image

        key = ("strip", str(Path(path).resolve()), height, width)
        if key in self._cache:
            return self._cache[key]
        with Image.open(path) as image:
            base = image.convert("RGB")
        scale = height / base.height
        base = base.resize((max(1, int(round(base.width * scale))), height), Image.LANCZOS)
        tiles, total, flipped = [], 0, False
        while total < width:
            tile = base.transpose(Image.FLIP_LEFT_RIGHT) if flipped else base
            tiles.append(tile)
            total += tile.width
            flipped = not flipped
        strip = Image.new("RGB", (total, height))
        offset = 0
        for tile in tiles:
            strip.paste(tile, (offset, 0))
            offset += tile.width
        digest = hashlib.sha1(repr(key).encode()).hexdigest()[:12]
        out = self.work / f"strip_{digest}.jpg"
        strip.save(out, quality=94)
        result = self.url_for(out)
        self._cache[key] = result
        return result


GRAIN_SVG = (
    "<svg xmlns='http://www.w3.org/2000/svg' width='320' height='320'>"
    "<filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3' stitchTiles='stitch'/>"
    "<feColorMatrix type='saturate' values='0'/></filter>"
    "<rect width='100%' height='100%' filter='url(#n)'/></svg>"
)


# --------------------------------------------------------------------------- #
# Layout: presets -> layers
# --------------------------------------------------------------------------- #

PRESET_DEFAULTS = {
    "hero": {"h": 1.02, "y": 0.035, "x": 0.5, "rotate": 0},
    "tilt": {"h": 1.0, "y": 0.06, "x": 0.53, "rotate": -8, "tilt_x": 8, "tilt_y": -16, "perspective": 2600},
    "ui_card": {"w": 0.86, "y": 0.03, "x": 0.5, "radius": 0.05},
    "full_bleed": {"focus": 0.5, "scrim": 0.42},
    "zoom": {"h": 0.86, "x": 0.35, "y": 0.06, "zoom_w": 0.6, "zoom_x": 0.66, "zoom_cy": 0.6, "rotate": -3, "zoom_rotate": 2},
    "duo": {"back_h": 0.8, "back_x": 0.31, "back_y": 0.14, "back_rotate": -7,
            "front_h": 0.92, "front_x": 0.64, "front_y": 0.04, "front_rotate": 4},
    "trio": {"center_h": 0.92, "side_h": 0.74, "side_x": 0.2, "side_y": 0.17, "side_rotate": 8, "y": 0.04},
    "before_after": {"h": 0.8, "y": 0.13, "gap": 0.46},
    "panorama": {"h": 1.1, "x": 0.5, "y": 0.0, "rotate": -12, "tilt_x": 6, "tilt_y": 14, "perspective": 3000},
    "custom": {},
    "feature_split": {"text_w": 0.44, "h": 1.08, "x": 0.56, "y": 0.12, "rotate": -10, "tilt_x": 6, "tilt_y": -14,
                      "second_h": 0.9, "second_x": 0.92, "second_y": 0.24, "second_rotate": 9},
    "feature_custom": {},
}


def slide_screens(slide):
    screens = slide.get("screens")
    if screens:
        return list(screens)
    if slide.get("screen"):
        return [slide["screen"]]
    return []


def preset_layers(layout, slide, params):
    """Return layers in stage coordinates (x centre / y top / h or w as fractions)."""
    p = deep_merge(PRESET_DEFAULTS.get(layout, {}), params or {})
    screens = slide_screens(slide)
    s0 = screens[0] if screens else None
    s1 = screens[1] if len(screens) > 1 else s0
    s2 = screens[2] if len(screens) > 2 else s1
    device = slide.get("device") or {}
    bleed = slide.get("bleed", True)

    def dev(screen, **kw):
        layer = {"type": "device", "screen": screen, "bleed": bleed}
        layer.update(device)
        layer.update(kw)
        return layer

    if layout == "hero":
        h = p["h"] if bleed else min(p["h"], 0.93)
        return [dev(s0, h=h, x=p["x"], y=p["y"], rotate=p["rotate"],
                    tilt_x=p.get("tilt_x", 0), tilt_y=p.get("tilt_y", 0), perspective=p.get("perspective", 2600))]
    if layout == "tilt":
        return [dev(s0, h=p["h"], x=p["x"], y=p["y"], rotate=p["rotate"], tilt_x=p["tilt_x"],
                    tilt_y=p["tilt_y"], perspective=p["perspective"], bleed=True)]
    if layout == "ui_card":
        return [{"type": "card", "screen": s0, "w": p["w"], "x": p["x"], "y": p["y"],
                 "radius": p["radius"], "bleed": True, "shift": p.get("shift", 0.0)}]
    if layout == "full_bleed":
        return [{"type": "cover", "screen": s0, "focus": p["focus"], "scrim": p["scrim"], "bleed": True}]
    if layout == "zoom":
        region = slide.get("region") or [0.05, 0.2, 0.9, 0.3]
        return [
            dev(s0, h=p["h"], x=p["x"], y=p["y"], rotate=p["rotate"], mark=region, z=1, bleed=True),
            {"type": "zoom", "screen": s0, "region": region, "w": p["zoom_w"], "x": p["zoom_x"],
             "cy": p["zoom_cy"], "rotate": p["zoom_rotate"], "z": 3},
        ]
    if layout == "duo":
        return [
            dev(s1, h=p["back_h"], x=p["back_x"], y=p["back_y"], rotate=p["back_rotate"], dim=0.18, z=1),
            dev(s0, h=p["front_h"], x=p["front_x"], y=p["front_y"], rotate=p["front_rotate"], z=2),
        ]
    if layout == "trio":
        return [
            dev(s1, h=p["side_h"], x=p["side_x"], y=p["side_y"], rotate=-p["side_rotate"], dim=0.2, z=1),
            dev(s2, h=p["side_h"], x=1 - p["side_x"], y=p["side_y"], rotate=p["side_rotate"], dim=0.2, z=1),
            dev(s0, h=p["center_h"], x=0.5, y=p["y"], z=2),
        ]
    if layout == "before_after":
        half = p["gap"] / 2
        return [
            dev(s0, h=p["h"], x=0.5 - half, y=p["y"], label_index=0, bleed=False),
            dev(s1, h=p["h"], x=0.5 + half, y=p["y"], label_index=1, bleed=False),
            {"type": "arrow", "x": 0.5, "cy": p["y"] + p["h"] / 2, "w": 0.09, "z": 3},
        ]
    if layout == "panorama":
        return [dev(s0, h=p["h"], x=p["x"], y=p["y"], rotate=p["rotate"], tilt_x=p["tilt_x"],
                    tilt_y=p["tilt_y"], perspective=p["perspective"], bleed=True)]
    if layout == "feature_split":
        layers = [dev(s0, h=p["h"], x=p["x"], y=p["y"], rotate=p["rotate"], tilt_x=p["tilt_x"],
                      tilt_y=p["tilt_y"], perspective=2400, bleed=True, z=2)]
        if len(screens) > 1:
            layers.insert(0, dev(screens[1], h=p["second_h"], x=p["second_x"], y=p["second_y"],
                                 rotate=p["second_rotate"], dim=0.15, bleed=True, z=1))
        return layers
    return []


# --------------------------------------------------------------------------- #
# HTML building
# --------------------------------------------------------------------------- #

class SlideBuild:
    """Everything needed to render one canvas (one slide, a panorama or the feature graphic)."""

    def __init__(self, cfg, assets, report, locale, device_name, width, height, parts, kind="slide"):
        self.cfg = cfg
        self.assets = assets
        self.report = report
        self.locale = locale
        self.device_name = device_name
        self.W = width
        self.H = height
        self.parts = parts  # list of (slide_id, x_offset) for split outputs
        self.kind = kind
        self.theme = cfg.theme
        self.u = min(width / max(1, len(parts)), height) / 100.0
        self.layer_html = []
        self.layer_count = 0

    # ---- fonts -------------------------------------------------------------
    def font_faces(self):
        faces = []
        for role in ("headline", "body"):
            font = self.theme["fonts"][role]
            family = font.get("family")
            for index, file in enumerate(font.get("files") or []):
                path = self.cfg.path(file)
                if not path.is_file():
                    self.report.error(self.locale, "theme", f"font file not found: {path}")
                    continue
                url = self.assets.url_for(path)
                weight = font.get("weight", 400)
                style = font.get("style", "normal")
                faces.append(
                    f'@font-face{{font-family:"{family}";src:url("{url}");'
                    f"font-weight:{weight};font-style:{style};font-display:block;}}"
                )
        return "\n".join(faces)

    def family_for(self, role):
        font = self.theme["fonts"][role] if role != "kicker" else self.theme["fonts"]["kicker"]
        override = locale_lookup(font.get("by_locale") or {}, self.locale)
        if override:
            return list(override)
        base = [font.get("family")] if font.get("family") else []
        return base + list(font.get("fallback") or [])

    # ---- background --------------------------------------------------------
    def background_html(self, offset, strip_width):
        bg = self.theme["background"]
        colors = self.theme["colors"]
        base_color = bg.get("color") or colors["background"]
        out = []
        if bg.get("image"):
            image_path = self.cfg.path(bg["image"])
            if not image_path.is_file():
                self.report.error(self.locale, "theme", f"background image not found: {image_path}")
            elif bg.get("continuous") or bg.get("image_mode") == "strip":
                url = self.assets.background_strip(image_path, self.H, int(strip_width))
                out.append(
                    f'<img class="bg-img" src="{url}" style="left:{-offset:.1f}px;top:0;height:{self.H}px;'
                    f'width:auto;opacity:{bg.get("image_opacity", 1)}">'
                )
            else:
                url = self.assets.url_for(image_path)
                out.append(
                    f'<img class="bg-img" src="{url}" style="left:0;top:0;width:{self.W}px;height:{self.H}px;'
                    f'object-fit:cover;opacity:{bg.get("image_opacity", 1)}">'
                )
        if bg.get("gradient"):
            if bg.get("continuous"):
                out.append(
                    f'<div class="bg-grad" style="left:{-offset:.1f}px;width:{strip_width:.1f}px;'
                    f'background:{bg["gradient"]}"></div>'
                )
            else:
                out.append(f'<div class="bg-grad" style="left:0;width:{self.W}px;background:{bg["gradient"]}"></div>')
        return base_color, "\n".join(out)

    def decor_html(self, offset, strip_width, front):
        out = []
        for item in self.theme.get("decor") or []:
            if bool(item.get("front")) != front:
                continue
            if item.get("only") and self.kind not in item["only"]:
                continue
            kind = item.get("type", "glow")
            in_strip = bool(item.get("strip")) and self.kind == "slide"
            span_w = strip_width if in_strip else self.W
            cx = item.get("x", 0.5) * span_w - (offset if in_strip else 0)
            cy = item.get("y", 0.5) * self.H
            opacity = item.get("opacity", 1)
            blend = item.get("blend", "normal")
            if kind == "glow":
                radius = item.get("r", 0.4) * self.u * 100 * (1 if self.kind == "slide" else 1.2)
                color = item.get("color", "#ffffff")
                out.append(
                    f'<div class="decor" style="left:{cx - radius:.1f}px;top:{cy - radius:.1f}px;'
                    f"width:{2 * radius:.1f}px;height:{2 * radius:.1f}px;opacity:{opacity};mix-blend-mode:{blend};"
                    f'background:radial-gradient(circle, {rgba(color, 1)} 0%, {rgba(color, 0.35)} 32%, {rgba(color, 0)} 70%)"></div>'
                )
            elif kind in ("svg", "image"):
                width = item.get("w", 0.3) * self.W
                rotate = item.get("rotate", 0)
                if item.get("svg"):
                    inner = item["svg"]
                else:
                    path = self.cfg.path(item.get("file", ""))
                    if not path or not path.is_file():
                        self.report.error(self.locale, "theme", f"decor file not found: {path}")
                        continue
                    inner = f'<img src="{self.assets.url_for(path)}" style="width:100%;height:auto;display:block">'
                out.append(
                    f'<div class="decor" style="left:{cx - width / 2:.1f}px;top:{cy:.1f}px;width:{width:.1f}px;'
                    f'opacity:{opacity};mix-blend-mode:{blend};transform:rotate({rotate}deg)">{inner}</div>'
                )
        return "\n".join(out)

    # ---- product layers ------------------------------------------------------
    def stage_for(self, text_cfg, x0, total_w, part_w):
        """Product area: below/above the text block (portrait) or beside it (landscape/feature).

        `total_w` is the whole canvas (two parts for a panorama); `part_w` one output image,
        which decides the orientation."""
        landscape = part_w > self.H
        if self.kind == "feature":
            text_w = text_cfg.get("feature_text_w", 0.44)
            return (x0 + total_w * text_w, 0, total_w * (1 - text_w), self.H)
        if landscape:
            text_w = text_cfg.get("landscape_text_w", 0.42)
            return (x0 + part_w * text_w, 0, total_w - part_w * text_w, self.H)
        top = text_cfg["top"] * self.H
        area = text_cfg["area"] * self.H
        if text_cfg["position"] == "bottom":
            return (x0, 0, total_w, self.H - top - area)
        if text_cfg["position"] == "none":
            return (x0, 0, total_w, self.H)
        return (x0, top + area, total_w, self.H - top - area)

    def screen_info(self, key, slide_id):
        path, crop = self.cfg.resolve_screen(key, self.locale, self.report, slide_id)
        if not path:
            return None
        url, width, height = self.assets.screen(path, crop)
        return {"url": url, "w": width, "h": height, "aspect": width / height, "path": str(path)}

    def add_layer(self, layer, stage, slide_id, labels):
        kind = layer.get("type", "device")
        sx, sy, sw, sh = stage
        z = layer.get("z", 2)
        self.layer_count += 1
        lid = f"{slide_id}:{kind}{self.layer_count}"
        dev_theme = self.theme["device"]
        colors = self.theme["colors"]

        if kind == "device":
            info = self.screen_info(layer.get("screen"), slide_id)
            if not info:
                return
            style = layer.get("style", dev_theme["style"])
            k = dev_theme["bezel"] if style == "modern" else 0.0
            if layer.get("w") and not layer.get("h"):
                outer_w = layer["w"] * sw
                outer_h = outer_w / ((1 - 2 * k) * info["aspect"] + 2 * k)
            else:
                outer_h = layer.get("h", 0.9) * sh
            bezel = k * outer_h
            screen_h = outer_h - 2 * bezel
            screen_w = screen_h * info["aspect"]
            outer_w = screen_w + 2 * bezel
            left = sx + layer.get("x", 0.5) * sw - outer_w / 2
            top = sy + (layer["cy"] * sh - outer_h / 2 if "cy" in layer else layer.get("y", 0.05) * sh)
            radius = dev_theme["radius"] * outer_w
            inner_radius = max(0.0, radius - bezel)
            transform = []
            if layer.get("tilt_x") or layer.get("tilt_y"):
                transform.append(f"perspective({layer.get('perspective', 2600)}px)")
                transform.append(f"rotateX({layer.get('tilt_x', 0)}deg) rotateY({layer.get('tilt_y', 0)}deg)")
            if layer.get("rotate"):
                transform.append(f"rotate({layer['rotate']}deg)")
            transform_css = " ".join(transform) or "none"
            shadow = layer.get("shadow", dev_theme["shadow"])
            shadow_css = {
                "soft": f"0 {0.9 * self.u:.1f}px {2.2 * self.u:.1f}px rgba(0,0,0,.28), 0 {3.4 * self.u:.1f}px {7 * self.u:.1f}px rgba(0,0,0,.36)",
                "strong": f"0 {1.2 * self.u:.1f}px {3 * self.u:.1f}px rgba(0,0,0,.4), 0 {5 * self.u:.1f}px {10 * self.u:.1f}px rgba(0,0,0,.5)",
                "none": "none",
            }.get(shadow, shadow)
            if dev_theme.get("halo") and shadow_css != "none":
                # A thin light rim plus a coloured glow separates dark frames from dark backgrounds.
                shadow_css += (f", 0 0 0 {max(1.0, 0.16 * self.u):.1f}px rgba(255,255,255,.12),"
                               f" 0 0 {4.5 * self.u:.1f}px {dev_theme['halo']}")
            frame = dev_theme["frame"]
            edge = dev_theme["edge"]
            parts = [
                f'<div class="layer device" data-qa-layer="{lid}" data-kind="device" data-bleed="{1 if layer.get("bleed") else 0}" '
                f'style="left:{left:.1f}px;top:{top:.1f}px;width:{outer_w:.1f}px;height:{outer_h:.1f}px;'
                f'z-index:{z};transform:{transform_css}">'
            ]
            if style == "modern":
                parts.append(
                    f'<div class="frame" style="border-radius:{radius:.1f}px;box-shadow:{shadow_css};'
                    f"background:linear-gradient(140deg,{edge} 0%,{frame} 9%,{frame} 88%,{edge} 100%)\"></div>"
                    f'<div class="frame-rim" style="border-radius:{radius:.1f}px;'
                    f'box-shadow:inset 0 0 0 {max(1.0, 0.18 * self.u):.1f}px rgba(255,255,255,.10)"></div>'
                )
                if dev_theme.get("buttons"):
                    bw = max(2.0, 0.009 * outer_w)
                    parts.append(
                        f'<div class="btn" style="right:{-bw * 0.7:.1f}px;top:{0.2 * outer_h:.1f}px;width:{bw:.1f}px;'
                        f'height:{0.075 * outer_h:.1f}px;background:{edge}"></div>'
                        f'<div class="btn" style="right:{-bw * 0.7:.1f}px;top:{0.31 * outer_h:.1f}px;width:{bw:.1f}px;'
                        f'height:{0.045 * outer_h:.1f}px;background:{edge}"></div>'
                    )
            else:
                parts.append(f'<div class="frame" style="border-radius:{radius:.1f}px;box-shadow:{shadow_css};background:transparent"></div>')
            dim = layer.get("dim", 0)
            parts.append(
                f'<div class="screen" style="left:{bezel:.1f}px;top:{bezel:.1f}px;width:{screen_w:.1f}px;'
                f'height:{screen_h:.1f}px;border-radius:{inner_radius:.1f}px">'
                f'<img src="{info["url"]}" style="width:100%;height:100%;object-fit:cover;object-position:50% 0%">'
            )
            status = dev_theme.get("status_bar")
            if status and style == "modern":
                parts.append(self.status_bar_html(screen_w, status))
            if dev_theme.get("camera") and style == "modern":
                cam = 0.026 * screen_w
                parts.append(
                    f'<div class="camera" style="top:{0.012 * screen_h:.1f}px;left:{screen_w / 2 - cam / 2:.1f}px;'
                    f'width:{cam:.1f}px;height:{cam:.1f}px"></div>'
                )
            if layer.get("mark"):
                mx, my, mw, mh = layer["mark"]
                parts.append(
                    f'<div class="mark" style="left:{mx * 100:.2f}%;top:{my * 100:.2f}%;width:{mw * 100:.2f}%;'
                    f'height:{mh * 100:.2f}%;border:{max(2.0, 0.42 * self.u):.1f}px solid {colors["accent"]};'
                    f'border-radius:{1.2 * self.u:.1f}px;box-shadow:0 0 {1.6 * self.u:.1f}px {rgba(colors["accent"], 0.55)}"></div>'
                )
            if dim:
                parts.append(f'<div class="dim" style="background:rgba(0,0,0,{dim})"></div>')
            parts.append("</div>")
            if labels is not None and layer.get("label_index") is not None:
                label_list = labels or []
                index = layer["label_index"]
                if index < len(label_list):
                    parts.append(
                        f'<div class="chip qa-text" style="top:{-5.2 * self.u:.1f}px;font-size:{2.6 * self.u:.1f}px">'
                        f"{markup_to_html(label_list[index])}</div>"
                    )
            parts.append("</div>")
            self.layer_html.append("".join(parts))
            return

        if kind == "card":
            info = self.screen_info(layer.get("screen"), slide_id)
            if not info:
                return
            width = layer.get("w", 0.86) * sw
            height = width / info["aspect"]
            left = sx + layer.get("x", 0.5) * sw - width / 2
            # `shift` scrolls the screen inside the card (a fraction of the screen's height
            # is cut from the top) to show a lower part; the card itself stays put.
            shift = max(0.0, min(0.9, layer.get("shift", 0.0)))
            top = sy + layer.get("y", 0.03) * sh
            card_h = height * (1 - shift)
            radius = layer.get("radius", 0.05) * width
            self.layer_html.append(
                f'<div class="layer card" data-qa-layer="{lid}" data-kind="card" data-bleed="1" '
                f'style="left:{left:.1f}px;top:{top:.1f}px;width:{width:.1f}px;height:{card_h:.1f}px;z-index:{z};'
                f'border-radius:{radius:.1f}px;box-shadow:0 {2 * self.u:.1f}px {6 * self.u:.1f}px rgba(0,0,0,.45);'
                f'outline:{max(1.0, 0.2 * self.u):.1f}px solid rgba(255,255,255,.08)">'
                f'<div class="card-inner" style="border-radius:{radius:.1f}px">'
                f'<img src="{info["url"]}" style="position:absolute;left:0;top:{-shift * height:.1f}px;'
                f'width:100%;height:{height:.1f}px;max-width:none">'
                f"</div></div>"
            )
            return

        if kind == "cover":
            info = self.screen_info(layer.get("screen"), slide_id)
            if not info:
                return
            part_left = layer.get("_part_left", 0)
            part_w = layer.get("_part_w", self.W)
            focus = layer.get("focus", 0.5)
            self.layer_html.append(
                f'<div class="layer cover" data-qa-layer="{lid}" data-kind="cover" data-bleed="1" data-text-over="1" '
                f'style="left:{part_left:.1f}px;top:0;width:{part_w:.1f}px;height:{self.H}px;z-index:{z}">'
                f'<div class="card-inner"><img src="{info["url"]}" style="width:100%;height:100%;object-fit:cover;'
                f'object-position:50% {focus * 100:.0f}%"></div></div>'
            )
            scrim = layer.get("scrim", 0.42)
            base = self.theme["colors"]["background"]
            if part_w > self.H:  # landscape: text sits on the left, so the scrim runs left to right
                self.layer_html.append(
                    f'<div class="layer scrim" style="left:{part_left:.1f}px;top:0;width:{max(scrim, 0.55) * part_w:.1f}px;'
                    f'height:{self.H}px;z-index:{z + 1};background:linear-gradient(to right,{rgba(base, 0.96)} 0%,'
                    f'{rgba(base, 0.82)} 60%,{rgba(base, 0)} 100%)"></div>'
                )
                return
            self.layer_html.append(
                f'<div class="layer scrim" style="left:{part_left:.1f}px;top:0;width:{part_w:.1f}px;height:{scrim * self.H:.1f}px;'
                f'z-index:{z + 1};background:linear-gradient(to bottom,{rgba(base, 0.96)} 0%,{rgba(base, 0.82)} 55%,{rgba(base, 0)} 100%)"></div>'
            )
            return

        if kind == "zoom":
            info = self.screen_info(layer.get("screen"), slide_id)
            if not info:
                return
            rx, ry, rw, rh = layer.get("region") or [0, 0, 1, 0.3]
            width = layer.get("w", 0.6) * sw
            height = width * (rh * info["h"]) / (rw * info["w"])
            cx = sx + layer.get("x", 0.66) * sw
            cy = sy + layer.get("cy", 0.6) * sh
            left, top = cx - width / 2, cy - height / 2
            radius = 2.2 * self.u
            border = max(2.0, 0.55 * self.u)
            self.layer_html.append(
                f'<div class="layer zoom" data-qa-layer="{lid}" data-kind="zoom" data-bleed="0" '
                f'style="left:{left:.1f}px;top:{top:.1f}px;width:{width:.1f}px;height:{height:.1f}px;z-index:{z};'
                f'transform:rotate({layer.get("rotate", 0)}deg);border-radius:{radius:.1f}px;'
                f'box-shadow:0 0 0 {border:.1f}px {colors["accent"]},0 {2.4 * self.u:.1f}px {7 * self.u:.1f}px rgba(0,0,0,.55)">'
                f'<div class="zoom-inner" style="border-radius:{radius:.1f}px">'
                f'<img src="{info["url"]}" style="position:absolute;width:{100 / rw:.3f}%;height:{100 / rh:.3f}%;'
                f'left:{-rx / rw * 100:.3f}%;top:{-ry / rh * 100:.3f}%;max-width:none"></div></div>'
            )
            return

        if kind == "image":
            path = self.cfg.path(layer.get("file", ""))
            if not path or not path.is_file():
                self.report.error(self.locale, slide_id, f"image layer not found: {path}")
                return
            width = layer.get("w", 0.4) * sw
            iw, ih = self.assets.image_size(path)
            height = width * ih / iw
            left = sx + layer.get("x", 0.5) * sw - width / 2
            top = sy + (layer["cy"] * sh - height / 2 if "cy" in layer else layer.get("y", 0.1) * sh)
            shadow = layer.get("shadow", "soft")
            filt = "" if shadow == "none" else f"filter:drop-shadow(0 {1.4 * self.u:.1f}px {3 * self.u:.1f}px rgba(0,0,0,.45));"
            radius = layer.get("radius", 0) * width
            self.layer_html.append(
                f'<div class="layer image" data-qa-layer="{lid}" data-kind="image" data-bleed="{1 if layer.get("bleed") else 0}" '
                f'style="left:{left:.1f}px;top:{top:.1f}px;width:{width:.1f}px;height:{height:.1f}px;z-index:{z};'
                f'transform:rotate({layer.get("rotate", 0)}deg);{filt}">'
                f'<img src="{self.assets.url_for(path)}" style="width:100%;height:100%;border-radius:{radius:.1f}px"></div>'
            )
            return

        if kind == "arrow":
            width = layer.get("w", 0.09) * sw
            left = sx + layer.get("x", 0.5) * sw - width / 2
            top = sy + layer.get("cy", 0.5) * sh - width / 2
            color = colors["accent"]
            self.layer_html.append(
                f'<div class="layer" style="left:{left:.1f}px;top:{top:.1f}px;width:{width:.1f}px;height:{width:.1f}px;z-index:{z}">'
                f'<svg viewBox="0 0 48 48" width="100%" height="100%"><circle cx="24" cy="24" r="23" fill="{colors["surface"]}"/>'
                f'<path d="M17 24h14M25 17l7 7-7 7" stroke="{color}" stroke-width="3.6" fill="none" '
                f'stroke-linecap="round" stroke-linejoin="round"/></svg></div>'
            )
            return

        self.report.error(self.locale, slide_id, f"unknown layer type '{kind}'")

    def status_bar_html(self, screen_w, status):
        if not isinstance(status, dict):
            status = {}
        light = status.get("light", True)
        color = "#FFFFFF" if light else "#111111"
        time_text = html.escape(str(status.get("time", "9:41")))
        bar_h = 0.075 * screen_w
        font = 0.034 * screen_w
        icon_h = 0.03 * screen_w
        icons = (
            f'<svg viewBox="0 0 70 16" height="{icon_h:.1f}" fill="{color}">'
            '<path d="M1 14h3v-3H1zM6 14h3V8H6zM11 14h3V5h-3zM16 14h3V2h-3z"/>'
            '<path d="M30 14.5l-8-8a11.5 11.5 0 0116 0z"/>'
            '<rect x="44" y="3" width="22" height="11" rx="2.5" fill="none" stroke="' + color + '" stroke-width="1.6"/>'
            '<rect x="46.5" y="5.5" width="15" height="6" rx="1"/><rect x="67" y="6.5" width="2" height="4" rx="1"/></svg>'
        )
        return (
            f'<div class="statusbar" style="height:{bar_h:.1f}px;padding:0 {0.07 * screen_w:.1f}px;'
            f'font-size:{font:.1f}px;color:{color}"><span>{time_text}</span><span>{icons}</span></div>'
        )

    # ---- text --------------------------------------------------------------
    def text_html(self, text_cfg, copy_entry, part_left, part_w, qa_id, labels_only=False):
        if labels_only or not copy_entry:
            return ""
        colors = self.theme["colors"]
        u = self.u
        align = text_cfg.get("align", "center")
        landscape = part_w > self.H and self.kind != "feature"
        if self.kind == "feature":
            width = part_w * text_cfg.get("feature_text_w", 0.44) - 2 * 5 * u
            left = part_left + 6 * u
            top_css = f"top:{self.H / 2:.1f}px;transform:translateY(-50%)"
            max_h = self.H * 0.84
            align = "left"
        elif landscape:
            width = part_w * text_cfg.get("landscape_text_w", 0.42) - 8 * u
            left = part_left + 5 * u
            top_css = f"top:{self.H / 2:.1f}px;transform:translateY(-50%)"
            max_h = self.H * 0.8
            align = "left" if align == "center" else align
        else:
            width = part_w * text_cfg["width"]
            left = part_left + (part_w - width) / 2
            if text_cfg["position"] == "bottom":
                top_css = f"bottom:{text_cfg['top'] * self.H:.1f}px"
            else:
                top_css = f"top:{text_cfg['top'] * self.H:.1f}px"
            max_h = text_cfg["area"] * self.H
        hsize = text_cfg["headline_size"] * u
        hmin = text_cfg["headline_min"] * u
        ssize = text_cfg["sub_size"] * u
        smin = text_cfg["sub_min"] * u
        ksize = text_cfg["kicker_size"] * u
        gap = text_cfg["gap"] * u
        kicker = copy_entry.get("kicker")
        headline = copy_entry.get("headline")
        sub = copy_entry.get("sub")
        shadow = text_cfg.get("shadow")
        shadow_css = f"text-shadow:{shadow};" if shadow else ""
        items = []
        if kicker:
            items.append(
                f'<div class="kicker qa-text" style="font-size:{ksize:.1f}px;color:{colors.get("kicker") or colors["accent"]};{shadow_css}">'
                f"{markup_to_html(kicker)}</div>"
            )
        if headline:
            items.append(
                f'<div class="headline qa-text" style="font-size:{hsize:.1f}px;color:{colors["text"]};{shadow_css}">'
                f"{markup_to_html(headline)}</div>"
            )
        if sub:
            items.append(
                f'<div class="sub qa-text" style="font-size:{ssize:.1f}px;color:{colors["muted"]};{shadow_css}">'
                f"{markup_to_html(sub)}</div>"
            )
        align_items = {"center": "center", "left": "flex-start", "right": "flex-end"}.get(align, "center")
        return (
            f'<div class="text" data-qa-id="{html.escape(qa_id)}" data-maxh="{max_h:.1f}" '
            f'data-maxlines="{text_cfg["max_lines"]}" data-submaxlines="{text_cfg["sub_max_lines"]}" '
            f'data-hsize="{hsize:.2f}" data-hmin="{hmin:.2f}" data-ssize="{ssize:.2f}" data-smin="{smin:.2f}" '
            f'style="left:{left:.1f}px;width:{width:.1f}px;{top_css};gap:{gap:.1f}px;'
            f'align-items:{align_items};text-align:{align}">'
            + "".join(items)
            + "</div>"
        )

    # ---- document ------------------------------------------------------------
    def document(self, body, base_color):
        fonts = self.theme["fonts"]
        head_family = css_family_list(self.family_for("headline"))
        body_family = css_family_list(self.family_for("body"))
        kicker_family = css_family_list(self.family_for("kicker"))
        hf, bf, kf = fonts["headline"], fonts["body"], fonts["kicker"]
        colors = self.theme["colors"]
        bg = self.theme["background"]
        overlays = []
        if bg.get("grain"):
            grain_url = "data:image/svg+xml;base64," + base64.b64encode(GRAIN_SVG.encode()).decode()
            overlays.append(
                f'<div class="overlay" style="background-image:url(\'{grain_url}\');background-size:{int(28 * self.u)}px;'
                f'opacity:{bg["grain"]};mix-blend-mode:overlay"></div>'
            )
        if bg.get("vignette"):
            overlays.append(
                f'<div class="overlay" style="background:radial-gradient(ellipse at 50% 45%, rgba(0,0,0,0) 52%, '
                f'rgba(0,0,0,{bg["vignette"]}) 100%)"></div>'
            )
        css = f"""
{self.font_faces()}
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:{self.W}px;height:{self.H}px;overflow:hidden;background:{base_color}}}
#canvas{{position:relative;width:{self.W}px;height:{self.H}px;overflow:hidden;background:{base_color};
  -webkit-font-smoothing:antialiased;text-rendering:geometricPrecision;font-kerning:normal}}
.bg-img{{position:absolute;display:block;max-width:none;z-index:0}}
.bg-grad{{position:absolute;top:0;height:100%;z-index:0}}
.decor{{position:absolute;z-index:1;pointer-events:none}}
.decor svg{{width:100%;height:auto;display:block}}
.overlay{{position:absolute;inset:0;z-index:8;pointer-events:none}}
.layer{{position:absolute;transform-origin:50% 50%}}
.device .frame,.device .frame-rim{{position:absolute;inset:0}}
.device .frame-rim{{pointer-events:none;z-index:3}}
.device .btn{{position:absolute;border-radius:2px;z-index:-1}}
.device .screen{{position:absolute;overflow:hidden;background:#000;z-index:2}}
.device .screen img{{display:block}}
.device .camera{{position:absolute;border-radius:50%;background:radial-gradient(circle at 40% 35%,#2b3040 0%,#05060a 55%);
  box-shadow:0 0 0 1px rgba(255,255,255,.05);z-index:4}}
.device .statusbar{{position:absolute;left:0;right:0;top:0;display:flex;align-items:center;justify-content:space-between;
  font-family:{body_family};font-weight:600;z-index:3}}
.device .statusbar svg{{display:block}}
.device .mark{{position:absolute;z-index:5}}
.device .dim{{position:absolute;inset:0;z-index:6}}
.chip{{position:absolute;left:50%;transform:translateX(-50%);padding:.35em .9em;border-radius:999px;white-space:nowrap;
  background:{colors["surface"]};color:{colors["text"]};font-family:{body_family};font-weight:700}}
.card .card-inner,.cover .card-inner,.zoom .zoom-inner{{position:absolute;inset:0;overflow:hidden}}
.card img,.cover img{{display:block}}
.text{{position:absolute;display:flex;flex-direction:column;z-index:9}}
.text > *{{min-width:0;max-width:100%}}
.headline{{font-family:{head_family};font-weight:{hf.get("weight", 700)};font-style:{hf.get("style", "normal")};
  line-height:{hf.get("line_height", 1.06)};letter-spacing:{hf.get("letter_spacing", "0")};text-transform:{hf.get("transform", "none")};
  text-wrap:balance;overflow-wrap:normal;word-break:normal;hyphens:manual;max-width:100%}}
.headline em{{font-style:normal;color:{colors["accent"]}}}
.sub{{font-family:{body_family};font-weight:{bf.get("weight", 500)};line-height:{bf.get("line_height", 1.3)};
  letter-spacing:{bf.get("letter_spacing", "0")};text-wrap:balance;max-width:100%}}
.sub em{{font-style:normal;color:{colors["text"]}}}
.kicker{{font-family:{kicker_family};font-weight:{kf.get("weight", 700)};letter-spacing:{kf.get("letter_spacing", "0.16em")};
  text-transform:{kf.get("transform", "uppercase")}}}
:lang(ko) .headline,:lang(ko) .sub,:lang(ja) .headline{{word-break:keep-all}}
:lang(zh) .headline,:lang(zh) .sub,:lang(ja) .headline,:lang(ja) .sub{{line-break:strict}}
.qa-hide-text .text,.qa-hide-text .chip{{visibility:hidden !important}}
"""
        lang = html.escape(self.locale if self.locale != "default" else "en")
        return (
            f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{css}</style></head>'
            f'<body><div id="canvas">{body}{"".join(overlays)}</div></body></html>'
        )


# --------------------------------------------------------------------------- #
# Renderer (Playwright + Chrome)
# --------------------------------------------------------------------------- #

FIT_AND_MEASURE_JS = r"""
async () => {
  await Promise.all([...document.fonts].map(f => f.load().catch(() => null)));
  await document.fonts.ready;
  await Promise.all([...document.images].map(img => (img.complete && img.naturalWidth)
      ? img.decode().catch(() => null)
      : new Promise(r => { img.addEventListener('load', r, {once: true}); img.addEventListener('error', r, {once: true}); })));
  const inkRects = el => {
    if (!el || !el.textContent.trim()) return [];
    const r = document.createRange(); r.selectNodeContents(el);
    return [...r.getClientRects()].filter(rc => rc.width > 0.5 && rc.height > 0.5);
  };
  const lineCount = el => {
    const tops = [];
    for (const rc of inkRects(el)) { if (!tops.some(t => Math.abs(t - rc.top) < rc.height * 0.5)) tops.push(rc.top); }
    return tops.length;
  };
  const union = rects => {
    if (!rects.length) return null;
    let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
    for (const r of rects) { x1 = Math.min(x1, r.left); y1 = Math.min(y1, r.top); x2 = Math.max(x2, r.right); y2 = Math.max(y2, r.bottom); }
    return [x1, y1, x2 - x1, y2 - y1];
  };
  const hOverflow = el => {
    if (!el) return false;
    const box = el.closest('.text').getBoundingClientRect();
    for (const rc of inkRects(el)) { if (rc.right > box.right + 1 || rc.left < box.left - 1) return true; }
    return el.scrollWidth > el.clientWidth + 1;
  };
  const out = {texts: [], layers: [], images: []};
  for (const block of document.querySelectorAll('.text')) {
    const d = block.dataset;
    const h = block.querySelector('.headline'), s = block.querySelector('.sub'), k = block.querySelector('.kicker');
    const maxH = +d.maxh, maxL = +d.maxlines, subMaxL = +d.submaxlines;
    let hs = +d.hsize, ss = +d.ssize;
    const hmin = +d.hmin, smin = +d.smin;
    const apply = () => { if (h) h.style.fontSize = hs + 'px'; if (s) s.style.fontSize = ss + 'px'; };
    const subBad = () => !!s && (lineCount(s) > subMaxL || hOverflow(s));
    const headBad = () => !!h && (lineCount(h) > maxL || hOverflow(h));
    const tooTall = () => block.getBoundingClientRect().height > maxH + 0.5;
    apply();
    let steps = 0;
    while ((subBad() || headBad() || tooTall()) && steps < 300) {
      if (subBad() && ss > smin) ss = Math.max(smin, ss * 0.97);
      else if ((headBad() || tooTall()) && hs > hmin) hs = Math.max(hmin, hs * 0.97);
      else if (ss > smin) ss = Math.max(smin, ss * 0.97);
      else break;
      apply(); steps++;
    }
    const em = h ? h.querySelector('em') : null;
    out.texts.push({
      id: d.qaId, maxH,
      blockRect: (() => { const r = block.getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; })(),
      ink: union([...inkRects(k), ...inkRects(h), ...inkRects(s)]),
      headlineInk: union(inkRects(h)), subInk: union(inkRects(s)),
      headlinePx: hs, headlineMax: +d.hsize, headlineMin: hmin, subPx: ss, subMin: smin,
      headlineLines: lineCount(h), subLines: lineCount(s),
      overflow: subBad() || headBad() || tooTall(),
      headlineColor: h ? getComputedStyle(h).color : null,
      accentColor: em ? getComputedStyle(em).color : null,
      subColor: s ? getComputedStyle(s).color : null,
    });
  }
  for (const el of document.querySelectorAll('[data-qa-layer]')) {
    const r = el.getBoundingClientRect();
    const inner = el.querySelector('.screen, .card-inner, .zoom-inner');
    const q = inner ? inner.getBoundingClientRect() : r;
    out.layers.push({id: el.dataset.qaLayer, kind: el.dataset.kind, bleed: el.dataset.bleed === '1',
      textOver: el.dataset.textOver === '1', rect: [r.left, r.top, r.width, r.height], screen: [q.left, q.top, q.width, q.height]});
  }
  for (const img of document.images) out.images.push({src: img.getAttribute('src'), ok: img.naturalWidth > 0});
  return out;
}
"""


class Renderer:
    def __init__(self, browser_pref, assets):
        self.pref = (browser_pref or "chrome").strip()
        self.assets = assets
        self._pw = None
        self.browser = None
        self.pages = {}
        self.blocked = []

    def __enter__(self):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError as exc:
            raise PromoError("playwright is not installed (Script4Me installs DEPENDENCIES automatically; "
                             "otherwise: uv pip install playwright).") from exc
        self._pw = sync_playwright().start()
        self.browser = self._launch()
        return self

    def __exit__(self, *exc):
        try:
            if self.browser:
                self.browser.close()
        finally:
            if self._pw:
                self._pw.stop()

    def _launch(self):
        args = ["--force-color-profile=srgb", "--font-render-hinting=none", "--hide-scrollbars", "--disable-lcd-text"]
        attempts = []
        if self.pref not in ("chrome", "chromium", "") and Path(self.pref).exists():
            attempts.append({"executable_path": self.pref})
        if self.pref in ("chrome", ""):
            attempts.append({"channel": "chrome"})
        attempts.append({})
        last = None
        for kwargs in attempts:
            try:
                browser = self._pw.chromium.launch(headless=True, args=args, **kwargs)
                log(f"Browser: {kwargs.get('channel') or kwargs.get('executable_path') or 'playwright chromium'} "
                    f"{browser.version}")
                return browser
            except Exception as exc:  # noqa: BLE001 - try the next browser
                last = exc
        log("No usable browser found; installing Playwright's Chromium (one-time download)...")
        subprocess.run([sys.executable, "-m", "playwright", "install", "chromium"], check=False)
        try:
            return self._pw.chromium.launch(headless=True, args=args)
        except Exception as exc:  # noqa: BLE001
            raise PromoError(f"Could not start a browser: {last or exc}") from exc

    def _page(self, width, height):
        key = (width, height)
        if key in self.pages:
            return self.pages[key]
        context = self.browser.new_context(viewport={"width": width, "height": height}, device_scale_factor=1)
        page = context.new_page()
        page.route("**/*", self._handle)
        cdp = context.new_cdp_session(page)
        self.pages[key] = (page, cdp)
        return self.pages[key]

    def _handle(self, route):
        url = route.request.url
        if url.startswith("data:"):
            route.continue_()
            return
        if not url.startswith(ASSET_HOST):
            self.blocked.append(url)
            route.abort()
            return
        key = urlparse(url).path
        entry = self.assets.routes.get(key)
        if entry is None:
            route.fulfill(status=404, body="missing")
            return
        if isinstance(entry, tuple):
            body, content_type = entry
            route.fulfill(status=200, body=body, content_type=content_type)
            return
        content_type = mimetypes.guess_type(entry)[0] or "application/octet-stream"
        if entry.lower().endswith((".ttf", ".otf")):
            content_type = "font/ttf" if entry.lower().endswith(".ttf") else "font/otf"
        route.fulfill(status=200, path=entry, content_type=content_type)

    def render(self, document_html, width, height, name):
        page, cdp = self._page(width, height)
        url = self.assets.register_bytes(f"{name}.html", document_html.encode("utf-8"), "text/html; charset=utf-8")
        page.goto(url, wait_until="load", timeout=60000)
        metrics = page.evaluate(FIT_AND_MEASURE_JS)
        fonts = self._fonts(cdp)
        shot = page.screenshot(type="png", clip={"x": 0, "y": 0, "width": width, "height": height},
                               animations="disabled", caret="hide", timeout=60000)
        page.evaluate("document.documentElement.classList.add('qa-hide-text')")
        bare = page.screenshot(type="png", clip={"x": 0, "y": 0, "width": width, "height": height},
                               animations="disabled", caret="hide", timeout=60000)
        page.evaluate("document.documentElement.classList.remove('qa-hide-text')")
        return shot, bare, metrics, fonts

    def _fonts(self, cdp):
        used = {}
        try:
            cdp.send("DOM.enable")
            cdp.send("CSS.enable")
            root = cdp.send("DOM.getDocument", {"depth": -1})["root"]["nodeId"]
            for selector, label in ((".headline, .headline *", "headline"), (".sub, .sub *", "sub"),
                                    (".kicker, .kicker *", "kicker"), (".chip", "chip")):
                node_ids = cdp.send("DOM.querySelectorAll", {"nodeId": root, "selector": selector})["nodeIds"]
                for node_id in node_ids:
                    for font in cdp.send("CSS.getPlatformFontsForNode", {"nodeId": node_id}).get("fonts", []):
                        entry = used.setdefault(label, {})
                        name = font.get("familyName") or font.get("postScriptName") or "?"
                        record = entry.setdefault(name, {"glyphs": 0, "custom": font.get("isCustomFont", False)})
                        record["glyphs"] += font.get("glyphCount", 0)
        except Exception as exc:  # noqa: BLE001 - font report is best effort
            used["_error"] = str(exc)
        return used


# --------------------------------------------------------------------------- #
# Job: plan, render, check, report
# --------------------------------------------------------------------------- #

class Job:
    def __init__(self, cfg, params, out_root):
        self.cfg = cfg
        self.params = params
        self.report = Report()
        self.run_dir = Path(out_root) / cfg.slug / (os.environ.get("SCRIPT4ME_RUN_ID") or time.strftime("%Y%m%d_%H%M%S"))
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.work = Path(tempfile.mkdtemp(prefix="promo_"))
        self.assets = Assets(self.work)
        self.outputs = {}  # (locale, device) -> list of dicts
        self.features = {}
        fmt = (params.get("output_format") or cfg.output.get("format") or "png").lower()
        self.fmt = "jpg" if fmt in ("jpg", "jpeg") else "png"
        wanted_locales = [x.strip() for x in (params.get("locales") or "").split(",") if x.strip()]
        self.locales = [l for l in cfg.locales if not wanted_locales or l in wanted_locales]
        missing = [l for l in wanted_locales if l not in cfg.locales]
        if missing:
            raise PromoError(f"Unknown locale(s): {', '.join(missing)}. Config has: {', '.join(cfg.locales)}")
        wanted_slides = [x.strip() for x in (params.get("slides") or "").split(",") if x.strip()]
        self.slides = [s for s in cfg.slides if not wanted_slides or s["id"] in wanted_slides]
        devices = [x.strip() for x in (params.get("devices") or "").split(",") if x.strip()]
        self.devices = devices or list(cfg.output.get("devices") or ["phone"])
        for device in self.devices:
            if device not in CANVASES and not re.match(r"^\d+x\d+$", device):
                raise PromoError(f"Unknown device '{device}'. Use {', '.join(CANVASES)} or WxH.")

    def canvas(self, device):
        if device in CANVASES:
            return CANVASES[device]
        width, height = device.split("x")
        return int(width), int(height)

    # ---- planning ------------------------------------------------------------
    def groups(self):
        """Slides grouped into canvases; a panorama spans two output images."""
        groups = []
        for slide in self.slides:
            span = 2 if slide.get("layout") == "panorama" else int(slide.get("span", 1))
            groups.append((slide, max(1, span)))
        return groups

    def strip_offsets(self, width, groups):
        shift = float(self.cfg.theme["background"].get("shift", 0.34))
        offsets, cursor = [], 0.0
        for _, span in groups:
            offsets.append(cursor)
            cursor += (span - 1) * width + shift * width
        last_span = groups[-1][1] if groups else 1
        total = (offsets[-1] if offsets else 0) + last_span * width
        return offsets, total

    def text_cfg(self, slide=None):
        merged = copy.deepcopy(self.cfg.theme["text"])
        if slide and slide.get("text"):
            merged = deep_merge(merged, slide["text"])
        return merged

    # ---- run -------------------------------------------------------------------
    def run(self):
        started = time.time()
        render_count = 0
        with Renderer(self.params.get("browser"), self.assets) as renderer:
            for device in self.devices:
                width, height = self.canvas(device)
                groups = self.groups()
                offsets, strip_w = self.strip_offsets(width, groups)
                for locale in self.locales:
                    files = []
                    position = 0
                    for (slide, span), offset in zip(groups, offsets):
                        files.extend(self.render_group(renderer, locale, device, width, height, slide, span,
                                                       offset, strip_w, position))
                        position += span
                        render_count += 1
                    self.outputs[(locale, device)] = files
                    log(f"  {device} {locale}: {len(files)} image(s)")
            if self.cfg.feature and not self.params.get("skip_feature_graphic"):
                for locale in self.locales:
                    self.render_feature(renderer, locale)
                    render_count += 1
            if renderer.blocked:
                self.report.warn("*", "network", f"blocked {len(renderer.blocked)} external request(s), e.g. {renderer.blocked[0]}")
        self.set_checks()
        self.contact_sheets()
        report_md = self.write_reports(time.time() - started, render_count)
        if self.params.get("export"):
            self.export()
        shutil.rmtree(self.work, ignore_errors=True)
        return report_md

    def render_group(self, renderer, locale, device, width, height, slide, span, offset, strip_w, position):
        slide_id = slide["id"]
        layout = slide.get("layout", "hero")
        canvas_w = width * span
        parts = [(f"{slide_id}" if span == 1 else f"{slide_id}-{i + 1}", i * width) for i in range(span)]
        build = SlideBuild(self.cfg, self.assets, self.report, locale, device, canvas_w, height, parts)
        build.u = min(width, height) / 100.0
        text_cfg = self.text_cfg(slide)
        base_color, bg_html = build.background_html(offset, strip_w)
        body = [bg_html, build.decor_html(offset, strip_w, front=False)]

        copy_entry = self.cfg.copy_for(locale, slide_id, self.report) if text_cfg.get("position") != "none" else {}
        copies = copy_entry if isinstance(copy_entry, list) else [copy_entry] + [{}] * (span - 1)
        labels = None
        if isinstance(copy_entry, dict):
            labels = copy_entry.get("labels")
        for index, (part_id, part_left) in enumerate(parts):
            entry = copies[index] if index < len(copies) else {}
            body.append(build.text_html(text_cfg, entry, part_left, width, part_id))

        stage = build.stage_for(text_cfg, 0, canvas_w, width)
        if layout != "custom":
            for layer in preset_layers(layout, slide, slide.get("params")):
                if layer.get("type") == "cover":
                    layer["_part_left"], layer["_part_w"] = 0, canvas_w
                build.add_layer(layer, stage, slide_id, labels)
        for layer in slide.get("layers") or []:
            build.add_layer(layer, stage, slide_id, labels)
        body.extend(build.layer_html)
        body.append(build.decor_html(offset, strip_w, front=True))
        document = build.document("\n".join(body), base_color)

        name = slugify(f"{locale}_{device}_{slide_id}")
        shot, bare, metrics, fonts = renderer.render(document, canvas_w, height, name)
        out_dir = self.run_dir / locale / device
        out_dir.mkdir(parents=True, exist_ok=True)
        if self.params.get("keep_html"):
            (out_dir / f"{position + 1:02d}_{slide_id}.html").write_text(document, encoding="utf-8")
        results = []
        for index, (part_id, part_left) in enumerate(parts):
            number = position + index + 1
            path = out_dir / f"{number:02d}_{part_id}.{self.fmt}"
            self.save(shot, path, crop=(part_left, 0, part_left + width, height))
            record = {"slide": part_id, "base": slide_id, "layout": layout, "role": slide.get("role"),
                      "path": str(path), "number": number,
                      "screens": slide_screens(slide), "copy": copies[index] if index < len(copies) else {}}
            self.check_image(record, locale, device, width, height, part_left, metrics, fonts, bare)
            results.append(record)
        return results

    def render_feature(self, renderer, locale):
        fg = self.cfg.feature
        width, height = FEATURE_SIZE
        build = SlideBuild(self.cfg, self.assets, self.report, locale, "feature", width, height,
                           [("feature", 0)], kind="feature")
        build.u = height / 100.0
        text_cfg = self.text_cfg(fg)
        text_cfg.setdefault("feature_text_w", fg.get("text_w", 0.44))
        text_cfg["headline_size"] = fg.get("headline_size", 12.5)
        text_cfg["headline_min"] = fg.get("headline_min", 8.5)
        text_cfg["sub_size"] = fg.get("sub_size", 5.2)
        text_cfg["sub_min"] = fg.get("sub_min", 4.2)
        text_cfg["kicker_size"] = fg.get("kicker_size", 3.6)
        text_cfg["max_lines"] = fg.get("max_lines", 3)
        text_cfg["gap"] = fg.get("gap", 2.6)
        key = fg.get("copy", "feature")
        base_color, bg_html = build.background_html(0, width)
        body = [bg_html, build.decor_html(0, width, front=False)]
        body.append(build.text_html(text_cfg, self.cfg.copy_for(locale, key, self.report), 0, width, "feature"))
        stage = build.stage_for(text_cfg, 0, width, width)
        layout = fg.get("layout", "feature_split")
        if layout != "feature_custom":
            for layer in preset_layers(layout, fg, fg.get("params")):
                build.add_layer(layer, stage, "feature", None)
        for layer in fg.get("layers") or []:
            build.add_layer(layer, stage, "feature", None)
        body.extend(build.layer_html)
        body.append(build.decor_html(0, width, front=True))
        document = build.document("\n".join(body), base_color)
        shot, bare, metrics, fonts = renderer.render(document, width, height, f"{slugify(locale)}_feature")
        out_dir = self.run_dir / locale
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / f"feature_graphic.{self.fmt}"
        self.save(shot, path)
        record = {"slide": "feature", "base": "feature", "layout": layout, "path": str(path), "number": 0,
                  "screens": slide_screens(fg), "copy": {}}
        self.check_image(record, locale, "feature", width, height, 0, metrics, fonts, bare, feature=True)
        self.features[locale] = record

    def save(self, png_bytes, path, crop=None):
        from io import BytesIO
        from PIL import Image

        with Image.open(BytesIO(png_bytes)) as image:
            image = image.convert("RGB")
            if crop:
                image = image.crop(crop)
            if self.fmt == "png":
                image.save(path, optimize=True)
            else:
                image.save(path, quality=93, subsampling=0, optimize=True)

    # ---- checks ----------------------------------------------------------------
    def check_image(self, record, locale, device, width, height, part_left, metrics, fonts, bare_png, feature=False):
        from io import BytesIO
        from PIL import Image

        slide = record["slide"]
        rep = self.report
        path = Path(record["path"])
        with Image.open(path) as image:
            w, h = image.size
            mode = image.mode
        size = path.stat().st_size
        record.update({"width": w, "height": h, "bytes": size})
        if (w, h) != (width, height):
            rep.error(locale, slide, f"size {w}x{h}, expected {width}x{height}", device)
        if mode not in ("RGB", "L"):
            rep.error(locale, slide, f"image mode {mode} (alpha not allowed)", device)
        # The screenshot rules (sides, 2:1) don't apply to the feature graphic, which is fixed at 1024x500.
        if not feature and (min(w, h) < PLAY_LIMITS["min_side"] or max(w, h) > PLAY_LIMITS["max_side"]):
            rep.error(locale, slide, f"side outside {PLAY_LIMITS['min_side']}-{PLAY_LIMITS['max_side']} px", device)
        if not feature and max(w, h) / min(w, h) > PLAY_LIMITS["max_ratio"] + 1e-6:
            rep.error(locale, slide, "aspect ratio above 2:1", device)
        if size > PLAY_LIMITS["max_bytes"]:
            rep.error(locale, slide, f"file is {size / 1e6:.1f} MB (Play limit 8 MB)", device)
        for img in metrics.get("images", []):
            if not img.get("ok"):
                rep.error(locale, slide, f"image failed to load: {img.get('src')}", device)

        part = (part_left, 0, width, height)
        margin = 0.03 * min(width, height)
        texts = [t for t in metrics.get("texts", []) if t.get("id") == slide]
        record["text"] = []
        bare = Image.open(BytesIO(bare_png)).convert("RGB")
        for text in texts:
            info = {"headline_px": round(text["headlinePx"], 1), "headline_lines": text["headlineLines"],
                    "sub_px": round(text["subPx"], 1), "sub_lines": text["subLines"]}
            if text["overflow"]:
                rep.error(locale, slide, "text does not fit its area even at minimum size: shorten the copy", device)
            elif text["headlinePx"] <= text["headlineMin"] + 0.01 and text["headlineLines"]:
                rep.warn(locale, slide, f"headline shrunk to its minimum ({text['headlinePx']:.0f}px): consider shorter copy", device)
            # Legibility at Play's carousel size (~160 dp wide phone screenshots).
            thumb = text["headlinePx"] * (160 / width) if width < height else text["headlinePx"] * (300 / width)
            info["headline_dp_in_store"] = round(thumb, 1)
            if not feature and text["headlineLines"] and thumb < 10:
                rep.warn(locale, slide, f"headline ~{thumb:.1f}dp in the store carousel (small)", device)
            ink = text.get("ink")
            if ink:
                local = [ink[0] - part_left, ink[1], ink[2], ink[3]]
                if local[0] < margin or local[1] < margin or local[0] + local[2] > width - margin or local[1] + local[3] > height - margin:
                    rep.warn(locale, slide, "text closer than 3% to the edge", device)
                if feature:
                    play = (width / 2 - 80, height / 2 - 80, 160, 160)
                    if rect_intersection(local, play) > 0:
                        rep.warn(locale, slide, "text under the centre play-button zone (video thumbnail)", device)
                for layer in metrics.get("layers", []):
                    if layer.get("textOver"):
                        continue
                    screen_rect = [layer["screen"][0] - part_left] + layer["screen"][1:]
                    overlap = rect_intersection(local, screen_rect)
                    if overlap > 0.02 * local[2] * local[3]:
                        rep.warn(locale, slide, f"text overlaps product UI ({overlap / (local[2] * local[3]):.0%} of the text)", device)
                        break
            for kind, color_key, box_key, minimum in (("headline", "headlineColor", "headlineInk", 3.0),
                                                       ("accent", "accentColor", "headlineInk", 3.0),
                                                       ("sub", "subColor", "subInk", 4.5)):
                color = parse_color(text.get(color_key))
                box = text.get(box_key)
                if not color or not box:
                    continue
                ratio = self.contrast(bare, color, box)
                if ratio is None:
                    continue
                info[f"contrast_{kind}"] = round(ratio, 2)
                if ratio < minimum:
                    rep.warn(locale, slide, f"{kind} contrast {ratio:.1f}:1 (want ≥ {minimum}:1)", device)
            record["text"].append(info)

        # Product visibility: the biggest piece of real UI must be large enough to recognise.
        best = 0.0
        for layer in metrics.get("layers", []):
            sx_, sy_, sw_, sh_ = layer["screen"]
            best = max(best, rect_intersection((sx_ - part_left, sy_, sw_, sh_), (0, 0, width, height)))
        record["product_area"] = round(best / (width * height), 3)
        if not feature and metrics.get("layers") and record["product_area"] < 0.18:
            rep.warn(locale, slide, f"largest product UI covers only {record['product_area']:.0%} of the image", device)

        for layer in metrics.get("layers", []):
            if layer.get("bleed"):
                continue
            x, y, lw, lh = layer["rect"]
            x -= part_left
            if x < -1 or y < -1 or x + lw > width + 1 or y + lh > height + 1:
                rep.warn(locale, slide, f"{layer['kind']} cropped by the canvas edge (set bleed if intended)", device)

        # Font coverage: tofu is an error, unexpected fallbacks are worth a look.
        record["fonts"] = {}
        for label, families in (fonts or {}).items():
            if label.startswith("_"):
                rep.info(locale, slide, f"font report unavailable: {families}", device)
                continue
            record["fonts"][label] = sorted(families)
            declared = [f.lower() for f in self.declared_families(label, locale)]
            for family, data in families.items():
                # Chrome reports face names ("Avenir Next Medium") for the declared family ("Avenir Next").
                known = any(family.lower().startswith(d) or d.startswith(family.lower()) for d in declared)
                if "lastresort" in family.lower():
                    rep.error(locale, slide, f"{label}: {data['glyphs']} glyph(s) missing from every font (tofu)", device)
                elif not data["custom"] and not known and data["glyphs"]:
                    rep.warn(locale, slide, f"{label}: {data['glyphs']} glyph(s) fell back to '{family}' "
                                            f"(add it to fonts.*.by_locale for {locale} to control the look)", device)
            if len(families) > 1 and label == "headline":
                custom = [f for f, d in families.items() if d["custom"]]
                system = [f for f, d in families.items() if not d["custom"]]
                if custom and system:
                    rep.warn(locale, slide, f"headline mixes fonts {', '.join(custom + system)}: "
                                            "set a single family for this locale", device)

    def declared_families(self, label, locale):
        theme_fonts = self.cfg.theme["fonts"]
        role = {"headline": "headline", "sub": "body", "kicker": "kicker", "chip": "body"}.get(label, "body")
        font = theme_fonts[role]
        families = []
        override = locale_lookup(font.get("by_locale") or {}, locale)
        if override:
            families.extend(override)
        else:
            if font.get("family"):
                families.append(font["family"])
            families.extend(font.get("fallback") or [])
        return [f for f in families if f]

    def contrast(self, bare, color, box):
        x, y, w, h = [int(round(v)) for v in box]
        x, y = max(0, x), max(0, y)
        w, h = max(1, min(w, bare.width - x)), max(1, min(h, bare.height - y))
        if w <= 1 or h <= 1:
            return None
        region = bare.crop((x, y, x + w, y + h)).resize((min(160, w), min(80, h)))
        pixels = region.get_flattened_data() if hasattr(region, "get_flattened_data") else region.getdata()
        if pixels and not isinstance(pixels[0], tuple):
            pixels = list(zip(*[iter(pixels)] * 3))
        lums = sorted(relative_luminance(px) for px in pixels)
        text_l = relative_luminance(color[:3])
        median = lums[len(lums) // 2]
        worst = lums[int(len(lums) * 0.9)] if text_l > median else lums[int(len(lums) * 0.1)]
        return contrast_ratio(text_l, worst)

    def set_checks(self):
        rep = self.report
        banned = [re.compile(p, re.I) for p in (self.cfg.qa.get("banned_terms") or DEFAULT_BANNED)]
        for (locale, device), files in self.outputs.items():
            layouts = [f["layout"] for f in files]
            distinct = len(set(layouts))
            if len(files) >= 4 and distinct < 3:
                rep.warn(locale, "set", f"only {distinct} distinct layout(s) across {len(files)} images", device)
            for prev, cur in zip(files, files[1:]):
                if prev["layout"] == cur["layout"] and prev["layout"] != "panorama" and prev["screens"] == cur["screens"]:
                    rep.warn(locale, cur["slide"], "same layout and screen as the previous image", device)
                elif (prev["screens"] and cur["screens"] and prev["screens"][0] == cur["screens"][0]
                      and prev["base"] != cur["base"]):
                    rep.warn(locale, cur["slide"], "same main screen as the previous image", device)
            if files and not files[0]["screens"]:
                rep.warn(locale, files[0]["slide"], "first image shows no product screen", device)
            headlines = [plain_text(f["copy"].get("headline")) for f in files if f["copy"].get("headline")]
            if len(headlines) != len(set(h.lower() for h in headlines)):
                rep.warn(locale, "set", "two images share the same headline", device)
            for record in files:
                text = " ".join(plain_text(record["copy"].get(k)) for k in ("kicker", "headline", "sub") if record["copy"].get(k))
                for pattern in banned:
                    if pattern.search(text):
                        rep.warn(locale, record["slide"], f"policy-sensitive wording '{pattern.pattern}' (rankings, price, calls to action)", device)
        expected = self.cfg.output.get("count")
        if expected:
            for (locale, device), files in self.outputs.items():
                if len(files) != expected and not self.params.get("slides"):
                    rep.warn(locale, "set", f"{len(files)} images, config expects {expected}", device)
        for (locale, device), files in self.outputs.items():
            if device.startswith("phone") and 0 < len(files) < 4 and self.cfg.category != "game":
                rep.info(locale, "set", "Google recommends at least 4 phone screenshots (1080 px) for apps", device)

    # ---- outputs -----------------------------------------------------------------
    def contact_sheets(self):
        from PIL import Image, ImageDraw

        font = self._ui_font(26)
        small = self._ui_font(20)
        sheets = []
        for (locale, device), files in self.outputs.items():
            if not files:
                continue
            thumb_h = 640
            thumbs = []
            for record in files:
                with Image.open(record["path"]) as image:
                    scale = thumb_h / image.height
                    thumbs.append(image.convert("RGB").resize((int(image.width * scale), thumb_h), Image.LANCZOS))
            gap, pad, label_h = 24, 40, 56
            width = pad * 2 + sum(t.width for t in thumbs) + gap * (len(thumbs) - 1)
            sheet = Image.new("RGB", (width, pad * 2 + thumb_h + label_h * 2), (241, 243, 244))
            draw = ImageDraw.Draw(sheet)
            issues = [i for i in self.report.items if i["locale"] == locale and i["device"] in (device, None)]
            errors = sum(1 for i in issues if i["level"] == "error")
            warnings = sum(1 for i in issues if i["level"] == "warning")
            draw.text((pad, pad - 8), f"{self.cfg.app_name} · {locale} · {device} · {errors} error(s), {warnings} warning(s)",
                      fill=(32, 33, 36), font=font)
            x = pad
            for record, thumb in zip(files, thumbs):
                sheet.paste(thumb, (x, pad + label_h - 12))
                status = "ok"
                levels = {i["level"] for i in self.report.for_image(locale, record["slide"], device)}
                if "error" in levels:
                    status = "ERROR"
                elif "warning" in levels:
                    status = "warn"
                draw.text((x, pad + label_h + thumb_h - 4), f"{record['number']:02d} {record['slide']} · {record['layout']} · {status}",
                          fill=(95, 99, 104) if status == "ok" else (197, 34, 31), font=small)
                x += thumb.width + gap
            out = self.run_dir / f"contact_{locale}_{device}.jpg"
            sheet.save(out, quality=88)
            sheets.append(out)
        # Every locale at once, at roughly the size Play shows them.
        for device in self.devices:
            rows = [(locale, self.outputs.get((locale, device), [])) for locale in self.locales]
            rows = [(l, f) for l, f in rows if f]
            if len(rows) < 2:
                continue
            thumb_h = 300
            label_w, gap, pad = 120, 12, 24
            row_w = 0
            grid = []
            for locale, files in rows:
                thumbs = []
                for record in files:
                    with Image.open(record["path"]) as image:
                        scale = thumb_h / image.height
                        thumbs.append(image.convert("RGB").resize((int(image.width * scale), thumb_h), Image.LANCZOS))
                grid.append((locale, thumbs))
                row_w = max(row_w, sum(t.width for t in thumbs) + gap * (len(thumbs) - 1))
            sheet = Image.new("RGB", (pad * 2 + label_w + row_w, pad * 2 + len(grid) * (thumb_h + gap)), (241, 243, 244))
            draw = ImageDraw.Draw(sheet)
            y = pad
            for locale, thumbs in grid:
                draw.text((pad, y + thumb_h // 2 - 12), locale, fill=(32, 33, 36), font=font)
                x = pad + label_w
                for thumb in thumbs:
                    sheet.paste(thumb, (x, y))
                    x += thumb.width + gap
                y += thumb_h + gap
            out = self.run_dir / f"contact_all_{device}.jpg"
            sheet.save(out, quality=85)
            sheets.append(out)
        if self.features:
            items = list(self.features.items())
            cols = 2
            tw, th = 512, 250
            rows_n = math.ceil(len(items) / cols)
            sheet = Image.new("RGB", (24 + cols * (tw + 24), 24 + rows_n * (th + 48)), (241, 243, 244))
            draw = ImageDraw.Draw(sheet)
            for index, (locale, record) in enumerate(items):
                x = 24 + (index % cols) * (tw + 24)
                y = 24 + (index // cols) * (th + 48)
                with Image.open(record["path"]) as image:
                    sheet.paste(image.convert("RGB").resize((tw, th), Image.LANCZOS), (x, y + 30))
                draw.text((x, y), locale, fill=(32, 33, 36), font=small)
            out = self.run_dir / "contact_feature_graphics.jpg"
            sheet.save(out, quality=88)
            sheets.append(out)
        self.sheets = sheets

    def _ui_font(self, size):
        from PIL import ImageFont

        for candidate in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc",
                          "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "C:/Windows/Fonts/arial.ttf"):
            if Path(candidate).exists():
                try:
                    return ImageFont.truetype(candidate, size)
                except OSError:
                    continue
        return ImageFont.load_default()

    def write_reports(self, seconds, render_count):
        rep = self.report
        data = {
            "app": self.cfg.app_name,
            "config": self.cfg.source,
            "run_dir": str(self.run_dir),
            "locales": self.locales,
            "devices": self.devices,
            "format": self.fmt,
            "errors": rep.count("error"),
            "warnings": rep.count("warning"),
            "issues": rep.items,
            "images": {f"{locale}/{device}": files for (locale, device), files in self.outputs.items()},
            "feature_graphics": self.features,
            "contact_sheets": [str(s) for s in getattr(self, "sheets", [])],
            "seconds": round(seconds, 1),
            "renders": render_count,
        }
        (self.run_dir / "qa_report.json").write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        lines = [
            f"# {self.cfg.app_name}: store asset QA",
            "",
            f"- Config: `{self.cfg.source}`",
            f"- Output: `{self.run_dir}`",
            f"- Locales: {', '.join(self.locales)} · devices: {', '.join(self.devices)} · format: {self.fmt}",
            f"- {rep.count('error')} error(s), {rep.count('warning')} warning(s), {rep.count('info')} note(s) · "
            f"{render_count} render(s) in {seconds:.0f} s",
            "",
            "## Contact sheets",
            "",
        ]
        lines += [f"- `{s}`" for s in getattr(self, "sheets", [])]
        lines += ["", "## Images", "", "| Locale | Device | # | Slide | Layout | Headline px (store dp) | Contrast | Issues |",
                  "|---|---|---|---|---|---|---|---|"]
        for (locale, device), files in self.outputs.items():
            for record in files:
                text = (record.get("text") or [{}])[0]
                contrast = ", ".join(f"{k.split('_')[1]} {v}" for k, v in text.items() if k.startswith("contrast_"))
                issues = self.report.for_image(locale, record["slide"], device)
                issue_text = "; ".join(f"{i['level']}: {i['message']}" for i in issues if i["level"] != "info") or "—"
                headline = f"{text.get('headline_px', '—')} ({text.get('headline_dp_in_store', '—')})" if text else "—"
                lines.append(f"| {locale} | {device} | {record['number']:02d} | {record['slide']} | {record['layout']} | "
                             f"{headline} | {contrast or '—'} | {issue_text} |")
        for locale, record in self.features.items():
            issues = self.report.for_image(locale, "feature", "feature")
            issue_text = "; ".join(f"{i['level']}: {i['message']}" for i in issues if i["level"] != "info") or "—"
            lines.append(f"| {locale} | feature | — | feature | {record['layout']} | — | — | {issue_text} |")
        other = [i for i in rep.items if i["slide"] in ("set", "theme", "network")]
        if other:
            lines += ["", "## Set-level", ""]
            lines += [f"- {i['level']} · {i['locale']} {i.get('device') or ''}: {i['message']}" for i in other]
        lines += ["", "## Manual review (not automatable)", "",
                  "- Each image has one clear purpose; image 1 sells the app on its own.",
                  "- The first three images show real product functionality.",
                  "- Nothing shown or claimed is fabricated; numbers match the listing and the app.",
                  "- Translations read naturally (ask a native speaker for launch markets).",
                  "- Look at the contact sheets at small size and every image at full size."]
        report = "\n".join(lines) + "\n"
        (self.run_dir / "qa_report.md").write_text(report, encoding="utf-8")
        return report

    def export(self):
        if not self.cfg.export_dir:
            self.report.warn("*", "export", "export requested but the config has no export_dir")
            return
        for (locale, device), files in self.outputs.items():
            target = self.cfg.export_dir / locale / device
            target.mkdir(parents=True, exist_ok=True)
            for old in target.glob("[0-9][0-9]_*.*"):
                old.unlink()
            for record in files:
                shutil.copy2(record["path"], target / Path(record["path"]).name)
        for locale, record in self.features.items():
            target = self.cfg.export_dir / locale
            target.mkdir(parents=True, exist_ok=True)
            shutil.copy2(record["path"], target / Path(record["path"]).name)
        log(f"Exported to {self.cfg.export_dir}")


# --------------------------------------------------------------------------- #
# Entry points
# --------------------------------------------------------------------------- #

def process_files(file_paths, locales, slides, devices, output_format, skip_feature_graphic, export, strict,
                  keep_html, browser, headers, background_path):
    out_root = os.environ.get("SCRIPT4ME_OUTPUT_DIR")
    if not out_root:
        out_root = str(Path.cwd() / "promo_output")
        log(f"SCRIPT4ME_OUTPUT_DIR not set: writing to {out_root}")
    os.makedirs(out_root, exist_ok=True)
    params = {"locales": locales, "slides": slides, "devices": devices, "output_format": output_format,
              "skip_feature_graphic": skip_feature_graphic, "export": export, "keep_html": keep_html,
              "browser": browser}
    configs = [p for p in file_paths if p.lower().endswith(".json")]
    images = [p for p in file_paths if not p.lower().endswith(".json")]
    jobs = [load_config(p) for p in configs] if configs else [quick_config(images, headers, background_path)]
    failed = False
    for cfg in jobs:
        log(f"Rendering {cfg.app_name} ({cfg.source})")
        job = Job(cfg, params, out_root)
        job.run()
        errors, warnings = job.report.count("error"), job.report.count("warning")
        summary = {"ok": errors == 0 and not (strict and warnings), "app": cfg.app_name, "run_dir": str(job.run_dir),
                   "errors": errors, "warnings": warnings, "report": str(job.run_dir / "qa_report.md"),
                   "contact_sheets": [str(s) for s in getattr(job, "sheets", [])]}
        for item in job.report.items:
            if item["level"] in ("error", "warning"):
                log(f"  {item['level'].upper():7} {item['locale']} {item.get('device') or ''} {item['slide']}: {item['message']}")
        log(f"Done: {errors} error(s), {warnings} warning(s). Report: {job.run_dir / 'qa_report.md'}")
        log("PROMO_RESULT " + json.dumps(summary, ensure_ascii=False))
        failed = failed or not summary["ok"]
    if failed:
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("file_paths", nargs="+", help="A promo config (.json) or, in quick mode, screenshots")
    for param in PARAMETERS:
        param_type = param["type"]
        if param_type == "bool":
            parser.add_argument(f'--{param["name"]}', action="store_true", default=param["default"],
                                help=param.get("description", ""))
        elif param_type in ("file_path", "folder_path", "str"):
            parser.add_argument(f'--{param["name"]}', type=str, default=param["default"],
                                help=param.get("description", ""))
        else:
            parser.add_argument(f'--{param["name"]}', type=eval(param_type), default=param["default"],
                                help=param.get("description", ""))
    args = parser.parse_args()
    kwargs = {param["name"]: getattr(args, param["name"]) for param in PARAMETERS}
    try:
        process_files(args.file_paths, **kwargs)
    except PromoError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
