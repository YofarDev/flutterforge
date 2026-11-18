"""Upgrade an existing app to a newer FlutterForge template, file by file.

Rebuilds the template-owned files exactly as the generator shipped them at two
template revisions (BASE: what the app was generated from; HEAD: the target)
and classifies every file the template changed:

  take      app still has the base version  -> replaced by the template's
  merge     app and template both changed it -> 3-way merged cleanly
  CONFLICT  same, with overlapping edits     -> written with conflict markers
  add       new template file, the app has its area -> created
  delete    template deleted it, app never changed it -> deleted
  keep      template deleted it, app changed it -> left alone (review)
  skip      new file the app has no place for (missing feature/folder, or
            it imports something the app will not have)
  absent    template changed a file the app removed or moved -> left alone

Nothing is staged or committed. When less than 25% of the base template files
are unchanged in the app, the app counts as DIVERGED and the plan is only
printed unless --apply-diverged is given.

Usage (stdlib only):
    uv run --no-project prepare_upgrade.py --template PATH [--app PATH]
        [--base REV] [--head REV] [--dry-run] [--apply-diverged]
"""
from __future__ import annotations

import argparse
import datetime
import io
import json
import os
import re
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
    "build.yaml": "build.yaml",
    "l10n.yaml": "l10n.yaml",
    "template-README.md": "README.md",
    "templates/github/workflows/flutter-ci.yml": ".github/workflows/flutter-ci.yml",
}
# Template directories copied wholesale (scripts/ is filtered separately).
DIR_MAP = {"lib/": "lib/", "test/": "test/", ".agents/": ".agents/", ".codex/": ".codex/"}
TEMPLATE_ONLY_SCRIPTS = {"scripts/verify_template.sh", "scripts/README.md"}


