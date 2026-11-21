#!/usr/bin/env python3
"""List test-exchange candidates from r/<subreddit>/new via RSS.

Extracts Google Group / opt-in / Play links + package id from each post,
and marks posts already handled (package installed on phone, or in tested.tsv).

Usage: uv run python -I feed.py [--limit 50] [--all] [--json] [--prep N]
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
# Personal state (config, logs, device cache) lives OUTSIDE the skill so the skill folder stays
# shareable (FlutterForge copies .agents/ into every new app). Override with ANDROID_TEST_EXCHANGE_HOME.
DATA_DIR = Path(os.environ.get("ANDROID_TEST_EXCHANGE_HOME", Path.home() / ".config" / "android-test-exchange"))
if not (DATA_DIR / "config.json").exists():
    sys.exit(f"missing {DATA_DIR / 'config.json'}: copy {SKILL_DIR / 'config.example.json'} there and fill it in")
CONFIG = json.loads((DATA_DIR / "config.json").read_text())
TESTED = DATA_DIR / "tested.tsv"
PENDING = DATA_DIR / "pending.tsv"  # opted in, waiting for install
NS = {"a": "http://www.w3.org/2005/Atom"}
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 Chrome/130 Safari/537.36"

RE_GROUP = re.compile(r"https?://groups\.google\.com/(?:u/\d+/)?g/[A-Za-z0-9._-]+")
RE_TESTING = re.compile(r"https?://play\.google\.com/apps/(?:internaltest|testing)/[A-Za-z0-9._]+")
RE_DETAILS = re.compile(r"https?://play\.google\.com/store/apps/details\?id=([A-Za-z0-9._]+)")
RE_PKG_TESTING = re.compile(r"/apps/(?:internaltest|testing)/([A-Za-z0-9._]+)")
SKIP_WORDS = {
    "wear os": "wearos", "wearos": "wearos", "smartwatch": "wearos", "watch face": "wearos",
    "internaltest": "internal-test", "internal test": "internal-test",
    "send me your email": "wants-email", "send me your emails": "wants-email", "dm me your email": "wants-email",
    "leave a review": "wants-review", "write a review": "wants-review", "give us a review": "wants-review",
    "rate my app": "wants-review", "review on play": "wants-review", "rating on play": "wants-review",
}


CDP_PORT = 9222


def fetch(limit: int, source: str = "auto") -> list[dict]:
    """Newest posts of r/<sub> as [{title, author, ts, post, body_html}].

    Since 2026-11 Reddit refuses .rss (404) and .json (403) even to a signed-in browser,
    and blocks anonymous requests from the home network entirely. What still works: the
    subreddit HTML page, loaded inside the phone's Chrome (signed in to reddit.com) over
    adb + DevTools. Direct RSS is kept only as a fallback in case Reddit reopens it."""
    if source in ("auto", "phone"):
        try:
            return fetch_html_via_phone(limit)
        except Exception as e:
            if source == "phone":
                sys.exit(f"phone Chrome fetch failed: {e}")
            print(f"phone Chrome fetch failed ({e}); trying direct RSS", file=sys.stderr)
    url = f"https://www.reddit.com/r/{CONFIG['subreddit']}/new/.rss?limit={limit}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=20) as r:
            return rss_entries(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"direct RSS failed: HTTP {e.code} (Reddit blocks anonymous access here). "
                 "Sign in to reddit.com in Chrome on the phone and use the default source.")


def rss_entries(xml_bytes: bytes) -> list[dict]:
    root = ET.fromstring(xml_bytes)
    return [{
        "title": e.findtext("a:title", "", NS),
        "author": e.findtext("a:author/a:name", "", NS).removeprefix("/u/"),
        "ts": e.findtext("a:updated", "", NS) or e.findtext("a:published", "", NS),
        "post": e.find("a:link", NS).get("href"),
        "body_html": html.unescape(e.findtext("a:content", "", NS)),
    } for e in root.findall("a:entry", NS)]


RE_POST_TAG = re.compile(r"<shreddit-post\s([^>]*)>")
RE_ATTR = re.compile(r'([\w-]+)="([^"]*)"')


def html_entries(chunks: list[str]) -> list[dict]:
    """Parse <shreddit-post> elements from the subreddit page + its more-posts partials.
    The full body is in <div id="t3_<id>-post-rtjson-content">, inside the same element."""
    out, seen = [], set()
    for chunk in chunks:
        tags = list(RE_POST_TAG.finditer(chunk))
        for i, m in enumerate(tags):
            attrs = {k: html.unescape(v) for k, v in RE_ATTR.findall(m.group(1))}
            pid = attrs.get("id", "")
            if not pid or pid in seen or attrs.get("promoted") is not None:
                continue
            seen.add(pid)
            region = chunk[m.end(): tags[i + 1].start() if i + 1 < len(tags) else len(chunk)]
            out.append({
                "id": pid,
                "title": attrs.get("post-title", ""),
                "author": attrs.get("author", ""),
                "ts": attrs.get("created-timestamp", "").replace("+0000", "+00:00"),
                "post": "https://www.reddit.com" + attrs.get("permalink", ""),
                "body_html": rtjson_body(region, pid),
            })
    return out


def rtjson_body(page: str, pid: str) -> str:
    start = page.find(f'id="{pid}-post-rtjson-content"')
    if start < 0:
        return ""
    end = page.find("</shreddit-post-text-body>", start)
    if end < 0:  # post page: body is not wrapped in shreddit-post-text-body
        end = page.find("</shreddit-post>", start)
    return html.unescape(page[page.find(">", start) + 1: end if end > 0 else start + 20000])


def fetch_html_via_phone(limit: int) -> list[dict]:
    sub = CONFIG["subreddit"]
    # one round trip: page 1, then follow the lazy-load partial until `limit` posts or 10 pages
    expr = """(async () => {
      const chunks = []; let url = %s, n = 0;
      for (let page = 0; page < 10 && url && n < %d; page++) {
        const r = await fetch(url, {credentials: 'include'});
        if (r.status !== 200) return JSON.stringify({status: r.status, chunks});
        const t = await r.text(); chunks.push(t);
        n += (t.match(/<shreddit-post\\s/g) || []).length;
        const m = t.match(/src="(\\/svc\\/shreddit\\/community-more-posts\\/new\\/[^"]+)"/);
        url = m ? m[1].replace(/&amp;/g, '&') : null;
      }
      return JSON.stringify({status: 200, chunks});
    })()""" % (json.dumps(f"/r/{sub}/new/"), limit)
    res = json.loads(eval_in_phone_chrome(expr))
    posts = html_entries(res["chunks"])[:limit]
    if not posts:
        hint = " (blocked: sign in to reddit.com in Chrome on the phone)" if res["status"] in (403, 404, 429) else ""
        raise RuntimeError(f"HTTP {res['status']}, no posts parsed{hint}")
    # image/gallery/link posts carry no body in the listing: load their post pages (one parallel batch)
    bare = [p for p in posts if not RE_TESTING.search(p["body_html"]) and not RE_DETAILS.search(p["body_html"])]
    if bare:
        paths = [p["post"].removeprefix("https://www.reddit.com") for p in bare]
        expr = """(async () => JSON.stringify(await Promise.all(%s.map(async u => {
          try { const r = await fetch(u, {credentials: 'include'}); return r.status === 200 ? await r.text() : ''; }
          catch (e) { return ''; } }))))()""" % json.dumps(paths)
        pages = json.loads(eval_in_phone_chrome(expr))
        for p, page in zip(bare, pages):
            p["body_html"] = rtjson_body(page, p["id"]) or p["body_html"]
    return posts


# ---- phone Chrome over the DevTools protocol (stdlib-only websocket client) ----

def _ws_connect(ws_url: str):
    import base64
    import socket
    from urllib.parse import urlparse
    u = urlparse(ws_url)
    s = socket.create_connection((u.hostname, u.port or 80), timeout=30)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall((f"GET {u.path} HTTP/1.1\r\nHost: {u.hostname}:{u.port}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    head = b""
    while b"\r\n\r\n" not in head:
        chunk = s.recv(1)
        if not chunk:
            raise ConnectionError("websocket handshake closed")
        head += chunk
    if b" 101 " not in head.split(b"\r\n", 1)[0]:
        raise ConnectionError(f"websocket handshake refused: {head[:80]!r}")
    return s


def _ws_send(s, text: str) -> None:
    import struct
    data = text.encode()
    mask = os.urandom(4)
    n = len(data)
    hdr = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else
                           bytes([0x80 | 126]) + struct.pack(">H", n) if n < 65536 else
                           bytes([0x80 | 127]) + struct.pack(">Q", n))
    s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


def _recv_exact(s, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("websocket closed")
        buf += chunk
    return buf


def _ws_recv(s) -> str:
    import struct
    msg = b""
    while True:
        b0, b1 = _recv_exact(s, 2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", _recv_exact(s, 2))[0]
        elif n == 127:
            n = struct.unpack(">Q", _recv_exact(s, 8))[0]
        payload = _recv_exact(s, n)
        if b0 & 0x0F == 0x8:
            raise ConnectionError("websocket closed by Chrome")
        if b0 & 0x0F in (0x0, 0x1, 0x2):
            msg += payload
            if b0 & 0x80:
                return msg.decode()


def _cdp_http(path: str, method: str = "GET"):
    req = urllib.request.Request(f"http://127.0.0.1:{CDP_PORT}{path}", method=method)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())


def eval_in_phone_chrome(expr: str) -> str:
    """Evaluate a JS expression (may return a Promise of a string) inside a reddit.com tab of
    the phone's Chrome, so requests carry the user's own reddit session and the phone's
    browser fingerprint. The session never leaves the phone; we only read the result."""
    subprocess.run([*adb_base(), "forward", f"tcp:{CDP_PORT}", "localabstract:chrome_devtools_remote"],
                   capture_output=True, timeout=10, check=True)
    try:
        tabs = _cdp_http("/json/list")
    except Exception:
        # Chrome not running: start it on reddit.com, then retry once
        subprocess.run([*adb_base(), "shell", "am", "start", "-a", "android.intent.action.VIEW",
                        "-d", "https://www.reddit.com/robots.txt", "-p", "com.android.chrome"],
                       capture_output=True, timeout=10)
        time.sleep(4)
        tabs = _cdp_http("/json/list")
    # Android freezes a backgrounded Chrome / background tab (CDP calls then time out):
    # bring Chrome to the front and activate the reddit tab first.
    subprocess.run([*adb_base(), "shell", "monkey", "-p", "com.android.chrome", "-c",
                    "android.intent.category.LAUNCHER", "1"], capture_output=True, timeout=15)
    tab = next((t for t in tabs if t.get("type") == "page" and t.get("url", "").startswith("https://www.reddit.com/")), None)
    if tab is None:
        tab = _cdp_http("/json/new?https://www.reddit.com/robots.txt", method="PUT")
        time.sleep(3)
    else:
        req = urllib.request.Request(f"http://127.0.0.1:{CDP_PORT}/json/activate/{tab['id']}")
        urllib.request.urlopen(req, timeout=10).read()
        time.sleep(1)
    s = _ws_connect(tab["webSocketDebuggerUrl"].replace("localhost", "127.0.0.1"))
    try:
        _ws_send(s, json.dumps({"id": 1, "method": "Runtime.evaluate",
                                "params": {"expression": expr, "awaitPromise": True, "returnByValue": True}}))
        while True:
            msg = json.loads(_ws_recv(s))
            if msg.get("id") == 1:
                break
    finally:
        s.close()
    res = msg.get("result", {})
    if "exceptionDetails" in res:
        raise RuntimeError(res["exceptionDetails"].get("exception", {}).get("description", "JS exception")[:200])
    return res.get("result", {}).get("value", "")


def adb_base() -> list[str]:
    """Serial-pinned adb base, same policy as phone.py (ANDROID_SERIAL, then .device_serial cache).
    Without this, a second device (emulator) makes every `adb shell` fail with 'more than one device'."""
    serial = os.environ.get("ANDROID_SERIAL")
    if not serial:
        cache = DATA_DIR / ".device_serial"
        if cache.exists():
            serial = cache.read_text().strip()
    return ["adb", "-s", serial] if serial else ["adb"]


def installed_packages() -> set[str]:
    try:
        out = subprocess.run([*adb_base(), "shell", "pm", "list", "packages"], capture_output=True, text=True, timeout=20).stdout
    except Exception:
        return set()
    return {l.split(":", 1)[1].strip() for l in out.splitlines() if l.startswith("package:")}


def pkgs_in(path: Path, col: int) -> set[str]:
    if not path.exists():
        return set()
    return {l.split("\t")[col] for l in path.read_text().splitlines() if l.count("\t") >= col}


def tested_packages() -> set[str]:
    return pkgs_in(TESTED, 1)


def age(ts: str) -> str:
    dt = datetime.fromisoformat(ts)
    mins = int((datetime.now(timezone.utc) - dt).total_seconds() // 60)
    return f"{mins}m" if mins < 60 else f"{mins // 60}h{mins % 60:02d}"


def parse(entries: list[dict]) -> list[dict]:
    inst, tested, pending = installed_packages(), tested_packages(), pkgs_in(PENDING, 0)
    mine = CONFIG["my_app"]["package"]
    posts, seen = [], set()
    for e in entries:
        body_html = e["body_html"]
        text = html.unescape(re.sub(r"<[^>]+>", " ", body_html))
        blob = body_html + " " + text
        title = e["title"]
        group = RE_GROUP.search(blob)
        testing = RE_TESTING.search(blob)
        details = RE_DETAILS.search(blob)
        # guard: an internaltest/odd link can match RE_TESTING but not the pkg regex -> None crash
        pkg_m = RE_PKG_TESTING.search(testing.group(0)) if testing else None
        pkg = details.group(1) if details else (pkg_m.group(1) if pkg_m else None)
        low = (title + " " + text).lower()
        skip = sorted({v for k, v in SKIP_WORDS.items() if k in low})
        status = "todo"
        if pkg == mine:
            status = "mine"
        elif pkg in tested:
            status = "tested"
        elif pkg in inst:
            status = "installed"
        elif not pkg:
            status = "no-links"
        elif skip:
            status = "skip:" + ",".join(skip)
        elif pkg in seen:
            status = "duplicate"
        elif pkg in pending:
            status = "pending"
        if pkg:
            seen.add(pkg)
        posts.append({
            "status": status,
            "age": age(e["ts"]) if e["ts"] else "?",
            "author": e["author"],
            "title": title,
            "post": e["post"],
            "package": pkg,
            "group": group.group(0) if group else None,
            "optin": testing.group(0) if testing else (f"https://play.google.com/apps/testing/{pkg}" if pkg else None),
            "play": details.group(0) if details else (f"https://play.google.com/store/apps/details?id={pkg}" if pkg else None),
            "text": re.sub(r"\s+", " ", text).strip()[:600],
        })
    return posts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=50)
    ap.add_argument("--all", action="store_true", help="also show non-todo posts")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--prep", type=int, default=0, help="join group + opt in for the N newest todo posts")
    ap.add_argument("--source", choices=["auto", "phone", "direct"], default="auto",
                    help="auto = phone Chrome (signed in) then direct RSS")
    a = ap.parse_args()
    posts = parse(fetch(a.limit, a.source))
    if a.prep:
        phone = [sys.executable, "-I", str(Path(__file__).with_name("phone.py"))]
        run = lambda *x: subprocess.run([*phone, *x], capture_output=True, text=True).stdout.strip()
        for p in [p for p in posts if p["status"] == "todo"][:a.prep]:
            g = run("join_group", p["group"]) if p["group"] else "no group"
            o = run("optin", p["optin"])
            print(f"{p['package']}\t{g}\t{o}\t{p['post']}")
            if o.startswith("tester"):
                with PENDING.open("a") as f:
                    f.write(f"{p['package']}\t{p['post']}\t{p['title']}\t{datetime.now():%Y-%m-%d %H:%M}\n")
            elif o.startswith("not-available"):
                run("log", p["package"], p["post"], "skipped: opt-in not available")
        n = sum(1 for l in PENDING.read_text().splitlines() if l.strip()) if PENDING.exists() else 0
        print(f"\npending.tsv: {n} opted in. Next: `phone.py install_all`")
        return
    shown = posts if a.all else [p for p in posts if p["status"] in ("todo", "pending")]
    if a.json:
        print(json.dumps(shown, indent=1, ensure_ascii=False))
        return
    for p in shown:
        print(f"[{p['status']}] {p['age']} u/{p['author']} — {p['title']}")
        print(f"   pkg={p['package']}\n   post={p['post']}\n   group={p['group']}\n   optin={p['optin']}")
    counts: dict[str, int] = {}
    for p in posts:
        counts[p["status"]] = counts.get(p["status"], 0) + 1
    print(f"\n{len(posts)} posts: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))


if __name__ == "__main__":
    main()
