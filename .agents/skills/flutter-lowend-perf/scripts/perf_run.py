#!/usr/bin/env python3
"""Build, install and run a perf take on an Android device, safely.

    uv run perf_run.py --device <serial> --package com.example.app.perf \
        --tag baseline [--define PERF_RIVE=true ...] [--real-package com.example.app]

Run from the Flutter app's root. What it does, in order:

1. Shows the device's foreground app and screen state (a take attaches to
   the FIRST Flutter VM it finds: another Flutter app in front = wrong data).
2. Builds `flutter build apk --profile` for the take target with every
   define passed as its own argument (never a shell string: zsh does not
   word-split "$D", which silently merges all defines into one value).
   PERF_CAPTURE=true is always added: the app's Gradle file must turn it
   into an applicationIdSuffix (see SKILL.md).
3. Refuses to go on unless the APK's package (aapt) is exactly --package
   and differs from --real-package: a perf build must never replace the
   owner's installed app.
4. Force-stops the perf app (a leftover instance would be attached to
   instead of a fresh one), installs it with `adb install -r` (skipped when
   the same APK is already installed: some phones ask the owner to accept
   every USB install).
5. Runs `flutter drive --use-application-binary --keep-app-running
   --no-dds`: Flutter never installs or uninstalls anything (plain
   `flutter drive` uninstalls by the manifest's base id, i.e. the real
   app, when an install fails, and removes the perf app after the run).
6. Copies build/integration_response_data.json to <out>/<tag>.json, keeps
   the log at <out>/<tag>.log, checks the real app is still installed, and
   prints the report.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sh(cmd: list[str], check: bool = True, capture: bool = True, **kw) -> subprocess.CompletedProcess:
    r = subprocess.run(cmd, capture_output=capture, text=True, **kw)
    if check and r.returncode != 0:
        sys.exit(f"FAILED: {' '.join(cmd)}\n{(r.stdout or '')[-2000:]}{(r.stderr or '')[-2000:]}")
    return r


def adb(device: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return sh(["adb", "-s", device, *args], check=check)


def aapt() -> str:
    sdk = Path(os.environ.get("ANDROID_HOME", Path.home() / "Library/Android/sdk"))
    tools = sorted((sdk / "build-tools").glob("*/aapt"))
    if not tools:
        sys.exit("aapt not found under $ANDROID_HOME/build-tools")
    return str(tools[-1])


def apk_package(apk: Path) -> str:
    line = sh([aapt(), "dump", "badging", str(apk)]).stdout.splitlines()[0]
    return line.split("name='")[1].split("'")[0] if "name='" in line else ""


def installed(device: str, package: str) -> bool:
    out = adb(device, "shell", "pm", "list", "packages", package, check=False).stdout
    return any(l.strip() == f"package:{package}" for l in out.splitlines())


def pick_device(requested: str | None) -> str:
    lines = sh(["adb", "devices"]).stdout.splitlines()[1:]
    online = [l.split()[0] for l in lines if l.strip().endswith("device")]
    if requested:
        if requested not in online:
            sys.exit(f"device {requested} not online; online: {online}")
        return requested
    if len(online) != 1:
        sys.exit(f"pass --device (online: {online})")
    return online[0]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--device")
    p.add_argument("--package", required=True, help="expected package of the perf APK (with its suffix)")
    p.add_argument("--real-package", help="the owner's real app id: must differ, must survive the run")
    p.add_argument("--target", default="integration_test/perf_take_test.dart")
    p.add_argument("--driver", default="test_driver/perf_driver.dart")
    p.add_argument("--define", action="append", default=[], help="K=V, repeatable")
    p.add_argument("--id-define", default="PERF_CAPTURE=true", help="define that switches the app id suffix")
    p.add_argument("--tag", default="take")
    p.add_argument("--out", default="build/perf")
    p.add_argument("--no-build", action="store_true", help="reuse the last APK (still id-checked)")
    a = p.parse_args()

    if not Path("pubspec.yaml").exists():
        sys.exit("run from the Flutter app root")
    device = pick_device(a.device)
    if a.real_package and a.real_package == a.package:
        sys.exit("REFUSED: --package equals --real-package")
    defines = [f"--dart-define={a.id_define}", *[f"--dart-define={d}" for d in a.define]]
    apk = Path("build/app/outputs/flutter-apk/app-profile.apk")
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    # 1. device state
    top = adb(device, "shell", "dumpsys", "activity", "activities", check=False).stdout
    resumed = next((l.strip() for l in top.splitlines() if "topResumedActivity" in l or "mResumedActivity" in l), "?")
    awake = adb(device, "shell", "dumpsys", "power", check=False).stdout
    wake = next((l.strip() for l in awake.splitlines() if "mWakefulness=" in l), "?")
    print(f"device {device}: {wake}; front: {resumed}")
    if "Asleep" in wake or "Dozing" in wake:
        sys.exit("screen is off: unlock the device and keep it untouched during the take")
    real_before = installed(device, a.real_package) if a.real_package else None

    # 2. build
    if not a.no_build:
        print("build:", " ".join(["flutter", "build", "apk", "--profile", f"--target={a.target}", *defines]), flush=True)
        sh(["flutter", "build", "apk", "--profile", f"--target={a.target}", *defines], capture=True)

    # 3. id guard
    pkg = apk_package(apk)
    if pkg != a.package:
        sys.exit(f"REFUSED: {apk} is '{pkg}', expected '{a.package}'. Is {a.id_define.split('=')[0]} wired to "
                 "applicationIdSuffix in android/app/build.gradle(.kts)? Nothing was installed.")

    # 4. install
    adb(device, "shell", "am", "force-stop", a.package, check=False)
    local = hashlib.sha256(apk.read_bytes()).hexdigest()
    path = adb(device, "shell", "pm", "path", a.package, check=False).stdout.strip().removeprefix("package:")
    remote = adb(device, "shell", "sha256sum", path, check=False).stdout.split(" ")[0].strip() if path else ""
    if remote == local:
        print(f"install {a.package}: same APK already on the device")
    else:
        print(f"install {a.package}: accept the install on the device if it asks", flush=True)
        r = adb(device, "install", "-r", str(apk), check=False)
        if "Success" not in r.stdout:
            sys.exit(f"adb install failed: {(r.stdout + r.stderr).strip()[-400:]}")

    # 5. drive
    resp = Path("build/integration_response_data.json")
    resp.unlink(missing_ok=True)
    log = out / f"{a.tag}.log"
    cmd = ["flutter", "drive", "--profile", "--no-dds", "-d", device,
           f"--use-application-binary={apk}", "--keep-app-running",
           f"--driver={a.driver}", f"--target={a.target}", *defines]
    print("drive:", " ".join(cmd), flush=True)
    with log.open("w") as f:
        rc = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, text=True).returncode
    text = log.read_text(errors="replace")
    passed = "All tests passed" in text
    print(f"take: {'PASSED' if passed else 'FAILED'} (exit {rc}); log {log}")
    if not passed:
        for line in text.splitlines():
            if "I/flutter" in line and any(k in line for k in ("Exception", "Error", "fail", "timed out")):
                print("  ", line[:240])

    # 6. results
    if a.real_package and real_before and not installed(device, a.real_package):
        print(f"WARNING: {a.real_package} was installed before the run and is GONE now. Tell the owner.")
    if not resp.exists() or resp.stat().st_size < 10:
        sys.exit("no report data (the take failed before probe.finish(), or drive attached to another app)")
    dst = out / f"{a.tag}.json"
    shutil.copy(resp, dst)
    print(f"report: {dst}\n")
    subprocess.run([sys.executable, str(HERE / "perf_report.py"), str(dst)])
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
