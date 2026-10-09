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


def run_generator(args: list[str], cwd: Path, env: dict | None = None, timeout: int = COMMAND_TIMEOUT) -> subprocess.CompletedProcess:
    command = [REAL_DART, str(GENERATOR), *args]
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
    """Sorted (relative path, content) snapshot of a tree, symlink-safe."""
    entries: list[tuple[str, bytes]] = []
    for path in sorted(root.rglob("*")):
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
                "import 'package:flutter/material.dart';\n"
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
        ):
            self.assertIn(f"{package}:", joined)


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

    def test_30_fgen_generates_lean_feature_with_normalized_name(self) -> None:
        """Lean default: no service, no DTO, but repository failure tests exist."""
        result = run_fgen("mySecondFeature", cwd=self.app, timeout=SLOW_TIMEOUT)
        self.assertEqual(result.returncode, 0, msg=fmt(result))
        feature = "lib/features/my_second_feature"
        tests = "test/features/my_second_feature"
        for relative in [
            f"{feature}/domain/models/my_second_feature.dart",
            f"{feature}/domain/repositories/my_second_feature_repository.dart",
            f"{feature}/data/datasources/my_second_feature_remote_datasource.dart",
            f"{feature}/data/repositories/my_second_feature_repository_impl.dart",
            f"{feature}/presentation/bloc/my_second_feature_cubit.dart",
            f"{feature}/presentation/bloc/my_second_feature_state.dart",
            f"{feature}/presentation/screens/my_second_feature_screen.dart",
            f"{tests}/data/repositories/my_second_feature_repository_impl_test.dart",
            f"{tests}/presentation/bloc/my_second_feature_cubit_test.dart",
            f"{tests}/presentation/screens/my_second_feature_screen_test.dart",
        ]:
            self.assertTrue((self.app / relative).exists(), msg=relative)
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
        self.assertIn("NOT a routed feature", result.stdout)
        cubit_test = (
            self.app / f"{tests}/presentation/bloc/my_second_feature_cubit_test.dart"
        ).read_text()
        self.assertIn("package:smoke_app/", cubit_test)

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
            f"{tests}/domain/services/my_third_feature_service_test.dart",
            f"{tests}/data/models/my_third_feature_dto_test.dart",
            f"{tests}/data/repositories/my_third_feature_repository_impl_test.dart",
        ]:
            self.assertTrue((self.app / relative).exists(), msg=relative)
        service = (self.app / f"{feature}/domain/services/my_third_feature_service.dart").read_text()
        self.assertIn("PLACEHOLDER", service)
        # The full cubit depends on the service seam.
        cubit = (self.app / f"{feature}/presentation/bloc/my_third_feature_cubit.dart").read_text()
        self.assertIn("MyThirdFeatureService", cubit)
        # The printed DI instructions register the service for this combination.
        self.assertIn("registerLazySingleton<MyThirdFeatureService>", result.stdout)

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
            f"{tests}/data/repositories/fourth_feature_repository_impl_test.dart",
        ]:
            self.assertTrue((self.app / relative).exists(), msg=relative)
        for relative in [
            f"{feature}/domain/services/fourth_feature_service.dart",
            f"{tests}/domain/services/fourth_feature_service_test.dart",
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
        self.assertIn("registerFactory<FourthFeatureCubit>", result.stdout)
        self.assertIn("getIt<IFourthFeatureRepository>()", result.stdout)
        self.assertNotIn("FourthFeatureService>", result.stdout)

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
            f"{tests}/domain/services/fifth_feature_service_test.dart",
        ]:
            self.assertTrue((self.app / relative).exists(), msg=relative)
        for relative in [
            f"{feature}/data/models/fifth_feature_dto.dart",
            f"{tests}/data/models/fifth_feature_dto_test.dart",
        ]:
            self.assertFalse((self.app / relative).exists(), msg=relative)
        # The cubit depends on the service seam for this combination.
        cubit = (self.app / f"{feature}/presentation/bloc/fifth_feature_cubit.dart").read_text()
        self.assertIn("FifthFeatureService", cubit)
        # The lean domain model carries no JSON serialization.
        model = (self.app / f"{feature}/domain/models/fifth_feature.dart").read_text()
        self.assertNotIn("fromJson", model)
        # The printed DI instructions register the service and use it for the cubit.
        self.assertIn("registerLazySingleton<FifthFeatureService>", result.stdout)
        self.assertIn("FifthFeatureCubit(getIt<FifthFeatureService>())", result.stdout)
        self.assertNotIn(
            "FifthFeatureCubit(getIt<IFifthFeatureRepository>())", result.stdout
        )

    def test_32_app_with_generated_features_passes_fverify(self) -> None:
        result = run_command(["bash", "scripts/fverify.sh"], cwd=self.app, timeout=SLOW_TIMEOUT)
        self.assertEqual(result.returncode, 0, msg=fmt(result))

    def test_40_fgen_rerun_preserves_edits_and_exits_nonzero(self) -> None:
        cubit = self.app / "lib/features/my_second_feature/presentation/bloc/my_second_feature_cubit.dart"
        cubit_test = self.app / "test/features/my_second_feature/presentation/bloc/my_second_feature_cubit_test.dart"
        state_file = self.app / "lib/features/my_second_feature/presentation/bloc/my_second_feature_state.dart"
        cubit_before = cubit.read_bytes()
        state_before = state_file.read_bytes()
        cubit.write_text(cubit.read_text() + "\n// user customization\n")
        cubit_test.write_text(cubit_test.read_text() + "\n// test customization\n")

        result = run_fgen("mySecondFeature", cwd=self.app, timeout=SLOW_TIMEOUT)
        self.assertNotEqual(result.returncode, 0, msg=fmt(result))
        self.assertIn("already exists", result.stderr)
        self.assertIn("// user customization", cubit.read_text())
        self.assertIn("// test customization", cubit_test.read_text())
        self.assertEqual(state_file.read_bytes(), state_before)
        # The pre-edit generated content is still recognizable (not regenerated).
        self.assertIn("class MySecondFeatureCubit", cubit_before.decode())

    # -- Full-workflow step 3: apply the printed DI/route wiring, prove it -------

    def _patch(
        self, app: Path, relative: str, anchor: str, insertion: str, *, before: bool = False
    ) -> None:
        """Inserts `insertion` after (or before) `anchor` in a file (harness
        fixture only — the production CLI stays free of patching logic; this
        mirrors exactly what the fgen 'Next steps' instructions tell the
        developer to type)."""
        path = app / relative
        content = path.read_text()
        self.assertIn(anchor, content, msg=f"anchor missing in {relative}")
        self.assertEqual(content.count(anchor), 1, msg=f"anchor not unique in {relative}")
        replacement = insertion + anchor if before else anchor + insertion
        path.write_text(content.replace(anchor, replacement, 1))

    def test_50_wired_feature_resolves_and_renders_through_real_router(self) -> None:
        """The documented DI/route instructions produce a WORKING feature.

        Applies exactly the registrations/route fgen printed for the lean
        `my_second_feature` (fixture patch, see _patch), adds the DI smoke-test
        expectations the instructions call for, and proves resolution +
        rendering by navigating the real router with the real service locator.
        """
        app = self.app
        # 1. service_locator.dart: imports + the three printed registrations.
        self._patch(
            app,
            "lib/core/di/service_locator.dart",
            "import '../../features/home/presentation/bloc/home_cubit.dart';\n",
            "import '../../features/my_second_feature/data/datasources"
            "/my_second_feature_remote_datasource.dart';\n"
            "import '../../features/my_second_feature/data/repositories"
            "/my_second_feature_repository_impl.dart';\n"
            "import '../../features/my_second_feature/domain/repositories"
            "/my_second_feature_repository.dart';\n"
            "import '../../features/my_second_feature/presentation/bloc"
            "/my_second_feature_cubit.dart';\n",
        )
        self._patch(
            app,
            "lib/core/di/service_locator.dart",
            "  getIt.registerFactory<HomeCubit>(() => HomeCubit(getIt<IHomeRepository>()));\n",
            "\n  // --- my_second_feature (wired per the fgen instructions) ---\n"
            "  getIt.registerLazySingleton<IMySecondFeatureRemoteDataSource>(\n"
            "    () => MySecondFeatureRemoteDataSource(),\n"
            "  );\n"
            "  getIt.registerLazySingleton<IMySecondFeatureRepository>(\n"
            "    () => MySecondFeatureRepository(getIt<IMySecondFeatureRemoteDataSource>()),\n"
            "  );\n"
            "  getIt.registerFactory<MySecondFeatureCubit>(\n"
            "    () => MySecondFeatureCubit(getIt<IMySecondFeatureRepository>()),\n"
            "  );\n",
        )
        # 2. route_constants.dart: the printed constant.
        self._patch(
            app,
            "lib/core/router/route_constants.dart",
            "  static const String counter = '/counter';\n",
            "  static const String mySecondFeature = '/my_second_feature';\n",
        )
        # 3. app_router.dart: imports + the printed GoRoute (route provides cubit).
        self._patch(
            app,
            "lib/core/router/app_router.dart",
            "import '../../features/home/presentation/screens/home_screen.dart';\n",
            "import '../../features/my_second_feature/presentation/bloc"
            "/my_second_feature_cubit.dart';\n"
            "import '../../features/my_second_feature/presentation/screens"
            "/my_second_feature_screen.dart';\n",
        )
        self._patch(
            app,
            "lib/core/router/app_router.dart",
            "    ],\n    errorBuilder:",
            "      GoRoute(\n"
            "        path: Routes.mySecondFeature,\n"
            "        name: 'MySecondFeature',\n"
            "        builder: (BuildContext context, GoRouterState state) {\n"
            "          return BlocProvider<MySecondFeatureCubit>(\n"
            "            create: (_) => getIt<MySecondFeatureCubit>()..loadData(),\n"
            "            child: const MySecondFeatureScreen(),\n"
            "          );\n"
            "        },\n"
            "      ),\n",
            before=True,
        )
        # 4. service_locator_test.dart: the expectations step 3 asks for.
        self._patch(
            app,
            "test/core/di/service_locator_test.dart",
            "import 'package:smoke_app/features/home/presentation/bloc/home_cubit.dart';\n",
            "import 'package:smoke_app/features/my_second_feature/data/datasources"
            "/my_second_feature_remote_datasource.dart';\n"
            "import 'package:smoke_app/features/my_second_feature/data/repositories"
            "/my_second_feature_repository_impl.dart';\n"
            "import 'package:smoke_app/features/my_second_feature/domain/repositories"
            "/my_second_feature_repository.dart';\n"
            "import 'package:smoke_app/features/my_second_feature/presentation/bloc"
            "/my_second_feature_cubit.dart';\n",
        )
        self._patch(
            app,
            "test/core/di/service_locator_test.dart",
            "    expect(getIt<CounterService>(), isA<CounterService>());\n",
            "\n    expect(\n"
            "      getIt<IMySecondFeatureRemoteDataSource>(),\n"
            "      isA<MySecondFeatureRemoteDataSource>(),\n"
            "    );\n"
            "    expect(\n"
            "      getIt<IMySecondFeatureRepository>(),\n"
            "      isA<MySecondFeatureRepository>(),\n"
            "    );\n",
        )
        self._patch(
            app,
            "test/core/di/service_locator_test.dart",
            "    addTearDown(homeCubitSecond.close);\n",
            "    final MySecondFeatureCubit featureCubitFirst =\n"
            "        getIt<MySecondFeatureCubit>();\n"
            "    final MySecondFeatureCubit featureCubitSecond =\n"
            "        getIt<MySecondFeatureCubit>();\n"
            "    addTearDown(featureCubitFirst.close);\n"
            "    addTearDown(featureCubitSecond.close);\n",
        )
        self._patch(
            app,
            "test/core/di/service_locator_test.dart",
            "    expect(identical(homeCubitFirst, homeCubitSecond), isFalse);\n",
            "    expect(identical(featureCubitFirst, featureCubitSecond), isFalse);\n",
        )
        # 5. Harness-owned navigation fixture: real DI + real router + real screen.
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
        # The DI smoke test also proves the new registrations resolve.
        result = run_command(
            ["flutter", "test", "test/core/di/service_locator_test.dart"],
            cwd=app,
            timeout=SLOW_TIMEOUT,
        )
        self.assertEqual(result.returncode, 0, msg=fmt(result))

    def test_51_wired_app_passes_fverify(self) -> None:
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
        verify1 = run_command(["bash", "scripts/fverify.sh"], cwd=fresh, timeout=SLOW_TIMEOUT)
        self.assertEqual(verify1.returncode, 0, msg=fmt(verify1))
        locator = (fresh / "lib/core/di/service_locator.dart").read_text()
        self.assertNotIn("ounter", locator)

        # Repeated removal: harmless no-op that does not damage the app.
        snapshot = tree_snapshot(fresh / "lib")
        second = run_command(["bash", "remove_counter.sh"], cwd=fresh, timeout=SLOW_TIMEOUT)
        self.assertEqual(second.returncode, 0, msg=fmt(second))
        self.assertEqual(tree_snapshot(fresh / "lib"), snapshot)
        verify2 = run_command(["bash", "scripts/fverify.sh"], cwd=fresh, timeout=SLOW_TIMEOUT)
        self.assertEqual(verify2.returncode, 0, msg=fmt(verify2))

    # -- Full-workflow step 7: skill synchronization, check-only ----------------

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
