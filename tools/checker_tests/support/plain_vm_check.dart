/// Runs the checker under a plain Dart VM (no flutter_tester): exits 0 when
/// the valid base fixture app is analyzed cleanly, 1 otherwise. Used by the
/// "plain Dart VM" self-test to prove the SDK path is resolved there too.
library;

import 'dart:io';

import '../../support/architecture_checker.dart';
import 'fixture_app.dart';

Future<void> main() async {
  final CheckerResult result = await ArchitectureChecker.checkSources(
    fixtureApp,
  );
  if (!result.isClean) {
    stderr.writeln('${result.violations} ${result.errors}');
    exit(1);
  }
}