def run(args: list[str], cwd: Path | None = None, check: bool = True,
        data: bytes | None = None, env: dict | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(args, cwd=cwd, input=data, capture_output=True,
                            env=None if env is None else {**os.environ, **env})
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


# Mirrors create_project.dart: the package placeholder is replaced only in
# these extensions under these app paths (placeholderRoots).
PLACEHOLDER_ROOTS = ("lib", "test", "scripts", ".agents", ".codex", "AGENTS.md",
                     "README.md", "analysis_options.yaml", "l10n.yaml")
PLACEHOLDER_EXTENSIONS = (".dart", ".md", ".yaml", ".arb")


def substitutes_placeholder(app_path: str) -> bool:
    root = app_path.split("/", 1)[0]
    return root in PLACEHOLDER_ROOTS and app_path.endswith(PLACEHOLDER_EXTENSIONS)


def render(path: str, raw: bytes, package: str, app_path: str | None = None) -> bytes:
    """Applies the generator's substitutions to one shipped file (template
    path [path], published at [app_path])."""
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw
    if path == "template-README.md":
        text = text.replace("{PROJECT_NAME}", package)
    if substitutes_placeholder(app_path if app_path is not None else path):
        text = text.replace(PLACEHOLDER, package)
    return text.encode("utf-8")


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
            target.write_bytes(render(member.name, tar.extractfile(member).read(), package,
                                      mapping[member.name]))
            target.chmod(member.mode & 0o777)
    if not with_counter and (out / "remove_counter.sh").exists():
        # Apply the same Counter removal the app went through, to both trees.
        (out / "pubspec.yaml").write_text(f"name: {package}\n")
        # A reference tree is not a Flutter app: skip localization codegen.
        result = run(["bash", "remove_counter.sh"], cwd=out, check=False,
                     env={"FORGE_SKIP_GEN_L10N": "1"})
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
    # Both detection paths need the template's history: the stamp commit must
    # be resolvable, and content matching scores every commit up to head. A
    # shallow clone holds only head, so either path would silently pick head
    # and report "Already up to date" for an app that is commits behind.
    if git(template, "rev-parse", "--is-shallow-repository", check=False).strip() == "true":
        sys.exit(
            "error: the template checkout is a shallow clone, so the app's base commit "
            "cannot be found. Fetch full history (git -C <template> fetch --unshallow) "
            "or pass --base REV explicitly."
        )
    stamp = app / STAMP
    if stamp.exists():
        try:
            data = json.loads(stamp.read_text())
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            sys.exit(f"error: {STAMP} is not valid JSON ({error}); fix it, delete it to "
                     "detect the base by file matching, or pass --base REV explicitly.")
        commit = data.get("templateCommit") if isinstance(data, dict) else None
        if commit:
            if git(template, "cat-file", "-t", commit, check=False).strip() != "commit":
                sys.exit(
                    f"error: {STAMP} records template commit {commit[:10]}, which is not in "
                    "this template checkout (rewritten history, a fork, or an outdated "
                    "clone). Point --template at a checkout that contains it, or pass "
                    "--base REV explicitly."
                )
            note = (" — generated from an uncommitted template: review re-applied hunks"
                    if data.get("templateDirty") else "")
            return commit, f"{STAMP} stamp{note}"
    # Score each template commit by how many shipped files the app still has
    # byte-identical (after reversing the package-name substitution). Ties go
    # to the EARLIEST commit: re-applying a change the app already has merges
    # cleanly, while skipping one would silently lose it.
    def normalize(p: Path) -> bytes:
        raw = (app / p).read_bytes()
        if not substitutes_placeholder(p.as_posix()):
            return raw
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


DART_DIRECTIVE = re.compile(r"""^\s*(?:import|export|part)\s+['"]([^'"]+)['"]""", re.M)
DIVERGED_RATIO = 0.25


def read_tree(root: Path) -> dict[str, bytes]:
    return {str(f.relative_to(root)): f.read_bytes() for f in root.rglob("*") if f.is_file()}


def local_deps(path: str, text: bytes, package: str) -> list[str]:
    """App-relative files a Dart file imports/exports/parts (generated ones excluded)."""
    if not path.endswith(".dart"):
        return []
    deps = []
    for uri in DART_DIRECTIVE.findall(text.decode("utf-8", errors="replace")):
        if uri.startswith(f"package:{package}/"):
            target = "lib/" + uri[len(f"package:{package}/"):]
        elif ":" in uri:
            continue  # dart:, other packages
        else:
            target = os.path.normpath(os.path.join(os.path.dirname(path), uri))
        if "/generated/" in target or target.endswith((".g.dart", ".freezed.dart")):
            continue
        deps.append(target)
    return deps


def area_missing(path: str, app: Path) -> str | None:
    """Why a NEW template file has no place in this app, or None."""
    parts = path.split("/")
    if len(parts) > 3 and parts[0] in ("lib", "test") and parts[1] == "features":
        if not (app / parts[0] / "features" / parts[2]).is_dir():
            return f"feature '{parts[2]}' not in app"
    for root in (".agents", ".codex", "scripts/feature_templates"):
        if path.startswith(root + "/") and not (app / root).is_dir():
            return f"app has no {root}/"
    if not (app / parts[0]).exists():
        return f"app has no {parts[0]}/"
    return None


def merge3(app_text: bytes, base_text: bytes, head_text: bytes) -> tuple[bytes, bool]:
    """git merge-file of app/base/template; returns (result, has_conflicts)."""
    with tempfile.TemporaryDirectory() as raw:
        tmp = Path(raw)
        for name, data in (("app", app_text), ("base", base_text), ("template", head_text)):
            (tmp / name).write_bytes(data)
        result = run(["git", "merge-file", "-p", "-L", "app", "-L", "base", "-L", "template",
                      str(tmp / "app"), str(tmp / "base"), str(tmp / "template")], check=False)
        if result.returncode < 0:
            sys.exit(f"error: git merge-file failed: {result.stderr.decode(errors='replace')}")
        return result.stdout, result.returncode > 0


def plan_upgrade(app: Path, package: str, base_tree: dict[str, bytes],
                 head_tree: dict[str, bytes]) -> tuple[list[tuple[str, str, str]], dict[str, bytes], float]:
    """Classifies every template-owned path. Returns (rows, writes, match_ratio):
    rows are (action, path, note); writes maps path -> new bytes (None = delete)."""
    rows: list[tuple[str, str, str]] = []
    writes: dict[str, bytes | None] = {}
    base_files = [p for p in base_tree if (app / p).is_file()]
    same = sum((app / p).read_bytes() == base_tree[p] for p in base_files)
    ratio = same / len(base_tree) if base_tree else 1.0

    for path in sorted(set(base_tree) | set(head_tree)):
        b, h = base_tree.get(path), head_tree.get(path)
        if b == h:
            continue
        a = (app / path).read_bytes() if (app / path).is_file() else None
        if a == h:
            continue
        if b is None:  # template added the file
            if a is None:
                why = area_missing(path, app)
                if why:
                    rows.append(("skip", path, why))
                else:
                    rows.append(("add", path, ""))
                    writes[path] = h
            else:
                merged, conflict = merge3(a, b"", h)
                rows.append(("CONFLICT" if conflict else "merge", path, "both added"))
                writes[path] = merged
        elif h is None:  # template deleted the file
            if a is None:
                continue
            if a == b:
                rows.append(("delete", path, ""))
                writes[path] = None
            else:
                rows.append(("keep", path, "template deleted it; app changed it: review"))
        elif a is None:  # template changed a file the app does not have
            rows.append(("absent", path, "app removed or moved it"))
        elif a == b:
            rows.append(("take", path, ""))
            writes[path] = h
        else:
            merged, conflict = merge3(a, b, h)
            rows.append(("CONFLICT" if conflict else "merge", path, ""))
            writes[path] = merged

    # Never delete a file that something staying in the app still imports
    # (e.g. a support file of a test the app customized and keeps).
    def importer_of(target: str) -> str | None:
        for folder in ("lib", "test"):
            for file in (app / folder).rglob("*.dart") if (app / folder).is_dir() else []:
                rel = str(file.relative_to(app))
                if rel == target or writes.get(rel, b"") is None:
                    continue
                # Conservative: the app's current copy or the planned new one.
                for content in (file.read_bytes(), writes.get(rel) or b""):
                    if target in local_deps(rel, content, package):
                        return rel
        return None

    kept_one = True
    while kept_one:  # cancelling one delete can make another file needed
        kept_one = False
        for path in [p for p, data in writes.items() if data is None]:
            user = importer_of(path)
            if user:
                del writes[path]
                rows = [(("keep", p, f"template deleted it; still imported by {user}")
                         if p == path else (act, p, note)) for act, p, note in rows]
                kept_one = True

    # A new/updated Dart file must not import something this app will not have.
    def exists_after(target: str) -> bool:
        if target in writes:
            return writes[target] is not None
        return (app / target).is_file()

    changed = True
    while changed:
        changed = False
        for path, data in list(writes.items()):
            if data is None:
                continue
            missing = [d for d in local_deps(path, data, package) if not exists_after(d)]
            if missing:
                del writes[path]
                rows = [(("skip", p, f"needs {missing[0]}") if p == path else (act, p, note))
                        for act, p, note in rows]
                changed = True

    return rows, writes, ratio


MEANING = {
    "CONFLICT": "app and template edited the same lines; written with markers",
    "merge": "app and template both changed it; 3-way merged, review",
    "take": "app copy is byte-identical to the original template file: NOT customized, safe to replace",
    "add": "new template file in an area the app has; check it fits",
    "delete": "template removed it; app copy never changed",
    "keep": "left as is; review",
    "skip": "not written",
    "absent": "template changed it; the app removed or moved it; not written",
}


def print_plan(rows: list[tuple[str, str, str]]) -> None:
    order = ["CONFLICT", "merge", "take", "add", "delete", "keep", "skip", "absent"]
    for action in order:
        group = [(p, n) for a, p, n in rows if a == action]
        if not group:
            continue
        print(f"{action} ({len(group)}) - {MEANING[action]}:")
        if action in ("skip", "absent") and len(group) > 8:
            by_dir: dict[tuple[str, str], list[str]] = {}
            for p, n in group:
                by_dir.setdefault((os.path.dirname(p), n), []).append(p)
            for (folder, note), paths in sorted(by_dir.items()):
                shown = paths[0] if len(paths) == 1 else f"{folder}/ x{len(paths)}"
                print(f"  {shown}  ({note})")
        else:
            for p, n in group:
                print(f"  {p}" + (f"  ({n})" if n else ""))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--app", default=Path.cwd(), type=Path)
    parser.add_argument("--base", help="template revision the app was generated from")
    parser.add_argument("--head", default="HEAD", help="template revision to upgrade to")
    parser.add_argument("--dry-run", action="store_true", help="print the plan; change nothing")
    parser.add_argument("--apply-diverged", action="store_true",
                        help="apply the plan even when the app has diverged from the template")
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
    # Untracked files (audit reports, notes) never block: the upgrade only
    # writes the paths it plans, and refuses below if one of them is untracked.
    if not args.dry_run and git(app, "status", "--porcelain", "--untracked-files=no").strip():
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
    if run(["git", "-C", str(template), "merge-base", "--is-ancestor", base, head],
           check=False).returncode != 0:
        sys.exit(f"error: base {base[:10]} is not an ancestor of head {head[:10]}: the template "
                 "checkout (or --head) is older than the app's template, or on another branch. "
                 "Upgrading would revert template changes; update the template checkout.")
    log = git(template, "log", "--oneline", "--no-decorate", f"{base}..{head}").splitlines()
    print(f"template commits ({len(log)}):")
    for line in log[:40]:
        print(f"  {line}")

    with tempfile.TemporaryDirectory(prefix="flutterforge-upgrade-") as raw:
        trees = {}
        for label, rev in (("base", base), ("head", head)):
            out = Path(raw) / label
            out.mkdir()
            build_tree(template, rev, package, out, with_counter)
            trees[label] = read_tree(out)
        # Permission bits of the target files, so new scripts stay executable.
        head_modes = {path: (Path(raw) / "head" / path).stat().st_mode & 0o777
                      for path in trees["head"]}
    rows, writes, ratio = plan_upgrade(app, package, trees["base"], trees["head"])
    diverged = ratio < DIVERGED_RATIO
    print(f"match:    {ratio:.0%} of the base template files are unchanged in the app"
          + ("  -> DIVERGED" if diverged else ""))
    print_plan(rows)
    deps = dependency_changes(template, base, head)
    if deps:
        print("dependency changes (apply with the commands shown):")
        print("\n".join(deps))
    if args.dry_run:
        print("dry run: nothing changed.")
        return 0
    if diverged and not args.apply_diverged:
        print("Not applied: the app diverged from the template. --apply-diverged writes exactly")
        print("the take/merge/CONFLICT/add/delete files listed above (nothing else); resolve the")
        print("CONFLICT and merge files keeping the app's conventions. Or port the plan by hand.")
        return 3

    untracked = set(git(app, "ls-files", "--others", "--exclude-standard").splitlines())
    clobbered = sorted(path for path in writes if path in untracked)
    if clobbered:
        sys.exit("error: the upgrade would overwrite untracked files; move or commit them first:\n  "
                 + "\n  ".join(clobbered))

    branch = f"flutterforge-upgrade-{head[:7]}"
    git(app, "switch", "-c", branch)
    for path, data in writes.items():
        target = app / path
        if data is None:
            target.unlink()
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        existed = target.exists()
        target.write_bytes(data)
        if not existed and path in head_modes:
            target.chmod(head_modes[path])
    (app / STAMP).write_text(json.dumps({
        "templateCommit": head,
        "upgradedFrom": base,
        "upgradedAt": datetime.date.today().isoformat(),
    }, indent=2) + "\n")
    conflicts = [p for a, p, _ in rows if a == "CONFLICT"]
    print(f"branch:   {branch} (nothing staged or committed)")
    print(f"applied {len(writes)} change(s); "
          + (f"{len(conflicts)} file(s) have conflict markers to resolve." if conflicts
             else "no conflicts."))
    print(f"wrote {STAMP} (records the new base for the next upgrade)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
