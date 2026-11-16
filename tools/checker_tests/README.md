# Architecture checker self-tests

Regression fixtures for `test/support/architecture_checker.dart`: positive and
negative fixtures for every rule the checker enforces.

They test the checker, not an app, so they are **not shipped** into generated
apps (which keep only `test/architecture_test.dart`, the gate itself). The full
template suite (`./scripts/verify_template.sh --full`) copies this directory
into a generated app as `test/checker_selftest/` and runs it there; the import
paths assume that location.

When you add a rule to the checker, add its negative fixture here.
