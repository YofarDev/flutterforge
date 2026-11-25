#!/usr/bin/env python3
"""adb helpers for the Android test-exchange workflow (phone mirrored by scrcpy, driven via adb).

Usage: uv run python -I phone.py <command> [args]
  status                     START HERE: wake + my app + pending queue + last log lines
  look <path>                small JPEG screenshot (read it) + labels with tap coords. Use instead of shot
  act <label>|<x> <y> [--exact]
                             tap, wait until the screen changes, print new labels (no sleeps needed)
  skip_intro [max]           auto-tap Skip/Next/Continue/Allow/Only this time... through onboarding
  swipe x1 y1 x2 y2 [ms]     raw swipe (games, scrolling)
  key <KEYCODE>              e.g. KEYCODE_BACK, KEYCODE_ENTER (never 111/ESC in a browser: it navigates away)
  push <image>               make image the first gallery thumbnail (for manual image attach)
  wake                       wake screen, lock portrait, report if keyguard is showing
  shot <path>                save a PNG screenshot
  texts                      list visible text / content-desc with tap centers
  tap <x> <y>                tap physical coords
  tap_text <substr> [--last] [--exact] tap element whose text/desc contains substr (case-insensitive)
  swipe_up | swipe_down      scroll content
  back
  open <url> [--pkg P]       open a URL (optionally forcing an app package)
  join_group <url>           open Google Group and join it if a Join button exists
  optin <url>                open Play opt-in page and press "Become a tester"
                             ("not-available" = Play not caught up yet: WAIT, never skip)
  retry_optins [--max N]     retry opt-ins queued in optin_wait.tsv (due = last try 10+ min ago);
                             testers move to pending.tsv. install_all already does 5 per pass
  wait_optin <pkg> <post_url> <optin_url> [group_url]
                             queue a hand-made not-available opt-in for automatic retries
  install <pkg> [--wait 90]  install from Play; prints installed / pending / error
  to_folder <pkg|label>... [--folder NAME] [--remove]
                             add installed apps to a Nova app-drawer folder named after today
                             ("21 Nov"; created if missing) via Nova Settings > Drawer groups
  install_all [--wait M]     batch: retry up to 5 waiting opt-ins, then start every install Play
                             offers for pending.tsv (one pass, or repeat passes for up to M
                             minutes); logs+drops incompatible apps
  launch <pkg>
  type <text>                type text (newlines become Enter)
  comment <post_url> <text_file> <image> [--post]
                             open post in Reddit app, write comment, attach image; Post only with --post.
                             Self-checks: verifies the typed text (one retype on mismatch) and that your
                             group link renders in the posted comment
  edit <match-text> <text_file> <image> [--save]
                             rewrite my own comment (found in profile list), re-attach image
  draft <app_name> <feedback> <out.txt>
                             build the comment from config.json template (ASCII-cleaned, right links)
  fix_link <app_name> <proof.png> [--save]
                             fix the old /u/1/ group link in my comment "Tested <app_name>: ..."
  log <pkg> <post_url> <note>  append to tested.tsv

Device pinning: one adb device is auto-picked on first use and cached in .device_serial
(next to config.json). ANDROID_SERIAL env overrides; delete .device_serial to re-pin.
"""
import html
import json
import os
import re
import unicodedata
import shlex
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
# Personal state (config, logs, device cache) lives OUTSIDE the skill so the skill folder stays
# shareable (FlutterForge copies .agents/ into every new app). Override with ANDROID_TEST_EXCHANGE_HOME.
DATA_DIR = Path(os.environ.get("ANDROID_TEST_EXCHANGE_HOME", Path.home() / ".config" / "android-test-exchange"))
if not (DATA_DIR / "config.json").exists():
    sys.exit(f"missing {DATA_DIR / 'config.json'}: copy {SKILL_DIR / 'config.example.json'} there and fill it in")
TESTED = DATA_DIR / "tested.tsv"
CONFIG = json.loads((DATA_DIR / "config.json").read_text())
FIX_LINKS = DATA_DIR / "fix_links.tsv"
REDDIT = "com.reddit.frontpage"
CONFIG_USER = CONFIG["reddit_user"]  # reddit username of the phone account
VENDING = "com.android.vending"
NODE = re.compile(r'<node [^>]*?text="([^"]*)"[^>]*?content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')


SERIAL_FILE = DATA_DIR / ".device_serial"


def _list_devices() -> list[str]:
    out = subprocess.run(["adb", "devices"], capture_output=True, text=True, timeout=10).stdout
    return [l.split("\t")[0] for l in out.splitlines() if "\tdevice" in l]


def select_serial() -> str | None:
    """Pin ONE adb device for the session: an emulator coming online mid-session otherwise
    hijacks plain `adb` (stale screenshots, 'more than one device' errors, taps to nowhere).
    Precedence: ANDROID_SERIAL env, then the cached serial (if still attached), then the
    first non-emulator device. Only real devices are cached."""
    devs = _list_devices()
    cached = SERIAL_FILE.read_text().strip() if SERIAL_FILE.exists() else ""
    pick = os.environ.get("ANDROID_SERIAL") or cached
    if not (pick and pick in devs):
        real = [d for d in devs if not d.startswith("emulator-")]
        pick = real[0] if real else (devs[0] if devs else "")
        if pick and not pick.startswith("emulator-"):
            SERIAL_FILE.write_text(pick + "\n")
    elif pick and pick != cached:
        SERIAL_FILE.write_text(pick + "\n")
    return pick or None


SERIAL = select_serial()


def adb(*args: str, timeout: int = 30) -> str:
    cmd = ["adb", *(["-s", SERIAL] if SERIAL else []), *args]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout


def adb_bytes(*args: str, timeout: int = 30) -> bytes:
    cmd = ["adb", *(["-s", SERIAL] if SERIAL else []), *args]
    return subprocess.run(cmd, capture_output=True, timeout=timeout).stdout


