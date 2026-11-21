---
name: play-store-screenshots
description: Create or refresh localised Play Store / App Store screenshots and the feature graphic for one of the owner's apps from REAL app captures, with the Script4Me generator (`app_store_promo_generator.py`, run via `s4m`). Storyboard, per-app theme, per-locale copy, headless-Chrome typesetting, automated QA, contact sheets, export, then (with approval) upload. Use for "store screenshots", "Play Store assets", "feature graphic", "localise the screenshots", "redo the listing visuals".
---

# Store screenshots (real UI, automated, localised)

The generator only typesets and composes what you give it. Nothing is AI-generated:
the app's real screens are the proof, and the config gives one visual identity per app.

- Script: `scripts/app_store_promo_generator.py` next to this file (source of truth,
  versioned in the FlutterForge repo). `~/.script4me/scripts/app_store_promo_generator.py`
  is a symlink to it, so `s4m` and the Script4Me app run this copy. New machine:
  `ln -s <this skill>/scripts/app_store_promo_generator.py ~/.script4me/scripts/`.
- Run: `s4m run app_store_promo_generator.py <promo.json> [--param k=v]... --output-dir <dir>`.
  Params: `locales=fr-FR,de-DE`, `slides=hook,cards`, `devices=phone,tablet10`,
  `output_format=png|jpg`, `skip_feature_graphic=true`, `export=true`, `strict=true`,
  `keep_html=true`, `browser=chrome|chromium|<path>`.
- Output: `<output-dir>/app_store_promo_generator/<slug>/<run>/` with
  `<locale>/<device>/NN_<slide>.png`, `<locale>/feature_graphic.png`, `contact_*.jpg`,
  `qa_report.md|json`. The last stdout line is `PROMO_RESULT {json}`. Exit 1 on QA errors
  (or on warnings with `strict`).
- Renderer: Playwright driving the installed Google Chrome (falls back to Playwright's
  Chromium). The first run installs `playwright` into the Script4Me env (~2 min).

## Workflow

1. **Facts first.** Read the app's listing copy (`docs/play-store/listing-*-aso.txt`) and
   the code for every claim you'll put in a headline (counts, mechanics, modes). Numbers
   must match the listing.
2. **Storyboard (decide before capturing).** Usually 5–6 images, each with ONE message and
   a role. These roles are guidance, not slots to fill:
   1. `hook`: the strongest benefit with the most compelling real screen. It must sell the
      app on its own.
   2. `core`: how it works (main interaction or gameplay loop).
   3. `differentiator`: what competitors don't have, shown rather than told.
   4. `depth`: modes, content variety, customisation.
   5. `value`: why keep it (collection, progress, history).
   For games, images 1–3 are gameplay. Never invent a feature to fill a slot.
3. **Capture real screens per locale**, in the same state in every locale.
   App-specific harness: for Who Made This Movie it's `tool/capture_store_screens.sh` (see
   `docs/play-store/promo/CAPTURE.md`). On the owner's phone, follow the safe path: build
   the `.film` APK, check the id with aapt, `adb install -r`,
   `flutter drive --use-application-binary`. Never run a plain `flutter drive/run/install`
   against it. Prefer clean captures without the status bar (in-app grabs); otherwise
   crop it with `screens.<id>.crop`.
4. **Config + copy** in the app repo, e.g. `docs/play-store/promo/promo.json` +
   `copy/<locale>.json` + `screens/<locale>/<id>.png`. Copy is written per locale and
   adapted rather than translated literally; brand names stay as in the app.
5. **Render**, then read `qa_report.md` and LOOK at `contact_<locale>_phone.jpg`,
   `contact_all_phone.jpg` and a few full-size images, including the longest languages
   (de, ru, fr) and CJK (zh, ko). Fix the copy or the theme and re-render only what you
   touched with `slides=`/`locales=`.
