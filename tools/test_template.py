#!/usr/bin/env python3
"""Regression tests for the FlutterForge generator and CLI scripts.

Run from the repository root (or use scripts/verify_template.sh):

    ./scripts/verify_template.sh                 # fast level (FORGE_SKIP_SLOW=1)
    ./scripts/verify_template.sh --full          # + real-Flutter smoke suite
    uv run --no-project tools/test_template.py                          # full suite
    uv run --no-project tools/test_template.py -k Refusals              # refusal tests only
    FORGE_SKIP_SLOW=1 uv run --no-project tools/test_template.py        # skip real-Flutter e2e

Note: `unittest -k` matches case-sensitively against test ids and each flag is
an independent pattern (multiple flags are OR'ed); composite expressions with
`or`/`and` are not supported by the CLI.

Two documented levels live here (see docs/compatibility.md):

* FAST tests use controlled fake `flutter`/`dart` executables — never real
  Flutter. They prove that the generator refuses unsafe destinations, parses
  arguments deterministically, stages and publishes at the right paths, and
  reports subprocess failures; that fgen refuses invalid names and existing
  features; that the shipped scripts honor the Bash 3.2 shell contract; that
  `packages_to_add.json` carries constrained dependency specs; and that
  `remove_counter.sh` is harmless when there is nothing to remove.
* The FULL smoke class really runs `flutter create`, template copying,
  package installation, build_runner and `scripts/fverify.sh`; verifies the
  published app from its FINAL path; exercises every fgen combination;
  applies the documented DI/route wiring for a generated feature and proves
  resolution + rendering through the real router; removes the counter feature
  from a second, otherwise-fresh generated app (twice); runs skill
  synchronization in check-only mode; and records Flutter/Dart versions, the
  template git revision and the resolved generated pubspec.lock into
  $FORGE_ARTIFACTS_DIR when that variable is set.

Every generated app is created in a fresh `tempfile.TemporaryDirectory`
outside this checkout and removed afterwards.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATOR = REPO_ROOT / "create_project.dart"
FGEN = REPO_ROOT / "scripts" / "fgen.sh"

COMMAND_TIMEOUT = int(os.environ.get("FORGE_TIMEOUT", "300"))
SLOW_TIMEOUT = int(os.environ.get("FORGE_SLOW_TIMEOUT", "1800"))

# Every script that runs tests holds the machine-wide queue (scripts/fqueue.sh).
# The harness gets its own, so it never waits on (or blocks) the developer's
# other projects and its runs stay deterministic.
os.environ.setdefault("FORGE_QUEUE_DIR", tempfile.mkdtemp(prefix="forge-queue-"))

REAL_DART = shutil.which("dart")
if REAL_DART is None:
    sys.exit("dart must be on PATH to run the FlutterForge generator tests.")

# --- Fake tool machinery (fast tests) --------------------------------------------
# Fake `flutter`/`dart` log every invocation (one argument per line, '---'
# separates invocations) and can be told to fail. `create` also creates the
# staging directory and a minimal pubspec.yaml so the generator can proceed.

FAKE_FLUTTER = """#!/bin/sh
printf '%s\\n' "$@" >> "$FORGE_FAKE_LOG"
echo '---' >> "$FORGE_FAKE_LOG"
if [ -n "${FORGE_FAKE_FLUTTER_FAIL:-}" ]; then
  echo 'fake-flutter: simulated failure' >&2
  exit 64
fi
if [ "${1:-}" = "create" ]; then
  for a in "$@"; do :; done
  mkdir -p "$a"
  printf 'name: fake_created_project\\ndescription: placeholder\\nenvironment:\\n  sdk: ">=3.0.0 <4.0.0"\\nflutter:\\n' > "$a/pubspec.yaml"
fi
exit 0
"""

FAKE_DART = """#!/bin/sh
printf '%s\\n' "$@" >> "$FORGE_FAKE_LOG"
echo '---' >> "$FORGE_FAKE_LOG"
if [ -n "${FORGE_FAKE_DART_FAIL:-}" ]; then
  echo 'fake-dart: simulated failure' >&2
  exit 70
fi
if [ "${1:-}" = "fix" ] && [ "${2:-}" = "--dry-run" ]; then
  echo "${FORGE_FAKE_FIX_PREVIEW:-3 proposed fixes in 2 files.}"
