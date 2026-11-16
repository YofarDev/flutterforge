"""Stage a FlutterForge template upgrade in an existing app as a 3-way merge.

Rebuilds the template-owned files exactly as the generator shipped them at two
template revisions (BASE: what the app was generated from; HEAD: the target),
commits both into a throwaway reference repository, then cherry-picks the
BASE→HEAD change into the app with `--no-commit`. Files the app customized
get ordinary merge conflicts instead of being overwritten; nothing is
committed or pushed.

Usage (from anywhere; stdlib only):
    uv run --no-project prepare_upgrade.py --template PATH [--app PATH]
        [--base REV] [--head REV] [--dry-run]

Prints a compact report: chosen base (and why), template commits applied,
changed/deleted files, conflicts, and dependency changes to apply by hand.
"""
from __future__ import annotations

import argparse
import datetime
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

PLACEHOLDER = "my_flutter_app"
STAMP = ".flutterforge.json"
# Template path -> app path, for single files the generator copies or renders.
FILE_MAP = {
    "AGENTS.md": "AGENTS.md",
    "remove_counter.sh": "remove_counter.sh",
    "analysis_options.yaml": "analysis_options.yaml",
    "l10n.yaml": "l10n.yaml",
    "template-README.md": "README.md",
    "templates/github/workflows/flutter-ci.yml": ".github/workflows/flutter-ci.yml",
}
# Template directories copied wholesale (scripts/ is filtered separately).
DIR_MAP = {"lib/": "lib/", "test/": "test/", ".agents/": ".agents/", ".codex/": ".codex/"}
TEMPLATE_ONLY_SCRIPTS = {"scripts/verify_template.sh", "scripts/README.md"}