6. **Show the owner** the contact sheets before anything goes to Play Console.
7. **Export** (`export=true` writes into `export_dir`) and commit only when asked.
8. **Upload** in Play Console per language (Store listing → language → Phone screenshots /
   Feature graphic) only with explicit approval. Saving a draft is fine; sending for
   review needs its own yes (see the `play-store-aso` skill §6–7). Translated listings
   without their own screenshots show the default language's.

## Config reference (`promo.json`)

Paths are relative to the config file.

```json
{
  "app": {"name": "Who Made This Movie", "slug": "who-made-this-movie", "category": "game"},
  "locales": ["en-GB", "fr-FR"],
  "fallback_locale": "en-GB",
  "screens_dir": "screens",
  "screens": {"quiz": "quiz.png", "album": {"file": "album.png", "crop": [0, 0.03, 1, 1]}},
  "copy_dir": "copy",
  "export_dir": "../store-assets",
  "output": {"devices": ["phone"], "format": "png", "count": 6},
  "theme": { ... },
  "slides": [ ... ],
  "feature_graphic": {"layout": "feature_split", "screens": ["quiz", "legendary"], "copy": "feature"},
  "qa": {"banned_terms": ["regex", "..."]}
}
```

- **screens** map an id to a file looked up in `screens/<locale>/`. If it's missing there, the
  generator uses `screens/<fallback_locale>/` and warns that the screen isn't localised,
  then tries `screens/`. Absolute paths work too. `crop` is `[left, top, right, bottom]`
  as fractions.
- **copy/<locale>.json**: `{"<slide id>": {"kicker"?, "headline", "sub"?, "labels"?}}`.
  - `*word*` renders in the accent colour, and `\n` forces a line break. Otherwise
    lines are balanced automatically.
  - A panorama takes a list of two entries, one per image.
  - `labels` are the chips used by `before_after`.
  - The feature graphic reads the key named by `feature_graphic.copy` (default `feature`).
- **theme**: see the sub-blocks below; all optional, merged over neutral defaults.
  - `colors`: `background`, `text`, `accent`, `muted` (sub line), `surface`, `kicker`.
  - `background`: `color`, `gradient` (raw CSS), `image` (+ `image_mode` cover|strip,
    `image_opacity`), `continuous` + `shift` (one wide background panned across the set so
    neighbouring images flow), `grain` (0–0.1), `vignette` (0–0.5).
  - `fonts.headline|body|kicker`: `family`, `files` (bundled TTF/OTF), `weight`,
    `fallback`, `by_locale` (`{"ko": ["AppleMyungjo", "serif"], "zh": ["Songti SC"]}`
    replaces the stack for that language), `letter_spacing`, `line_height`, `transform`.
  - `text`: `position` top|bottom|none, `align`, `top`, `area` (fractions of the height),
    `width`. Sizes are in units of 1% of the short side: `headline_size` and
    `headline_min` (auto-fit shrinks between them), `sub_size` and `sub_min`,
    `kicker_size`. Also `max_lines`, `sub_max_lines`, `gap`, `shadow`. Any slide can
    override these under `"text"`.
  - `device`: `style` modern|flat, `frame`, `edge`, `bezel`, `radius`, `shadow`
    soft|strong|none|CSS, `camera`, `buttons`, `status_bar` (`{"time": "9:41"}`, only
    for captures without one).
  - `decor`: `{"type": "glow", "x", "y", "r", "color", "opacity", "strip": true}`
    (`strip` places it in the continuous background's coordinates, so it flows across
    images). For motifs, use `{"type": "svg", "svg": "<svg…>"}` or
    `{"type": "image", "file": …}` with `x`, `y`, `w`, `rotate`, `front`, `only`.
- **slides**: `{"id", "role", "layout", "screen" | "screens": [...], "region"?,
  "params"?, "text"?, "device"?, "bleed"?, "layers"?}`.
  - `params` override a layout's geometry. Layer coordinates are fractions of the stage
    (the area left by the text): `x` is the centre, `y` the top, and `h` or `w` the size.
  - `layers` are added on top of the preset: `device`, `card`, `zoom`, `image`,
    `arrow`. With `layout: "custom"` only `layers` are used.