fi
exit 0
"""


def fake_tool_env(
    directory: Path, *, flutter_fail: bool = False, dart_fail: bool = False
) -> tuple[dict, Path]:
    """Creates fake `flutter`/`dart` shadowing the real ones on PATH."""
    bin_dir = directory / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    flutter = bin_dir / "flutter"
    flutter.write_text(FAKE_FLUTTER)
    flutter.chmod(0o755)
    dart = bin_dir / "dart"
    dart.write_text(FAKE_DART)
    dart.chmod(0o755)
    log = directory / "fake_tools.log"
    log.touch()
    env = dict(os.environ)
    env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '')}"
    env["FORGE_FAKE_LOG"] = str(log)
    env.pop("FORGE_FAKE_FLUTTER_FAIL", None)
    env.pop("FORGE_FAKE_DART_FAIL", None)
    if flutter_fail:
        env["FORGE_FAKE_FLUTTER_FAIL"] = "1"
    if dart_fail:
        env["FORGE_FAKE_DART_FAIL"] = "1"
    return env, log


def read_invocations(log: Path) -> list[list[str]]:
    if not log.exists():
        return []
    invocations: list[list[str]] = []
    current: list[str] = []
    for line in log.read_text().splitlines():
        if line == "---":
            if current:
                invocations.append(current)
                current = []
        else:
            current.append(line)
    if current:
        invocations.append(current)
    return invocations


def run_generator(args: list[str], cwd: Path, env: dict | None = None, timeout: int = COMMAND_TIMEOUT,
                  generator: Path = GENERATOR) -> subprocess.CompletedProcess:
    command = [REAL_DART, str(generator), *args]
    return subprocess.run(
        command,
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def run_fgen(name: str, cwd: Path, timeout: int = COMMAND_TIMEOUT, flags: list[str] | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(FGEN), name, *(flags or [])],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def run_command(command: list[str], cwd: Path, timeout: int = COMMAND_TIMEOUT) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        cwd=str(cwd),
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def fmt(result: subprocess.CompletedProcess) -> str:
    out = (result.stdout or "")[-4000:]
    err = (result.stderr or "")[-4000:]
    return f"\n--- exit: {result.returncode} ---\n--- stdout tail ---\n{out}\n--- stderr tail ---\n{err}"


def tree_snapshot(root: Path) -> list[tuple[str, bytes]]:
    """Sorted (relative path, content) snapshot of a tree, symlink-safe.

    Git's own object store is skipped: background maintenance (gc, the
    `maintenance.lock`) may change it at any time without any tool writing to
    the working tree. Worktree state is what these snapshots protect.
    """
    entries: list[tuple[str, bytes]] = []
    for path in sorted(root.rglob("*")):
        if path.relative_to(root).parts[:2] == (".git", "objects"):
            continue
        if path.is_symlink():
            entries.append((str(path.relative_to(root)), os.readlink(path).encode()))
        elif path.is_file():
            entries.append((str(path.relative_to(root)), path.read_bytes()))
        else:
            entries.append((str(path.relative_to(root)), b"<dir>"))
    return entries


def make_fake_app(parent: Path, name: str = "fake_app") -> Path:
    """Minimal app skeleton for fgen refusal tests (never runs Flutter)."""
    app = parent / name
    (app / "lib").mkdir(parents=True)
    (app / "pubspec.yaml").write_text("name: fake_app\ndescription: fake\n")
    return app


# ----------------------------------------------------------------------------------
# Fast: argument parsing, staging paths, publication (fake tools)
# ----------------------------------------------------------------------------------


class TestArgumentParsing(unittest.TestCase):
    """Supported argument orderings produce the intended destination and metadata.

    Success here (with fake tools) proves argument handling, staging paths and
    publication only — real Flutter creation is covered by the e2e class.
    """

    def test_attached_org_before_destination(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            result = run_generator(
                ["--org=com.example.custom", "--no-open", "my_app"], cwd=workdir, env=env
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            invocations = read_invocations(log)
            self.assertTrue(invocations, "the generator should invoke the fake tools")
            create = invocations[0]
            self.assertEqual(create[0], "create")
            self.assertIn("--org=com.example.custom", create)
            self.assertIn("--project-name=my_app", create)
            staging = create[-1]
            self.assertTrue(
                staging.startswith(str(workdir) + "/.flutterforge-stage-my_app-"),
                msg=staging,
            )
            for invocation in invocations:
                self.assertNotIn(
                    str(workdir / "my_app"),
                    invocation,
                    "the final destination must not be passed to any tool",
                )
            self.assertTrue((workdir / "my_app").is_dir())

    def test_separate_option_values_after_destination(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            result = run_generator(
                [
                    "my_app",
                    "--org",
                    "com.example.custom",
                    "--platforms",
                    "android,ios",
                    "--description",
                    "My custom description",
                    "--no-open",
                ],
                cwd=workdir,
                env=env,
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            create = read_invocations(log)[0]
            self.assertIn("--org=com.example.custom", create)
            self.assertIn("--project-name=my_app", create)
            self.assertIn("--platforms", create)
            self.assertIn("android,ios", create)
            self.assertIn("--description=My custom description", create)

    def test_default_org_used_when_omitted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            result = run_generator(["--no-open", "my_app"], cwd=workdir, env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("--org=fr.yofardev", read_invocations(log)[0])

    def test_explicit_project_name_decouples_package_from_directory(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            result = run_generator(
                ["--no-open", "--project-name=custom_name", "weird dir name"],
                cwd=workdir,
                env=env,
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            create = read_invocations(log)[0]
            self.assertIn("--project-name=custom_name", create)
            self.assertNotIn("--project-name=weird dir name", create)
            self.assertTrue((workdir / "weird dir name").is_dir())

    def test_absolute_destination_with_spaces_in_parent(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            parent = workdir / "parent dir with spaces"
            parent.mkdir()
            env, log = fake_tool_env(workdir)
            destination = parent / "dest_app"
            result = run_generator(
                ["--no-open", str(destination)], cwd=workdir, env=env
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            create = read_invocations(log)[0]
            staging = create[-1]
            self.assertTrue(
                staging.startswith(str(parent) + "/.flutterforge-stage-dest_app-"),
                msg=staging,
            )
            self.assertIn(" ", staging, "the spaced path must survive as one argument")
            self.assertTrue(destination.is_dir())

    def test_relative_destination_with_spaces_in_parent(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = (Path(raw).resolve()) / "spaced parent"
            workdir.mkdir()
            env, log = fake_tool_env(workdir)
            result = run_generator(["--no-open", "my_app"], cwd=workdir, env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            staging = read_invocations(log)[0][-1]
            self.assertTrue(
                staging.startswith(str(workdir) + "/.flutterforge-stage-my_app-"),
                msg=staging,
            )
            self.assertTrue((workdir / "my_app").is_dir())

    def test_multiple_destinations_rejected_before_flutter(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir, flutter_fail=True)
            result = run_generator(["first_app", "second_app"], cwd=workdir, env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(read_invocations(log), [])
            self.assertFalse((workdir / "first_app").exists())
            self.assertFalse((workdir / "second_app").exists())

    def test_missing_destination_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir, flutter_fail=True)
            result = run_generator(["--no-open"], cwd=workdir, env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(read_invocations(log), [])

    def test_option_value_without_value_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir, flutter_fail=True)
            result = run_generator(["--org"], cwd=workdir, env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(read_invocations(log), [])

    def test_help_exits_zero_without_generating(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_arg_") as raw:
            workdir = Path(raw).resolve()
            result = run_generator(["--help"], cwd=workdir)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Usage", result.stdout)
            self.assertEqual(list(workdir.iterdir()), [])


# ----------------------------------------------------------------------------------
# Fast: destination refusals (fake tools, flutter must not be invoked)
# ----------------------------------------------------------------------------------


class TestDestinationRefusals(unittest.TestCase):
    """Existing targets are refused without changing content."""

    def _run_refusal(self, parent: Path, destination: Path) -> subprocess.CompletedProcess:
        env, log = fake_tool_env(parent, flutter_fail=True)
        result = run_generator(["--no-open", str(destination)], cwd=parent, env=env)
        self.assertEqual(read_invocations(log), [], "flutter must not be invoked")
        return result

    def test_existing_directory_with_sentinel_files_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_refuse_") as raw:
            parent = Path(raw).resolve()
            destination = parent / "dest"
            destination.mkdir()
            (destination / "lib").mkdir()
            (destination / "lib" / "user_edit.dart").write_text("// precious user work\n")
            (destination / "sentinel.txt").write_text("user data")
            before = tree_snapshot(destination)
            result = self._run_refusal(parent, destination)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(tree_snapshot(destination), before)
            self.assertIn("already exists", result.stderr)

    def test_empty_directory_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_refuse_") as raw:
            parent = Path(raw).resolve()
            destination = parent / "dest"
            destination.mkdir()
            result = self._run_refusal(parent, destination)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(list(destination.iterdir()), [])
            self.assertIn("already exists", result.stderr)

    def test_existing_file_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_refuse_") as raw:
            parent = Path(raw).resolve()
            destination = parent / "dest"
            destination.write_text("i am a plain file")
            result = self._run_refusal(parent, destination)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(destination.read_text(), "i am a plain file")

    def test_symlinked_directory_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_refuse_") as raw:
            parent = Path(raw).resolve()
            target = parent / "real_dir"
            target.mkdir()
            (target / "keep.txt").write_text("inside")
            destination = parent / "dest"
            destination.symlink_to(target)
            result = self._run_refusal(parent, destination)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertTrue(destination.is_symlink())
            self.assertEqual((target / "keep.txt").read_text(), "inside")

    def test_dangling_symlink_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_refuse_") as raw:
            parent = Path(raw).resolve()
            destination = parent / "dest"
            destination.symlink_to(parent / "does_not_exist")
            result = self._run_refusal(parent, destination)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertTrue(destination.is_symlink())
            self.assertFalse((parent / "does_not_exist").exists())

    def test_template_root_itself_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_refuse_") as raw:
            parent = Path(raw).resolve()
            env, log = fake_tool_env(parent, flutter_fail=True)
            result = run_generator(["--no-open", str(REPO_ROOT)], cwd=parent, env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(read_invocations(log), [])
            self.assertIn("template root", result.stderr)

    def test_rerunning_project_generation_preserves_edits_and_exits_nonzero(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_refuse_") as raw:
            parent = Path(raw).resolve()
            destination = parent / "dest"
            # Simulate an existing app the user has edited.
            (destination / "lib").mkdir(parents=True)
            (destination / "pubspec.yaml").write_text("name: dest\n")
            (destination / "lib" / "user_edit.dart").write_text("// precious user work\n")
            before = tree_snapshot(destination)
            result = self._run_refusal(parent, destination)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(tree_snapshot(destination), before)
            self.assertIn("never overwrites", result.stderr)


# ----------------------------------------------------------------------------------
# Fast: subprocess failures (fake tools, failure modes)
# ----------------------------------------------------------------------------------


class TestGeneratorEdgeCases(unittest.TestCase):
    """Edge cases of argument parsing, names and failure reporting."""

    def test_trailing_slash_names_the_directory(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_edge_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            result = run_generator(["--no-open", "my_app/"], cwd=workdir, env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("--project-name=my_app", read_invocations(log)[0])
            self.assertTrue((workdir / "my_app").is_dir())

    def test_help_flag_as_an_option_value_is_a_value(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_edge_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            result = run_generator(
                ["--no-open", "--description", "-h", "my_app"], cwd=workdir, env=env
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("--description=-h", read_invocations(log)[0])

    def test_repeated_option_is_rejected_before_any_tool_runs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_edge_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            result = run_generator(
                ["--no-open", "--org=a.b", "--org=c.d", "my_app"], cwd=workdir, env=env
            )
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("more than once", result.stderr)
            self.assertEqual(read_invocations(log), [])

    def test_dependency_package_name_is_rejected_up_front(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_edge_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            for name in ("go_router", "intl", "flutter_test"):
                with self.subTest(name=name):
                    result = run_generator(["--no-open", name], cwd=workdir, env=env)
                    self.assertNotEqual(result.returncode, 0, msg=fmt(result))
                    self.assertIn("depends on", result.stderr)
                    self.assertFalse((workdir / name).exists())
            self.assertEqual(read_invocations(log), [])

    def test_destination_inside_the_template_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_edge_") as raw:
            workdir = Path(raw).resolve()
            env, log = fake_tool_env(workdir)
            inside = REPO_ROOT / "forge_inside_template_probe"
            self.assertFalse(inside.exists())
            result = run_generator(["--no-open", str(inside)], cwd=workdir, env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("inside the template checkout", result.stderr)
            self.assertFalse(inside.exists())

    def test_unexpected_error_takes_the_documented_failure_path(self) -> None:
        """A permission error (not a FailureException) still prints a message
        and exits 1, never a raw unhandled-exception crash (exit 255)."""
        if os.geteuid() == 0:
            self.skipTest("root ignores directory permissions")
        with tempfile.TemporaryDirectory(prefix="forge_edge_") as raw:
            workdir = Path(raw).resolve()
            env, _ = fake_tool_env(workdir)
            parent = workdir / "readonly"
            parent.mkdir()
            parent.chmod(0o555)
            try:
                result = run_generator(["--no-open", str(parent / "my_app")], cwd=workdir, env=env)
            finally:
                parent.chmod(0o755)
            self.assertEqual(result.returncode, 1, msg=fmt(result))
            self.assertIn("Error: unexpected failure", result.stderr)
            self.assertNotIn("Unhandled exception", result.stderr)


class TestSubprocessFailure(unittest.TestCase):
    """A subprocess failure returns nonzero and never reports setup complete."""

    def _assert_failure_keeps_staging(self, result: subprocess.CompletedProcess, parent: Path) -> None:
        self.assertNotEqual(result.returncode, 0, msg=fmt(result))
        combined = (result.stdout or "") + (result.stderr or "")
        self.assertNotIn("Project setup complete", combined)
        self.assertFalse((parent / "my_app").exists(), "destination must not be published")
        retained = [p for p in parent.iterdir() if p.name.startswith(".flutterforge-stage-")]
        self.assertEqual(len(retained), 1, "failed staging directory should be retained")
        self.assertIn(retained[0].name, combined, "the retained staging path must be reported")

    def test_flutter_create_failure_is_reported(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fail_") as raw:
            parent = Path(raw).resolve()
            env, log = fake_tool_env(parent, flutter_fail=True)
            result = run_generator(["--no-open", "my_app"], cwd=parent, env=env)
            self._assert_failure_keeps_staging(result, parent)
            self.assertEqual(len(read_invocations(log)), 1)

    def test_late_subprocess_failure_is_reported(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fail_") as raw:
            parent = Path(raw).resolve()
            env, log = fake_tool_env(parent, dart_fail=True)
            result = run_generator(["--no-open", "my_app"], cwd=parent, env=env)
            self._assert_failure_keeps_staging(result, parent)
            self.assertTrue(read_invocations(log), "flutter create should have been attempted")


# ----------------------------------------------------------------------------------
# Fast: fgen refusals (no Flutter involved)
# ----------------------------------------------------------------------------------


class TestFgenRefusals(unittest.TestCase):
    """Invalid feature names and execution outside an app write nothing."""

    INVALID_NAMES = [
        "",
        "..",
        ".",
        "foo/bar",
        "foo bar",
        "my-feature",
        "1abc",
        "_abc",
        "foo..bar",
        "with.dot",
        "class",
        "import",
        "return",
        "sealed",
        "UPPER!",
        "new_",
        "abc_",
        "a__b",
    ]

    def test_invalid_names_write_nothing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fgen_") as raw:
            parent = Path(raw).resolve()
            for index, name in enumerate(self.INVALID_NAMES):
                with self.subTest(name=name):
                    app = make_fake_app(parent, f"app_{index}")
                    result = run_fgen(name, cwd=app)
                    self.assertNotEqual(result.returncode, 0, msg=fmt(result))
                    self.assertFalse((app / "lib" / "features").exists(), msg=result.stderr)
                    self.assertFalse((app / "test" / "features").exists(), msg=result.stderr)

    def test_execution_outside_an_app_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fgen_") as raw:
            outside = Path(raw).resolve() / "not_an_app"
            outside.mkdir()
            result = run_fgen("valid_name", cwd=outside)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(list(outside.iterdir()), [])
            self.assertIn("No Flutter application found", result.stderr)

    def test_existing_feature_is_refused_and_preserved(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fgen_") as raw:
            app = make_fake_app(Path(raw).resolve())
            feature_dir = app / "lib" / "features" / "existing" / "domain"
            feature_dir.mkdir(parents=True)
            sentinel = feature_dir / "keep.dart"
            sentinel.write_text("// user edit\n")
            result = run_fgen("existing", cwd=app)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(sentinel.read_text(), "// user edit\n")
            self.assertIn("already exists", result.stderr)
            self.assertFalse((app / "test" / "features" / "existing").exists())

    def test_existing_test_dir_only_is_refused_without_publishing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fgen_") as raw:
            app = make_fake_app(Path(raw).resolve())
            (app / "test" / "features" / "pair").mkdir(parents=True)
            result = run_fgen("pair", cwd=app)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertFalse((app / "lib" / "features" / "pair").exists())

    def test_l10n_key_collision_is_refused_before_writing(self) -> None:
        """A feature whose '<camel>Title' key already exists is refused cleanly.

        The screen references '<camel>Title'/'<camel>Data'; colliding with an
        existing ARB key must be a refusal BEFORE anything is staged or
        published — not a post-publish fstr failure leaving a half-feature.
        """
        with tempfile.TemporaryDirectory(prefix="forge_fgen_") as raw:
            app = make_fake_app(Path(raw).resolve())
            arb_dir = app / "lib" / "core" / "l10n"
            arb_dir.mkdir(parents=True)
            for locale in ("en", "fr"):
                (arb_dir / f"app_localizations_{locale}.arb").write_text(
                    '{\n  "collidedTitle": "Already used"\n}\n'
                )
            result = run_fgen("collided", cwd=app)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            # Nothing was written: no feature directories were created.
            self.assertFalse((app / "lib" / "features").exists(), msg=result.stderr)
            self.assertFalse((app / "test" / "features").exists(), msg=result.stderr)
            # The failure identifies the colliding key and the ARB path (the
            # English ARB is checked first, so it is the one named).
            self.assertIn("collidedTitle", result.stderr)
            self.assertIn("app_localizations_en.arb", result.stderr)

    def test_symlinked_feature_dir_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fgen_") as raw:
            app = make_fake_app(Path(raw).resolve())
            target = app / "elsewhere"
            target.mkdir()
            link = app / "lib" / "features" / "linked"
            link.parent.mkdir(parents=True)
            link.symlink_to(target)
            result = run_fgen("linked", cwd=app)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertTrue(link.is_symlink())
            self.assertEqual(list(target.iterdir()), [])

    def test_subdirectory_of_app_resolves_root(self) -> None:
        """The app root is resolved from ancestors, not the current directory."""
        with tempfile.TemporaryDirectory(prefix="forge_fgen_") as raw:
            app = make_fake_app(Path(raw).resolve())
            nested = app / "lib" / "core"
            nested.mkdir(parents=True)
            # An invalid name is enough to prove the root resolved: the error
            # must be about the name, not about a missing application.
            result = run_fgen("class", cwd=nested)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertNotIn("No Flutter application found", result.stderr)


# ----------------------------------------------------------------------------------
# Fast: shell contract — shipped scripts must run under macOS's stock Bash 3.2
# ----------------------------------------------------------------------------------


SYSTEM_BASH = "/bin/bash" if Path("/bin/bash").exists() else "bash"
SHIPPED_SCRIPTS = sorted((REPO_ROOT / "scripts").glob("*.sh")) + [
    REPO_ROOT / "remove_counter.sh"
]


class TestFeatureRenderer(unittest.TestCase):
    def test_values_are_literal_and_not_recursively_expanded(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_render_") as raw:
            template = Path(raw) / "feature.dart.tpl"
            template.write_text("{{VALUE}}\n{{OTHER}}\n")
            value = "$(touch sentinel) `touch sentinel` $HOME {{OTHER}}"
            result = run_command([
                "uv", "run", "--no-project", str(REPO_ROOT / "scripts/render_feature.py"),
                str(template), "VALUE", value, "OTHER", "done",
            ], cwd=template.parent)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(result.stdout, value + "\ndone\n")
            self.assertFalse((template.parent / "sentinel").exists())

    def test_missing_values_fail_without_partial_output(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_render_") as raw:
            template = Path(raw) / "feature.dart.tpl"
            template.write_text("before {{MISSING}} after\n")
            result = run_command([
                "uv", "run", "--no-project", str(REPO_ROOT / "scripts/render_feature.py"),
                str(template),
            ], cwd=template.parent)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(result.stdout, "")
            self.assertIn("MISSING", result.stderr)


    def _jobs(self, path: Path, *jobs: tuple[str, ...]) -> None:
        path.write_bytes(b"".join(field.encode() + b"\0" for job in jobs for field in job))

    def test_batch_writes_and_appends_in_order(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_render_") as raw:
            root = Path(raw)
            (root / "a.tpl").write_text("head {{X}}\n")
            (root / "b.tpl").write_text("tail {{Y}}\n")
            jobs = root / "render.jobs"
            out = root / "out.dart"
            self._jobs(
                jobs,
                ("w", str(out), str(root / "a.tpl"), "1", "X", "multi\nline %s"),
                ("a", str(out), str(root / "b.tpl"), "1", "Y", "$(nope)"),
            )
            result = run_command([
                "uv", "run", "--no-project", str(REPO_ROOT / "scripts/render_feature.py"),
                "--batch", str(jobs),
            ], cwd=root)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(out.read_text(), "head multi\nline %s\ntail $(nope)\n")

    def test_batch_failure_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_render_") as raw:
            root = Path(raw)
            (root / "ok.tpl").write_text("{{X}}\n")
            (root / "bad.tpl").write_text("{{MISSING}}\n")
            jobs = root / "render.jobs"
            self._jobs(
                jobs,
                ("w", str(root / "first.dart"), str(root / "ok.tpl"), "1", "X", "x"),
                ("w", str(root / "second.dart"), str(root / "bad.tpl"), "0"),
            )
            result = run_command([
                "uv", "run", "--no-project", str(REPO_ROOT / "scripts/render_feature.py"),
                "--batch", str(jobs),
            ], cwd=root)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("MISSING", result.stderr)
            self.assertFalse((root / "first.dart").exists())


class TestShellContract(unittest.TestCase):
    """The documented shell contract (docs/compatibility.md) is enforced.

    On the macOS dev machine /bin/bash IS the stock 3.2.57, so this is a real
    Bash 3.2 parse/run; on Linux it is the system Bash (still a full parse
    and functional run of the helpers).
    """

    def test_every_shipped_script_parses_under_system_bash(self) -> None:
        for script in SHIPPED_SCRIPTS:
            with self.subTest(script=script.name):
                result = run_command([SYSTEM_BASH, "-n", str(script)], cwd=REPO_ROOT)
                self.assertEqual(result.returncode, 0, msg=fmt(result))

    def test_no_bash4_only_constructs_in_shipped_scripts(self) -> None:
        """No mapfile/readarray/namerefs — they break macOS's stock Bash 3.2."""
        for script in SHIPPED_SCRIPTS:
            with self.subTest(script=script.name):
                for lineno, line in enumerate(
                    script.read_text().splitlines(), start=1
                ):
                    code = line.split("#", 1)[0]
                    for forbidden in ("mapfile ", "readarray ", "local -n", "declare -n"):
                        self.assertNotIn(
                            forbidden,
                            code,
                            msg=f"{script.name}:{lineno} uses '{forbidden.strip()}'",
                        )

    def test_fdead_runs_under_system_bash(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_shell_") as raw:
            app = Path(raw).resolve() / "app"
            (app / "lib" / "core").mkdir(parents=True)
            (app / "pubspec.yaml").write_text("name: fake_app\n")
            (app / "lib" / "main.dart").write_text("void main() {}\n")
            (app / "lib" / "orphan.dart").write_text("void main() {}\n")
            result = run_command(
                [SYSTEM_BASH, str(REPO_ROOT / "scripts" / "fdead.sh"), "--test"],
                cwd=app,
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("orphan.dart", result.stdout)

    def test_fl10n_runs_under_system_bash(self) -> None:
        if shutil.which("uv") is None:
            self.skipTest("uv is not on PATH")
        with tempfile.TemporaryDirectory(prefix="forge_shell_") as raw:
            app = Path(raw).resolve() / "app"
            (app / "lib").mkdir(parents=True)
            (app / "pubspec.yaml").write_text("name: fake_app\n")
            (app / "lib" / "foo.dart").write_text(
                "import 'package:material_ui/material_ui.dart';\n"
                "class Foo extends StatelessWidget {\n"
                "  const Foo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return const Text('Hello Wonderful World');\n"
                "  }\n"
                "}\n"
            )
            result = run_command(
                [SYSTEM_BASH, str(REPO_ROOT / "scripts" / "fl10n.sh")], cwd=app
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Hello Wonderful World", result.stdout)


class TestFdeadAdvisory(unittest.TestCase):
    """fdead.sh is advisory only: no supported invocation deletes anything.

    The textual basename scan cannot prove deletion is safe, so the cleanup
    flags must be refused and ordinary scans must leave the tree untouched.
    """

    def _make_app(self, parent: Path, name: str = "fdead_app") -> Path:
        """App with an orphan, conditional implementation files, and an empty
        directory whose only content is a .gitkeep placeholder."""
        app = parent / name
        (app / "lib").mkdir(parents=True)
        (app / "pubspec.yaml").write_text("name: fdead_app\n")
        (app / "lib" / "main.dart").write_text(
            "import 'feature.dart';\nvoid main() {}\n"
        )
        (app / "lib" / "feature.dart").write_text(
            "import 'impl_stub.dart' if (dart.library.io) 'impl_io.dart';\n"
            "void feature() {}\n"
        )
        (app / "lib" / "impl_stub.dart").write_text("void impl() {}\n")
        (app / "lib" / "impl_io.dart").write_text("void impl() {}\n")
        # Not imported anywhere — the advisory finding.
        (app / "lib" / "orphan.dart").write_text("void orphan() {}\n")
        (app / "lib" / "empty" / ".gitkeep").parent.mkdir()
        (app / "lib" / "empty" / ".gitkeep").write_text("")
        return app

    def _run_fdead(self, app: Path, *flags: str) -> subprocess.CompletedProcess:
        return run_command(
            ["bash", str(REPO_ROOT / "scripts" / "fdead.sh"), *flags], cwd=app
        )

    def test_default_scan_reports_orphans_and_changes_nothing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fdead_") as raw:
            app = self._make_app(Path(raw).resolve())
            before = tree_snapshot(app)
            result = self._run_fdead(app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("orphan.dart", result.stdout)
            self.assertIn("Potentially Unreferenced Files", result.stdout)
            self.assertNotIn("--clean-dead", result.stdout)
            self.assertEqual(tree_snapshot(app), before, "a scan must not mutate the tree")

    def test_test_flag_scan_is_non_mutating(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fdead_") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "test").mkdir()
            (app / "test" / "orphan_test.dart").write_text("void main() {}\n")
            (app / "test" / "unreferenced_helper.dart").write_text("void h() {}\n")
            before = tree_snapshot(app)
            result = self._run_fdead(app, "--test")
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("unreferenced_helper.dart", result.stdout)
            self.assertNotIn("orphan_test.dart", result.stdout, "test entry points are excluded")
            self.assertEqual(tree_snapshot(app), before)

    def test_clean_dead_flag_is_rejected_without_any_change(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fdead_") as raw:
            app = self._make_app(Path(raw).resolve())
            before = tree_snapshot(app)
            result = self._run_fdead(app, "--clean-dead")
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("deletion is disabled", result.stdout + result.stderr)
            self.assertIn("manual review", result.stdout + result.stderr)
            self.assertEqual(tree_snapshot(app), before)

    def test_clean_empty_flag_is_rejected_and_gitkeep_survives(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fdead_") as raw:
            app = self._make_app(Path(raw).resolve())
            before = tree_snapshot(app)
            result = self._run_fdead(app, "--clean-empty")
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("deletion is disabled", result.stdout + result.stderr)
            self.assertEqual(tree_snapshot(app), before)
            self.assertTrue((app / "lib" / "empty" / ".gitkeep").exists())

    def test_unimported_feature_barrel_is_not_reported(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fdead_") as raw:
            app = self._make_app(Path(raw).resolve())
            barrel = app / "lib" / "features" / "shop" / "shop.dart"
            barrel.parent.mkdir(parents=True)
            barrel.write_text("library;\n")
            result = self._run_fdead(app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertNotIn("shop.dart", result.stdout)

    def test_conditional_implementation_files_survive_scan(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fdead_") as raw:
            app = self._make_app(Path(raw).resolve())
            impl_io = app / "lib" / "impl_io.dart"
            content_before = impl_io.read_bytes()
            result = self._run_fdead(app, "--test")
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertTrue(impl_io.exists())
            self.assertEqual(impl_io.read_bytes(), content_before)

    def test_reports_caveats_about_textual_scan(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fdead_") as raw:
            app = self._make_app(Path(raw).resolve())
            result = self._run_fdead(app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            for caveat in ("conditional", "entry", "collisions"):
                self.assertIn(caveat, result.stdout.lower(), msg=caveat)


class TestFstrInsertion(unittest.TestCase):
    """fstr.sh validates both ARB files strictly and never alters existing
    translations — a failed insertion performs no writes at all."""

    def _make_app(self, parent: Path, name: str = "fstr_app") -> Path:
        app = parent / name
        l10n = app / "lib" / "core" / "l10n"
        l10n.mkdir(parents=True)
        (app / "lib" / "main.dart").write_text("void main() {}\n")
        (l10n / "app_localizations_en.arb").write_text(
            '{\n'
            '  "@@locale": "en",\n'
            '  "hello": "Hello",\n'
            '  "@hello": "Greeting shown on the home screen",\n'
            '  "farewell": "Goodbye"\n'
            '}\n'
        )
        (l10n / "app_localizations_fr.arb").write_text(
            '{\n'
            '  "@@locale": "fr",\n'
            '  "hello": "Bonjour",\n'
            '  "@hello": "Salutation affichée sur l\\u2019écran d\\u2019accueil",\n'
            '  "farewell": "Au revoir"\n'
            '}\n'
        )
        return app

    def _run_fstr(self, app: Path, key: str, fr: str, en: str, env: dict | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(REPO_ROOT / "scripts" / "fstr.sh"), key, fr, en, str(app)],
            cwd=str(app),
            env=env,
            capture_output=True,
            text=True,
            timeout=COMMAND_TIMEOUT,
        )

    def _assert_arbs_unchanged(self, app: Path, before: dict[str, bytes]) -> None:
        l10n = app / "lib" / "core" / "l10n"
        self.assertEqual((l10n / "app_localizations_en.arb").read_bytes(), before["en"])
        self.assertEqual((l10n / "app_localizations_fr.arb").read_bytes(), before["fr"])

    def _arb_snapshot(self, app: Path) -> dict[str, bytes]:
        l10n = app / "lib" / "core" / "l10n"
        return {
            "en": (l10n / "app_localizations_en.arb").read_bytes(),
            "fr": (l10n / "app_localizations_fr.arb").read_bytes(),
        }

    def test_trailing_commas_brackets_and_braces_survive_unchanged(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            env, _ = fake_tool_env(app)
            for language, value in (("en", "Hello, } and, ]"), ("fr", "Bonjour, } et, ]")):
                path = app / f"lib/core/l10n/app_localizations_{language}.arb"
                data = json.loads(path.read_text())
                data["hello"] = value
                path.write_text(json.dumps(data))
            result = self._run_fstr(app, "punctKey", "Nouveau", "New", env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            en = json.loads((app / "lib/core/l10n/app_localizations_en.arb").read_text())
            fr = json.loads((app / "lib/core/l10n/app_localizations_fr.arb").read_text())
            self.assertEqual(en["punctKey"], "New")
            self.assertEqual(fr["punctKey"], "Nouveau")
            self.assertEqual(en["hello"], "Hello, } and, ]")
            self.assertEqual(fr["hello"], "Bonjour, } et, ]")

    def test_reserved_and_generated_member_keys_are_rejected(self) -> None:
        for key in ("localeName", "of", "delegate", "supportedLocales", "localizationsDelegates", "new", "class"):
            with self.subTest(key=key):
                with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
                    app = self._make_app(Path(raw).resolve())
                    env, _ = fake_tool_env(app)
                    before = self._arb_snapshot(app)
                    result = self._run_fstr(app, key, "Nouveau", "New", env=env)
                    self.assertNotEqual(result.returncode, 0, msg=fmt(result))
                    self._assert_arbs_unchanged(app, before)

    def test_failed_gen_l10n_restores_both_arbs_exactly(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            env, _ = fake_tool_env(app, flutter_fail=True)
            before = self._arb_snapshot(app)
            result = self._run_fstr(app, "badIcu", "Use {a, b}", "Use {a, b}", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self._assert_arbs_unchanged(app, before)

    def test_non_json_numeric_constants_change_neither_arb(self) -> None:
        for language in ("fr", "en"):
            for constant in ("NaN", "Infinity", "-Infinity"):
                with self.subTest(language=language, constant=constant):
                    with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
                        app = self._make_app(Path(raw).resolve())
                        path = app / f"lib/core/l10n/app_localizations_{language}.arb"
                        path.write_text('{"hello": "Hello", "@hello": {"value": ' + constant + '}}')
                        env, _ = fake_tool_env(app)
                        before = self._arb_snapshot(app)
                        result = self._run_fstr(app, "newKey", "Nouveau", "New", env=env)
                        self.assertNotEqual(result.returncode, 0, msg=fmt(result))
                        self._assert_arbs_unchanged(app, before)

    def test_escapes_newlines_unicode_and_placeholders_survive(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            env, _ = fake_tool_env(app)
            fr = "Prix: \"€100\"\nPour {userName}, chemin C:\\temp → café"
            en = "Price: \"$100\"\nFor {userName}, path C:\\temp — ok"
            result = self._run_fstr(app, "priceKey", fr, en, env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            en_data = json.loads((app / "lib/core/l10n/app_localizations_en.arb").read_text())
            fr_data = json.loads((app / "lib/core/l10n/app_localizations_fr.arb").read_text())
            self.assertEqual(en_data["priceKey"], en)
            self.assertEqual(fr_data["priceKey"], fr)

    def test_metadata_survives_reserialization(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            env, _ = fake_tool_env(app)
            result = self._run_fstr(app, "newKey", "Nouveau", "New", env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            en = json.loads((app / "lib/core/l10n/app_localizations_en.arb").read_text())
            fr = json.loads((app / "lib/core/l10n/app_localizations_fr.arb").read_text())
            self.assertEqual(en["@hello"], "Greeting shown on the home screen")
            self.assertEqual(en["@@locale"], "en")
            self.assertEqual(fr["@hello"], "Salutation affichée sur l’écran d’accueil")
            self.assertEqual(fr["@@locale"], "fr")

    def test_invalid_fr_json_changes_neither_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "lib/core/l10n/app_localizations_fr.arb").write_text(
                '{\n  "hello": "Bonjour",\n}\n'  # trailing comma: invalid strict JSON
            )
            env, _ = fake_tool_env(app)
            before = self._arb_snapshot(app)
            result = self._run_fstr(app, "newKey", "Nouveau", "New", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self._assert_arbs_unchanged(app, before)
            self.assertFalse(
                list((app / "lib/core/l10n").glob("*.tmp-*")),
                "no temp files may be left behind",
            )

    def test_invalid_en_json_changes_neither_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "lib/core/l10n/app_localizations_en.arb").write_text("{ not json")
            env, _ = fake_tool_env(app)
            before = self._arb_snapshot(app)
            result = self._run_fstr(app, "newKey", "Nouveau", "New", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self._assert_arbs_unchanged(app, before)

    def test_fr_only_collision_changes_nothing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            fr_path = app / "lib/core/l10n/app_localizations_fr.arb"
            fr_path.write_text('{\n  "hello": "Bonjour",\n  "collidedKey": "pris"\n}\n')
            env, _ = fake_tool_env(app)
            before = self._arb_snapshot(app)
            result = self._run_fstr(app, "collidedKey", "Nouveau", "New", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("app_localizations_fr.arb", result.stderr)
            self._assert_arbs_unchanged(app, before)

    def test_en_only_collision_changes_nothing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            en_path = app / "lib/core/l10n/app_localizations_en.arb"
            en_path.write_text('{\n  "hello": "Hello",\n  "enOnlyKey": "English only"\n}\n')
            env, _ = fake_tool_env(app)
            before = self._arb_snapshot(app)
            result = self._run_fstr(app, "enOnlyKey", "Français", "English only", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("app_localizations_en.arb", result.stderr)
            self._assert_arbs_unchanged(app, before)

    def test_duplicate_json_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "lib/core/l10n/app_localizations_en.arb").write_text(
                '{\n  "hello": "Hello",\n  "hello": "Hi again"\n}\n'
            )
            env, _ = fake_tool_env(app)
            before = self._arb_snapshot(app)
            result = self._run_fstr(app, "newKey", "Nouveau", "New", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Duplicate JSON key", result.stderr)
            self._assert_arbs_unchanged(app, before)

    def test_successful_insertion_updates_both_languages(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            env, log = fake_tool_env(app)
            result = self._run_fstr(app, "welcomeKey", "Bienvenue", "Welcome", env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            en = json.loads((app / "lib/core/l10n/app_localizations_en.arb").read_text())
            fr = json.loads((app / "lib/core/l10n/app_localizations_fr.arb").read_text())
            self.assertEqual(en["welcomeKey"], "Welcome")
            self.assertEqual(fr["welcomeKey"], "Bienvenue")
            self.assertIn("gen-l10n", read_invocations(log)[0])

    def test_gen_l10n_failure_returns_nonzero_and_rolls_back(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            env, log = fake_tool_env(app, flutter_fail=True)
            result = self._run_fstr(app, "welcomeKey", "Bienvenue", "Welcome", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("gen-l10n", result.stdout + result.stderr)
            # Generation failed, so the ARB update is rolled back.
            en = json.loads((app / "lib/core/l10n/app_localizations_en.arb").read_text())
            self.assertNotIn("welcomeKey", en)

    def test_non_object_root_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fstr_") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "lib/core/l10n/app_localizations_en.arb").write_text("[1, 2, 3]\n")
            env, _ = fake_tool_env(app)
            before = self._arb_snapshot(app)
            result = self._run_fstr(app, "newKey", "Nouveau", "New", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("not a JSON object", result.stderr)
            self._assert_arbs_unchanged(app, before)


class TestFimpPreviewFirst(unittest.TestCase):
    """fimp.sh contract: preview by default, --apply repairs and verifies.

    Uses a stateful fake `flutter`: the first `analyze` reports the broken
    imports (exit 1, as the real analyzer does), the second (verification)
    run's output/status is configurable.
    """

    FAKE_FLUTTER_ANALYZE = """#!/bin/sh
printf '%s\\n' "$@" >> "$FORGE_FAKE_LOG"
echo '---' >> "$FORGE_FAKE_LOG"
if [ "${1:-}" = "analyze" ]; then
  if [ -f "$FORGE_ANALYZE_STATE" ]; then
    printf '%s' "$FORGE_FIMP_SECOND_OUTPUT"
    exit ${FORGE_FIMP_SECOND_STATUS:-0}
  fi
  touch "$FORGE_ANALYZE_STATE"
  printf '%s' "$FORGE_FIMP_FIRST_OUTPUT"
  exit ${FORGE_FIMP_FIRST_STATUS:-1}
fi
if [ -n "${FORGE_FAKE_FLUTTER_FAIL:-}" ]; then
  exit 64
fi
exit 0
"""

    def _make_app(self, parent: Path, name: str = "fimp_app") -> Path:
        app = parent / name
        (app / "lib").mkdir(parents=True)
        (app / "pubspec.yaml").write_text("name: fimp_app\n")
        return app

    def _fake_env(self, app: Path, first_output: str, *, first_status: int = 1,
                  second_output: str = "No issues found!", second_status: int = 0) -> dict:
        bin_dir = app.parent / "fakebin"
        bin_dir.mkdir(exist_ok=True)
        flutter = bin_dir / "flutter"
        flutter.write_text(self.FAKE_FLUTTER_ANALYZE)
        flutter.chmod(0o755)
        log = app.parent / "fake_tools.log"
        log.touch()
        (bin_dir / "analyze_state").unlink(missing_ok=True)
        env = dict(os.environ)
        env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '')}"
        env["FORGE_FAKE_LOG"] = str(log)
        env["FORGE_ANALYZE_STATE"] = str(bin_dir / "analyze_state")
        env["FORGE_FIMP_FIRST_OUTPUT"] = first_output
        env["FORGE_FIMP_FIRST_STATUS"] = str(first_status)
        env["FORGE_FIMP_SECOND_OUTPUT"] = second_output
        env["FORGE_FIMP_SECOND_STATUS"] = str(second_status)
        env.pop("FORGE_FAKE_FLUTTER_FAIL", None)
        return env

    def _run_fimp(self, app: Path, *flags: str, env: dict | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(REPO_ROOT / "scripts" / "fimp.sh"), *flags],
            cwd=str(app), env=env,
            capture_output=True, text=True, timeout=COMMAND_TIMEOUT,
        )

    BROKEN_MAIN = (
        "Analyzing fimp_app...\n"
        "\n"
        "lib/main.dart:3:8: Error: Target of URI doesn't exist: './old/helper.dart'.\n"
        "import './old/helper.dart';\n"
        "       ^^^^^^^^^^^^^^^^^^\n"
        "1 issue found.\n"
    )

    def _app_with_moved_helper(self, parent: Path) -> Path:
        """helper.dart moved from lib/old/ to lib/new/; main.dart not updated.
        The file also contains decoys: a comment and a string with the same
        URI text, which must remain unchanged."""
        app = self._make_app(parent)
        (app / "lib" / "new").mkdir()
        (app / "lib" / "new" / "helper.dart").write_text("void helper() {}\n")
        (app / "lib" / "main.dart").write_text(
            "import './old/helper.dart' as h;\n"
            "\n"
            "// A comment mentioning './old/helper.dart' must stay.\n"
            "const String decoy = \"./old/helper.dart\";\n"
            "void main() { h.helper(); print(decoy); }\n"
        )
        return app

    def test_default_run_is_a_harmless_preview(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            env = self._fake_env(app, self.BROKEN_MAIN)
            before = (app / "lib/main.dart").read_bytes()
            result = self._run_fimp(app, env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("+ ./new/helper.dart", result.stdout)
            self.assertIn("Preview only", result.stdout)
            self.assertEqual((app / "lib/main.dart").read_bytes(), before)

    def test_location_field_is_parsed_not_searched(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fimp_loc_") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "lib" / "new").mkdir()
            (app / "lib" / "new" / "contest.dart").write_text("void c() {}\n")
            (app / "lib" / "main.dart").write_text("import './old/contest.dart';\nvoid main() {}\n")
            out = (
                "Analyzing fimp_app...\n\n"
                "  error \u2022 Target of URI doesn't exist: './old/contest.dart' \u2022 lib/main.dart:1:8 \u2022 uri_does_not_exist\n"
                "  error \u2022 Target of URI doesn't exist: 'package:fimp_app/features/contest/contest.dart' "
                "\u2022 lib/x.dart:1:8 \u2022 uri_does_not_exist\n"
                "2 issues found.\n"
            )
            (app / "lib" / "x.dart").write_text("import 'package:fimp_app/features/contest/contest.dart';\n")
            env = self._fake_env(app, out)
            result = self._run_fimp(app, env=env)
            self.assertNotIn("Traceback", result.stderr, msg=fmt(result))
            self.assertNotIn("OSError", result.stderr, msg=fmt(result))
            self.assertIn("+ ./new/contest.dart", result.stdout, msg=fmt(result))

    def test_token_repairs_preserve_comments_strings_and_combinators(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fimp_tokens_") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            path = app / "lib/main.dart"
            path.write_text(
                "/*\nimport './old/helper.dart';\n/* nested */\n*/\n"
                "import 'other.dart'; // previous URI './old/helper.dart'\n"
                "import\n  './old/helper.dart'\n  as h show helper;\n"
                "const String sample = '''\nimport './old/helper.dart';\n''';\n"
                "void main() { h.helper(); }\n"
            )
            (app / "lib/other.dart").write_text("class Other {}\n")
            before = path.read_text()
            result = self._run_fimp(app, "--apply", env=self._fake_env(app, self.BROKEN_MAIN))
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(path.read_text(), before.replace(
                "import\n  './old/helper.dart'\n", "import\n  './new/helper.dart'\n"))

    def test_repeated_uri_and_conditional_branch_tokens_are_all_repaired(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fimp_tokens_") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            path = app / "lib/main.dart"
            path.write_text(
                "import './old/helper.dart' as a;\n"
                "import 'fallback.dart' if (dart.library.io) './old/helper.dart' as b;\n"
                "export './old/helper.dart' show helper;\n"
                "void main() {}\n"
            )
            (app / "lib/fallback.dart").write_text("void helper() {}\n")
            result = self._run_fimp(app, "--apply", env=self._fake_env(app, self.BROKEN_MAIN))
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(path.read_text().count("'./new/helper.dart'"), 3)
            self.assertNotIn("'./old/helper.dart'", path.read_text())

    def test_relative_imports_work_in_lib_and_test_including_bare_uris(self) -> None:
        for tree in ("lib", "test"):
            for uri in ("old/helper.dart", "./old/helper.dart", "../old/helper.dart"):
                with self.subTest(tree=tree, uri=uri):
                    with tempfile.TemporaryDirectory(prefix="forge_fimp_relative_") as raw:
                        app = self._make_app(Path(raw).resolve())
                        (app / tree / "new").mkdir(parents=True)
                        (app / tree / "new/helper.dart").write_text("void helper() {}\n")
                        (app / tree / "unit").mkdir()
                        path = app / tree / "unit/consumer.dart"
                        path.write_text(f"import '{uri}';\nvoid main() {{ helper(); }}\n")
                        diagnostic = f"{tree}/unit/consumer.dart:1:8: Error: Target of URI doesn't exist: '{uri}'.\n"
                        result = self._run_fimp(app, "--apply", env=self._fake_env(app, diagnostic))
                        self.assertEqual(result.returncode, 0, msg=fmt(result))
                        self.assertIn("import '../new/helper.dart';", path.read_text())
                        self.assertNotIn("infrastructure failure", result.stdout)

    def test_conditional_comparison_strings_are_not_uri_tokens(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fimp_conditional_") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            path = app / "lib/main.dart"
            source = (
                "import './old/helper.dart'\n"
                "    if (dart.library.io == './old/helper.dart') './old/helper.dart' as h;\n"
                "void main() { h.helper(); }\n"
            )
            path.write_text(source)
            result = self._run_fimp(app, "--apply", env=self._fake_env(app, self.BROKEN_MAIN))
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(path.read_text(), source.replace(
                "import './old/helper.dart'", "import './new/helper.dart'"
            ).replace("') './old/helper.dart' as h;", "') './new/helper.dart' as h;"))

    def test_unterminated_directive_is_not_partially_repaired(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fimp_unterminated_") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            path = app / "lib/main.dart"
            source = "import './old/helper.dart'"
            path.write_text(source)
            result = self._run_fimp(app, "--apply", env=self._fake_env(app, self.BROKEN_MAIN))
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(path.read_text(), source)
            self.assertIn("Unsupported directive form", result.stdout)

    def test_raw_uri_literal_and_crlf_are_preserved(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fimp_tokens_") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            path = app / "lib/main.dart"
            path.write_bytes(b"import r'./old/helper.dart' as h;\r\nvoid main() { h.helper(); }\r\n")
            result = self._run_fimp(app, "--apply", env=self._fake_env(app, self.BROKEN_MAIN))
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(path.read_bytes(), b"import r'./new/helper.dart' as h;\r\nvoid main() { h.helper(); }\r\n")

    def test_unresolved_apply_fails_and_preview_remains_advisory(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fimp_unresolved_") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            (app / "lib/new/helper.dart").unlink()
            before = tree_snapshot(app)
            result = self._run_fimp(app, env=self._fake_env(app, self.BROKEN_MAIN))
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Unresolved", result.stdout)
            self.assertEqual(tree_snapshot(app), before)
            result = self._run_fimp(app, "--apply", env=self._fake_env(app, self.BROKEN_MAIN))
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Verification FAILED", result.stdout)
            self.assertEqual(tree_snapshot(app), before)

    def test_real_analysis_errors_are_not_reported_as_startup_failures(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fimp_error_") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            result = self._run_fimp(app, env=self._fake_env(
                app, "lib/main.dart:1:1: Error: unrelated syntax error\n1 issue found.\n"))
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("outside supported import repairs", result.stdout)
            self.assertNotIn("infrastructure failure", result.stdout)

    def test_dry_run_is_identical_to_default(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            env = self._fake_env(app, self.BROKEN_MAIN)
            before = (app / "lib/main.dart").read_bytes()
            result = self._run_fimp(app, "--dry-run", env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("+ ./new/helper.dart", result.stdout)
            self.assertIn("Preview only", result.stdout)
            self.assertEqual((app / "lib/main.dart").read_bytes(), before)

    def test_apply_rewrites_only_the_import_directive(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            env = self._fake_env(app, self.BROKEN_MAIN)
            result = self._run_fimp(app, "--apply", env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Applied:", result.stdout)
            content = (app / "lib/main.dart").read_text()
            self.assertIn("import './new/helper.dart' as h;\n", content)
            self.assertIn("// A comment mentioning './old/helper.dart' must stay.", content)
            self.assertIn('const String decoy = "./old/helper.dart";', content)

    def test_unknown_and_conflicting_flags_fail_without_editing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            env = self._fake_env(app, self.BROKEN_MAIN)
            before = (app / "lib/main.dart").read_bytes()
            for flags in (("--bogus",), ("--apply", "--dry-run"), ("--dry-run", "--apply")):
                with self.subTest(flags=flags):
                    result = self._run_fimp(app, *flags, env=env)
                    self.assertNotEqual(result.returncode, 0, msg=fmt(result))
                    self.assertEqual((app / "lib/main.dart").read_bytes(), before)

    def test_lib_import_is_never_repaired_into_test(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "test" / "helper").mkdir(parents=True)
            (app / "test" / "helper" / "helper.dart").write_text("void h() {}\n")
            (app / "lib" / "main.dart").write_text(
                "import './helper/helper.dart';\nvoid main() {}\n"
            )
            broken = (
                "Analyzing fimp_app...\n\n"
                "lib/main.dart:1:8: Error: Target of URI doesn't exist: './helper/helper.dart'.\n"
                "import './helper/helper.dart';\n"
                "       ^^^^^^^^^^^^^^^^^^\n"
                "1 issue found.\n"
            )
            env = self._fake_env(app, broken)
            before = (app / "lib/main.dart").read_bytes()
            result = self._run_fimp(app, "--apply", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Unresolved", result.stdout)
            self.assertIn("not found in lib/", result.stdout)
            self.assertEqual((app / "lib/main.dart").read_bytes(), before)

    def test_test_to_test_repair_produces_relative_import(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "test" / "support").mkdir(parents=True)
            (app / "test" / "support" / "fake_repo.dart").write_text("class FakeRepo {}\n")
            (app / "test" / "unit").mkdir()
            (app / "test" / "unit" / "thing_test.dart").write_text(
                "import 'package:fimp_app/support/fake_repo.dart';\nvoid main() {}\n"
            )
            broken = (
                "Analyzing fimp_app...\n\n"
                "test/unit/thing_test.dart:1:8: Error: Target of URI doesn't exist: "
                "'package:fimp_app/support/fake_repo.dart'.\n"
                "import 'package:fimp_app/support/fake_repo.dart';\n"
                "       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n"
                "1 issue found.\n"
            )
            env = self._fake_env(app, broken)
            result = self._run_fimp(app, "--apply", env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("+ ../support/fake_repo.dart", result.stdout)
            content = (app / "test/unit/thing_test.dart").read_text()
            self.assertIn("import '../support/fake_repo.dart';", content)
            self.assertNotIn("package:", content)

    def test_test_to_lib_repair_produces_package_import(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "lib" / "widgets").mkdir(parents=True)
            (app / "lib" / "widgets" / "button.dart").write_text("class Button {}\n")
            (app / "test").mkdir()
            (app / "test" / "button_test.dart").write_text(
                "import 'package:fimp_app/old/button.dart';\nvoid main() {}\n"
            )
            broken = (
                "Analyzing fimp_app...\n\n"
                "test/button_test.dart:1:8: Error: Target of URI doesn't exist: "
                "'package:fimp_app/old/button.dart'.\n"
                "import 'package:fimp_app/old/button.dart';\n"
                "       ^^^^^^^^^^^^^^^^^^\n"
                "1 issue found.\n"
            )
            env = self._fake_env(app, broken)
            result = self._run_fimp(app, "--apply", env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("+ package:fimp_app/widgets/button.dart", result.stdout)
            self.assertIn("import 'package:fimp_app/widgets/button.dart';",
                          (app / "test/button_test.dart").read_text())

    def test_ambiguous_basename_is_skipped_without_editing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._make_app(Path(raw).resolve())
            (app / "lib" / "a").mkdir()
            (app / "lib" / "b").mkdir()
            (app / "lib" / "a" / "dup.dart").write_text("A\n")
            (app / "lib" / "b" / "dup.dart").write_text("B\n")
            (app / "lib" / "main.dart").write_text(
                "import './a/dup.dart';\nvoid main() {}\n"
            )
            broken = (
                "Analyzing fimp_app...\n\n"
                "lib/main.dart:1:8: Error: Target of URI doesn't exist: './a/dup.dart'.\n"
                "import './a/dup.dart';\n"
                "       ^^^^^^^^^^^^^^\n"
                "1 issue found.\n"
            )
            env = self._fake_env(app, broken)
            before = (app / "lib/main.dart").read_bytes()
            result = self._run_fimp(app, "--apply", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Ambiguous", result.stdout)
            self.assertIn("lib/a/dup.dart", result.stdout)
            self.assertIn("lib/b/dup.dart", result.stdout)
            self.assertEqual((app / "lib/main.dart").read_bytes(), before)

    def test_parent_paths_with_spaces_work(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            parent = Path(raw).resolve() / "parent dir with spaces"
            parent.mkdir()
            app = self._app_with_moved_helper(parent)
            env = self._fake_env(app, self.BROKEN_MAIN)
            result = self._run_fimp(app, "--apply", env=env)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("import './new/helper.dart' as h;",
                          (app / "lib/main.dart").read_text())

    def test_analyzer_startup_failure_is_not_nothing_to_repair(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            env = self._fake_env(
                app, "flutter: command failed to start: crash", first_status=64
            )
            before = (app / "lib/main.dart").read_bytes()
            result = self._run_fimp(app, env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("infrastructure failure", result.stdout + result.stderr)
            self.assertNotIn("Nothing to repair", result.stdout)
            self.assertEqual((app / "lib/main.dart").read_bytes(), before)

    def test_verification_failure_is_reported_and_edits_retained(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge fimp parent ") as raw:
            app = self._app_with_moved_helper(Path(raw).resolve())
            env = self._fake_env(
                app, self.BROKEN_MAIN,
                second_output="lib/main.dart:9:7: Error: getter not found\n1 issue found.",
                second_status=1,
            )
            result = self._run_fimp(app, "--apply", env=env)
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            combined = result.stdout + result.stderr
            self.assertIn("Verification FAILED", combined)
            self.assertIn("RETAINED", combined)
            self.assertNotIn("passes after repair", combined)
            # The applied edit is kept (no rollback).
            self.assertIn("import './new/helper.dart' as h;",
                          (app / "lib/main.dart").read_text())


class TestShippedToolingAllowlist(unittest.TestCase):
    """Generated apps ship EXACTLY the allowlisted scripts — no more.

    The generator copies only `shippedScripts` from create_project.dart;
    template-maintenance and personal tooling never reach an app.
    """

    ALLOWED_SCRIPTS = {
        "fverify.sh",
        "fgen.sh",
        "fstr.sh",
        "fl10n.sh",
        "fanal.sh",
        "fimp.sh",
        "fdead.sh",
        "fcheck.sh",
        "fmap.sh",
        "ftest.sh",
        "fqueue.sh",
        "sync_skills.sh",
        "fimp.py",
        "render_feature.py",
        "fwire.py",
        "feature_templates",
    }
    FORBIDDEN = {
        "verify_template.sh",  # template maintenance
        "fbuild.sh",  # personal
        "pre_script_claude.sh",  # personal
        "flutter_analyze_interceptor.py",  # retired
    }

    def _generate_fast_app(self, workdir: Path, name: str = "ship_app", generator: Path = GENERATOR) -> Path:
        env, _ = fake_tool_env(workdir)
        result = run_generator(["--no-open", name], cwd=workdir, env=env, generator=generator)
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        return workdir / name

    def test_generated_app_ships_exactly_the_allowlist(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_ship_") as raw:
            workdir = Path(raw).resolve()
            app = self._generate_fast_app(workdir)
            shipped = {path.name for path in (app / "scripts").iterdir()}
            self.assertEqual(shipped, self.ALLOWED_SCRIPTS)
            self.assertFalse((app / "tools").exists(), "test_template.py never ships")
            self.assertEqual(
                (app / "build.yaml").read_text(),
                (REPO_ROOT / "build.yaml").read_text(),
                "build.yaml (codegen scope) ships verbatim",
            )
            self.assertFalse(
                (app / "test" / "architecture_checker_test.dart").exists(),
                "checker self-tests stay in the template (tools/checker_tests/)",
            )

    def test_generated_app_records_its_template_commit(self) -> None:
        """The upgrade skill's merge base: .flutterforge.json names HEAD."""
        with tempfile.TemporaryDirectory(prefix="forge_stamp_") as raw:
            app = self._generate_fast_app(Path(raw).resolve(), name="stamp_app")
            stamp = json.loads((app / ".flutterforge.json").read_text())
            head = run_command(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT).stdout.strip()
            self.assertEqual(stamp["templateCommit"], head)
            self.assertIsInstance(stamp["templateDirty"], bool)

    def test_generated_scripts_are_executable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_ship_") as raw:
            workdir = Path(raw).resolve()
            app = self._generate_fast_app(workdir)
            for name in self.ALLOWED_SCRIPTS:
                if not name.endswith('.sh'):
                    continue
                with self.subTest(script=name):
                    self.assertTrue(os.access(app / "scripts" / name, os.X_OK))

    def test_new_script_in_template_does_not_automatically_ship(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_ship_") as raw:
            workdir = Path(raw).resolve()
            template = workdir / "template"
            shutil.copytree(REPO_ROOT, template, ignore=shutil.ignore_patterns(".git", ".dart_tool", "__pycache__"))
            probe = template / "scripts" / "zzz_probe_do_not_ship.sh"
            probe.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            app = self._generate_fast_app(workdir, generator=template / "create_project.dart")
            self.assertFalse((app / "scripts" / probe.name).exists())
            self.assertEqual({path.name for path in (app / "scripts").iterdir()}, self.ALLOWED_SCRIPTS)

    def test_missing_required_script_fails_before_flutter_runs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_ship_") as raw:
            workdir = Path(raw).resolve()
            template = workdir / "template"
            shutil.copytree(REPO_ROOT, template, ignore=shutil.ignore_patterns(".git", ".dart_tool", "__pycache__"))
            (template / "scripts/fverify.sh").unlink()
            env, log = fake_tool_env(workdir, flutter_fail=True)
            result = run_generator(["--no-open", "my_app"], cwd=workdir, env=env, generator=template / "create_project.dart")
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Required template entry is missing", result.stderr)
            self.assertEqual(read_invocations(log), [], "flutter must not be invoked")

    def test_missing_support_assets_fail_before_flutter_runs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_ship_") as raw:
            workdir = Path(raw).resolve()
            template = workdir / "template"
            shutil.copytree(REPO_ROOT, template, ignore=shutil.ignore_patterns(".git", ".dart_tool", "__pycache__"))
            for relative in ("scripts/fimp.py", "scripts/feature_templates/cubit.dart.tpl"):
                with self.subTest(asset=relative):
                    path = template / relative
                    saved = path.read_bytes()
                    path.unlink()
                    env, log = fake_tool_env(workdir)
                    result = run_generator(["--no-open", "my_app"], cwd=workdir, env=env, generator=template / "create_project.dart")
                    self.assertNotEqual(result.returncode, 0, msg=fmt(result))
                    self.assertEqual(read_invocations(log), [])
                    path.write_bytes(saved)

    def test_generated_app_has_standalone_ci_workflow(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_ship_") as raw:
            workdir = Path(raw).resolve()
            app = self._generate_fast_app(workdir)
            workflow = app / ".github" / "workflows" / "flutter-ci.yml"
            self.assertTrue(workflow.exists(), "the app CI workflow must ship")
            text = workflow.read_text()
            # Generation precedes verification.
            commands = [line.strip() for line in text.splitlines() if line.strip().startswith('run:')]
            gen_position = commands.index('run: dart run build_runner build --delete-conflicting-outputs')
            l10n_position = commands.index('run: flutter gen-l10n')
            verify_position = commands.index('run: bash scripts/fverify.sh')
            self.assertLess(l10n_position, verify_position)
            self.assertLess(gen_position, verify_position)
            # No references to the FlutterForge root harness.
            self.assertNotIn("verify_template", text)
            self.assertNotIn("test_template", text)
            # Read-only, bounded, superseded runs cancelled.
            self.assertIn("contents: read", text)
            self.assertIn("timeout-minutes", text)
            self.assertIn("cancel-in-progress", text)
            # The repository's own template workflow is NOT copied.
            self.assertFalse(
                (app / ".github" / "workflows" / "template-verification.yml").exists()
            )


class TestFverifyGate(unittest.TestCase):
    """fverify.sh: non-mutating by default, opt-in --fix preparation, quiet
    test reporter, and plain (colour-free) output when captured."""

    # Only the Dart source roots that exist (here lib/ and test/): never `.`,
    # which would walk build/ (SPM checkouts, vendored plugin code).
    FORMAT_CHECK = ["format", "--output=none", "--set-exit-if-changed", "lib", "test"]

    def _run(
        self, args: list[str], *, flutter_fail: bool = False, dart_fail: bool = False,
        fix_preview: str | None = None,
    ) -> tuple[subprocess.CompletedProcess, list[list[str]]]:
        with tempfile.TemporaryDirectory(prefix="forge_fverify_") as raw:
            root = Path(raw).resolve()
            app = make_fake_app(root)
            (app / "test").mkdir()
            (app / "build" / "ios" / "SourcePackages").mkdir(parents=True)
            env, log = fake_tool_env(root, flutter_fail=flutter_fail, dart_fail=dart_fail)
            if fix_preview is not None:
                env["FORGE_FAKE_FIX_PREVIEW"] = fix_preview
            result = subprocess.run(
                [SYSTEM_BASH, str(REPO_ROOT / "scripts" / "fverify.sh"), *args],
                cwd=str(app),
                env=env,
                capture_output=True,
                text=True,
                timeout=COMMAND_TIMEOUT,
            )
            return result, read_invocations(log)

    def test_default_run_is_non_mutating_and_quiet(self) -> None:
        result, calls = self._run([])
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        self.assertEqual(
            calls,
            [
                self.FORMAT_CHECK,
                ["analyze", "--no-pub"],
                ["test", "--concurrency=4", "--reporter", "failures-only"],
            ],
        )
        self.assertNotIn("\x1b[", result.stdout + result.stderr)

    def test_fix_prepares_then_runs_the_same_gate(self) -> None:
        result, calls = self._run(["--fix"])
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        self.assertEqual(
            calls,
            [
                ["fix", "--dry-run"],
                ["fix", "--apply"],
                ["format", "lib", "test"],
                self.FORMAT_CHECK,
                ["analyze", "--no-pub"],
                ["test", "--concurrency=4", "--reporter", "failures-only"],
            ],
        )

    def test_fix_refuses_a_sweeping_dart_fix_migration(self) -> None:
        result, calls = self._run(["--fix"], fix_preview="1312 proposed fixes in 218 files.")
        self.assertNotEqual(result.returncode, 0, msg=fmt(result))
        self.assertEqual(calls, [["fix", "--dry-run"]])
        self.assertIn("218 files", result.stdout)

    def test_fix_with_nothing_to_fix_skips_apply(self) -> None:
        result, calls = self._run(["--fix"], fix_preview="Nothing to fix!")
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        self.assertEqual(calls[:2], [["fix", "--dry-run"], ["format", "lib", "test"]])

    def test_explicit_reporter_and_extra_arguments_are_forwarded(self) -> None:
        result, calls = self._run(["-r", "expanded", "--fix", "--coverage"])
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        self.assertEqual(calls[-1], ["test", "--concurrency=4", "-r", "expanded", "--coverage"])

    def test_format_failure_still_reports_analysis_and_tests(self) -> None:
        result, calls = self._run([], dart_fail=True)
        self.assertNotEqual(result.returncode, 0, msg=fmt(result))
        self.assertEqual([call[0] for call in calls], ["format", "analyze", "test"])

    def test_analysis_failure_stops_before_tests(self) -> None:
        result, calls = self._run([], flutter_fail=True)
        self.assertNotEqual(result.returncode, 0, msg=fmt(result))
        self.assertEqual([call[0] for call in calls], ["format", "analyze"])


class TestTestQueue(unittest.TestCase):
    """ftest.sh / fverify.sh share a machine-wide queue (scripts/fqueue.sh):
    concurrent runs take turns, a dead holder's slot is reclaimed, failures
    propagate, and FORGE_QUEUE=0 bypasses it. Runs under the system Bash."""

    FAKE_FLUTTER = (
        "#!/bin/bash\n"
        "echo \"start $FAKE_ID\" >> \"$FAKE_LOG\"\n"
        "sleep 1\n"
        "echo \"end $FAKE_ID\" >> \"$FAKE_LOG\"\n"
        "exit \"${FAKE_EXIT:-0}\"\n"
    )

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="forge-queue-test-")
        root = Path(self.tmp.name)
        self.app = root / "app"
        (self.app / "scripts").mkdir(parents=True)
        (self.app / "pubspec.yaml").write_text("name: queue_app\n")
        for name in ("ftest.sh", "fqueue.sh"):
            shutil.copy(REPO_ROOT / "scripts" / name, self.app / "scripts" / name)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        flutter = bin_dir / "flutter"
        flutter.write_text(self.FAKE_FLUTTER)
        flutter.chmod(0o755)
        self.queue = root / "queue"
        self.log = root / "log"
        self.log.touch()
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "FORGE_QUEUE_DIR": str(self.queue),
            "FAKE_LOG": str(self.log),
        }
        self.env.pop("FQUEUE_HELD", None)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _start(self, fake_id: str, **extra: str) -> subprocess.Popen:
        return subprocess.Popen(
            [SYSTEM_BASH, "scripts/ftest.sh"],
            cwd=self.app,
            env={**self.env, "FAKE_ID": fake_id, **extra},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

    def _events(self) -> list[str]:
        return self.log.read_text().split("\n")[:-1]

    def test_concurrent_runs_take_turns(self) -> None:
        first = self._start("A")
        import time

        time.sleep(0.4)
        second = self._start("B")
        out_b, _ = second.communicate(timeout=60)
        first.communicate(timeout=60)
        self.assertEqual(self._events(), ["start A", "end A", "start B", "end B"])
        self.assertIn("waiting for a free slot", out_b)
        self.assertEqual(list(self.queue.iterdir()), [], "slot released")

    def test_two_slots_allow_two_concurrent_runs(self) -> None:
        runs = [self._start(i, FORGE_QUEUE_SLOTS="2") for i in ("A", "B")]
        for run in runs:
            run.communicate(timeout=60)
        self.assertEqual(sorted(self._events()[:2]), ["start A", "start B"])

    def test_dead_holder_slot_is_reclaimed(self) -> None:
        slot = self.queue / "heavy-slot-0"
        slot.mkdir(parents=True)
        (slot / "owner").write_text("999999\n/elsewhere\nghost\n")
        result = self._start("C")
        out, _ = result.communicate(timeout=60)
        self.assertEqual(result.returncode, 0, msg=out)
        self.assertEqual(self._events(), ["start C", "end C"])

    def test_failure_propagates_and_releases(self) -> None:
        result = self._start("D", FAKE_EXIT="7")
        result.communicate(timeout=60)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(list(self.queue.iterdir()), [])

    def test_slowest_prints_a_timing_summary_and_keeps_the_exit_code(self) -> None:
        if shutil.which("uv") is None:
            self.skipTest("uv not on PATH")
        events = [
            {"type": "suite", "suite": {"id": 0, "path": "test/a_test.dart"}},
            {"type": "testStart", "test": {"id": 1, "suiteID": 0, "name": "loading test/a_test.dart"}, "time": 0},
            {"type": "testDone", "testID": 1, "time": 3000},
            {"type": "testStart", "test": {"id": 2, "suiteID": 0, "name": "slow one"}, "time": 3000},
            {"type": "testDone", "testID": 2, "time": 5500},
            {"type": "testStart", "test": {"id": 3, "suiteID": 0, "name": "fast one"}, "time": 5500},
            {"type": "testDone", "testID": 3, "time": 5600},
        ]
        canned = Path(self.tmp.name) / "events.jsonl"
        canned.write_text("".join(json.dumps(event) + "\n" for event in events))
        fake = Path(self.tmp.name) / "bin" / "flutter"
        fake.write_text(
            "#!/bin/bash\n"
            "for arg in \"$@\"; do case \"$arg\" in json:*) cp \"$CANNED\" \"${arg#json:}\" ;; esac; done\n"
            "exit 3\n"
        )
        result = subprocess.run(
            [SYSTEM_BASH, "scripts/ftest.sh", "--slowest=1"],
            cwd=self.app, env={**self.env, "CANNED": str(canned)},
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 3, msg=fmt(result))
        self.assertIn("5.60s  test/a_test.dart", result.stdout)
        self.assertIn("2.50s  test/a_test.dart: slow one", result.stdout)
        self.assertNotIn("fast one", result.stdout)
        self.assertEqual(list(self.queue.iterdir()), [])

    def test_slowest_rejects_a_bad_count(self) -> None:
        result = self._start("Z")
        result.communicate(timeout=60)
        bad = subprocess.run(
            [SYSTEM_BASH, "scripts/ftest.sh", "--slowest=abc"],
            cwd=self.app, env=self.env, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(bad.returncode, 2)
        self.assertIn("positive number", bad.stderr)

    def test_queue_can_be_disabled(self) -> None:
        slot = self.queue / "heavy-slot-0"
        slot.mkdir(parents=True)
        (slot / "owner").write_text(f"{os.getpid()}\n/busy\nholder\n")
        result = self._start("E", FORGE_QUEUE="0")
        out, _ = result.communicate(timeout=60)
        self.assertEqual(result.returncode, 0, msg=out)
        self.assertEqual(self._events(), ["start E", "end E"])


class TestFtestRuns(unittest.TestCase):
    """ftest.sh run shapes (fake flutter records its arguments): scoped runs
    take the light lane with -j2; full runs compile one aggregated entrypoint,
    keep golden/annotated files standalone, skip an unchanged architecture
    gate; compile errors print once; a holder killed while its command still
    runs keeps the slot."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="forge-ftest-")
        root = Path(self.tmp.name)
        self.app = root / "app"
        for rel in ("scripts", "lib", "test/features/a", "test/core"):
            (self.app / rel).mkdir(parents=True)
        (self.app / "pubspec.yaml").write_text("name: run_app\n")
        (self.app / "lib" / "a.dart").write_text("int a = 1;\n")
        for name in ("ftest.sh", "fqueue.sh"):
            shutil.copy(REPO_ROOT / "scripts" / name, self.app / "scripts" / name)
        (self.app / "test" / "flutter_test_config.dart").write_text("// config\n")
        (self.app / "test" / "architecture_test.dart").write_text("void main() {}\n")
        (self.app / "test" / "features" / "a" / "a_flow_test.dart").write_text("void main() {}\n")
        (self.app / "test" / "core" / "golden_test.dart").write_text(
            "void main() { matchesGoldenFile('x.png'); }\n"
        )
        (self.app / "test" / "core" / "args_test.dart").write_text("void main(List<String> a) {}\n")
        (self.app / "test" / "core" / "boot_test.dart").write_text("// ftest:isolate\nvoid main() {}\n")
        bin_dir = root / "bin"
        bin_dir.mkdir()
        self.calls = root / "calls"
        flutter = bin_dir / "flutter"
        flutter.write_text(
            "#!/bin/bash\n"
            "echo \"$*\" >> \"$CALLS\"\n"
            "if [ -n \"${FAKE_OUTPUT:-}\" ]; then cat \"$FAKE_OUTPUT\"; fi\n"
            "sleep \"${FAKE_SLEEP:-0}\"\n"
            "exit \"${FAKE_EXIT:-0}\"\n"
        )
        flutter.chmod(0o755)
        self.queue = root / "queue"
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "FORGE_QUEUE_DIR": str(self.queue),
            "CALLS": str(self.calls),
        }
        for key in ("FQUEUE_HELD", "CI", "FORGE_ARCH_ALWAYS", "FORGE_TEST_AGGREGATE", "FORGE_TEST_CONCURRENCY"):
            self.env.pop(key, None)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _ftest(self, *args: str, **extra: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [SYSTEM_BASH, "scripts/ftest.sh", *args], cwd=self.app,
            env={**self.env, **extra}, capture_output=True, text=True, timeout=120,
        )

    def _last_call(self) -> list[str]:
        return self.calls.read_text().splitlines()[-1].split()

    def test_scoped_run_uses_the_light_lane_without_aggregation(self) -> None:
        result = self._ftest("test/features/a")
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        self.assertEqual(
            self._last_call(),
            ["test", "--concurrency=2", "--reporter", "failures-only", "test/features/a"],
        )

    def test_full_run_aggregates_and_skips_an_unchanged_architecture_gate(self) -> None:
        first = self._ftest()
        self.assertEqual(first.returncode, 0, msg=fmt(first))
        call = self._last_call()
        self.assertEqual(call[:4], ["test", "--concurrency=4", "--reporter", "failures-only"])
        self.assertEqual(
            sorted(call[4:]),
            sorted([
                ".dart_tool/flutterforge/shard_0_test.dart",
                "test/core/args_test.dart",
                "test/core/golden_test.dart",
                "test/core/boot_test.dart",
                "test/architecture_test.dart",
            ]),
        )
        entry = (self.app / ".dart_tool" / "flutterforge" / "shard_0_test.dart").read_text()
        self.assertIn("import '../../test/features/a/a_flow_test.dart' as t0;", entry)
        self.assertIn("forge_config.testExecutable(_all)", entry)
        self.assertNotIn("golden_test", entry)

        second = self._ftest()
        self.assertIn("architecture gate", second.stdout)
        self.assertNotIn("test/architecture_test.dart", self._last_call())

        (self.app / "lib" / "a.dart").write_text("int a = 2;\n")
        self._ftest()
        self.assertIn("test/architecture_test.dart", self._last_call())

    def test_failed_run_never_stamps_the_architecture_gate(self) -> None:
        self._ftest(FAKE_EXIT="1")
        self._ftest()
        self.assertIn("test/architecture_test.dart", self._last_call())

    def test_ci_always_runs_the_architecture_gate(self) -> None:
        self._ftest()
        self._ftest(CI="true")
        self.assertIn("test/architecture_test.dart", self._last_call())

    def test_aggregation_can_be_disabled(self) -> None:
        self._ftest(FORGE_TEST_AGGREGATE="0")
        self.assertEqual(self._last_call(), ["test", "--concurrency=4", "--reporter", "failures-only"])

    def test_compile_errors_print_once_without_tool_frames(self) -> None:
        output = Path(self.tmp.name) / "out.txt"
        root = str(self.app.resolve())  # flutter prints physical paths
        block = (
            f"{root}/lib/a.dart:1:5: Error: Expected ';' after this.\n"
            "int a = 1\n"
            "    ^\n"
            "#0 main (package:flutter_tools/src/test/runner.dart:12:3)\n"
            "#1 x (dart:async/zone.dart:1:1)\n"
        )
        output.write_text(block * 5)
        result = self._ftest("test/features/a", FAKE_OUTPUT=str(output), FAKE_EXIT="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.count("Error: Expected"), 1, msg=result.stdout)
        self.assertIn("lib/a.dart:1:5", result.stdout)
        self.assertNotIn(root, result.stdout)
        self.assertNotIn("flutter_tools", result.stdout)
        self.assertIn("4 repeated compile error(s) omitted", result.stdout)

    def test_light_run_does_not_wait_behind_a_heavy_run(self) -> None:
        slot = self.queue / "heavy-slot-0"
        slot.mkdir(parents=True)
        (slot / "owner").write_text(f"{os.getpid()}\n/busy\nholder\n")
        result = self._ftest("test/features/a")
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        self.assertNotIn("waiting", result.stdout)

    def test_slot_survives_its_killed_holder_while_the_command_runs(self) -> None:
        import signal
        import time

        holder = subprocess.Popen(
            [SYSTEM_BASH, "scripts/ftest.sh", "test/features/a"], cwd=self.app,
            env={**self.env, "FAKE_SLEEP": "6"}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        slot = self.queue / "light-slot-0"
        deadline = time.time() + 20
        while not (slot / "child").exists() and time.time() < deadline:
            time.sleep(0.1)
        child = int((slot / "child").read_text().split()[0])
        holder.send_signal(signal.SIGKILL)
        holder.wait(timeout=10)
        waiter = self._ftest("test/features/a")  # must wait for the orphaned run
        self.assertIn("waiting", waiter.stdout)
        with self.assertRaises(ProcessLookupError):
            os.kill(child, 0)


class TestFlutterShim(unittest.TestCase):
    """personal_tools/flutter_shim.sh: a `flutter` ahead of the SDK on PATH
    queues `test`/`analyze` (scripts/fqueue.sh) and passes everything else,
    `--watch` and already-queued runs straight to the real flutter."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="forge-shim-")
        root = Path(self.tmp.name)
        real = root / "real"
        shim_bin = root / "shim"
        real.mkdir()
        shim_bin.mkdir()
        fake = real / "flutter"
        fake.write_text(
            "#!/bin/bash\n"
            "echo \"start $FAKE_ID $*\" >> \"$FAKE_LOG\"\n"
            "[ \"$1\" = test ] && sleep 1\n"
            "echo \"end $FAKE_ID\" >> \"$FAKE_LOG\"\n"
        )
        fake.chmod(0o755)
        (shim_bin / "flutter").symlink_to(REPO_ROOT / "personal_tools" / "flutter_shim.sh")
        self.log = root / "log"
        self.log.touch()
        self.queue = root / "queue"
        self.env = {
            **os.environ,
            "PATH": f"{shim_bin}{os.pathsep}{real}{os.pathsep}{os.environ['PATH']}",
            "FORGE_QUEUE_DIR": str(self.queue),
            "FAKE_LOG": str(self.log),
        }
        self.env.pop("FQUEUE_HELD", None)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _start(self, fake_id: str, *args: str, **extra: str) -> subprocess.Popen:
        return subprocess.Popen(
            ["flutter", *args],
            env={**self.env, "FAKE_ID": fake_id, **extra},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

    def _events(self) -> list[str]:
        return self.log.read_text().split("\n")[:-1]

    def test_bare_flutter_test_runs_take_turns(self) -> None:
        import time

        first = self._start("A", "test")
        time.sleep(0.4)
        second = self._start("B", "test")
        second.communicate(timeout=60)
        first.communicate(timeout=60)
        self.assertEqual(self._events(), ["start A test", "end A", "start B test", "end B"])

    def test_other_commands_and_held_runs_pass_through(self) -> None:
        slot = self.queue / "heavy-slot-0"
        slot.mkdir(parents=True)
        (slot / "owner").write_text(f"{os.getpid()}\n/busy\nholder\n")
        for fake_id, args, extra in (
            ("V", ("--version",), {}),
            ("W", ("analyze", "--watch"), {}),
            ("H", ("test",), {"FQUEUE_HELD": "1"}),
        ):
            with self.subTest(args=args):
                run = self._start(fake_id, *args, **extra)
                run.communicate(timeout=30)
                self.assertEqual(run.returncode, 0)
        self.assertEqual(
            [event for event in self._events() if event.startswith("start")],
            ["start V --version", "start W analyze --watch", "start H test"],
        )


class TestFanalModules(unittest.TestCase):
    """fanal.sh counts feature-module registrations/routes and flags modules
    that are not wired (a commented-out call does not count)."""

    def test_reports_module_wiring(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fanal_") as raw:
            app = make_fake_app(Path(raw).resolve())
            files = {
                "lib/core/di/service_locator.dart": (
                    "void setup() {\n  registerShopFeature(getIt);\n  // registerCartFeature(getIt);\n}\n"
                ),
                "lib/core/router/app_router.dart": "final r = [\n  ...shopRoutes(getIt),\n];\n",
                "lib/features/shop/shop_module.dart": (
                    "void registerShopFeature(GetIt getIt) {\n  getIt.registerFactory<A>(() => A());\n}\n"
                    "List<RouteBase> shopRoutes(GetIt getIt) => [GoRoute(path: '/shop')];\n"
                ),
                "lib/features/cart/cart_module.dart": (
                    "void registerCartFeature(GetIt getIt) {\n  getIt.registerFactory<B>(() => B());\n}\n"
                    "List<RouteBase> cartRoutes(GetIt getIt) => [GoRoute(path: '/cart')];\n"
                ),
            }
            for rel, text in files.items():
                (app / rel).parent.mkdir(parents=True, exist_ok=True)
                (app / rel).write_text(text)
            result = run_command([SYSTEM_BASH, str(REPO_ROOT / "scripts" / "fanal.sh"), str(app)], cwd=app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            report = (app / "flutter_analysis.md").read_text()
            self.assertIn("0 direct registration(s)", report)
            self.assertIn("2 feature module(s) - 2 registration(s)", report)
            self.assertIn("2 route(s) (router: 0, feature modules: 2)", report)
            self.assertIn("Modules not called from `lib/core/di/service_locator.dart`: `lib/features/cart/cart_module.dart`", report)
            self.assertIn("not spread into `lib/core/router/app_router.dart`: `lib/features/cart/cart_module.dart`", report)
            self.assertNotIn("shop_module.dart`", report.split("Modules not called")[1].split("\n")[0])


class TestFanalCrossFeature(unittest.TestCase):
    """fanal.sh resolves relative and package imports before comparing features,
    and counts only *_test.dart files per feature."""

    def test_relative_and_package_cross_feature_imports_and_test_counts(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fanal_x_") as raw:
            app = make_fake_app(Path(raw).resolve())
            name = next(
                line.split(":", 1)[1].strip()
                for line in (app / "pubspec.yaml").read_text().splitlines()
                if line.startswith("name:")
            )
            files = {
                "lib/features/home/presentation/screens/home_screen.dart": (
                    "import '../../../counter/data/repositories/counter_repository_impl.dart';\n"
                    f"import 'package:{name}/features/cart/presentation/cart_view.dart';\n"
                    "import '../../../cart/domain/cart.dart';\n"
                    "import '../widgets/own.dart';\n"
                ),
                "lib/features/counter/data/repositories/counter_repository_impl.dart": "class A {}\n",
                "lib/features/cart/presentation/cart_view.dart": "class B {}\n",
                "lib/features/cart/domain/cart.dart": "class C {}\n",
                "test/features/counter/data/repositories/counter_repository_impl_test.dart": "void main() {}\n",
                "test/features/counter/data/x_test.dart": "void main() {}\n",
            }
            for rel, text in files.items():
                (app / rel).parent.mkdir(parents=True, exist_ok=True)
                (app / rel).write_text(text)
            result = run_command([SYSTEM_BASH, str(REPO_ROOT / "scripts" / "fanal.sh"), str(app)], cwd=app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            report = (app / "flutter_analysis.md").read_text()
            self.assertNotIn("No imports into another feature's data/presentation layers", report)
            self.assertIn("**home** -> **counter/data**", report)
            self.assertIn("**home** -> **cart/presentation**", report)
            self.assertIn("**home** -> **cart/domain**", report)
            self.assertIn("counter (2 file(s))", report)


class TestFdeadEntryPoints(unittest.TestCase):
    """fdead --test never reports auto-loaded test config or flavor entry points."""

    def test_flavor_main_and_test_config_not_reported(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fdead_ep_") as raw:
            app = Path(raw).resolve() / "app"
            files = {
                "pubspec.yaml": "name: app\n",
                "lib/main.dart": "void main() {}\n",
                "lib/main_dev.dart": "void main() {}\n",
                "lib/orphan.dart": "void o() {}\n",
                "test/flutter_test_config.dart": "Future<void> testExecutable(f) async => f();\n",
            }
            for rel, text in files.items():
                (app / rel).parent.mkdir(parents=True, exist_ok=True)
                (app / rel).write_text(text)
            result = run_command(["bash", str(REPO_ROOT / "scripts" / "fdead.sh"), "--test"], cwd=app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("orphan.dart", result.stdout)
            self.assertNotIn("main_dev.dart", result.stdout)
            self.assertNotIn("flutter_test_config.dart", result.stdout.split("advisory")[0])


class TestFcheckImports(unittest.TestCase):
    """fcheck.sh sees double-quoted imports and exports, and matches package names exactly."""

    def _app(self, parent: Path) -> Path:
        app = parent / "app"
        (app / "lib").mkdir(parents=True)
        (app / "pubspec.yaml").write_text(
            "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n  alpha: ^1.0.0\n"
            "  beta: ^1.0.0\n  get: ^1.0.0\n  get_it: ^1.0.0\n  gamma: ^1.0.0\n"
        )
        (app / "lib" / "a.dart").write_text(
            'import "package:alpha/alpha.dart";\nexport \'package:beta/beta.dart\';\n'
            "import 'package:get_it/get_it.dart';\n"
        )
        return app

    def test_all_mode_counts_double_quotes_and_exports(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fcheck_") as raw:
            app = self._app(Path(raw).resolve())
            result = run_command(["bash", str(REPO_ROOT / "scripts" / "fcheck.sh")], cwd=app)
            self.assertNotIn("❌ alpha", result.stdout, msg=fmt(result))
            self.assertNotIn("❌ beta", result.stdout, msg=fmt(result))
            self.assertIn("❌ gamma", result.stdout)
            self.assertIn("❌ get\n", result.stdout + "\n")

    def test_single_package_mode_is_exact(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fcheck1_") as raw:
            app = self._app(Path(raw).resolve())
            script = str(REPO_ROOT / "scripts" / "fcheck.sh")
            self.assertIn("IS used", run_command(["bash", script, "get_it"], cwd=app).stdout)
            self.assertIn("IS used", run_command(["bash", script, "alpha"], cwd=app).stdout)
            self.assertIn("NOT directly imported", run_command(["bash", script, "get"], cwd=app).stdout)


class TestFl10nScan(unittest.TestCase):
    """fl10n.sh: l10n ancestor dirs, generated-dir exclusion, '/*' inside strings."""

    def test_ancestor_l10n_dir_and_glob_string_and_no_venv(self) -> None:
        if shutil.which("uv") is None:
            self.skipTest("uv is not on PATH")
        with tempfile.TemporaryDirectory(prefix="forge_fl10n_") as raw:
            outer = Path(raw).resolve()
            (outer / "pyproject.toml").write_text('[project]\nname = "outer"\nversion = "0"\nrequires-python = ">=3.9"\n')
            app = outer / "l10n" / "app"
            (app / "lib" / "core" / "l10n" / "generated").mkdir(parents=True)
            (app / "pubspec.yaml").write_text("name: fake_app\n")
            (app / "lib" / "core" / "l10n" / "generated" / "app_localizations.dart").write_text(
                "const a = 'Generated Message Here';\n"
            )
            (app / "lib" / "foo.dart").write_text(
                "const String glob = 'docs/*';\n"
                "const Widget w = Text('Visible After Glob');\n"
            )
            result = run_command([SYSTEM_BASH, str(REPO_ROOT / "scripts" / "fl10n.sh")], cwd=app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Visible After Glob", result.stdout)
            self.assertNotIn("Generated Message Here", result.stdout)
            self.assertFalse((outer / ".venv").exists())
            self.assertFalse((outer / "uv.lock").exists())


class TestFmap(unittest.TestCase):
    """fmap.sh: read-only, one line per feature with its wiring."""

    def test_reports_wiring_routes_and_barrel_dependencies(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fmap_") as raw:
            app = make_fake_app(Path(raw).resolve())
            files = {
                "lib/core/di/service_locator.dart": "void setup() {\n  registerShopFeature(getIt);\n}\n",
                "lib/core/router/app_router.dart": "final r = [\n  ...shopRoutes(getIt),\n];\n",
                "lib/core/router/route_constants.dart": "  static const String shop = '/shop';\n",
                "lib/features/shop/shop.dart": "library;\n",
                "lib/features/shop/shop_module.dart": (
                    "void registerShopFeature(GetIt getIt) {}\n"
                    "List<RouteBase> shopRoutes(GetIt getIt) => [GoRoute(path: Routes.shop)];\n"
                ),
                "lib/features/shop/domain/uses_cart.dart": "import '../../cart/cart.dart';\n",
                "lib/features/cart/cart.dart": "library;\n",
            }
            for rel, text in files.items():
                (app / rel).parent.mkdir(parents=True, exist_ok=True)
                (app / rel).write_text(text)
            before = tree_snapshot(app)
            result = run_command([SYSTEM_BASH, str(REPO_ROOT / "scripts" / "fmap.sh")], cwd=app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            shop = next(line for line in result.stdout.splitlines() if line.strip().startswith("shop "))
            self.assertIn("/shop", shop)
            self.assertIn("DI:yes router:yes", shop)
            self.assertIn("uses: cart", shop)
            cart = next(line for line in result.stdout.splitlines() if line.strip().startswith("cart "))
            self.assertIn("no module", cart)
            self.assertEqual(tree_snapshot(app), before)


class TestFwire(unittest.TestCase):
    """fwire.py: fgen's automatic wiring at the `// fgen:` markers."""

    FWIRE = REPO_ROOT / "scripts" / "fwire.py"
    ARGS = ["shop_item", "ShopItem", "shopItem", "demo_app"]

    def _app(self, root: Path, with_markers: bool = True) -> Path:
        files = {
            "lib/core/di/service_locator.dart": (
                "import 'package:get_it/get_it.dart';\n\nvoid setup() {\n"
                "  // fgen:register-features\n}\n"
            ),
            "lib/core/router/app_router.dart": (
                "import 'package:go_router/go_router.dart';\n\nfinal List<RouteBase> r = <RouteBase>[\n"
                "  // fgen:routes\n];\n"
            ),
            "lib/core/router/route_constants.dart": (
                "abstract final class Routes {\n  static const String home = '/';\n"
                "  // fgen:route-constants\n}\n"
            ),
            "test/core/di/service_locator_test.dart": (
                "import 'package:flutter_test/flutter_test.dart';\n\nvoid main() {\n"
                "  test('x', () {\n    // fgen:resolve\n  });\n}\n"
            ),
        }
        for rel, text in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text if with_markers else re.sub(r".*// fgen:.*\n", "", text))
        return root

    def _run(self, mode: str, app: Path) -> subprocess.CompletedProcess:
        return run_command(
            ["uv", "run", "--no-project", str(self.FWIRE), mode, str(app), *self.ARGS], cwd=app
        )

    def test_apply_inserts_at_every_marker_and_keeps_markers(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fwire_") as raw:
            app = self._app(Path(raw).resolve())
            result = self._run("apply", app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            locator = (app / "lib/core/di/service_locator.dart").read_text()
            self.assertIn("import '../../features/shop_item/shop_item_module.dart';", locator)
            self.assertIn("  registerShopItemFeature(getIt);\n  // fgen:register-features", locator)
            router = (app / "lib/core/router/app_router.dart").read_text()
            self.assertIn("  ...shopItemRoutes(getIt),\n  // fgen:routes", router)
            constants = (app / "lib/core/router/route_constants.dart").read_text()
            self.assertIn("static const String shopItem = '/shop_item';", constants)
            di_test = (app / "test/core/di/service_locator_test.dart").read_text()
            self.assertIn("package:demo_app/features/shop_item/domain/repositories/shop_item_repository.dart", di_test)
            self.assertIn("isA<ShopItemRepository>()", di_test)
            self.assertEqual(result.stdout.count("wired: "), 4)

    def test_missing_markers_print_manual_edits_and_exit_2(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fwire_") as raw:
            app = self._app(Path(raw).resolve(), with_markers=False)
            before = tree_snapshot(app)
            result = self._run("apply", app)
            self.assertEqual(result.returncode, 2, msg=fmt(result))
            self.assertIn("registerShopItemFeature(getIt);", result.stderr)
            self.assertEqual(tree_snapshot(app), before)

    def test_route_constant_collision_is_refused_by_check(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fwire_") as raw:
            app = self._app(Path(raw).resolve())
            constants = app / "lib/core/router/route_constants.dart"
            constants.write_text(constants.read_text().replace(
                "  // fgen:route-constants", "  static const String shopItem = '/x';\n  // fgen:route-constants"))
            result = self._run("check", app)
            self.assertEqual(result.returncode, 1, msg=fmt(result))
            self.assertIn("already exists", result.stderr)


class TestFwireMultilineImports(unittest.TestCase):
    def test_imports_go_after_a_multiline_import_statement(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fwire_ml_") as raw:
            app = Path(raw).resolve()
            locator = app / "lib/core/di/service_locator.dart"
            locator.parent.mkdir(parents=True)
            locator.write_text(
                "import 'package:get_it/get_it.dart';\n"
                "import '../../features/a/a.dart'\n    show A,\n        B;\n\n"
                "void setup() {\n  // fgen:register-features\n}\n"
            )
            run_command(["uv", "run", "--no-project", str(REPO_ROOT / "scripts/fwire.py"), "apply",
                         str(app), "shop", "Shop", "shop", "demo_app"], cwd=app)
            text = locator.read_text()
            self.assertIn("        B;\nimport '../../features/shop/shop_module.dart';\n", text)


class TestFwireCrlf(unittest.TestCase):
    def test_crlf_files_keep_crlf(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_fwire_crlf_") as raw:
            app = Path(raw).resolve()
            locator = app / "lib/core/di/service_locator.dart"
            locator.parent.mkdir(parents=True)
            locator.write_bytes(
                b"import 'package:get_it/get_it.dart';\r\n\r\nvoid setup() {\r\n  // fgen:register-features\r\n}\r\n"
            )
            result = run_command(["uv", "run", "--no-project", str(REPO_ROOT / "scripts/fwire.py"), "apply",
                                  str(app), "shop", "Shop", "shop", "demo_app"], cwd=app)
            data = locator.read_bytes()
            self.assertIn(b"registerShopFeature(getIt);", data, msg=fmt(result))
            self.assertEqual(data.count(b"\n"), data.count(b"\r\n"), msg=repr(data))


class TestUpgradePlan(unittest.TestCase):
    """prepare_upgrade.py on a synthetic two-commit template and an app that
    diverged the way real apps do (removed demo feature, no feature templates,
    customized files): every plan category, and the diverged-app gate."""

    HELPER = REPO_ROOT / ".agents" / "skills" / "flutterforge-upgrade" / "prepare_upgrade.py"
    BASE_FILES = {
        "AGENTS.md": "line one\nline two\nline three\n",
        "lib/core/a.dart": "// a v1\n",
        "lib/core/gone.dart": "// gone\n",
        "lib/features/home/home.dart": "// home v1\n",
        "scripts/tool.sh": "echo v1\n",
        "scripts/feature_templates/x.tpl": "x v1\n",
        "test/core/a_test.dart": "import 'package:my_flutter_app/core/a.dart';\n",
        "lib/core/helper.dart": "// helper\n",
        "lib/core/helper_base.dart": "// base\n",
        "lib/core/helper_mid.dart": "import 'helper_base.dart';\n",
        "test/core/helper_test.dart": "import 'package:my_flutter_app/core/helper.dart';\nimport 'package:my_flutter_app/core/helper_mid.dart';\n",
    }
    HEAD_CHANGES = {
        "AGENTS.md": "line ONE\nline two\nline three\n",
        "lib/core/a.dart": "// a v2\n",
        "lib/core/gone.dart": None,
        "lib/core/new.dart": "// new\n",
        "lib/core/needs.dart": "import 'missing.dart';\n",
        "lib/features/home/home_module.dart": "// module\n",
        "scripts/tool.sh": "echo v2\n",
        "scripts/feature_templates/x.tpl": "x v2\n",
        "test/core/new_test.dart": "import 'package:my_flutter_app/core/new.dart';\n",
        "lib/core/helper.dart": None,
        "lib/core/helper_base.dart": None,
        "lib/core/helper_mid.dart": None,
        "test/core/helper_test.dart": None,
    }
    IDENT = ["-c", "user.name=t", "-c", "user.email=t@t"]

    def _template(self, root: Path) -> Path:
        tpl = root / "template"
        tpl.mkdir()
        run_command(["git", "init", "-q"], cwd=tpl)
        for files in (self.BASE_FILES, self.HEAD_CHANGES):
            for rel, text in files.items():
                path = tpl / rel
                if text is None:
                    path.unlink()
                    continue
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            run_command(["git", "add", "-A"], cwd=tpl)
            run_command(["git", *self.IDENT, "commit", "-qm", "c"], cwd=tpl)
        return tpl

    def _app(self, root: Path, edits: dict) -> Path:
        app = root / "app"
        for rel, text in self.BASE_FILES.items():
            path = app / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text.replace("my_flutter_app", "demo_app"))
        (app / "pubspec.yaml").write_text("name: demo_app\n")
        for rel, text in edits.items():
            path = app / rel
            if text is None:
                shutil.rmtree(path) if path.is_dir() else path.unlink()
            else:
                path.write_text(text)
        run_command(["git", "init", "-q"], cwd=app)
        run_command(["git", "add", "-A"], cwd=app)
        run_command(["git", *self.IDENT, "commit", "-qm", "app"], cwd=app)
        return app

    def _run(self, tpl: Path, app: Path, *extra: str) -> subprocess.CompletedProcess:
        return run_command(
            ["uv", "run", "--no-project", str(self.HELPER), "--template", str(tpl),
             "--app", str(app), "--base", "HEAD~1", *extra],
            cwd=app,
        )

    def _section(self, stdout: str, action: str) -> str:
        match = re.search(rf"^{action} \(\d+\)[^\n]*:\n((?:  .*\n)*)", stdout, re.M)
        return match.group(1) if match else ""

    def test_plan_classifies_every_change_and_applies_only_safe_ones(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_plan_") as raw:
            root = Path(raw).resolve()
            tpl = self._template(root)
            app = self._app(root, {
                "lib/features/home": None,              # demo feature removed
                "scripts/feature_templates": None,      # app has no feature templates
                "scripts/tool.sh": "echo custom\n",     # same line as the template change
                "AGENTS.md": "line one\nline two\nline three\napp rule\n",
                # Customized test the template deleted: kept, and so must be
                # everything it imports (directly and through helper_mid).
                "test/core/helper_test.dart": (
                    "import 'package:demo_app/core/helper.dart';\n"
                    "import 'package:demo_app/core/helper_mid.dart';\n// ours\n"
                ),
            })
            result = self._run(tpl, app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            out = result.stdout
            self.assertIn("scripts/tool.sh", self._section(out, "CONFLICT"))
            self.assertIn("AGENTS.md", self._section(out, "merge"))
            self.assertIn("lib/core/a.dart", self._section(out, "take"))
            self.assertIn("lib/core/new.dart", self._section(out, "add"))
            self.assertIn("test/core/new_test.dart", self._section(out, "add"))
            self.assertIn("lib/core/gone.dart", self._section(out, "delete"))
            skipped = self._section(out, "skip")
            self.assertIn("lib/features/home/home_module.dart  (feature 'home' not in app)", skipped)
            self.assertIn("lib/core/needs.dart  (needs lib/core/missing.dart)", skipped)
            self.assertIn("scripts/feature_templates/x.tpl", self._section(out, "absent"))
            kept = self._section(out, "keep")
            self.assertIn("test/core/helper_test.dart", kept)
            self.assertIn("lib/core/helper.dart  (template deleted it; still imported by test/core/helper_test.dart)", kept)
            self.assertIn("lib/core/helper_base.dart  (template deleted it; still imported by lib/core/helper_mid.dart)", kept)
            for still in ("helper.dart", "helper_mid.dart", "helper_base.dart"):
                self.assertTrue((app / "lib/core" / still).exists(), still)

            self.assertEqual((app / "AGENTS.md").read_text(), "line ONE\nline two\nline three\napp rule\n")
            self.assertEqual((app / "lib/core/a.dart").read_text(), "// a v2\n")
            self.assertIn("<<<<<<< app", (app / "scripts/tool.sh").read_text())
            self.assertFalse((app / "lib/core/gone.dart").exists())
            self.assertFalse((app / "lib/core/needs.dart").exists())
            self.assertFalse((app / "lib/features/home").exists())
            self.assertFalse((app / "scripts/feature_templates").exists())
            self.assertIn("demo_app", (app / "test/core/new_test.dart").read_text())
            self.assertEqual(run_command(["git", "diff", "--cached", "--name-only"], cwd=app).stdout, "")

    def test_diverged_app_gets_the_plan_but_no_writes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_plan_") as raw:
            root = Path(raw).resolve()
            tpl = self._template(root)
            app = self._app(root, {
                "lib/features/home": None,
                "scripts/feature_templates": None,
                "scripts/tool.sh": "echo custom\n",
                "AGENTS.md": "ours\n",
                "lib/core/a.dart": "// ours\n",
                "test/core/a_test.dart": "// ours\n",
                "lib/core/gone.dart": "// ours\n",
                "lib/core/helper_mid.dart": "// ours\n",
                "test/core/helper_test.dart": "// ours\n",
            })
            before = tree_snapshot(app)
            result = self._run(tpl, app)
            self.assertEqual(result.returncode, 3, msg=fmt(result))
            self.assertIn("DIVERGED", result.stdout)
            self.assertEqual(tree_snapshot(app), before)
            forced = self._run(tpl, app, "--apply-diverged")
            self.assertEqual(forced.returncode, 0, msg=fmt(forced))
            self.assertTrue((app / "lib/core/new.dart").exists())


    def test_new_script_is_added_executable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_plan_") as raw:
            root = Path(raw).resolve()
            tpl = self._template(root)
            script = tpl / "scripts" / "new_tool.sh"
            script.write_text("echo new\n")
            script.chmod(0o755)
            run_command(["git", "add", "-A"], cwd=tpl)
            run_command(["git", *self.IDENT, "commit", "-qm", "c3"], cwd=tpl)
            app = self._app(root, {})
            result = run_command(
                ["uv", "run", "--no-project", str(self.HELPER), "--template", str(tpl),
                 "--app", str(app), "--base", "HEAD~2"],
                cwd=app,
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            added = app / "scripts" / "new_tool.sh"
            self.assertTrue(added.exists(), msg=result.stdout)
            self.assertTrue(os.access(added, os.X_OK), "new scripts must stay executable")

    def test_base_newer_than_head_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_plan_") as raw:
            root = Path(raw).resolve()
            tpl = self._template(root)
            app = self._app(root, {})
            before = tree_snapshot(app)
            result = run_command(
                ["uv", "run", "--no-project", str(self.HELPER), "--template", str(tpl),
                 "--app", str(app), "--base", "HEAD", "--head", "HEAD~1"],
                cwd=app,
            )
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("not an ancestor", result.stderr)
            self.assertEqual(tree_snapshot(app), before)

    def test_corrupt_stamp_is_a_clear_error(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_plan_") as raw:
            root = Path(raw).resolve()
            tpl = self._template(root)
            app = self._app(root, {})
            (app / ".flutterforge.json").write_text("{not json")
            run_command(["git", "add", "-A"], cwd=app)
            run_command(["git", *self.IDENT, "commit", "-qm", "stamp"], cwd=app)
            result = run_command(
                ["uv", "run", "--no-project", str(self.HELPER), "--template", str(tpl),
                 "--app", str(app), "--dry-run"],
                cwd=app,
            )
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("not valid JSON", result.stderr)
            self.assertNotIn("Traceback", result.stderr)


class TestUpgradeHelper(unittest.TestCase):
    """prepare_upgrade.py (flutterforge-upgrade skill) against this repository's
    own committed history: base detection, 3-way staging, and the stamp."""

    HELPER = REPO_ROOT / ".agents" / "skills" / "flutterforge-upgrade" / "prepare_upgrade.py"
    BASE_OFFSET = "HEAD~3"

    @classmethod
    def setUpClass(cls) -> None:
        probe = run_command(["git", "rev-parse", cls.BASE_OFFSET], cwd=REPO_ROOT)
        if probe.returncode != 0:
            raise unittest.SkipTest("needs template git history (shallow clone?)")
        cls.base = probe.stdout.strip()
        cls.head = run_command(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT).stdout.strip()
        import importlib.util

        spec = importlib.util.spec_from_file_location("prepare_upgrade", cls.HELPER)
        assert spec is not None and spec.loader is not None
        cls.helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.helper)

    def _make_app(self, root: Path, rev: str) -> Path:
        app = root / "old_app"
        app.mkdir()
        self.helper.build_tree(REPO_ROOT, rev, "demo_app", app, True)
        (app / "pubspec.yaml").write_text("name: demo_app\n")
        for command in (
            ["git", "init", "-q"],
            ["git", "add", "-A"],
            ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "generated"],
        ):
            self.assertEqual(run_command(command, cwd=app).returncode, 0)
        return app

    def _upgrade(self, app: Path, *extra: str) -> subprocess.CompletedProcess:
        return run_command(
            ["uv", "run", "--no-project", str(self.HELPER), "--template", str(REPO_ROOT),
             "--app", str(app), *extra],
            cwd=app,
            timeout=SLOW_TIMEOUT,
        )

    def _tree(self, rev: str, root: Path) -> dict[str, bytes]:
        out = Path(tempfile.mkdtemp(prefix=f"tree_{rev[:7]}_", dir=root))
        self.helper.build_tree(REPO_ROOT, rev, "demo_app", out, True)
        return {
            str(p.relative_to(out)): p.read_bytes()
            for p in out.rglob("*")
            if p.is_file() and p.name != "README.md"
        }

    def test_detected_base_ships_the_same_files_as_the_real_base(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_upgrade_") as raw:
            root = Path(raw).resolve()
            app = self._make_app(root, self.base)
            result = self._upgrade(app, "--dry-run")
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            detected = re.search(r"^base:\s+([0-9a-f]+)", result.stdout, re.M)
            assert detected is not None, result.stdout
            full = run_command(["git", "rev-parse", detected.group(1)], cwd=REPO_ROOT).stdout.strip()
            # Ties are allowed, but only between commits shipping identical files.
            self.assertEqual(self._tree(full, root), self._tree(self.base, root))

    def test_upgrade_stages_without_committing_and_keeps_customizations(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_upgrade_") as raw:
            app = self._make_app(Path(raw).resolve(), self.base)
            custom = app / "scripts" / "fverify.sh"
            custom.write_text(custom.read_text() + "\n# app customization\n")
            run_command(["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit",
                         "-qam", "customize"], cwd=app)
            before = run_command(["git", "rev-parse", "HEAD"], cwd=app).stdout

            result = self._upgrade(app, "--base", self.base)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(run_command(["git", "rev-parse", "HEAD"], cwd=app).stdout, before)
            self.assertIn("# app customization", custom.read_text())
            stamp = json.loads((app / ".flutterforge.json").read_text())
            self.assertEqual(stamp["templateCommit"], self.head)

    def test_untracked_files_do_not_block_the_upgrade(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_upgrade_") as raw:
            app = self._make_app(Path(raw).resolve(), self.base)
            notes = app / "ux-audit" / "report.md"
            notes.parent.mkdir()
            notes.write_text("# audit\n")
            result = self._upgrade(app, "--base", self.base)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(notes.read_text(), "# audit\n")

    def test_reference_tree_without_counter_builds_at_head(self) -> None:
        """Apps that removed the Counter demo: the helper replays
        remove_counter.sh in a reference tree that is not a Flutter app."""
        with tempfile.TemporaryDirectory(prefix="forge_upgrade_") as raw:
            out = Path(raw) / "tree"
            out.mkdir()
            self.helper.build_tree(REPO_ROOT, self.head, "demo_app", out, False)
            self.assertFalse((out / "lib" / "features" / "counter").exists())

    def test_stamp_at_head_reports_up_to_date(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_upgrade_") as raw:
            app = self._make_app(Path(raw).resolve(), self.head)
            (app / ".flutterforge.json").write_text(json.dumps({"templateCommit": self.head}))
            run_command(["git", "add", "-A"], cwd=app)
            run_command(["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit",
                         "-qm", "stamp"], cwd=app)
            result = self._upgrade(app)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("Already up to date.", result.stdout)

    def _stamped_app(self, root: Path, commit: str) -> Path:
        app = self._make_app(root, self.base)
        (app / ".flutterforge.json").write_text(json.dumps({"templateCommit": commit}))
        run_command(["git", "add", "-A"], cwd=app)
        run_command(["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit",
                     "-qm", "stamp"], cwd=app)
        return app

    def test_unresolvable_stamp_commit_is_an_error_not_up_to_date(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_upgrade_") as raw:
            app = self._stamped_app(Path(raw).resolve(), "0" * 40)
            result = self._upgrade(app, "--dry-run")
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertNotIn("Already up to date.", result.stdout)
            self.assertIn("not in this template checkout", result.stderr)

    def test_shallow_template_clone_is_refused(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_upgrade_") as raw:
            root = Path(raw).resolve()
            app = self._stamped_app(root, self.base)
            shallow = root / "shallow_template"
            clone = run_command(
                ["git", "clone", "-q", "--depth", "1", f"file://{REPO_ROOT}", str(shallow)],
                cwd=root,
            )
            self.assertEqual(clone.returncode, 0, msg=fmt(clone))
            result = run_command(
                ["uv", "run", "--no-project", str(self.HELPER), "--template", str(shallow),
                 "--app", str(app), "--dry-run"],
                cwd=app,
                timeout=SLOW_TIMEOUT,
            )
            self.assertNotEqual(result.returncode, 0, msg=fmt(result))
            self.assertNotIn("Already up to date.", result.stdout)
            self.assertIn("shallow clone", result.stderr)


class TestSyncSkillsTargets(unittest.TestCase):
    """sync_skills.sh --user from an (older) app never writes through a user
    skill symlink into another checkout's canonical .agents/skills, and syncs
    every skill file, not only Markdown."""

    def test_symlinked_canonical_source_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory(prefix="forge_sync_") as raw:
            root = Path(raw).resolve()
            app = root / "app"
            (app / "scripts").mkdir(parents=True)
            shutil.copytree(REPO_ROOT / ".agents", app / ".agents")
            shutil.copy(REPO_ROOT / "scripts" / "sync_skills.sh", app / "scripts")
            old = app / ".agents/skills/flutter-audit/SKILL.md"
            old.write_text(old.read_text() + "\n<!-- older app copy -->\n")

            canonical = root / "other_template/.agents/skills/flutter-audit"
            shutil.copytree(REPO_ROOT / ".agents/skills/flutter-audit", canonical)
            pristine = (canonical / "SKILL.md").read_bytes()
            home = root / "home"
            (home / ".agents/skills").mkdir(parents=True)
            (home / ".claude/skills").mkdir(parents=True)
            (home / ".agents/skills/flutter-audit").symlink_to(canonical)
            user_copy = home / ".agents/skills/flutterforge-upgrade"
            user_copy.mkdir()
            (user_copy / "SKILL.md").write_text("stale\n")

            env = dict(os.environ, HOME=str(home))
            result = subprocess.run(
                ["bash", "scripts/sync_skills.sh", "--user"],
                cwd=app, env=env, capture_output=True, text=True, timeout=COMMAND_TIMEOUT,
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual((canonical / "SKILL.md").read_bytes(), pristine)
            self.assertIn("another checkout's canonical source", result.stdout)
            # A real user copy is synchronized, helper script (and its mode) included.
            helper = user_copy / "prepare_upgrade.py"
            self.assertTrue(helper.exists(), msg=result.stdout)
            self.assertEqual(
                helper.stat().st_mode & 0o777,
                (app / ".agents/skills/flutterforge-upgrade/prepare_upgrade.py").stat().st_mode & 0o777,
            )


class TestVerifyTemplateScript(unittest.TestCase):
    """The root verification entry point obeys its own contract."""

    def test_exists_executable_and_parses(self) -> None:
        script = REPO_ROOT / "scripts" / "verify_template.sh"
        self.assertTrue(script.exists())
        self.assertTrue(os.access(script, os.X_OK))
        result = run_command([SYSTEM_BASH, "-n", str(script)], cwd=REPO_ROOT)
        self.assertEqual(result.returncode, 0, msg=fmt(result))

    def test_does_not_invoke_itself(self) -> None:
        """Template verification must never recursively call itself."""
        script = REPO_ROOT / "scripts" / "verify_template.sh"
        for lineno, line in enumerate(script.read_text().splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#") or stripped.startswith("echo"):
                continue  # documentation/usage text only
            self.assertNotIn(
                "verify_template",
                stripped,
                msg=f"line {lineno} would make the script recursive",
            )

    def test_name_distinct_from_generated_app_gate(self) -> None:
        """Template verification and app verification must have distinct names."""
        self.assertTrue((REPO_ROOT / "scripts" / "verify_template.sh").exists())
        self.assertTrue((REPO_ROOT / "scripts" / "fverify.sh").exists())

    def test_fast_level_runs_green(self) -> None:
        """The documented one-command fast level works from any directory.

        Skipped when the harness itself is already running inside
        scripts/verify_template.sh (FORGE_VERIFY_WRAPPER=1) so the wrapper
        never re-enters itself.
        """
        if os.environ.get("FORGE_VERIFY_WRAPPER") == "1":
            self.skipTest("already running inside scripts/verify_template.sh")
        with tempfile.TemporaryDirectory(prefix="forge_vt_") as raw:
            result = run_command(
                ["bash", str(REPO_ROOT / "scripts" / "verify_template.sh")],
                cwd=Path(raw).resolve(),
                timeout=600,
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertIn("fast suite ✓", result.stdout)


class TestPackageSpecs(unittest.TestCase):
    """packages_to_add.json carries constrained (major-pinned) dependency specs."""

    SPEC_PATTERN = re.compile(r"^[a-z_][a-z0-9_]*:\^[0-9]+\.[0-9]+(\.[0-9]+)?$")

    def test_every_entry_is_a_major_pinned_spec(self) -> None:
        data = json.loads((REPO_ROOT / "packages_to_add.json").read_text())
        for section in ("dependencies", "dev_dependencies"):
            self.assertIn(section, data)
            for entry in data[section]:
                with self.subTest(entry=entry):
                    self.assertRegex(
                        entry,
                        self.SPEC_PATTERN,
                        msg="entries must look like 'package:^major.minor' "
                        "(ranges are established empirically — see "
                        "docs/compatibility.md)",
                    )

    def test_template_stack_present(self) -> None:
        data = json.loads((REPO_ROOT / "packages_to_add.json").read_text())
        joined = " ".join(data["dependencies"] + data["dev_dependencies"])
        for package in (
            "flutter_bloc",
            "go_router",
            "freezed",
            "freezed_annotation",
            "get_it",
            "fpdart",
            "bloc_test",
            "mocktail",
            "material_ui",
            "cupertino_ui",
        ):
            self.assertIn(f"{package}:", joined)


class TestGeneratedGitignore(unittest.TestCase):
    """template-gitignore never swallows app source: a feature named after a
    generic tool directory (build, out, gen, bin, tags, ...) stays tracked,
    while the real build/generated outputs stay ignored."""

    FEATURE_NAMES = ("bin", "build", "captures", "freeline", "gen", "out", "proguard", "tags")

    def setUp(self) -> None:
        if shutil.which("git") is None:
            self.skipTest("git not on PATH")
        self.tmp = tempfile.TemporaryDirectory(prefix="forge-gitignore-")
        self.root = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        shutil.copy(REPO_ROOT / "template-gitignore", self.root / ".gitignore")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _ignored(self, paths: list[str]) -> set[str]:
        for rel in paths:
            target = self.root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.touch()
        result = subprocess.run(
            ["git", "check-ignore", *paths], cwd=self.root, capture_output=True, text=True
        )
        return set(result.stdout.split())

    def test_features_named_like_tool_directories_are_tracked(self) -> None:
        paths = [
            f"{tree}/features/{name}/{name}.dart"
            for name in self.FEATURE_NAMES
            for tree in ("lib", "test")
        ]
        self.assertEqual(self._ignored(paths), set())

    def test_pubspec_lock_is_committed(self) -> None:
        self.assertEqual(self._ignored(["pubspec.lock"]), set())

    def test_build_and_generated_outputs_stay_ignored(self) -> None:
        paths = [
            "build/app.dill",
            "android/app/build/out.apk",
            "ios/build/x.o",
            "lib/core/l10n/generated/app_localizations.dart",
        ]
        self.assertEqual(self._ignored(paths), set(paths))


class TestRemoveCounterHarmless(unittest.TestCase):
    """remove_counter.sh on an app without the counter is a harmless no-op."""

    def test_repeated_removal_outside_full_feature_is_harmless(self) -> None:
        if shutil.which("uv") is None:
            self.skipTest("uv is not on PATH")
        with tempfile.TemporaryDirectory(prefix="forge_rmctr_") as raw:
            app = Path(raw).resolve() / "app"
            (app / "lib").mkdir(parents=True)
            (app / "pubspec.yaml").write_text("name: fake_app\ndescription: x\n")
            sentinel = app / "lib" / "user_edit.dart"
            sentinel.write_text("// precious user work\n")
            for attempt in ("first", "second"):
                with self.subTest(attempt=attempt):
                    result = run_command(
                        ["bash", str(REPO_ROOT / "remove_counter.sh")], cwd=app
                    )
                    self.assertEqual(result.returncode, 0, msg=fmt(result))
            self.assertEqual(sentinel.read_text(), "// precious user work\n")
            self.assertEqual(
                (app / "pubspec.yaml").read_text(),
                "name: fake_app\ndescription: x\n",
            )


    def test_user_feature_with_counter_in_name_stays_wired_and_unused_keys_removed(self) -> None:
        if shutil.which("uv") is None:
            self.skipTest("uv is not on PATH")
        with tempfile.TemporaryDirectory(prefix="forge_rmctr2_") as raw:
            app = Path(raw).resolve() / "app"
            files = {
                "pubspec.yaml": "name: app\n",
                "lib/core/di/service_locator.dart": (
                    "import '../../features/counter/counter_module.dart';\n"
                    "import '../../features/counter/data/datasources/counter_local_datasource.dart';\n"
                    "import '../../features/step_counter/step_counter_module.dart';\n"
                    "Future<void> setupServiceLocator({\n"
                    "  ICounterLocalDataSource? counterLocalDataSourceOverride,\n"
                    "}) async {\n"
                    "  registerCounterFeature(\n    getIt,\n    localDataSource: counterLocalDataSourceOverride,\n  );\n"
                    "  registerStepCounterFeature(getIt);\n"
                    "  // fgen:register-features\n}\n"
                ),
                "lib/core/router/app_router.dart": (
                    "import '../../features/counter/counter_module.dart';\n"
                    "import '../../features/step_counter/step_counter_module.dart';\n"
                    "final r = [\n  ...counterRoutes(getIt),\n  ...stepCounterRoutes(getIt),\n];\n"
                ),
                "test/core/di/service_locator_test.dart": (
                    "import 'package:app/features/counter/data/repositories/counter_repository_impl.dart';\n"
                    "import 'package:app/features/step_counter/data/repositories/step_counter_repository_impl.dart';\n"
                    "void main() {\n  expect(getIt<ICounterRepository>(), isA<CounterRepository>());\n"
                    "  expect(getIt<IStepCounterRepository>(), isA<StepCounterRepository>());\n}\n"
                ),
                "lib/features/step_counter/step_counter_module.dart": "String k = l10n.reset;\n",
                "lib/core/l10n/app_localizations_en.arb": (
                    '{\n  "@@locale": "en",\n  "counterTitle": "Counter Demo",\n  "@counterTitle": {\n    "description": "d"\n  },\n'
                    '  "reset": "Reset",\n  "count": "Count",\n  "keep": "Keep"\n}\n'
                ),
                "lib/core/l10n/app_localizations_fr.arb": (
                    '{\n  "@@locale": "fr",\n  "counterTitle": "Demo",\n  "reset": "R",\n  "count": "C",\n  "keep": "K"\n}\n'
                ),
            }
            for rel, text in files.items():
                (app / rel).parent.mkdir(parents=True, exist_ok=True)
                (app / rel).write_text(text)
            env, log = fake_tool_env(app.parent)
            outputs = []
            for _ in range(2):
                result = subprocess.run(
                    ["bash", str(REPO_ROOT / "remove_counter.sh")], cwd=str(app), env=env,
                    capture_output=True, text=True, timeout=COMMAND_TIMEOUT,
                )
                self.assertEqual(result.returncode, 0, msg=fmt(result))
                outputs.append({rel: (app / rel).read_text() for rel in files})
            self.assertEqual(outputs[0], outputs[1])
            locator = (app / "lib/core/di/service_locator.dart").read_text()
            self.assertIn("step_counter_module.dart", locator)
            self.assertIn("registerStepCounterFeature(getIt);", locator)
            self.assertNotIn("features/counter/", locator)
            self.assertNotIn("registerCounterFeature", locator)
            self.assertNotIn("counterLocalDataSourceOverride", locator)
            router = (app / "lib/core/router/app_router.dart").read_text()
            self.assertIn("stepCounterRoutes(getIt)", router)
            self.assertNotIn("counterRoutes(getIt),\n  ...step", router)
            self.assertNotIn("features/counter/", router)
            smoke = (app / "test/core/di/service_locator_test.dart").read_text()
            self.assertIn("IStepCounterRepository", smoke)
            self.assertNotIn("ICounterRepository", smoke)
            en = json.loads((app / "lib/core/l10n/app_localizations_en.arb").read_text())
            fr = json.loads((app / "lib/core/l10n/app_localizations_fr.arb").read_text())
            self.assertEqual(list(en), ["@@locale", "reset", "keep"])
            self.assertEqual(list(fr), ["@@locale", "reset", "keep"])
            self.assertTrue(any("gen-l10n" in inv for inv in read_invocations(log)))


# ----------------------------------------------------------------------------------
# Slow: real Flutter end-to-end (create, publish, verify from FINAL path, fgen)
# ----------------------------------------------------------------------------------


class TestGeneratedAppEndToEnd(unittest.TestCase):
    """Real subprocess smoke test: the whole generator workflow with Flutter."""

    @classmethod
    def setUpClass(cls) -> None:
        if os.environ.get("FORGE_SKIP_SLOW") == "1":
            raise unittest.SkipTest("FORGE_SKIP_SLOW=1 — skipping real Flutter end-to-end tests")
        if shutil.which("flutter") is None:
            raise unittest.SkipTest("flutter is not on PATH — skipping real Flutter end-to-end tests")
        cls._tmp = tempfile.TemporaryDirectory(prefix="forge e2e parent ")
        cls.addClassCleanup(cls._tmp.cleanup)
        cls.parent = Path(cls._tmp.name).resolve()  # parent path contains a space
        cls.app = cls.parent / "smoke_app"
        print(f"\n[e2e] creating app in '{cls.parent}' (several minutes)...")
        cls.create_result = run_generator(
            [
                "--no-open",
                "--org=com.example.forge",
                "--platforms=linux,android",
                "--description=Forge smoke test app",
                "smoke_app",
            ],
            cwd=cls.parent,
            timeout=SLOW_TIMEOUT,
        )
        artifacts = os.environ.get("FORGE_ARTIFACTS_DIR")
        if artifacts:
            directory = Path(artifacts)
            directory.mkdir(parents=True, exist_ok=True)
            (directory / "creation.log").write_text(
                cls.create_result.stdout + "\n--- stderr ---\n" + cls.create_result.stderr
            )
        if cls.create_result.returncode != 0:
            raise AssertionError("Baseline generation failed; dependent smoke steps cannot run." + fmt(cls.create_result))

    def test_00_creation_succeeds_with_correct_metadata(self) -> None:
        result = self.create_result
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        self.assertIn("Project setup complete", result.stdout)

        pubspec = (self.app / "pubspec.yaml").read_text()
        self.assertIn("name: smoke_app", pubspec)
        # A supplied --description is preserved verbatim (flutter quotes it).
        self.assertIn('description: "Forge smoke test app"', pubspec)

        # Organization applied (android kotlin sources).
        self.assertTrue(
            (
                self.app
                / "android"
                / "app"
                / "src"
                / "main"
                / "kotlin"
                / "com"
                / "example"
                / "forge"
                / "smoke_app"
                / "MainActivity.kt"
            ).exists(),
            "expected com.example.forge kotlin sources",
        )

        # The placeholder is gone from every template-owned text path.
        for relative in ["lib", "test", "README.md"]:
            for path in (self.app / relative).rglob("*"):
                if path.is_file() and path.suffix in {".dart", ".md", ".yaml", ".arb"}:
                    self.assertNotIn(
                        "my_flutter_app",
                        path.read_text(errors="replace"),
                        msg=f"placeholder found in {path}",
                    )

        # The staging directory is gone after publication.
        retained = [p for p in self.parent.iterdir() if p.name.startswith(".flutterforge-stage-")]
        self.assertEqual(retained, [])
        self.assertTrue((self.app / "lib" / "features" / "counter").exists())

    def test_10_final_path_verification_passes(self) -> None:
        """The published app is verified from its FINAL path, after staging moved."""
        self.assertEqual(self.create_result.returncode, 0, msg=fmt(self.create_result))
        dart = shutil.which("dart")
        assert dart is not None
        for command in (
            ["flutter", "pub", "get"],
            [dart, "fix", "--apply"],
            [dart, "format", "."],
            ["bash", "scripts/fverify.sh"],
        ):
            print(f"[e2e] final-path verification: {' '.join(command)}")
            result = run_command(command, cwd=self.app, timeout=SLOW_TIMEOUT)
            self.assertEqual(
                result.returncode,
                0,
                msg=f"command failed: {' '.join(command)}\n{fmt(result)}",
            )

    def test_11_checker_selftests_pass_in_generated_app(self) -> None:
        """The checker's regression fixtures are not shipped, but they must pass
        against the checker a generated app actually contains."""
        self.assertFalse((self.app / "test" / "architecture_checker_test.dart").exists())
        self.assertTrue((self.app / "test" / "architecture_test.dart").exists())
        destination = self.app / "test" / "checker_selftest"
        shutil.copytree(REPO_ROOT / "tools" / "checker_tests", destination)
        try:
            result = run_command(
                ["flutter", "test", "--reporter", "failures-only", "test/checker_selftest"],
                cwd=self.app,
                timeout=SLOW_TIMEOUT,
            )
            self.assertEqual(result.returncode, 0, msg=fmt(result))
        finally:
            shutil.rmtree(destination)

    def test_20_project_rerun_preserves_edits_and_exits_nonzero(self) -> None:
        self.assertEqual(self.create_result.returncode, 0, msg=fmt(self.create_result))
        sentinel = self.app / "lib" / "user_edit.dart"
        sentinel.write_text("// precious user work\n")
        pubspec_before = (self.app / "pubspec.yaml").read_bytes()

        result = run_generator(
            [
                "--no-open",
                "--org=com.example.forge",
                "--platforms=linux,android",
                "smoke_app",
            ],
            cwd=self.parent,
            timeout=SLOW_TIMEOUT,
        )
        self.assertNotEqual(result.returncode, 0, msg=fmt(result))
        self.assertIn("already exists", result.stderr)
        self.assertEqual(sentinel.read_text(), "// precious user work\n")
        self.assertEqual((self.app / "pubspec.yaml").read_bytes(), pubspec_before)
        retained = [p for p in self.parent.iterdir() if p.name.startswith(".flutterforge-stage-")]
        self.assertEqual(retained, [], "a refusal must not create staging directories")

    def test_21_fimp_repairs_real_relative_imports_and_retains_failed_repairs(self) -> None:
        """Real analyzer diagnostics, comments, lib/test relocations and exit status."""
        files = {
            "lib/core/tooling/repair_lib_helper.dart": "const int repairValue = 7;\n",
            "lib/core/repair_consumer.dart": (
                "/* import 'missing/repair_lib_helper.dart'; */\n"
                "import 'missing/repair_lib_helper.dart'; // missing/repair_lib_helper.dart\n"
                "int readRepairValue() => repairValue;\n"
            ),
            "test/support/repair_test_helper.dart": "const int repairTestValue = 9;\n",
            "test/tooling/repair_probe_test.dart": (
                "import 'package:flutter_test/flutter_test.dart';\n"
                "import 'package:smoke_app/core/repair_consumer.dart';\n"
                "import '../old/repair_test_helper.dart';\n"
                "void main() {\n"
                "  test('repaired imports execute', () {\n"
                "    expect(readRepairValue(), 7);\n"
                "    expect(repairTestValue, 9);\n"
                "  });\n"
                "}\n"
            ),
        }
        paths = [self.app / relative for relative in files]
        try:
            for relative, source in files.items():
                path = self.app / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            snapshot = {path: path.read_bytes() for path in paths}
            preview = run_command(["bash", "scripts/fimp.sh"], cwd=self.app, timeout=SLOW_TIMEOUT)
            self.assertEqual(preview.returncode, 0, msg=fmt(preview))
            self.assertEqual({path: path.read_bytes() for path in paths}, snapshot)
            applied = run_command(["bash", "scripts/fimp.sh", "--apply"], cwd=self.app, timeout=SLOW_TIMEOUT)
            self.assertEqual(applied.returncode, 0, msg=fmt(applied))
            consumer = self.app / "lib/core/repair_consumer.dart"
            self.assertIn("import 'tooling/repair_lib_helper.dart'; // missing/repair_lib_helper.dart", consumer.read_text())
            self.assertIn("/* import 'missing/repair_lib_helper.dart'; */", consumer.read_text())
            self.assertIn("import '../support/repair_test_helper.dart';", paths[-1].read_text())
            execution = run_command(["flutter", "test", "test/tooling/repair_probe_test.dart"], cwd=self.app, timeout=SLOW_TIMEOUT)
            self.assertEqual(execution.returncode, 0, msg=fmt(execution))
            consumer.write_text(files["lib/core/repair_consumer.dart"] + "const String unrelatedError = 123;\n")
            failed = run_command(["bash", "scripts/fimp.sh", "--apply"], cwd=self.app, timeout=SLOW_TIMEOUT)
            self.assertNotEqual(failed.returncode, 0, msg=fmt(failed))
            self.assertIn("RETAINED", failed.stdout)
            self.assertIn("import 'tooling/repair_lib_helper.dart';", consumer.read_text())
        finally:
            for path in paths:
                path.unlink(missing_ok=True)
            for relative in ("lib/core/tooling", "test/tooling"):
                directory = self.app / relative
                if directory.exists() and not any(directory.iterdir()):
                    directory.rmdir()

    def test_22_fstr_generates_real_unicode_placeholder_localizations(self) -> None:
        paths = [self.app / f"lib/core/l10n/app_localizations_{locale}.arb" for locale in ("fr", "en")]
        original = {path: path.read_bytes() for path in paths}
        try:
            result = run_command([
                "bash", "scripts/fstr.sh", "toolingProbeGreeting",
                "Bonjour {name}, café !", "Hello {name}, café!",
            ], cwd=self.app, timeout=SLOW_TIMEOUT)
            self.assertEqual(result.returncode, 0, msg=fmt(result))
            for path, expected in zip(paths, ("Bonjour {name}, café !", "Hello {name}, café!")):
                self.assertEqual(json.loads(path.read_text())["toolingProbeGreeting"], expected)
            generated = self.app / "lib/core/l10n/generated/app_localizations.dart"
            self.assertIn("toolingProbeGreeting", generated.read_text())
        finally:
            for path, content in original.items():
                path.write_bytes(content)
            result = run_command(["flutter", "gen-l10n"], cwd=self.app, timeout=SLOW_TIMEOUT)
            self.assertEqual(result.returncode, 0, msg=fmt(result))

    def test_30_fgen_generates_lean_feature_with_normalized_name(self) -> None:
        """Lean default: no service, no DTO; one flow test is the feature's test."""
        result = run_fgen("mySecondFeature", cwd=self.app, timeout=SLOW_TIMEOUT)
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        feature = "lib/features/my_second_feature"
        tests = "test/features/my_second_feature"
        for relative in [
            f"{feature}/my_second_feature.dart",
            f"{feature}/domain/models/my_second_feature.dart",
            f"{feature}/domain/repositories/my_second_feature_repository.dart",
            f"{feature}/data/datasources/my_second_feature_remote_datasource.dart",
            f"{feature}/data/repositories/my_second_feature_repository_impl.dart",
            f"{feature}/presentation/bloc/my_second_feature_cubit.dart",
            f"{feature}/presentation/bloc/my_second_feature_state.dart",
            f"{feature}/presentation/screens/my_second_feature_screen.dart",
            f"{tests}/my_second_feature_flow_test.dart",
        ]:
            self.assertTrue((self.app / relative).exists(), msg=relative)
        # One generated test file: the flow test (success, timeout → localized
        # network failure, retry). No per-layer re-tests of the same paths.
        self.assertEqual(
            sorted(p.relative_to(self.app).as_posix() for p in (self.app / tests).rglob("*_test.dart")),
            [f"{tests}/my_second_feature_flow_test.dart"],
        )
        # Lean layout: the optional layers are absent.
        for relative in [
            f"{feature}/domain/services/my_second_feature_service.dart",
            f"{feature}/data/models/my_second_feature_dto.dart",
            f"{tests}/domain/services/my_second_feature_service_test.dart",
            f"{tests}/data/models/my_second_feature_dto_test.dart",
        ]:
            self.assertFalse((self.app / relative).exists(), msg=relative)
        # The cubit depends on the repository interface, not a service.
        cubit = (self.app / f"{feature}/presentation/bloc/my_second_feature_cubit.dart").read_text()
        self.assertIn("IMySecondFeatureRepository", cubit)
        self.assertNotIn("Service", cubit)
        # The lean domain model carries no JSON serialization.
        model = (self.app / f"{feature}/domain/models/my_second_feature.dart").read_text()
        self.assertNotIn("fromJson", model)
        # The screen is a single widget (no Screen→View forwarding pair).
        screen = (self.app / f"{feature}/presentation/screens/my_second_feature_screen.dart").read_text()
        self.assertIn("class MySecondFeatureScreen", screen)
        self.assertNotIn("View(", screen)
        # Localization keys were added through fstr (collision-checked).
        arb = (self.app / "lib/core/l10n/app_localizations_en.arb").read_text()
        self.assertIn("mySecondFeatureTitle", arb)
        self.assertIn("mySecondFeatureData", arb)
        # The printed wiring instructions include the unregistered-scaffold caveat.
        # fgen wires the module itself: DI, router, route constant, DI test.
        self.assertIn("Wired:", result.stdout)
        for wired, needle in (
            ("lib/core/di/service_locator.dart", "registerMySecondFeatureFeature(getIt);"),
            ("lib/core/router/app_router.dart", "...mySecondFeatureRoutes(getIt),"),
            ("lib/core/router/route_constants.dart", "mySecondFeature = '/my_second_feature';"),
            ("test/core/di/service_locator_test.dart", "isA<MySecondFeatureRepository>()"),
        ):
            self.assertIn(needle, (self.app / wired).read_text(), msg=wired)
        self.assertTrue((self.app / f"{feature}/my_second_feature_module.dart").exists())
        self.assertTrue((self.app / f"{tests}/my_second_feature_flow_test.dart").exists())
        flow_test = (self.app / f"{tests}/my_second_feature_flow_test.dart").read_text()
        self.assertIn("package:smoke_app/", flow_test)
        self.assertIn("TimeoutException", flow_test)
        self.assertIn("failureNetwork", flow_test)

    def test_31_fgen_full_variant_generates_service_and_dto(self) -> None:
        """--with-service --with-dto: optional layers plus their tests."""
        result = run_fgen(
            "myThirdFeature",
            cwd=self.app,
            timeout=SLOW_TIMEOUT,
            flags=["--with-service", "--with-dto"],
        )
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        feature = "lib/features/my_third_feature"
        tests = "test/features/my_third_feature"
        for relative in [
            f"{feature}/domain/services/my_third_feature_service.dart",
            f"{feature}/data/models/my_third_feature_dto.dart",
        ]:
            self.assertTrue((self.app / relative).exists(), msg=relative)
        # Flow test plus the DTO mapping test (real logic); no forwarding
        # service test, no per-layer re-tests.
        self.assertEqual(
            sorted(p.relative_to(self.app).as_posix() for p in (self.app / tests).rglob("*_test.dart")),
            [f"{tests}/data/models/my_third_feature_dto_test.dart",
             f"{tests}/my_third_feature_flow_test.dart"],
        )
        service = (self.app / f"{feature}/domain/services/my_third_feature_service.dart").read_text()
        self.assertIn("PLACEHOLDER", service)
        # The full cubit depends on the service seam.
        cubit = (self.app / f"{feature}/presentation/bloc/my_third_feature_cubit.dart").read_text()
        self.assertIn("MyThirdFeatureService", cubit)
        # The generated module registers the service for this combination.
        module = (self.app / "lib/features/my_third_feature/my_third_feature_module.dart").read_text()
        self.assertIn("registerLazySingleton<MyThirdFeatureService>", module)

    def test_31b_fgen_dto_only_variant(self) -> None:
        """--with-dto alone: transport layer without the service seam."""
        result = run_fgen(
            "fourthFeature",
            cwd=self.app,
            timeout=SLOW_TIMEOUT,
            flags=["--with-dto"],
        )
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        feature = "lib/features/fourth_feature"
        tests = "test/features/fourth_feature"
        for relative in [
            f"{feature}/data/models/fourth_feature_dto.dart",
            f"{tests}/data/models/fourth_feature_dto_test.dart",
            f"{tests}/fourth_feature_flow_test.dart",
        ]:
            self.assertTrue((self.app / relative).exists(), msg=relative)
        for relative in [
            f"{feature}/domain/services/fourth_feature_service.dart",
            f"{tests}/data/repositories/fourth_feature_repository_impl_test.dart",
        ]:
            self.assertFalse((self.app / relative).exists(), msg=relative)
        # No service seam: the cubit still depends on the repository interface.
        cubit = (self.app / f"{feature}/presentation/bloc/fourth_feature_cubit.dart").read_text()
        self.assertIn("IFourthFeatureRepository", cubit)
        self.assertNotIn("FourthFeatureService", cubit)
        # The data source returns the transport DTO, not the domain model.
        datasource = (
            self.app / f"{feature}/data/datasources/fourth_feature_remote_datasource.dart"
        ).read_text()
        self.assertIn("FourthFeatureDto", datasource)
        # The printed DI instructions match this combination (no service).
        module = (self.app / "lib/features/fourth_feature/fourth_feature_module.dart").read_text()
        self.assertIn("registerFactory<FourthFeatureCubit>", module)
        self.assertIn("getIt<IFourthFeatureRepository>()", module)
        self.assertNotIn("FourthFeatureService>", module)

    def test_31c_fgen_service_only_variant(self) -> None:
        """--with-service alone: coordination seam without a transport layer."""
        result = run_fgen(
            "fifthFeature",
            cwd=self.app,
            timeout=SLOW_TIMEOUT,
            flags=["--with-service"],
        )
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        feature = "lib/features/fifth_feature"
        tests = "test/features/fifth_feature"
        for relative in [
            f"{feature}/domain/services/fifth_feature_service.dart",
            f"{tests}/fifth_feature_flow_test.dart",
        ]:
            self.assertTrue((self.app / relative).exists(), msg=relative)
        for relative in [
            f"{feature}/data/models/fifth_feature_dto.dart",
            f"{tests}/data/models/fifth_feature_dto_test.dart",
            # A placeholder service only forwards: no forwarding test.
            f"{tests}/domain/services/fifth_feature_service_test.dart",
        ]:
            self.assertFalse((self.app / relative).exists(), msg=relative)
        # The cubit depends on the service seam for this combination.
        cubit = (self.app / f"{feature}/presentation/bloc/fifth_feature_cubit.dart").read_text()
        self.assertIn("FifthFeatureService", cubit)
        # The lean domain model carries no JSON serialization.
        model = (self.app / f"{feature}/domain/models/fifth_feature.dart").read_text()
        self.assertNotIn("fromJson", model)
        # The printed DI instructions register the service and use it for the cubit.
        module = (self.app / "lib/features/fifth_feature/fifth_feature_module.dart").read_text()
        self.assertIn("registerLazySingleton<FifthFeatureService>", module)
        self.assertIn("FifthFeatureCubit(getIt<FifthFeatureService>())", module)
        self.assertNotIn(
            "FifthFeatureCubit(getIt<IFifthFeatureRepository>())", module
        )

    def test_32_app_with_generated_features_passes_fverify(self) -> None:
        self._prepare_app(self.app)
        result = run_command(["bash", "scripts/fverify.sh"], cwd=self.app, timeout=SLOW_TIMEOUT)
        self.assertEqual(result.returncode, 0, msg=fmt(result))

    def test_40_fgen_rerun_preserves_edits_and_exits_nonzero(self) -> None:
        cubit = self.app / "lib/features/my_second_feature/presentation/bloc/my_second_feature_cubit.dart"
        flow_test = self.app / "test/features/my_second_feature/my_second_feature_flow_test.dart"
        state_file = self.app / "lib/features/my_second_feature/presentation/bloc/my_second_feature_state.dart"
        cubit_before = cubit.read_bytes()
        state_before = state_file.read_bytes()
        cubit.write_text(cubit.read_text() + "\n// user customization\n")
        flow_test.write_text(flow_test.read_text() + "\n// test customization\n")

        result = run_fgen("mySecondFeature", cwd=self.app, timeout=SLOW_TIMEOUT)
        self.assertNotEqual(result.returncode, 0, msg=fmt(result))
        self.assertIn("already exists", result.stderr)
        self.assertIn("// user customization", cubit.read_text())
        self.assertIn("// test customization", flow_test.read_text())
        self.assertEqual(state_file.read_bytes(), state_before)
        # The pre-edit generated content is still recognizable (not regenerated).
        self.assertIn("class MySecondFeatureCubit", cubit_before.decode())

    def test_41_fgen_refuses_names_clashing_with_imported_types(self) -> None:
        """`image` (material_ui), `failure` (core) and `string` (dart:core) would
        generate classes that do not compile: refused before anything is written."""
        wiring = [
            self.app / "lib/core/di/service_locator.dart",
            self.app / "lib/core/router/app_router.dart",
            self.app / "lib/core/router/route_constants.dart",
        ]
        before = [path.read_bytes() for path in wiring]
        for name, clash in (("image", "Image"), ("failure", "Failure"), ("string", "String")):
            with self.subTest(name=name):
                result = run_fgen(name, cwd=self.app, timeout=SLOW_TIMEOUT)
                self.assertNotEqual(result.returncode, 0, msg=fmt(result))
                self.assertIn(clash, result.stderr)
                self.assertFalse((self.app / "lib" / "features" / name).exists())
                self.assertFalse((self.app / "test" / "features" / name).exists())
        self.assertEqual([path.read_bytes() for path in wiring], before)
        self.assertEqual(list((self.app / "lib").glob("fgen_name_probe_*.dart")), [])

    # -- Full-workflow step 3: apply the printed DI/route wiring, prove it -------

    def test_50_wired_feature_resolves_and_renders_through_real_router(self) -> None:
        """fgen's automatic wiring produces a WORKING feature: it resolves
        through the real service locator and renders through the real router
        (not just the feature-local flow test)."""
        app = self.app
        # Harness-owned navigation fixture: real DI + real router + real screen.
        (app / "test/features/my_second_feature/presentation").mkdir(
            parents=True, exist_ok=True
        )
        (app / "test/features/my_second_feature/presentation/wiring_test.dart").write_text(
            "import 'package:flutter_test/flutter_test.dart';\n"
            "import 'package:go_router/go_router.dart';\n"
            "import 'package:smoke_app/app.dart';\n"
            "import 'package:smoke_app/core/di/service_locator.dart';\n"
            "import 'package:smoke_app/core/router/app_router.dart';\n"
            "\n"
            "/// Harness fixture: the wired feature must resolve through the real\n"
            "/// service locator and render through the real router. A scaffold that\n"
            "/// only passes its own unit tests is not a routed feature.\n"
            "void main() {\n"
            "  testWidgets('wired route resolves real DI and renders', (\n"
            "    WidgetTester tester,\n"
            "  ) async {\n"
            "    await setupServiceLocator();\n"
            "    addTearDown(getIt.reset);\n"
            "\n"
            "    final GoRouter router = AppRouter.createRouter();\n"
            "    addTearDown(router.dispose);\n"
            "    router.go('/my_second_feature');\n"
            "\n"
            "    await tester.pumpWidget(MyApp(router: router));\n"
            "    await tester.pump();\n"
            "    await tester.pump(const Duration(milliseconds: 100));\n"
            "\n"
            "    expect(find.text('Data: Placeholder'), findsOneWidget);\n"
            "  });\n"
            "}\n"
        )
        # The harness-written files must themselves be format-compliant —
        # checked here for a crisp message before the full gate runs.
        fmt_check = run_command(
            [
                "dart",
                "format",
                "--output=none",
                "--set-exit-if-changed",
                "lib/core/di/service_locator.dart",
                "lib/core/router/route_constants.dart",
                "lib/core/router/app_router.dart",
                "test/core/di/service_locator_test.dart",
                "test/features/my_second_feature/presentation/wiring_test.dart",
                "test/features/my_second_feature/my_second_feature_flow_test.dart",
            ],
            cwd=app,
        )
        self.assertEqual(fmt_check.returncode, 0, msg=fmt(fmt_check))
        result = run_command(
            ["flutter", "test", "test/features/my_second_feature/presentation/wiring_test.dart"],
            cwd=app,
            timeout=SLOW_TIMEOUT,
        )
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        # The DI smoke test and the generated flow test prove the rest.
        result = run_command(
            ["flutter", "test", "test/core/di/service_locator_test.dart",
             "test/features/my_second_feature/my_second_feature_flow_test.dart"],
            cwd=app,
            timeout=SLOW_TIMEOUT,
        )
        self.assertEqual(result.returncode, 0, msg=fmt(result))

    def test_51_wired_app_passes_fverify(self) -> None:
        self._prepare_app(self.app)
        result = run_command(["bash", "scripts/fverify.sh"], cwd=self.app, timeout=SLOW_TIMEOUT)
        self.assertEqual(result.returncode, 0, msg=fmt(result))

    # -- Full-workflow step 5: counter removal on an otherwise-fresh app --------

    def test_60_counter_removed_from_fresh_app_and_repeated_removal_is_harmless(self) -> None:
        """A SECOND, otherwise-fresh generated app; remove_counter twice."""
        print("\n[e2e] generating second (fresh) app for counter removal...")
        fresh = self.parent / "smoke_app_fresh"
        create = run_generator(
            ["--no-open", "--org=com.example.forge", "--platforms=linux", "smoke_app_fresh"],
            cwd=self.parent,
            timeout=SLOW_TIMEOUT,
        )
        self.assertEqual(create.returncode, 0, msg=fmt(create))
        self.assertTrue((fresh / "lib/features/counter").is_dir())

        # First removal: succeeds and leaves a fully verified app.
        first = run_command(["bash", "remove_counter.sh"], cwd=fresh, timeout=SLOW_TIMEOUT)
        self.assertEqual(first.returncode, 0, msg=fmt(first))
        self.assertFalse((fresh / "lib/features/counter").exists())
        self.assertFalse((fresh / "test/features/counter").exists())
        self._prepare_app(fresh)
        verify1 = run_command(["bash", "scripts/fverify.sh"], cwd=fresh, timeout=SLOW_TIMEOUT)
        self.assertEqual(verify1.returncode, 0, msg=fmt(verify1))
        locator = (fresh / "lib/core/di/service_locator.dart").read_text()
        self.assertNotIn("ounter", locator)

        # Repeated removal: harmless no-op that does not damage the app.
        snapshot = tree_snapshot(fresh / "lib")
        second = run_command(["bash", "remove_counter.sh"], cwd=fresh, timeout=SLOW_TIMEOUT)
        self.assertEqual(second.returncode, 0, msg=fmt(second))
        self.assertEqual(tree_snapshot(fresh / "lib"), snapshot)
        self._prepare_app(fresh)
        verify2 = run_command(["bash", "scripts/fverify.sh"], cwd=fresh, timeout=SLOW_TIMEOUT)
        self.assertEqual(verify2.returncode, 0, msg=fmt(verify2))

    # -- Full-workflow step 7: skill synchronization, check-only ----------------

    def _prepare_app(self, app: Path) -> None:
        for command in (["dart", "fix", "--apply"], ["dart", "format", "."]):
            result = run_command(command, cwd=app, timeout=SLOW_TIMEOUT)
            self.assertEqual(result.returncode, 0, msg=fmt(result))

    def test_70_skill_synchronization_check_only(self) -> None:
        result = run_command(
            ["bash", str(REPO_ROOT / "scripts" / "sync_skills.sh"), "--check"],
            cwd=REPO_ROOT,
        )
        self.assertEqual(result.returncode, 0, msg=fmt(result))

    # -- Full-workflow step 8: record versions, revision, resolved lockfile ------

    def test_80_records_smoke_metadata(self) -> None:
        flutter = run_command(["flutter", "--version"], cwd=self.app)
        dart_path = shutil.which("dart") or "dart"
        dart = run_command([dart_path, "--version"], cwd=self.app)
        revision = run_command(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT)
        dirty = run_command(["git", "status", "--porcelain"], cwd=REPO_ROOT)
        lines = [
            "FlutterForge full smoke — recorded metadata",
            f"flutter --version:\n{flutter.stdout.strip()}",
            f"dart --version: {(dart.stderr or dart.stdout).strip()}",
            f"template git revision: {revision.stdout.strip()}",
            f"template working tree dirty: {bool(dirty.stdout.strip())}",
        ]
        report = "\n".join(lines) + "\n"
        print("\n[e2e] smoke metadata:\n" + report)
        artifacts = os.environ.get("FORGE_ARTIFACTS_DIR")
        if artifacts:
            artifacts_dir = Path(artifacts)
            artifacts_dir.mkdir(parents=True, exist_ok=True)
            (artifacts_dir / "smoke-metadata.txt").write_text(report)
            shutil.copy2(self.app / "pubspec.lock", artifacts_dir / "smoke_app.pubspec.lock")
            fresh = self.parent / "smoke_app_fresh"
            if (fresh / "pubspec.lock").exists():
                shutil.copy2(
                    fresh / "pubspec.lock", artifacts_dir / "smoke_app_fresh.pubspec.lock"
                )


if __name__ == "__main__":
    unittest.main(verbosity=1)