def run(args: list[str], cwd: Path | None = None, check: bool = True,
        data: bytes | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(args, cwd=cwd, input=data, capture_output=True)
    if check and result.returncode != 0:
        sys.exit(f"error: {' '.join(args)}\n{result.stderr.decode(errors='replace')}")
    return result


def git(repo: Path, *args: str, check: bool = True, data: bytes | None = None) -> str:
    return run(["git", "-C", str(repo), *args], check=check, data=data).stdout.decode()


def shipped_scripts(template: Path, rev: str, files: list[str]) -> set[str]:
    """Allowlisted scripts at REV (parsed from create_project.dart), or every
    script except template-only ones for revisions before the allowlist."""
    source = git(template, "show", f"{rev}:create_project.dart", check=False)
    allow = set(re.findall(r"'(scripts/[^']+)'", source))
    candidates = {f for f in files if f.startswith("scripts/")}
    if allow:
        return candidates & allow
    return {f for f in candidates if f not in TEMPLATE_ONLY_SCRIPTS}


def shipped_map(template: Path, rev: str) -> dict[str, str]:
    """Template path -> app path for every file the generator ships at REV."""
    files = git(template, "ls-tree", "-r", "--name-only", rev).splitlines()
    mapping: dict[str, str] = {}
    for f in files:
        if f in FILE_MAP:
            mapping[f] = FILE_MAP[f]
        elif f.startswith("fonts/"):
            mapping[f] = "assets/" + f
        else:
            for src, dst in DIR_MAP.items():
                if f.startswith(src):
                    mapping[f] = dst + f[len(src):]
    for f in shipped_scripts(template, rev, files):
        mapping[f] = f
    return mapping


def render(path: str, raw: bytes, package: str) -> bytes:
    """Applies the generator's substitutions to one shipped file."""
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw
    if path == "template-README.md":
        text = text.replace("{PROJECT_NAME}", package)
    return text.replace(PLACEHOLDER, package).encode("utf-8")


def build_tree(template: Path, rev: str, package: str, out: Path, with_counter: bool) -> None:
    mapping = shipped_map(template, rev)
    archive = run(["git", "-C", str(template), "archive", "--format=tar", rev, "--",
                   *sorted(mapping)]).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            target = out / mapping[member.name]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(render(member.name, tar.extractfile(member).read(), package))
            target.chmod(member.mode & 0o777)
    if not with_counter and (out / "remove_counter.sh").exists():
        # Apply the same Counter removal the app went through, to both trees.
        (out / "pubspec.yaml").write_text(f"name: {package}\n")
        result = run(["bash", "remove_counter.sh"], cwd=out, check=False)
        (out / "pubspec.yaml").unlink()
        if result.returncode != 0:
            sys.exit(f"error: remove_counter.sh failed in reference tree for {rev}:\n"
                     + result.stdout.decode(errors="replace")[-2000:])


def blob_ids(repo: Path, paths: list[Path], normalize) -> dict[str, str]:
    ids: dict[str, str] = {}
    for p in paths:
        ids[str(p)] = git(repo, "hash-object", "--stdin", data=normalize(p)).strip()
    return ids


def detect_base(template: Path, app: Path, package: str, head: str) -> tuple[str, str]:
    stamp = app / STAMP
    if stamp.exists():
        data = json.loads(stamp.read_text())
        commit = data.get("templateCommit")
        if commit and git(template, "cat-file", "-t", commit, check=False).strip() == "commit":
            note = (" — generated from an uncommitted template: review re-applied hunks"
                    if data.get("templateDirty") else "")
            return commit, f"{STAMP} stamp{note}"
    # Score each template commit by how many shipped files the app still has
    # byte-identical (after reversing the package-name substitution). Ties go
    # to the EARLIEST commit: re-applying a change the app already has merges
    # cleanly, while skipping one would silently lose it.
    def normalize(p: Path) -> bytes:
        raw = (app / p).read_bytes()
        try:
            return raw.decode("utf-8").replace(package, PLACEHOLDER).encode("utf-8")
        except UnicodeDecodeError:
            return raw

    best: tuple[int, str] = (-1, "")
    ties: list[str] = []
    app_ids_cache: dict[str, str] = {}
    for rev in git(template, "rev-list", "--reverse", head).split():
        mapping = shipped_map(template, rev)
        tree = {}
        for line in git(template, "ls-tree", "-r", rev).splitlines():
            meta, path = line.split("\t", 1)
            tree[path] = meta.split()[2]
        score = 0
        for tpath, apath in mapping.items():
            if tpath == "template-README.md" or not (app / apath).is_file():
                continue
            if apath not in app_ids_cache:
                app_ids_cache[apath] = blob_ids(app, [Path(apath)], normalize)[apath]
            score += app_ids_cache[apath] == tree.get(tpath)
        if score > best[0]:
            best, ties = (score, rev), []
        elif score == best[0]:
            ties.append(rev)
    if best[0] <= 0:
        sys.exit("error: no template commit matches this app; pass --base REV explicitly.")
    reason = f"content match ({best[0]} identical shipped files)"
    if ties:
        reason += (f"; {len(ties)} later commit(s) tie up to {ties[-1][:10]} — earliest"
                   " chosen, so changes the app already has re-merge cleanly")
    return best[1], reason


def dependency_changes(template: Path, base: str, head: str) -> list[str]:
    def specs(rev: str) -> dict[str, str]:
        raw = git(template, "show", f"{rev}:packages_to_add.json", check=False)
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        result = {}
        for group in ("dependencies", "dev_dependencies"):
            for spec in data.get(group, []):
                name, _, version = spec.partition(":")
                result[f"{group}:{name}"] = version
        return result

    old, new = specs(base), specs(head)
    lines = []
    for key in sorted(set(old) | set(new)):
        group, name = key.split(":")
        dev = " --dev" if group == "dev_dependencies" else ""
        if key not in old:
            lines.append(f"  add:     flutter pub add{dev} '{name}:{new[key]}'")
        elif key not in new:
            lines.append(f"  removed from template (remove only if unused): {name}")
        elif old[key] != new[key] and not old[key]:
            lines.append(f"  pinned:  {name} {new[key]} (was unpinned; align pubspec.yaml only if"
                         " the app's constraint excludes it)")
        elif old[key] != new[key]:
            lines.append(f"  changed: flutter pub add{dev} '{name}:{new[key]}'  (was {old[key]})")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--app", default=Path.cwd(), type=Path)
    parser.add_argument("--base", help="template revision the app was generated from")
    parser.add_argument("--head", default="HEAD", help="template revision to upgrade to")
    parser.add_argument("--dry-run", action="store_true", help="report only; change nothing")
    args = parser.parse_args()
    template, app = args.template.resolve(), args.app.resolve()

    pubspec = (app / "pubspec.yaml")
    if not pubspec.exists():
        sys.exit(f"error: {app} has no pubspec.yaml")
    match = re.search(r"^name:\s*([A-Za-z0-9_]+)", pubspec.read_text(), re.M)
    if not match:
        sys.exit("error: no package name in pubspec.yaml")
    package = match.group(1)
    if git(app, "rev-parse", "--is-inside-work-tree", check=False).strip() != "true":
        sys.exit("error: the app must be a git repository (commit it first)")
    if not args.dry_run and git(app, "status", "--porcelain").strip():
        sys.exit("error: the app has uncommitted changes; commit or stash them first")
    if git(template, "status", "--porcelain", "--untracked-files=no").strip():
        print("warning: the template has uncommitted changes; only committed state is used")

    head = git(template, "rev-parse", args.head).strip()
    if args.base:
        base, reason = git(template, "rev-parse", args.base).strip(), "--base"
    else:
        base, reason = detect_base(template, app, package, head)
    with_counter = (app / "lib/features/counter").is_dir()

    print(f"app:      {app} (package {package}, counter demo {'kept' if with_counter else 'removed'})")
    print(f"base:     {base[:10]}  [{reason}]")
    print(f"head:     {head[:10]}")
    if base == head:
        print("Already up to date.")
        return 0
    log = git(template, "log", "--oneline", "--no-decorate", f"{base}..{head}").splitlines()
    print(f"template commits applied ({len(log)}):")
    for line in log[:40]:
        print(f"  {line}")

    with tempfile.TemporaryDirectory(prefix="flutterforge-upgrade-") as raw:
        tmp = Path(raw)
        ref = tmp / "ref"
        ref.mkdir()
        git(ref, "init", "-q")
        ident = ["-c", "user.name=flutterforge", "-c", "user.email=flutterforge@localhost"]
        for label, rev in (("base", base), ("head", head)):
            git(ref, "rm", "-rq", "--ignore-unmatch", ".")
            build_tree(template, rev, package, ref, with_counter)
            git(ref, "add", "-A")
            git(ref, *ident, "commit", "-q", "--allow-empty", "-m", f"template {label} {rev[:10]}")
        changes = git(ref, "diff", "--name-status", "HEAD~1", "HEAD").splitlines()
        print(f"template-owned files changed: {len(changes)}")
        for line in changes:
            print(f"  {line}")
        deps = dependency_changes(template, base, head)
        if deps:
            print("dependency changes (apply with the commands shown):")
            print("\n".join(deps))
        if args.dry_run:
            print("dry run: nothing changed.")
            return 0

        branch = f"flutterforge-upgrade-{head[:7]}"
        git(app, "switch", "-c", branch)
        git(app, "fetch", "-q", "--no-tags", str(ref), "HEAD")
        picked = run(["git", "-C", str(app), *ident, "cherry-pick", "--no-commit",
                      "FETCH_HEAD"], check=False)
    git(app, "cherry-pick", "--quit", check=False)  # keep changes, drop sequencer state

    (app / STAMP).write_text(json.dumps({
        "templateCommit": head,
        "upgradedFrom": base,
        "upgradedAt": datetime.date.today().isoformat(),
    }, indent=2) + "\n")
    conflicts = git(app, "diff", "--name-only", "--diff-filter=U").split()
    print(f"branch:   {branch} (nothing committed)")
    if conflicts:
        print(f"CONFLICTS ({len(conflicts)}) — resolve each, then `git add` it:")
        for path in conflicts:
            print(f"  {path}")
    elif picked.returncode != 0:
        print(picked.stderr.decode(errors="replace")[-2000:])
        return 1
    else:
        print("merged cleanly.")
    print(f"wrote {STAMP} (records the new base for the next upgrade)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