### Layouts

| layout | use it for | notes |
|---|---|---|
| `hero` | one strong screen, legible | `params.h/y/x/rotate`; `bleed:false` keeps the whole phone |
| `tilt` | dynamic hook | 3D tilt; `params.rotate/tilt_x/tilt_y` |
| `ui_card` | big UI, no bezel (lists, grids) | `params.w/y`, `shift` shows a lower part |
| `full_bleed` | immersive game/media screens | top scrim (left in landscape); `params.focus` |
| `zoom` | a detail that would be too small | phone + enlarged `region` [x,y,w,h] with an accent mark |
| `duo` | two related screens | `screens: [front, back]` |
| `trio` | variety, a collection | `screens: [centre, left, right]` |
| `before_after` | real transformations | `labels` in the copy |
| `panorama` | one phone across two images | portrait only; copy is a list of two |
| `custom` | anything else | `layers` only |
| `feature_split` | feature graphic, 1024×500 | text on the left, 1–2 tilted phones on the right |

Canvases: `phone` 1080×1920 (default), `phone_landscape` 1920×1080, `tablet7` 1200×1920,
`tablet10` 1600×2560, or `WxH`.

## Design rules

- One identity per app (theme), varied compositions: use at least 3 layouts across 5
  images and don't repeat a phone angle twice in a row. QA warns.
- The app is the hero. No fabricated UI, no fake ratings or prices, no "best / #1 /
  free / download now" (QA flags the English forms; check other languages by eye).
- Short, benefit-first headlines (1–2 lines), different structures across the set. Add a
  sub line only when it adds a fact.
- Text sits on calm background, never over important UI. QA checks overlap and contrast
  (headline ≥ 3:1, sub ≥ 4.5:1).
- Feature graphic: with a promo video, Play draws a play button in the centre, so keep
  text out of the middle (QA warns).
- Decoration supports the brand; it never fills space for its own sake.
- Every image proves its own headline. If the sub line promises something (e.g.
  trading), that thing is on screen; otherwise drop it from the copy.
- Put the biggest differentiator at image 2, right after the hook.
- Never show the same main screen twice in a row, even with different layouts (QA warns).
  For a mechanic, enlarge the part that explains it: use `custom` with several `zoom`
  layers over a dimmed phone (`dim`).
- Dense lists: zoom into a few rows rather than shrinking a whole screen. Crop regions
  are fixed fractions, so check them in EVERY locale: translated titles wrap and push
  content down. Start the crop a little above the first line.
- On dark backgrounds, set `device.halo` (e.g. `"rgba(167,123,243,0.28)"`) to separate
  dark frames from the background. Sub lines: `text.sub_size` ≥ 4 and a light `muted`.
- QA also warns when the largest product UI covers less than 18% of the image.
- Tablets (`tablet7`, `tablet10`) reuse the phone layouts. If you only have phone
  captures, the phones simply sit on tablet canvases. For Play's large-screen
  quality/featuring, real tablet captures are better, so say which one you shipped.

## QA, and what it can't do

It checks automatically:
- size, mode (no alpha), file size, the 2:1 ratio and the 320–3840 px sides
- images that fail to load
- text overflow after auto-fit, and headlines shrunk to their minimum
- headline size at Play's carousel scale
- text near the edges, text over product UI, and phones cropped without `bleed`
- contrast
- fonts: tofu is an error; unexpected fallback fonts and mixed fonts in a headline are
  warnings (fix with `by_locale`)
- layout variety, duplicate headlines, screens that aren't localised, missing copy and
  policy words

It cannot judge whether the story persuades, whether the claims are true, or whether
the translations sound natural. Those are your job and the owner's.
