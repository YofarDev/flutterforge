#!/usr/bin/env python3
import sys, os, json, subprocess, threading, time, shutil, argparse
from pathlib import Path
from collections import defaultdict

# ── Configuration & CLI ───────────────────────────────────────────────────────
parser = argparse.ArgumentParser(description="Fix missing Dart type annotations via Analysis Server")
parser.add_argument("--dry-run", action="store_true", help="Show changes without applying")
parser.add_argument("--yes",     action="store_true", help="Apply all without confirmation")
parser.add_argument("--verbose", action="store_true", help="Print advanced debug info")
args = parser.parse_args()

TYPE_LINT_CODES = {"always_specify_types", "type_annotate_public_apis", "strict_raw_type"}
TYPE_FIX_KEYWORDS = ["add type annotation", "specify type", "add explicit type", "add type arguments"]

def log(msg): print(f"\033[0;36m[info]\033[0m  {msg}")
def ok(msg):  print(f"\033[0;32m[ ok ]\033[0m  {msg}")
def warn(msg): print(f"\033[0;33m[warn]\033[0m  {msg}")
def err(msg): print(f"\033[0;31m[err ]\033[0m  {msg}", file=sys.stderr)

# ── Dart Analysis Server Client ───────────────────────────────────────────────
class AnalysisServerClient:
    def __init__(self, dart_bin: str):
        self._id = 0
        self._pending, self._responses = {}, {}
        self._errors = defaultdict(list)
        self._analysis_done = threading.Event()
        self._lock = threading.Lock()

        self._proc = subprocess.Popen(
            [dart_bin, "language-server", "--protocol=analyzer"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        threading.Thread(target=self._read_loop, daemon=True).start()

    def _send_wait(self, method: str, params: dict, timeout: float = 30) -> dict:
        with self._lock:
            self._id += 1
            msg_id = str(self._id)
        
        evt = threading.Event()
        self._pending[msg_id] = evt
        
        msg = {"id": msg_id, "method": method, "params": params}
        self._proc.stdin.write((json.dumps(msg) + "\n").encode())
        self._proc.stdin.flush()
        
        evt.wait(timeout=timeout)
        return self._responses.get(msg_id, {})

    def _read_loop(self):
        buf = b""
        while True:
            chunk = self._proc.stdout.read(4096)
            if not chunk: break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip(): continue
                try:
                    msg = json.loads(line.strip())
                    if "id" in msg:
                        self._responses[str(msg["id"])] = msg
                        if str(msg["id"]) in self._pending:
                            self._pending[str(msg["id"])].set()
                    elif msg.get("event") == "analysis.errors":
                        self._errors[msg["params"]["file"]] = msg["params"]["errors"]
                    elif msg.get("event") == "server.status":
                        if "analysis" in msg.get("params", {}):
                            if not msg["params"]["analysis"].get("isAnalyzing", True):
                                self._analysis_done.set()
                except json.JSONDecodeError: pass

    def initialize_project(self, root: str, excluded: list):
        self._send_wait("server.setSubscriptions", {"subscriptions": ["STATUS"]})
        self._send_wait("analysis.setAnalysisRoots", {"included": [root], "excluded": excluded})

    def wait_for_analysis(self):
        time.sleep(1.0)
        self._analysis_done.clear()
        sys.stdout.write("\033[0;36m[info]\033[0m  Analyzing Dart codebase (cold starts take time) ")
        sys.stdout.flush()
        
        elapsed = 0
        # Increased timeout to 180 seconds to allow cold-start analysis to finish
        while not self._analysis_done.wait(timeout=0.5):
            sys.stdout.write(".")
            sys.stdout.flush()
            elapsed += 0.5
            if elapsed > 180:
                sys.stdout.write(" Timeout! (Proceeding anyway, but AST might be incomplete)\n")
                return
        sys.stdout.write(" Done!\n")

    def get_fixes(self, filepath: str, offset: int) -> dict:
        return self._send_wait("edit.getFixes", {"file": filepath, "offset": offset}, timeout=15)

    def shutdown(self):
        try:
            self._send_wait("server.shutdown", {}, timeout=2)
            self._proc.terminate()
        except Exception: pass

# ── Core Logic ────────────────────────────────────────────────────────────────
def apply_edits(source: str, edits: list) -> str:
    unique_edits = { (e["offset"], e["length"], e["replacement"]): e for e in edits }.values()
    for edit in sorted(unique_edits, key=lambda e: e["offset"], reverse=True):
        o, l, r = edit["offset"], edit["length"], edit["replacement"]
        source = source[:o] + r + source[o + l:]
    return source

# ── Execution ─────────────────────────────────────────────────────────────────
project_root = Path.cwd()
if not (project_root / "pubspec.yaml").exists():
    err("Run this from the Flutter project root.")
    sys.exit(1)

dart_bin = shutil.which("dart")
if not dart_bin:
    err("'dart' not found in PATH.")
    sys.exit(1)

client = AnalysisServerClient(dart_bin)
client.initialize_project(str(project_root), excluded=[str(project_root / "test")])
client.wait_for_analysis()

lib_dir = str(project_root / "lib")
type_errors = []
fatal_blockers = 0

for filepath, errors in client._errors.items():
    if not filepath.startswith(lib_dir): continue
    if any(filepath.endswith(s) for s in (".g.dart", ".freezed.dart", ".gen.dart")): continue

    for error in errors:
        code = error.get("code", "")
        if code in ("uri_does_not_exist", "undefined_class", "undefined_method", "undefined_function"):
            fatal_blockers += 1

        if code in TYPE_LINT_CODES:
            type_errors.append((filepath, error["location"]["offset"], code))

if fatal_blockers > 0:
    warn(f"Detected {fatal_blockers} severe compiler errors (missing URIs, undefined classes).")
    warn("The Dart server CANNOT infer types if imports are broken. Run `flutter pub get` first!")
    print("")

if not type_errors:
    ok("No missing type annotations found.")
    client.shutdown()
    sys.exit(0)

log(f"Found {len(type_errors)} type-related warnings. Requesting AST fixes...")

fixes_by_file = defaultdict(list)

for i, (filepath, offset, code) in enumerate(type_errors, 1):
    filename = Path(filepath).name
    sys.stdout.write(f"\r\033[K\033[0;36m[info]\033[0m  Querying fix {i}/{len(type_errors)}: {filename}")
    sys.stdout.flush()
    
    fix_response = client.get_fixes(filepath, offset)
    fix_found = False
    available_fix_messages = []
    
    for error_fixes in fix_response.get("result", {}).get("fixes", []):
        for fix in error_fixes.get("fixes", []):
            msg = fix.get("message", "")
            available_fix_messages.append(msg)
            
            if any(kw in msg.lower() for kw in TYPE_FIX_KEYWORDS) or ("type" in msg.lower() and "ignore" not in msg.lower()):
                for file_edit in fix.get("change", {}).get("edits", []):
                    if file_edit.get("file") == filepath:
                        fixes_by_file[filepath].extend(file_edit.get("edits", []))
                        fix_found = True
                break 
    
    if args.verbose and not fix_found:
        sys.stdout.write(f"\n\033[0;33m[warn]\033[0m  No auto-fix for '{code}' in {filename}. Server suggested: {available_fix_messages if available_fix_messages else 'Nothing (Broken AST)'}\n")

sys.stdout.write("\n")
client.shutdown()

if not fixes_by_file:
    err("Dart Analysis Server found the errors, but could not auto-generate AST fixes.")
    if fatal_blockers > 0:
        err("This is almost certainly because of the missing URIs / undefined classes mentioned above.")
    sys.exit(0)

# ── Diff Generation ───────────────────────────────────────────────────────────
previews = {}
for filepath, all_edits in fixes_by_file.items():
    original = Path(filepath).read_text(encoding="utf-8")
    modified = apply_edits(original, all_edits)
    previews[filepath] = modified
    
    print(f"\n\033[1;36m{Path(filepath).relative_to(project_root)}\033[0m")
    for i, (a, b) in enumerate(zip(original.splitlines(), modified.splitlines())):
        if a != b:
            print(f"  \033[0;31m- {a.strip()}\033[0m\n  \033[0;32m+ {b.strip()}\033[0m")

if args.dry_run:
    sys.exit(0)

if not args.yes and input(f"\nApply changes to {len(previews)} file(s)? [y/N] ").lower() != 'y':
    sys.exit(0)

for filepath, modified in previews.items():
    Path(filepath).write_text(modified, encoding="utf-8")
    ok(f"Updated: {Path(filepath).relative_to(project_root)}")