def sh(cmd: str) -> str:
    return adb("shell", cmd)


def nodes() -> list[tuple[str, int, int]]:
    """UI labels with tap centers. Each dump costs ~2.3 s (app_process start + idle wait),
    so callers should reuse the list and use screen_hash() to detect changes."""
    xml = ""
    for _ in range(3):
        xml = adb("exec-out", "uiautomator dump /dev/tty 2>/dev/null")  # one round trip, no temp file
        if "<hierarchy" in xml:
            break
        time.sleep(0.5)
    out = []
    for t, d, x1, y1, x2, y2 in NODE.findall(xml):
        label = html.unescape(t or d).replace("\n", " ").replace("\u2019", "'").strip()
        if label:
            out.append((label, (int(x1) + int(x2)) // 2, (int(y1) + int(y2)) // 2))
    return out


NODES_CACHE = DATA_DIR / ".nodes_cache.json"


def cached_nodes() -> list[tuple[str, int, int]]:
    """nodes(), reusing the previous command's dump when the screen hash is unchanged
    (typical: `act`/`texts` printed labels, then `act "<label>"` taps one). Saves ~2.3 s."""
    h = screen_hash()
    try:
        c = json.loads(NODES_CACHE.read_text())
        if c.get("hash") == h and c.get("serial") == SERIAL:
            return [tuple(n) for n in c["nodes"]]
    except Exception:
        pass
    ns = nodes()
    if screen_hash() == h:  # screen held still during the dump: safe to cache
        NODES_CACHE.write_text(json.dumps({"hash": h, "serial": SERIAL, "nodes": ns}))
    return ns


def find(sub: str, last: bool = False, exact: bool = False, ns: list | None = None):
    hits = [n for n in (cached_nodes() if ns is None else ns)
            if (n[0].lower() == sub.lower() if exact else sub.lower() in n[0].lower())]
    return (hits[-1] if last else hits[0]) if hits else None


def tap(x: int, y: int) -> None:
    sh(f"input tap {x} {y}")


def tap_text(sub: str, last: bool = False, exact: bool = False, ns: list | None = None) -> bool:
    n = find(sub, last, exact, ns)
    if n:
        tap(n[1], n[2])
    return bool(n)


def screen_hash() -> str:
    """~0.25 s (hashed on the phone) vs ~2.3 s for a uiautomator dump."""
    return adb("exec-out", "screencap | md5sum").split(" ")[0]


def wait_nodes(subs: list[str], timeout: float = 15) -> tuple[str | None, list]:
    """Poll for any of subs; only re-dump when the screen actually changed.
    Returns (first matching sub or None, last node list) so callers can tap without re-dumping."""
    end = time.time() + timeout
    last, ns = None, []
    while time.time() < end:
        h = screen_hash()
        if h != last:
            last = h
            ns = nodes()
            labels = " | ".join(n[0] for n in ns).lower()
            for s in subs:
                if s.lower() in labels:
                    return s, ns
        time.sleep(0.4)
    return None, ns


def wait_text(subs: list[str], timeout: float = 15) -> str | None:
    return wait_nodes(subs, timeout)[0]


def open_url(url: str, pkg: str | None = None) -> None:
    cmd = f"am start -a android.intent.action.VIEW -d {shlex.quote(url)}"
    if pkg:
        cmd += f" -p {pkg}"
    sh(cmd)


def is_installed(pkg: str) -> bool:
    return f"package:{pkg}\n" in adb("shell", "pm", "list", "packages", pkg) + "\n"


def type_text(text: str, pause: float = 0.25) -> None:
    """IME-safe typing: 40-char chunks with pauses between `input text` calls.
    Back-to-back chunks make the Reddit composer drop chars deterministically
    (seen: leading T -> I, lost 'v' in 'movie', stray leading comma)."""
    for i, line in enumerate(text.split("\n")):
        if i:
            time.sleep(0.2)
            sh("input keyevent KEYCODE_ENTER")
            time.sleep(0.2)
        for j in range(0, len(line), 40):
            chunk = line[j:j + 40].replace(" ", "%s")
            if chunk:
                sh("input text " + shlex.quote(chunk))
                time.sleep(pause)


def first_missing(parts: list[str]) -> str | None:
    """Return the first expected substring not visible on screen (whitespace-insensitive)."""
    flat = re.sub(r"\s+", "", " ".join(n[0] for n in nodes()))
    for p in parts:
        if re.sub(r"\s+", "", p) not in flat:
            return p
    return None


def ascii_clean(text: str) -> str:
    text = text.replace("\u2019", "'").replace("\u2018", "'").replace("\u201c", '"').replace("\u201d", '"')
    text = text.replace("\u2013", "-").replace("\u2014", "-").replace("\u2026", "...")
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()


def links_block() -> str:
    m = CONFIG["my_app"]
    return (f"Could you test mine back? ({m['name']})\n\nJoin Group: {m['group']}\n\n"
            f"Web Link: {m['web']}\n\nAndroid Link: {m['android']}")


def check_text(text: str) -> str | None:
    if "/u/" in text and "groups.google.com/u/" in text:
        return "group link contains /u/N/ (broken for others)"
    if CONFIG["my_app"]["group"] not in text:
        return "my group link missing"
    if text != ascii_clean(text):
        return "non-ASCII characters (input text can't type them)"
    return None


def cmd_draft(app: str, feedback: str, out: str) -> None:
    m = CONFIG["my_app"]
    text = CONFIG["comment_template"].format(app=app, feedback=feedback.strip(), my_name=m["name"],
                                             my_group=m["group"], my_web=m["web"], my_android=m["android"])
    text = ascii_clean(text)
    Path(out).write_text(text + "\n")
    print(text)


def comment_visible() -> bool:
    return any(f"comment by {CONFIG_USER}".lower() in n[0].lower() for n in nodes())


def push_image(image: str) -> None:
    remote = f"/sdcard/Pictures/{Path(image).name}"
    adb("push", image, remote)
    sh(f"touch {remote}")  # adb push keeps the host mtime; the picker sorts by it, so make it newest
    sh(f"am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://{remote}")


def attach_image() -> None:
    """Reddit 2026-11 composer: 'Add an image' -> 'Photo Library' -> first tile -> Done
    (no editor step). Falls back to the old in-sheet picker if that is what opens."""
    if not tap_text("Add an image", exact=True):
        tap(896, 1634)  # composer toolbar, between Add Link and Add Gif
    time.sleep(2)
    if tap_text("Photo Library", exact=True):
        time.sleep(3)
        tap(202, 1486)  # first tile of the Google Photos picker (top-left of the grid)
        time.sleep(1.5)
        if not tap_text("Done", exact=True):
            tap(1018, 2484)
        time.sleep(3)
        return
    # old flow: gallery grid inline in the sheet, then an image editor
    time.sleep(2)
    tap(612, 598)  # first thumbnail after the Camera tile
    time.sleep(1)
    tap_text("Add", exact=True)
    time.sleep(3)
    tap_text("Next", exact=True)  # image editor
    time.sleep(3)


# ---- fast-loop helpers: fewer round trips, smaller images ----

INTRO_BUTTONS = ["Skip onboarding", "Skip", "Not now", "No thanks", "Maybe later", "Got it", "Continue",
                 "Get started", "Next", "Only this time", "While using the app", "Allow", "OK", "Close",
                 "Start", "Let's go", "Done", "Understood", "Dismiss"]


def wait_change(before: str, timeout: float = 4) -> bool:
    """Wait until the screen hash differs from `before`, then until it holds still
    (animations settled, max ~1.2 s). Returns whether it changed. No dumps."""
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(0.3)
        h = screen_hash()
        if h != before:
            settle = time.time() + 1.2
            while time.time() < settle:
                time.sleep(0.3)
                h2 = screen_hash()
                if h2 == h:
                    break
                h = h2
            return True
    return False


def print_texts(limit: int = 40, ns: list | None = None) -> None:
    for label, x, y in (cached_nodes() if ns is None else ns)[:limit]:
        print(f"({x},{y}) {label[:120]}")


def cmd_look(path: str) -> None:
    """Small JPEG (~4x fewer image tokens) + visible labels with PHYSICAL tap coords."""
    raw = adb_bytes("exec-out", "screencap", "-p")
    png = Path(path).with_suffix(".png")
    png.write_bytes(raw)
    jpg = Path(path).with_suffix(".jpg")
    subprocess.run(["sips", "-Z", "1000", "-s", "format", "jpeg", "-s", "formatOptions", "60",
                    str(png), "--out", str(jpg)], capture_output=True)
    print(f"image: {jpg}  (scaled: multiply image x,y by 2.712 for taps; prefer coords below)")
    print_texts()


def cmd_act(target: list[str], exact: bool) -> None:
    """Tap (by label or 'x y'), wait until the screen changes, print the new labels. No sleep guessing."""
    if len(target) == 2 and target[0].isdigit() and target[1].isdigit():
        before = screen_hash()
        tap(int(target[0]), int(target[1]))
    else:
        n = find(target[0], exact=exact)
        if not n:
            print(f"not found: {target[0]}")
            return
        before = screen_hash()
        tap(n[1], n[2])
    changed = wait_change(before)
    print("changed" if changed else "NO CHANGE (tap missed, or screen is a game/canvas: use look)")
    print_texts()


def cmd_skip_intro(max_taps: int = 10) -> None:
    """Tap through onboarding / permission / tips screens until none of the usual buttons remain."""
    done = []
    ns = nodes()
    for _ in range(max_taps):
        labels = {n[0].lower(): n for n in ns}
        hit = next((labels[b.lower()] for b in INTRO_BUTTONS if b.lower() in labels), None)
        if not hit:
            break
        before = screen_hash()
        tap(hit[1], hit[2])
        done.append(hit[0])
        if not wait_change(before, 5):
            break  # tap had no effect; stop to avoid looping
        ns = nodes()
    print("tapped: " + (", ".join(done) or "nothing"))
    print_texts(ns=ns)


def cmd_status() -> None:
    """One-call session start: phone state, my app, pending queue, recent log."""
    cmd_wake()
    m = CONFIG["my_app"]
    print(f"my app: {m['name']} | group {m['group']}")
    pend = (DATA_DIR / "pending.tsv")
    rows = pend.read_text().strip().splitlines() if pend.exists() else []
    print(f"pending ({len(rows)}):")
    for r in rows:
        print("  " + r)
    waiting = wait_rows()
    if waiting:
        print(f"optin_wait ({len(waiting)}): opted in, Play not caught up yet; install_all retries them")
    if TESTED.exists():
        print("last logged:")
        for r in TESTED.read_text().strip().splitlines()[-5:]:
            print("  " + "\t".join(r.split("\t")[1:4:2]))


def cmd_wake() -> None:
    if SERIAL is None:
        print("NO DEVICE: adb sees no phone. Check the USB cable / wireless debugging pairing, "
              "then rerun (delete .device_serial if it points at a stale serial).")
        return
    if SERIAL.startswith("emulator-"):
        print(f"warning: only an emulator ({SERIAL}) is connected - is the phone attached?")
    sh("input keyevent KEYCODE_WAKEUP")
    sh("settings put system accelerometer_rotation 0")
    sh("settings put system user_rotation 0")
    time.sleep(1)
    locked = "isKeyguardShowing=true" in sh("dumpsys window | grep isKeyguardShowing")
    print("LOCKED: ask user to unlock the phone" if locked else "awake, unlocked, portrait")


def join_group(url: str) -> str:
    open_url(url)
    hit, ns = wait_nodes(["Join group", "Mark all as read", "conversations", "Leave group"], 12)
    if hit != "Join group":
        return f"no Join button ({'member-or-open' if hit else 'unknown'})"
    before = screen_hash()
    tap_text("Join group", ns=ns)
    wait_change(before, 6)
    # confirmation dialog has its own "Join group" button (the last one on screen)
    before = screen_hash()
    tap_text("Join group", last=True)
    wait_change(before, 6)
    return "joined"


def cmd_join_group(url: str) -> None:
    print(join_group(url))


NOT_AVAILABLE_MSG = ("not-available: Play has not seen the group join yet. NORMAL right after joining "
                     "(takes 10 min to a few hours). NOT a skip: feed.py --prep queues it in optin_wait.tsv "
                     "and install_all retries it. Opted in by hand? run `wait_optin <pkg> <post_url> <optin_url> [group_url]`")


def optin(url: str) -> str:
    """tester | not-available | optin-failed"""
    open_url(url)
    hit, ns = wait_nodes(["App not available", "You are a tester", "Become a tester"], 15)
    if hit == "App not available":
        return "not-available"
    if hit == "Become a tester":
        tap_text("Become a tester", exact=True, ns=ns)
        hit = wait_text(["You are a tester"], 10)
    return "tester" if hit == "You are a tester" else "optin-failed"


def cmd_optin(url: str) -> None:
    r = optin(url)
    print({"not-available": NOT_AVAILABLE_MSG, "optin-failed": "optin-failed (check screenshot)"}.get(r, r))


# ---- opt-in wait queue: "App not available" right after joining the group is Play propagation,
# not a dead app (2026-11-25: 4 of ~47 such apps turned into testers on a retry an hour later).
# Rows: pkg, post, title, optin_url, group_url, first_try, last_try, tries  (times: %Y-%m-%d %H:%M)
OPTIN_WAIT = DATA_DIR / "optin_wait.tsv"
OPTIN_RETRY_GAP_MIN = 10      # retry a row at most every 10 min
OPTIN_GIVE_UP_HOURS = 48      # then log it as skipped


def wait_rows() -> list[list[str]]:
    if not OPTIN_WAIT.exists():
        return []
    return [r.split("\t") for r in OPTIN_WAIT.read_text().splitlines() if r.strip()]


def write_wait_rows(rows: list[list[str]]) -> None:
    OPTIN_WAIT.write_text("".join("\t".join(r) + "\n" for r in rows))


def queue_optin(pkg: str, post: str, title: str, optin_url: str, group: str) -> None:
    """Add (or keep) a not-available opt-in in the wait queue."""
    rows = wait_rows()
    if any(r[0] == pkg for r in rows):
        return
    now = f"{datetime.now():%Y-%m-%d %H:%M}"
    rows.append([pkg, post, title.replace("\t", " ")[:120], optin_url, group or "", now, now, "1"])
    write_wait_rows(rows)


def minutes_since(ts: str) -> float:
    try:
        return (datetime.now() - datetime.strptime(ts, "%Y-%m-%d %H:%M")).total_seconds() / 60
    except ValueError:
        return 1e9


def add_pending(pkg: str, post: str, title: str) -> None:
    if any(r[0] == pkg for r in pending_rows()):
        return
    with PENDING.open("a") as f:
        f.write(f"{pkg}\t{post}\t{title}\t{datetime.now():%Y-%m-%d %H:%M}\n")


def retry_optins(max_n: int | None = None) -> tuple[int, int]:
    """Retry due rows of optin_wait.tsv (oldest attempt first). tester -> moved to pending.tsv.
    Returns (became_tester, still_waiting)."""
    rows = wait_rows()
    due = sorted((r for r in rows if minutes_since(r[6]) >= OPTIN_RETRY_GAP_MIN), key=lambda r: r[6])
    if max_n is not None:
        due = due[:max_n]
    won = 0
    for r in due:
        pkg, post, title, url, group = r[0], r[1], r[2], r[3], r[4]
        if is_installed(pkg):
            res = "tester"
        else:
            if group:
                join_group(group)  # idempotent; a lost join is a common cause of not-available
            res = optin(url)
        waited = int(minutes_since(r[5]))
        if res == "tester":
            add_pending(pkg, post, title)
            rows = [x for x in rows if x[0] != pkg]
            won += 1
            print(f"optin-retry  tester         {pkg}  (after {waited} min) -> pending.tsv")
        elif waited >= OPTIN_GIVE_UP_HOURS * 60:
            rows = [x for x in rows if x[0] != pkg]
            with TESTED.open("a") as f:
                f.write(f"{datetime.now():%Y-%m-%d %H:%M}\t{pkg}\t{post}\t"
                        f"skipped: opt-in still not available after {OPTIN_GIVE_UP_HOURS}h\n")
            print(f"optin-retry  gave-up        {pkg}  (not available for {OPTIN_GIVE_UP_HOURS}h, logged)")
        else:
            r[6] = f"{datetime.now():%Y-%m-%d %H:%M}"
            r[7] = str(int(r[7]) + 1 if r[7].isdigit() else 1)
            print(f"optin-retry  still-waiting  {pkg}  (waiting {waited} min, try {r[7]})")
    write_wait_rows(rows)
    if due:
        sh("input keyevent KEYCODE_HOME")
    return won, len(rows)


def cmd_retry_optins(max_n: int | None) -> None:
    rows = wait_rows()
    if not rows:
        print("optin_wait.tsv is empty")
        return
    not_due = sum(1 for r in rows if minutes_since(r[6]) < OPTIN_RETRY_GAP_MIN)
    won, left = retry_optins(max_n)
    print(f"\n{won} became testers (now in pending.tsv: run install_all). {left} still waiting"
          + (f" ({not_due} not retried: last try < {OPTIN_RETRY_GAP_MIN} min ago)." if not_due else "."))


def cmd_install(pkg: str, wait: int = 90) -> None:
    if is_installed(pkg):
        print("installed (already)")
        return
    open_url(f"market://details?id={pkg}", VENDING)
    hit, ns = wait_nodes(["Item not found", "compatible", "not available in your country", "Cancel", "Install", "Open", "Update"], 15)
    if hit in ("compatible", "not available in your country"):
        print("incompatible: not available for this device/country (e.g. Wear OS, geo-locked) -> skip")
        return
    if hit == "Item not found" or hit is None:
        print("pending: not visible on Play yet (opt-in propagation, retry in a few min)")
        return
    if hit != "Cancel":  # "Cancel" = already downloading
        tap_text("Install", exact=True, ns=ns)
    end = time.time() + wait
    last = None
    while time.time() < end:
        if is_installed(pkg):
            print("installed")
            return
        h = screen_hash()
        if h != last:  # only dump when Play's screen changed (progress ring spins, so mostly yes)
            last = h
            ns = nodes()
            labels = " | ".join(n[0] for n in ns)
            if "Something went wrong" in labels or "Can't download" in labels:
                tap_text("Got it", ns=ns) or tap_text("Understood", ns=ns)
                print("pending: Play error, retry in a few min")
                return
        time.sleep(2)
    print("timeout: still downloading?")


PENDING = DATA_DIR / "pending.tsv"


def start_install(pkg: str) -> str:
    """Open the Play page and tap Install without waiting for the download (Play queues
    several downloads at once). Returns installed|started|downloading|not-visible|incompatible|play-error."""
    if is_installed(pkg):
        return "installed"
    open_url(f"market://details?id={pkg}", VENDING)
    subs = ["Item not found", "compatible", "not available in your country", "Cancel", "Install", "Open", "Update"]
    # Play's "Item not found" page exposes NO labels to uiautomator (and its mini-game keeps the
    # screen animating), so two label-less dumps in a row = not visible yet.
    hit, ns, empties, end = None, [], 0, time.time() + 12
    while time.time() < end and hit is None:
        ns = nodes()
        labels = " | ".join(n[0] for n in ns).lower()
        hit = next((s for s in subs if s.lower() in labels), None)
        empties = empties + 1 if not ns else 0
        if empties >= 2:
            return "not-visible"
        if hit is None:
            time.sleep(0.4)
    if hit in ("compatible", "not available in your country"):
        return "incompatible"
    if hit == "Item not found" or hit is None:
        return "not-visible"
    if hit == "Cancel":
        return "downloading"
    if hit in ("Open", "Update"):
        return "installed"
    tap_text("Install", exact=True, ns=ns)
    hit, ns = wait_nodes(["Cancel", "Something went wrong", "Can't download", "Open"], 6)
    if hit in ("Something went wrong", "Can't download"):
        tap_text("Got it", ns=ns) or tap_text("Understood", ns=ns)
        return "play-error"
    return "started"


def pending_rows() -> list[list[str]]:
    if not PENDING.exists():
        return []
    return [r.split("\t") for r in PENDING.read_text().splitlines() if r.strip()]


def drop_pending(pkg: str) -> None:
    rows = [r for r in pending_rows() if r[0] != pkg]
    PENDING.write_text("".join("\t".join(r) + "\n" for r in rows))


def opted_minutes(row: list[str]) -> int | None:
    try:
        return int((datetime.now() - datetime.strptime(row[3], "%Y-%m-%d %H:%M")).total_seconds() // 60)
    except (IndexError, ValueError):
        return None


def cmd_install_all(wait_min: float = 0) -> None:
    """Batch phase 2: one pass over pending.tsv starting every install Play now offers;
    incompatible apps are logged as skipped and dropped. With --wait M, repeat passes
    (every ~60 s, only for apps not yet started) until all are installed or M minutes pass.
    Installed apps STAY in pending.tsv (their post URL is needed to comment); drop them
    with `log ... commented` + removing the row, as in the main loop."""
    if wait_rows():  # first, promote opt-ins Play has caught up on (up to 5 per pass, ~20 s each)
        won, left = retry_optins(max_n=5)
        print(f"optin_wait: {won} became testers, {left} still waiting (retried automatically on every install_all)\n")
    deadline = time.time() + wait_min * 60
    state: dict[str, str] = {}
    while True:
        for row in pending_rows():
            pkg = row[0]
            if state.get(pkg) in ("installed", "started", "downloading", "incompatible"):
                if state[pkg] in ("started", "downloading") and is_installed(pkg):
                    state[pkg] = "installed"
                continue
            st = start_install(pkg)
            state[pkg] = st
            if st == "incompatible":
                cmd_log(pkg, row[1] if len(row) > 1 else "", "skipped: not available (incompatible/geo)")
                drop_pending(pkg)
        # let queued downloads land: poll pm only (cheap, phone stays free)
        end = time.time() + 45
        while time.time() < end and any(s in ("started", "downloading") for s in state.values()):
            for pkg, s in state.items():
                if s in ("started", "downloading") and is_installed(pkg):
                    state[pkg] = "installed"
            time.sleep(3)
        todo = [p for p, s in state.items() if s not in ("installed", "incompatible")]
        if not todo or time.time() >= deadline:
            break
        time.sleep(max(0.0, min(60.0, deadline - time.time())))
    sh("input keyevent KEYCODE_HOME")
    rows = {r[0]: r for r in pending_rows()}
    for pkg, s in state.items():
        row = rows.get(pkg, [pkg])
        age = opted_minutes(row)
        note = ""
        if s == "not-visible" and age is not None and age >= 45:
            note = f"  (opted in {age} min ago: consider `log ... skipped: never visible on Play` + drop)"
        title = row[2][:60] if len(row) > 2 else ""
        print(f"{s:13} {pkg}  {title}{note}")
    n_inst = sum(s == "installed" for s in state.values())
    print(f"\n{n_inst} installed, ready to test (post URLs in pending.tsv)")


def cmd_comment(post_url: str, text_file: str, image: str, post: bool) -> None:
    text = Path(text_file).read_text().strip()
    err = check_text(text)
    if err:
        print(f"REFUSED: {err}. Rebuild the text with `draft`.")
        return
    push_image(image)  # newest gallery item = first picker thumbnail
    open_url(post_url, REDDIT)
    # Reddit 2026-11 redesign renamed the box; try all three entry points.
    hit, ns = wait_nodes(["Add a comment", "Join the conversation"], 12)
    before = screen_hash()
    if not (hit and tap_text(hit, ns=ns)):
        tap(254, 2495)  # bottom comment bar
    wait_change(before, 5)
    ns = nodes()
    if not (find("Add comment", ns=ns) or find("Post", exact=True, ns=ns)):
        print("no comment composer opened (run `look` to find the box)")
        return
    time.sleep(2)
    type_text(text)
    miss = first_missing([text[-25:]])  # the composer scrolls, so check the tail (cursor end)
    if miss:  # one clear + slower retype
        sh("input keycombination 113 29")
        time.sleep(1)
        sh("input keyevent KEYCODE_DEL")
        time.sleep(1)
        type_text(text, pause=0.45)
        miss = first_missing([text[-25:]])
    if miss and not any(len(n[0]) >= 60 for n in nodes()):
        # Reddit composer does not expose its text to uiautomator (2026-11): the typed text
        # cannot be checked here. Attach the image, then stop before Post so a screenshot
        # check decides it (look, then `act Post --exact`).
        attach_image()
        print("UNCHECKED-TEXT: typed, but the composer text is not readable by uiautomator. "
              "Check the composer with `look` (full text and image), then tap Post yourself.")
        return
    if miss:
        print(f"TYPING-UNVERIFIED: {miss[:40]!r} not visible in the composer. Run `look`, fix by "
              "tapping just before the wrong char (DEL + retype); cursor keys do not work there.")
        return
    attach_image()
    if not post:
        print("ready: comment written, image attached, not posted")
        return
    tap_text("Post", exact=True)
    for _ in range(8):
        time.sleep(2)
        ns = nodes()
        if any("went wrong" in n[0].lower() or "try again" in n[0].lower() for n in ns):
            print("FAILED: Reddit says 'Something went wrong' (server side). Do NOT keep tapping Post: "
                  "tap Close, Discard, test another app, retry `comment` in 10 min.")
            return
        if any(f"comment by {CONFIG_USER}".lower() in n[0].lower() for n in ns):
            group = CONFIG["my_app"]["group"]
            if group in " ".join(n[0] for n in ns):
                print("posted+verified, links render")
                return
            sh("input swipe 610 1900 610 1250 400")  # links may sit below the fold
            time.sleep(2)
            if group in " ".join(n[0] for n in nodes()):
                print("posted+verified, links render")
            else:
                print("posted+verified, but GROUP LINK NOT SEEN - run `look`; fix with `edit` if wrong")
            return
    print("posted? NOT verified: run `look` and check")


def open_my_comment(match: str) -> bool:
    """Open the thread of my comment whose profile-list preview contains `match`."""
    open_url(f"https://www.reddit.com/user/{CONFIG_USER}/comments/", REDDIT)
    time.sleep(6)
    for _ in range(30):
        if find("having some trouble"):
            tap_text("Retry", exact=True)
            time.sleep(5)
            continue
        if tap_text(match):
            time.sleep(5)
            return True
        sh("input swipe 610 1900 610 1250 400")
        time.sleep(1)
    return False


def edit_open_comment(text: str, image: str, save: bool) -> None:
    for _ in range(6):
        if tap_text("options", exact=True):
            break
        sh("input swipe 610 1900 610 1100 300")
        time.sleep(1.5)
    else:
        print("options button not found (run `look`; tap the ... under YOUR comment, then Edit)")
        return
    time.sleep(2)
    if not tap_text("Edit", exact=True):
        print("Edit not in menu (not my comment?)")
        return
    time.sleep(3)
    tap(450, 700)
    sh("input keycombination 113 29")  # ctrl+a (also removes the old image)
    sh("input keyevent KEYCODE_DEL")
    type_text(text, pause=0.4)
    time.sleep(1)
    sh("input keyevent KEYCODE_BACK")  # hide keyboard
    time.sleep(1)
    attach_image()
    if save:
        tap_text("Save", exact=True)
        time.sleep(4)
        print("edited and saved")
    else:
        print("ready: edit prepared, not saved (tap Save or rerun with --save)")


def cmd_edit(match: str, text_file: str, image: str, save: bool) -> None:
    """Rewrite one of my own comments (found in my profile's comment list by `match` text) and re-attach the image."""
    text = Path(text_file).read_text().strip()
    err = check_text(text)
    if err:
        print(f"REFUSED: {err}")
        return
    push_image(image)
    if not open_my_comment(match):
        print("comment not found in profile list")
        return
    edit_open_comment(text, image, save)


def cmd_fix_link(app: str, image: str, save: bool) -> None:
    """Replace the broken /u/1/ group link in my old comment for `app`, keeping its feedback paragraph."""
    push_image(image)
    if not open_my_comment(f"Tested {app}"):
        print("comment not found in profile list")
        return
    first = next((n[0] for n in nodes() if n[0].startswith(f"Tested {app}")), None)
    if not first:
        print("could not read the comment body; do it by hand with `edit`")
        return
    first = first.split("Could you test mine back")[0].strip()
    text = ascii_clean(first + "\n\n" + links_block())
    print(text)
    edit_open_comment(text, image, save)
    if save and FIX_LINKS.exists():
        rows = [r for r in FIX_LINKS.read_text().splitlines() if r.split("\t")[1:2] != [app]]
        FIX_LINKS.write_text("\n".join(rows) + ("\n" if rows else ""))


AAPT_GLOB = "Library/Android/sdk/build-tools/*/aapt"
RE_RAW_NODE = re.compile(r"<node ([^>]*?)/?>")


def app_label(pkg: str) -> str | None:
    """Launcher label of an installed app: pull its base.apk and read it with the SDK's aapt
    (launchable-activity label first: that is what launchers show)."""
    import glob
    import tempfile
    tools = sorted(glob.glob(str(Path.home() / AAPT_GLOB)))
    path = adb("shell", "pm", "path", pkg).splitlines()
    path = next((l.removeprefix("package:").strip() for l in path if l.endswith("base.apk")), None)
    if not tools or not path:
        return None
    with tempfile.TemporaryDirectory() as d:
        local = Path(d) / "base.apk"
        adb("pull", path, str(local), timeout=120)
        out = subprocess.run([tools[-1], "dump", "badging", str(local)], capture_output=True, text=True).stdout
    m = re.search(r"launchable-activity: name='[^']*'\s+label='([^']+)'", out) or \
        re.search(r"application-label:'([^']+)'", out)
    return m.group(1) if m else None


def raw_nodes() -> list[dict]:
    """Like nodes() but keeps class / checked / bounds (needed for checkbox lists)."""
    xml = adb("exec-out", "uiautomator dump /dev/tty 2>/dev/null")
    out = []
    for m in RE_RAW_NODE.finditer(xml):
        a = dict(re.findall(r'([\w-]+)="([^"]*)"', m.group(1)))
        b = re.findall(r"\d+", a.get("bounds", ""))
        if len(b) == 4:
            x1, y1, x2, y2 = map(int, b)
            a["label"] = html.unescape(a.get("text") or a.get("content-desc") or "").strip()
            a["cx"], a["cy"] = (x1 + x2) // 2, (y1 + y2) // 2
            out.append(a)
    return out


NOVA = "com.teslacoilsw.launcher"


def session_folder() -> str:
    """Folder for this session's test apps: config `test_folder` if set, else today's date ("21 Nov")."""
    d = datetime.now()
    return CONFIG.get("test_folder") or f"{d.day} {d:%b}"


def nova_drawer_groups() -> list | None:
    """Open Nova Settings > App drawer > Drawer groups (folders list). Returns its nodes."""
    sh(f"am start -n {NOVA}/.preferences.SettingsActivity")
    for _ in range(8):
        hit, ns = wait_nodes(["Drawer groups", "App drawer", "Navigate up", "Back"], 5)
        labels = [n[0] for n in ns]
        if "Drawer groups" in labels and "Folders" in labels and "Tabs" in labels:
            return ns  # already on the folders screen
        if "Drawer groups" in labels:  # App drawer settings, scrolled to it
            tap_text("Drawer groups", exact=True, ns=ns)
            continue
        if "Home screen" in labels and "App drawer" in labels:  # settings root
            tap_text("App drawer", exact=True, ns=ns)
            continue
        if "Layout" in labels or "Advanced" in labels:  # App drawer settings, not scrolled yet
            sh("input swipe 610 2000 610 700 300")
            time.sleep(0.8)
            continue
        sh("input keyevent KEYCODE_BACK")  # some other settings page: go up
        time.sleep(0.8)
    return None


def nova_folder_row(folder: str, rn: list[dict]):
    """Title node of `folder` in the Drawer groups list and its More options button."""
    title = next((r for r in rn if r["label"] == folder and r.get("class") == "android.widget.TextView"), None)
    if not title:
        return None, None
    more = min((r for r in rn if r["label"] == "More options" and r["cy"] > title["cy"] - 80),
               key=lambda r: abs(r["cy"] - title["cy"]), default=None)
    return title, more


def pick_apps(labels: list[str], tick: bool = True) -> dict[str, str]:
    """In Nova's 'Select apps' checkbox list (alphabetical), set each label's box to `tick`.
    Never toggles a box that is already in the wanted state."""
    want = {l.lower(): l for l in labels}
    state: dict[str, str] = {}
    is_box = lambda r: r.get("class") == "android.widget.CheckBox"
    for _ in range(60):
        rn = raw_nodes()
        nudged = False
        for r in rn:
            key = r["label"].lower()
            if not (r.get("resource-id", "").endswith(":id/name") and key in want and key not in state):
                continue
            if not 320 < r["cy"] < 2400:  # under the toolbar / nav bar: taps would miss
                sh("input swipe 610 1800 610 1300 700" if r["cy"] >= 2400 else "input swipe 610 1000 610 1500 700")  # slow: no fling
                time.sleep(0.8)
                nudged = True
                break
            box = min((b for b in rn if is_box(b)), key=lambda b: abs(b["cy"] - r["cy"]), default=None)
            if box and (box.get("checked") == "true") == tick:
                state[key] = "already in folder" if tick else "not in folder"
                continue
            tap(r["cx"], r["cy"])
            time.sleep(0.6)
            box = min((b for b in raw_nodes() if is_box(b)), key=lambda b: abs(b["cy"] - r["cy"]), default=None)
            ok = box and (box.get("checked") == "true") == tick
            state[key] = ("added" if tick else "removed") if ok else "tap did not change the box"
        if nudged:
            continue
        if len(state) == len(want):
            break
        before = screen_hash()
        sh("input swipe 610 2200 610 900 900")  # slow drag: a fast one flings past rows
        if not wait_change(before, 2):
            break  # end of list
    return {want[k]: state.get(k, "not in the Select apps list") for k in want}


def cmd_to_folder(targets: list[str], folder: str, tick: bool = True) -> None:
    """Add installed apps (package ids or launcher labels) to a Nova app-drawer folder,
    creating the folder if needed. Works in Nova Settings > App drawer > Drawer groups,
    so it doesn't depend on the drawer layout. Idempotent."""
    labels = []
    for t in targets:
        if "." in t and " " not in t:
            lab = app_label(t)
            if not lab:
                print(f"FAILED: no label for {t} (not installed, or no aapt in ~/{AAPT_GLOB})")
                continue
            labels.append(lab)
        else:
            labels.append(t)
    if not labels:
        return
    if not nova_drawer_groups():
        print("FAILED: could not reach Nova Settings > App drawer > Drawer groups (run `look`)")
        return
    rn = raw_nodes()
    title, more = nova_folder_row(folder, rn)
    if not title:
        if not tick:
            print(f"folder '{folder}' does not exist: nothing to remove")
            return
        hdr = next((r for r in rn if r["label"] == "Folders"), None)
        if not hdr:
            print("FAILED: 'Folders' header not found on Drawer groups")
            return
        tap(1098, hdr["cy"])  # the + at the right of the Folders header
        hit, ns = wait_nodes(["Add drawer folder"], 5)
        field = find("Title", exact=True, ns=ns)
        if not (hit and field):
            print("FAILED: 'Add drawer folder' dialog did not open")
            return
        tap(field[1], field[2])
        time.sleep(0.4)
        type_text(folder)
        time.sleep(0.4)
        tap_text("ADD", exact=True)
        wait_nodes([folder], 5)
        title, more = nova_folder_row(folder, raw_nodes())
        if not title:
            print(f"FAILED: folder '{folder}' not created")
            return
        print(f"created folder '{folder}'")
    if not more:
        print("FAILED: folder's More options button not found")
        return
    tap(more["cx"], more["cy"])
    hit, ns = wait_nodes(["Select apps"], 5)
    if not (hit and tap_text("Select apps", exact=True, ns=ns)):
        print("FAILED: 'Select apps' not in the folder menu")
        return
    wait_nodes(["Navigate up"], 5)
    result = pick_apps(labels, tick)
    hit, ns = wait_nodes(["Navigate up"], 3)
    tap_text("Navigate up", exact=True, ns=ns)  # leaving the picker saves the selection
    time.sleep(1)
    title, _ = nova_folder_row(folder, rn := raw_nodes())
    summary = ""
    if title:
        summary = next((r["label"] for r in rn if r.get("class") == "android.widget.TextView"
                        and 0 < r["cy"] - title["cy"] < 140), "")
    sh("input keyevent KEYCODE_HOME")
    for lab, st in result.items():
        print(f"{st}: '{lab}'")
    print(f"folder '{folder}' now: {summary or '?'}")


def cmd_log(pkg: str, post: str, note: str) -> None:
    with TESTED.open("a") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M}\t{pkg}\t{post}\t{note}\n")
    if any(r[0] == pkg for r in wait_rows()):
        write_wait_rows([r for r in wait_rows() if r[0] != pkg])
        print("logged (removed from optin_wait.tsv)")
    elif any(r[0] == pkg for r in pending_rows()):
        drop_pending(pkg)
        print("logged (removed from pending.tsv)")
    else:
        print("logged")


def main() -> None:
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return
    c = a[0]
    if c == "wake":
        cmd_wake()
    elif c == "shot":
        Path(a[1]).write_bytes(adb_bytes("exec-out", "screencap", "-p"))
        print(a[1])
    elif c == "texts":
        for label, x, y in cached_nodes():
            print(f"({x},{y}) {label[:140]}")
    elif c == "tap":
        tap(int(a[1]), int(a[2]))
    elif c == "tap_text":
        print("ok" if tap_text(a[1], "--last" in a, "--exact" in a) else "not found")
    elif c == "look":
        cmd_look(a[1])
    elif c == "act":
        rest = [x for x in a[1:] if x != "--exact"]
        cmd_act(rest, "--exact" in a)
    elif c == "skip_intro":
        cmd_skip_intro(int(a[1]) if len(a) > 1 else 10)
    elif c == "status":
        cmd_status()
    elif c == "swipe":
        ms = a[5] if len(a) > 5 else "300"
        sh(f"input swipe {a[1]} {a[2]} {a[3]} {a[4]} {ms}")
    elif c == "push":
        push_image(a[1])
        print("pushed: first thumbnail in the gallery picker")
    elif c == "key":
        sh(f"input keyevent {a[1]}")
    elif c == "swipe_up":
        sh("input swipe 610 2000 610 900 300")
    elif c == "swipe_down":
        sh("input swipe 610 900 610 2000 300")
    elif c == "back":
        sh("input keyevent KEYCODE_BACK")
    elif c == "open":
        open_url(a[1], a[a.index("--pkg") + 1] if "--pkg" in a else None)
    elif c == "join_group":
        cmd_join_group(a[1])
    elif c == "optin":
        cmd_optin(a[1])
    elif c == "retry_optins":
        cmd_retry_optins(int(a[a.index("--max") + 1]) if "--max" in a else None)
    elif c == "wait_optin":
        queue_optin(a[1], a[2], "", a[3], a[4] if len(a) > 4 else "")
        print(f"queued in optin_wait.tsv ({len(wait_rows())} waiting)")
    elif c == "to_folder":
        folder = a[a.index("--folder") + 1] if "--folder" in a else session_folder()
        targets = [x for i, x in enumerate(a[1:], 1) if x not in ("--folder", "--remove") and a[i - 1] != "--folder"]
        cmd_to_folder(targets, folder, tick="--remove" not in a)
    elif c == "install_all":
        cmd_install_all(float(a[a.index("--wait") + 1]) if "--wait" in a else 0)
    elif c == "install":
        cmd_install(a[1], int(a[a.index("--wait") + 1]) if "--wait" in a else 90)
    elif c == "launch":
        sh(f"monkey -p {a[1]} -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1")
    elif c == "type":
        type_text(a[1])
    elif c == "comment":
        cmd_comment(a[1], a[2], a[3], "--post" in a)
    elif c == "edit":
        cmd_edit(a[1], a[2], a[3], "--save" in a)
    elif c == "draft":
        cmd_draft(a[1], a[2], a[3])
    elif c == "fix_link":
        cmd_fix_link(a[1], a[2], "--save" in a)
    elif c == "log":
        cmd_log(a[1], a[2], a[3] if len(a) > 3 else "")
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
