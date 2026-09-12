import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture boundary tests — the layering and coupling rules from the
/// flutter-architecture skill, enforced as tests instead of prose.
///
/// Rules enforced:
/// 1. No feature imports another feature's `data/` or `presentation/` internals.
/// 2. Presentation files never import their own feature's `data/` layer.
/// 3. `domain/` and `data/` files never import `presentation/`.
/// 4. No class in `lib/` stores a cubit/bloc as a field (no cubit-to-cubit or
///    service-to-cubit coupling).
/// 5. `core/` stays infrastructure-only: only the composition roots
///    (`service_locator.dart`, `app_router.dart`) may import features.
///
/// When you add a rule to the flutter-architecture skill, add it here too.
void main() {
  final Directory libDir = Directory('lib');
  final List<File> dartFiles =
      libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .where((File file) => !_isGenerated(file.path))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  test('lib/ contains dart files to check', () {
    expect(dartFiles, isNotEmpty);
  });

  group('architecture boundaries', () {
    for (final File file in dartFiles) {
      test('${file.path} respects layer boundaries', () {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String? import = _importTarget(lines[i], file);
          if (import == null) continue;

          final String? violation = _boundaryViolation(file.path, import);
          expect(
            violation,
            isNull,
            reason: '${file.path}:${i + 1} imports $import',
          );
        }
      });

      test('${file.path} stores no cubit/bloc as a field', () {
        if (_isCompositionRoot(file.path)) return;

        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          expect(
            _cubitFieldRegExp.hasMatch(lines[i]),
            isFalse,
            reason:
                '${file.path}:${i + 1} declares a cubit/bloc field — '
                'extract a domain service instead (flutter-architecture skill)',
          );
        }
      });
    }
  });
}

const List<String> _compositionRoots = <String>[
  'lib/core/di/service_locator.dart',
  'lib/core/router/app_router.dart',
];

final RegExp _importRegExp = RegExp(
  r'''^(?:import|export|part)\s+['"]([^'"]+)['"]''',
);

/// `final SomeXxxCubit _cubit;` / `final SomeXxxBloc bloc;` — a stored
/// cubit/bloc dependency. Does not match `extends Cubit<...>` declarations
/// or `getIt<...>()` resolutions, which declare no field.
final RegExp _cubitFieldRegExp = RegExp(
  r'^\s*final\s+[A-Z]\w*(Cubit|Bloc)\b\s+_?\w+\s*[;=]',
);

final RegExp _featurePathRegExp = RegExp(r'^lib/features/([^/]+)/(.*)$');

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.contains('l10n/generated');

bool _isCompositionRoot(String path) =>
    _compositionRoots.contains(_normalizePath(path));

String _normalizePath(String path) => path.replaceAll('\\', '/');

String? _importTarget(String line, File importingFile) {
  final Match? match = _importRegExp.firstMatch(line.trim());
  if (match == null) return null;

  final String uri = match.group(1)!;
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return null;

  final List<String> fileParts = importingFile.path.split('/')..removeLast();
  final String target = _normalizeSegments(<String>[
    ...fileParts,
    ...uri.split('/'),
  ]);
  return target.startsWith('lib/') ? target : null;
}

String _normalizeSegments(List<String> parts) {
  final List<String> stack = <String>[];
  for (final String part in parts) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (stack.isNotEmpty) stack.removeLast();
    } else {
      stack.add(part);
    }
  }
  return stack.join('/');
}

String? _boundaryViolation(String importerPath, String importPath) {
  final String importer = _normalizePath(importerPath);
  final String target = _normalizePath(importPath);
  final bool isCompositionRoot = _isCompositionRoot(importer);

  // Rule 1: cross-feature imports into internals (composition roots are the
  // sanctioned place to wire everything, so they are exempt)
  final RegExpMatch? targetFeature = _featurePathRegExp.firstMatch(target);
  if (targetFeature != null && !isCompositionRoot) {
    final RegExpMatch? importerFeature = _featurePathRegExp.firstMatch(
      importer,
    );
    final String targetLayer = targetFeature.group(2)!.split('/').first;
    final bool crossFeature =
        importerFeature == null ||
        importerFeature.group(1)! != targetFeature.group(1)!;

    if (crossFeature &&
        (targetLayer == 'data' || targetLayer == 'presentation')) {
      return 'imports feature internals: $target';
    }
  }

  // Rule 2: presentation imports data directly
  if (importer.contains('/presentation/') && target.contains('/data/')) {
    return 'presentation imports data directly: $target';
  }

  // Rule 3: lower layers import presentation
  if ((importer.contains('/domain/') || importer.contains('/data/')) &&
      target.contains('/presentation/')) {
    return 'lower layer imports presentation: $target';
  }

  // Rule 4: core imports features outside composition roots
  if (importer.startsWith('lib/core/') &&
      target.startsWith('lib/features/') &&
      !_isCompositionRoot(importer)) {
    return 'core imports feature outside composition roots: $target';
  }

  return null;
}
