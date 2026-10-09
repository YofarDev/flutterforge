/// FlutterForge project generator.
///
/// Creates a new Flutter application from this template. The generator:
///   1. Parses arguments deterministically and rejects ambiguous input.
///   2. Preflights the destination and refuses to touch anything that already
///      exists (file, empty directory, symlink — dangling or not, template
///      root). Ordinary retries are protected; concurrent writers to the same
///      destination are not supported.
///   3. Generates into a uniquely owned staging directory next to the
///      destination, verifies the app there (`scripts/fverify.sh`), then
///      publishes it under its final name.
///   4. On failure, keeps the staging directory for diagnosis. It never
///      recursively deletes a caller-supplied directory.
///
/// Usage: dart create_project.dart [options] <destination>
import 'dart:convert';
import 'dart:io';

/// Placeholder package name used in template-owned sources. It is substituted
/// only in files this generator copies from the template — never in Flutter's
/// generated metadata or platform files.
const String templatePackageNamePlaceholder = 'my_flutter_app';

/// Prefix of the staging directory created next to the destination.
const String stagingDirectoryPrefix = '.flutterforge-stage-';

/// Options that take a value, both in attached form (`--org=value`) and as a
/// separate token (`--org value`). Unknown options are forwarded to
/// `flutter create` as flags; to give an unknown option a value, use the
/// attached form (`--unknown-option=value`) so parsing stays deterministic.
const Set<String> knownValueOptions = <String>{
  '--org',
  '--project-name',
  '--description',
  '--platforms',
  '--template',
  '-t',
  '--sample',
};

/// Default organization, kept for backwards compatibility.
const String defaultOrg = 'fr.yofardev';

/// Dart reserved words and built-in identifiers rejected as package names.
const Set<String> dartReservedIdentifiers = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

/// Template-owned roots inside a generated app where the package-name
/// placeholder may be substituted. Everything else (Flutter metadata, platform
/// files, caches) is never rewritten.
const List<String> placeholderRoots = <String>[
  'lib',
  'test',
  'scripts',
  '.agents',
  '.codex',
  'AGENTS.md',
  'README.md',
  'analysis_options.yaml',
  'l10n.yaml',
];

/// Template entries the generator hard-depends on.
const List<String> requiredTemplatePaths = <String>[
  'lib',
  'test',
  'analysis_options.yaml',
  'packages_to_add.json',
  'l10n.yaml',
  'template-gitignore',
  'templates/github/workflows/flutter-ci.yml',
  ...shippedScripts,
  ...shippedScriptAssets,
];

/// The scripts explicitly shipped to generated applications, by template path
/// under `scripts/`. Copying is ALLOWLIST-BASED: an arbitrary new file added
/// to the template's `scripts/` directory does NOT automatically ship — it
/// must be added here.
///
/// Categories (see README.md "Shipped tooling"):
/// - standard app tools: `fverify`, `fgen`, `fstr`, `fl10n`;
/// - included advisory/optional tools: `fanal`, repaired `fimp`, advisory
///   `fdead`, `fcheck`, explicit `sync_skills`.
///
/// Template-maintenance tooling (`verify_template.sh`, `tools/test_template.py`)
/// and personal automation (moved to the template repository's
/// `personal_tools/` — `fbuild.sh`, `pre_script_claude.sh`) are deliberately
/// NOT shipped: generated apps must be self-contained with no template or
/// personal-tooling dependencies. The retired
/// `flutter_analyze_interceptor.py` was deleted from the template.
const List<String> shippedScripts = <String>[
  'scripts/fverify.sh',
  'scripts/fgen.sh',
  'scripts/fstr.sh',
  'scripts/fl10n.sh',
  'scripts/fanal.sh',
  'scripts/fimp.sh',
  'scripts/fdead.sh',
  'scripts/fcheck.sh',
  'scripts/sync_skills.sh',
];

/// Supporting files shipped with app scripts, also explicitly allowlisted.
const List<String> shippedScriptAssets = <String>[
  'scripts/fimp.py',
  'scripts/render_feature.py',
  'scripts/feature_templates/domain_model.dart.tpl',
  'scripts/feature_templates/repository_contract.dart.tpl',
  'scripts/feature_templates/domain_service.dart.tpl',
  'scripts/feature_templates/remote_datasource.dart.tpl',
  'scripts/feature_templates/dto.dart.tpl',
  'scripts/feature_templates/repository_impl_imports.dart.tpl',
  'scripts/feature_templates/repository_impl_dto_import.dart.tpl',
  'scripts/feature_templates/repository_impl_body.dart.tpl',
  'scripts/feature_templates/state.dart.tpl',
  'scripts/feature_templates/cubit.dart.tpl',
  'scripts/feature_templates/screen.dart.tpl',
  'scripts/feature_templates/repository_test_imports.dart.tpl',
  'scripts/feature_templates/repository_test_dto_import.dart.tpl',
  'scripts/feature_templates/repository_test_setup.dart.tpl',
  'scripts/feature_templates/repository_test_dto_result.dart.tpl',
  'scripts/feature_templates/repository_test_domain_result.dart.tpl',
  'scripts/feature_templates/repository_test_body.dart.tpl',
  'scripts/feature_templates/dto_test.dart.tpl',
  'scripts/feature_templates/service_test.dart.tpl',
  'scripts/feature_templates/cubit_test.dart.tpl',
  'scripts/feature_templates/screen_test.dart.tpl',
];

final RegExp packageNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// A fatal, user-facing error. Carries the process exit code to preserve.
class FailureException implements Exception {
  FailureException(this.message, {this.exitCode = 1});

  final String message;
  final int exitCode;
}

/// Result of parsing the command line.
class ParsedArguments {
  ParsedArguments({
    required this.destination,
    required this.org,
    required this.openInVsCode,
    required this.forwardedArguments,
    this.packageName,
    this.description,
  });

  /// Destination exactly as typed on the command line.
  final String destination;
  final String org;
  final bool openInVsCode;

  /// Explicit `--project-name`, if the caller supplied one.
  final String? packageName;

  /// Explicit `--description`, if the caller supplied one.
  final String? description;

  /// Arguments forwarded verbatim to `flutter create`.
  final List<String> forwardedArguments;
}

void printUsage() {
  stdout.writeln('Usage: dart create_project.dart [options] <destination>');
  stdout.writeln('');
  stdout.writeln(
    'Creates a new Flutter application from this template in <destination>.',
  );
  stdout.writeln(
    'The destination must not exist (the generator never overwrites).',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --org=<organization>        Organization (default: $defaultOrg).',
  );
  stdout.writeln(
    '  --project-name=<name>       Dart package name (default: final destination component).',
  );
  stdout.writeln(
    '  --description=<description> Project description (kept as supplied).',
  );
  stdout.writeln(
    '  --platforms=<platforms>     Comma-separated platforms for `flutter create`.',
  );
  stdout.writeln(
    '  --no-open                   Do not open the project in VS Code when done.',
  );
  stdout.writeln('  -h, --help                  Show this help.');
  stdout.writeln('');
  stdout.writeln(
    'Other `flutter create` options are forwarded. Options that take a value',
  );
  stdout.writeln(
    'must use the attached form (`--opt=value`) so parsing stays deterministic.',
  );
  stdout.writeln('');
  stdout.writeln(
    'Example: dart create_project.dart --org=com.mycompany --platforms=android,ios my_new_app',
  );
}

void main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    printUsage();
    return;
  }

  final String originalDirectory = Directory.current.path;
  String? stagingPath;
  String? publishedPath;

  try {
    final ParsedArguments parsed = parseArguments(args);

    final String templateRoot = resolveTemplateRoot();
    validateTemplate(templateRoot);
    validateRequiredExecutables();

    final String destination = absoluteDestination(
      parsed.destination,
      originalDirectory,
    );
    final String destinationName = finalComponent(parsed.destination);
    final String packageName = parsed.packageName ?? destinationName;
    validatePackageName(packageName);

    preflightDestination(destination, templateRoot);

    stagingPath = createStagingDirectory(destination);
    stdout.writeln(
      "🚀 Creating Flutter project '$packageName' in '$destination'...",
    );
    stdout.writeln('   Organization: ${parsed.org}');
    stdout.writeln('🏗️  Staging directory: $stagingPath');
    stdout.writeln(
      '   Generation is verified inside staging before the directory is published. '
      'This protects ordinary retries, not concurrent writers to the same destination.',
    );

    final List<String> createArguments = <String>[
      'create',
      '--org=${parsed.org}',
      '--project-name=$packageName',
      if (parsed.description != null) '--description=${parsed.description}',
      ...parsed.forwardedArguments,
      stagingPath,
    ];
    await runCommand('flutter', createArguments);

    Directory.current = stagingPath;
    await copyTemplateAssets(templateRoot);
    processPubspec(
      packageName: packageName,
      hasCustomDescription: parsed.description != null,
    );
    await addPackages(templateRoot);
    await runCommand('flutter', <String>['gen-l10n']);
    writeReadme(templateRoot, packageName);
    replacePlaceholderInTemplateCopies(packageName);

    stdout.writeln('🔧 Running build_runner for code generation...');
    await runCommand('dart', <String>[
      'run',
      'build_runner',
      'build',
      '--delete-conflicting-outputs',
    ]);

    stdout.writeln('🧪 Running fverify smoke test (analyze + tests)...');
    await runCommand('bash', <String>['scripts/fverify.sh']);

    // Recheck the final destination right before publishing.
    if (FileSystemEntity.typeSync(destination) !=
        FileSystemEntityType.notFound) {
      throw FailureException(
        'Destination "$destination" appeared while the project was being generated. '
        'Refusing to overwrite it; the verified staging directory was kept at $stagingPath.',
      );
    }
    Directory(stagingPath).renameSync(destination);
    publishedPath = destination;
    stagingPath = null;
    Directory.current = publishedPath;

    // The directory moved: refresh path-dependent metadata at the final path.
    stdout.writeln('🔁 Refreshing package resolution at the final path...');
    await runCommand('flutter', <String>['pub', 'get']);

    stdout.writeln('✅ Project setup complete! Published to: $publishedPath');

    if (parsed.openInVsCode) {
      stdout.writeln('📝 Opening project in VS Code...');
      try {
        await Process.start('code', <String>[
          '.',
        ], mode: ProcessStartMode.detached);
      } on ProcessException {
        stderr.writeln(
          "⚠️  Could not open VS Code. Make sure 'code' command is in your PATH.",
        );
      }
    }
  } on FailureException catch (failure) {
    stderr.writeln('Error: ${failure.message}');
    if (stagingPath != null) {
      stderr.writeln(
        'The staging directory was kept for diagnosis: $stagingPath',
      );
      stderr.writeln('Delete it manually once you no longer need it.');
    }
    if (publishedPath != null) {
      stderr.writeln('The generated project was kept at: $publishedPath');
    }
    exit(failure.exitCode);
  }
}

/// Parses arguments deterministically. Throws [FailureException] on ambiguous
/// or invalid input, before anything is invoked.
ParsedArguments parseArguments(List<String> args) {
  String? destination;
  String org = defaultOrg;
  String? packageName;
  String? description;
  bool openInVsCode = true;
  bool optionsEnded = false;
  final List<String> forwardedArguments = <String>[];

  void addPositional(String argument) {
    if (destination != null) {
      throw FailureException(
        'Multiple destinations given ("$destination" and "$argument"). '
        'Exactly one destination is required.',
      );
    }
    destination = argument;
  }

  int index = 0;
  while (index < args.length) {
    final String argument = args[index++];
    if (optionsEnded) {
      addPositional(argument);
      continue;
    }
    if (argument == '--') {
      optionsEnded = true;
      continue;
    }
    if (argument == '--no-open') {
      openInVsCode = false;
      continue;
    }
    if (argument.startsWith('--no-open=')) {
      throw FailureException("Option '--no-open' does not take a value.");
    }

    final int equalsIndex = argument.indexOf('=');
    final String flag = equalsIndex > 0
        ? argument.substring(0, equalsIndex)
        : argument;
    final String? attachedValue = equalsIndex > 0
        ? argument.substring(equalsIndex + 1)
        : null;

    if (knownValueOptions.contains(flag)) {
      String value;
      if (attachedValue != null) {
        value = attachedValue;
      } else {
        if (index >= args.length) {
          throw FailureException("Option '$flag' requires a value.");
        }
        value = args[index++];
      }
      if (value.isEmpty) {
        throw FailureException("Option '$flag' requires a non-empty value.");
      }
      switch (flag) {
        case '--org':
          org = value;
        case '--project-name':
          packageName = value;
        case '--description':
          description = value;
        default:
          // Forward options we do not consume in their original form.
          if (attachedValue != null) {
            forwardedArguments.add(argument);
          } else {
            forwardedArguments.add(flag);
            forwardedArguments.add(value);
          }
      }
      continue;
    }

    if (argument.startsWith('-') && argument.length > 1) {
      // Unknown option: forwarded as a flag. Its value (if any) must use the
      // attached form, otherwise it would be read as the destination.
      forwardedArguments.add(argument);
      continue;
    }

    addPositional(argument);
  }

  if (destination == null) {
    throw FailureException(
      'Missing destination. Usage: dart create_project.dart [options] <destination>',
    );
  }

  return ParsedArguments(
    destination: destination!,
    org: org,
    openInVsCode: openInVsCode,
    forwardedArguments: forwardedArguments,
    packageName: packageName,
    description: description,
  );
}

/// Canonical template root, resolved from this script's location so the
/// generator works from any working directory.
String resolveTemplateRoot() {
  final String scriptPath = File(Platform.script.toFilePath())
      .resolveSymbolicLinksSync();
  return File(scriptPath).parent.resolveSymbolicLinksSync();
}

void validateTemplate(String templateRoot) {
  for (final String relativePath in requiredTemplatePaths) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      '$templateRoot/$relativePath',
    );
    if (type == FileSystemEntityType.notFound) {
      throw FailureException(
        'Required template entry is missing: $templateRoot/$relativePath. '
        'The template checkout looks incomplete.',
      );
    }
  }
}

void validateRequiredExecutables() {
  final List<String> required = <String>[
    'flutter',
    'dart',
    if (!Platform.isWindows) 'bash',
  ];
  for (final String name in required) {
    if (findExecutable(name) == null) {
      throw FailureException(
        'Required executable "$name" was not found on PATH.',
      );
    }
  }
}

String? findExecutable(String name) {
  final String? pathEnvironment = Platform.environment['PATH'];
  if (pathEnvironment == null) {
    return null;
  }
  final String separator = Platform.isWindows ? ';' : ':';
  final List<String> extensions = Platform.isWindows
      ? <String>['.exe', '.bat', '.cmd', '']
      : <String>[''];
  for (final String directory in pathEnvironment.split(separator)) {
    if (directory.isEmpty) {
      continue;
    }
    for (final String extension in extensions) {
      final String candidate =
          '$directory${Platform.pathSeparator}$name$extension';
      final FileSystemEntityType type = FileSystemEntity.typeSync(candidate);
      if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        return candidate;
      }
    }
  }
  return null;
}

/// Converts the typed destination into an absolute path, relative to the
/// caller's original working directory.
String absoluteDestination(String destination, String originalDirectory) {
  String path;
  if (destination.startsWith('/')) {
    path = destination;
  } else if (originalDirectory == '/') {
    path = '/$destination';
  } else {
    path = '$originalDirectory/$destination';
  }
  path = path.replaceAll(Platform.pathSeparator, '/');
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

/// The final path component, used as the directory name to publish.
String finalComponent(String destination) {
  final String normalized = destination.replaceAll(Platform.pathSeparator, '/');
  final int index = normalized.lastIndexOf('/');
  final String component = index == -1
      ? normalized
      : normalized.substring(index + 1);
  if (component.isEmpty || component == '.' || component == '..') {
    throw FailureException(
      'Could not determine a project directory name from destination "$destination".',
    );
  }
  return component;
}

String parentOf(String path) {
  final String normalized = path.replaceAll(Platform.pathSeparator, '/');
  final int index = normalized.lastIndexOf('/');
  if (index <= 0) {
    return '/';
  }
  return normalized.substring(0, index);
}

void validatePackageName(String name) {
  if (!packageNamePattern.hasMatch(name)) {
    throw FailureException(
      'Invalid package name "$name". Use snake_case: lowercase letters, digits '
      'and underscores, starting with a letter. Pass --project-name=<name> to '
      'use a destination directory name that is not a valid package name.',
    );
  }
  if (dartReservedIdentifiers.contains(name)) {
    throw FailureException(
      '"$name" is a Dart reserved identifier and cannot be used as a package '
      'name. Pass --project-name=<name> to choose a valid package name.',
    );
  }
}

/// Refuses unsafe destinations before `flutter create` is ever invoked.
/// Never deletes or modifies the existing target.
void preflightDestination(String destination, String templateRoot) {
  final String parent = parentOf(destination);
  if (!Directory(parent).existsSync()) {
    throw FailureException('Parent directory "$parent" does not exist.');
  }
  final String canonicalParent = Directory(parent).resolveSymbolicLinksSync();
  final String candidate = canonicalParent == '/'
      ? '/${finalComponent(destination)}'
      : '$canonicalParent/${finalComponent(destination)}';
  if (candidate == templateRoot) {
    throw FailureException(
      'Refusing to use the template root ("$templateRoot") itself as the destination.',
    );
  }
  if (FileSystemEntity.isLinkSync(destination)) {
    throw FailureException(
      'Refusing to create the project: "$destination" is a symlink (dangling or not).',
    );
  }
  final FileSystemEntityType type = FileSystemEntity.typeSync(destination);
  if (type != FileSystemEntityType.notFound) {
    final String kind = type == FileSystemEntityType.directory
        ? 'directory'
        : 'file';
    throw FailureException(
      'Refusing to create the project: a $kind already exists at "$destination". '
      'The generator never overwrites or modifies an existing destination '
      '(empty directories included). Remove it or choose another name.',
    );
  }
}

/// Creates a uniquely owned staging directory under the destination's parent.
String createStagingDirectory(String destination) {
  final String stagingPath =
      '${parentOf(destination)}/$stagingDirectoryPrefix${finalComponent(destination)}-'
      '$pid-${DateTime.now().microsecondsSinceEpoch}';
  Directory(stagingPath).createSync();
  return stagingPath;
}

/// Runs a command with inherited stdio so output streams live. Preserves the
/// child's nonzero exit code.
Future<void> runCommand(String executable, List<String> arguments) async {
  stdout.writeln('▶ $executable ${arguments.join(' ')}');
  final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.inheritStdio,
    );
  } on ProcessException catch (error) {
    throw FailureException('Could not run "$executable": ${error.message}');
  }
  final int code = await process.exitCode;
  if (code != 0) {
    throw FailureException(
      'Command failed with exit code $code: $executable ${arguments.join(' ')}',
      exitCode: code,
    );
  }
}

/// Copies every template-owned asset into the current (staging) directory.
Future<void> copyTemplateAssets(String templateRoot) async {
  stdout.writeln("📂 Copying 'lib' folder from template...");
  final Directory libDestination = Directory('lib');
  if (libDestination.existsSync()) {
    libDestination.deleteSync(recursive: true);
  }
  copyDirectory(Directory('$templateRoot/lib'), libDestination);

  stdout.writeln("🧪 Copying 'test' folder from template...");
  final Directory testDestination = Directory('test');
  if (testDestination.existsSync()) {
    testDestination.deleteSync(recursive: true);
  }
  copyDirectory(Directory('$templateRoot/test'), testDestination);

  stdout.writeln('📜 Copying shipped scripts (explicit allowlist)...');
  final Directory scriptsDestination = Directory('scripts');
  if (!scriptsDestination.existsSync()) {
    scriptsDestination.createSync();
  }
  for (final String scriptPath in <String>[
    ...shippedScripts,
    ...shippedScriptAssets,
  ]) {
    final File source = File('$templateRoot/$scriptPath');
    if (!source.existsSync()) {
      throw FailureException(
        'Template asset missing: $scriptPath — the shipped-script allowlist '
        'and the template repository are out of sync.',
      );
    }
    File(scriptPath).parent.createSync(recursive: true);
    source.copySync(scriptPath);
  }

  if (!Platform.isWindows) {
    await runCommand('chmod', <String>['+x', ...shippedScripts]);
  }

  final Directory codexSource = Directory('$templateRoot/.codex');
  if (codexSource.existsSync()) {
    stdout.writeln("🤖 Copying '.codex' folder...");
    copyDirectory(codexSource, Directory('.codex'));
  }

  final Directory agentsSource = Directory('$templateRoot/.agents');
  if (agentsSource.existsSync()) {
    stdout.writeln("🤖 Copying '.agents' folder...");
    copyDirectory(agentsSource, Directory('.agents'));
  }

  final File agentsInstructionsSource = File('$templateRoot/AGENTS.md');
  if (agentsInstructionsSource.existsSync()) {
    stdout.writeln("🤖 Copying 'AGENTS.md'...");
    agentsInstructionsSource.copySync('AGENTS.md');
  }

  final File removeCounterSource = File('$templateRoot/remove_counter.sh');
  if (removeCounterSource.existsSync()) {
    stdout.writeln("🧹 Copying 'remove_counter.sh'...");
    removeCounterSource.copySync('remove_counter.sh');
    if (!Platform.isWindows) {
      await runCommand('chmod', <String>['+x', 'remove_counter.sh']);
    }
  }

  stdout.writeln("⚙️  Copying 'analysis_options.yaml'...");
  File('$templateRoot/analysis_options.yaml').copySync('analysis_options.yaml');

  // The generated app carries its OWN standalone quality workflow — never a
  // reference to this repository's template-verification harness.
  stdout.writeln("🤖 Copying '.github/workflows/flutter-ci.yml'...");
  final Directory workflowDestination = Directory('.github/workflows');
  workflowDestination.createSync(recursive: true);
  File('$templateRoot/templates/github/workflows/flutter-ci.yml')
      .copySync('${workflowDestination.path}/flutter-ci.yml');

  final File l10nSource = File('$templateRoot/l10n.yaml');
  if (l10nSource.existsSync()) {
    stdout.writeln("🌐 Copying 'l10n.yaml'...");
    l10nSource.copySync('l10n.yaml');
  }

  final File gitignoreTemplate = File('$templateRoot/template-gitignore');
  if (gitignoreTemplate.existsSync()) {
    stdout.writeln("📋 Updating '.gitignore'...");
    final File gitignoreFile = File('.gitignore');
    final String content = gitignoreFile.existsSync()
        ? gitignoreFile.readAsStringSync()
        : '';
    gitignoreFile.writeAsStringSync(
      '$content\n${gitignoreTemplate.readAsStringSync()}',
    );
  }

  final Directory fontSource = Directory('$templateRoot/fonts');
  if (fontSource.existsSync()) {
    stdout.writeln('🔤 Setting up Inter font...');
    final Directory fontDestination = Directory('assets/fonts');
    if (!fontDestination.existsSync()) {
      fontDestination.createSync(recursive: true);
    }
    copyDirectory(fontSource, fontDestination);
  }
}

/// Cleans up and configures pubspec.yaml. A caller-supplied `--description`
/// was already written by `flutter create` and is preserved.
void processPubspec({
  required String packageName,
  required bool hasCustomDescription,
}) {
  stdout.writeln('🧹 Cleaning and configuring pubspec.yaml...');
  final File pubspecFile = File('pubspec.yaml');
  String content = pubspecFile.readAsStringSync();

  content = content
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('#'))
      .join('\n');

  if (!hasCustomDescription) {
    content = content.replaceFirst(
      RegExp(r'^description: .*$', multiLine: true),
      'description: "$packageName — generated with the flutterforge template."',
    );
  }

  if (!content.contains('generate: true')) {
    content = content.replaceFirst(
      RegExp(r'^flutter:', multiLine: true),
      'flutter:\n  generate: true',
    );
  }

  if (!content.contains('assets:')) {
    content = content.replaceFirst(
      RegExp(r'^flutter:', multiLine: true),
      'flutter:\n  assets:\n    - assets/',
    );
  }

  if (!content.contains('fonts:') && Directory('assets/fonts').existsSync()) {
    const String fontsConfig = '''
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter/Inter-Regular.ttf
        - asset: assets/fonts/Inter/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter/Inter-Bold.ttf
          weight: 700''';

    content = content.replaceFirst(
      RegExp(r'^flutter:', multiLine: true),
      'flutter:\n$fontsConfig',
    );
  }

  pubspecFile.writeAsStringSync(content);
}

/// Adds localization packages and every package from packages_to_add.json.
Future<void> addPackages(String templateRoot) async {
  stdout.writeln('🌐 Adding localization packages...');
  await runCommand('flutter', <String>[
    'pub',
    'add',
    'flutter_localizations',
    '--sdk=flutter',
  ]);
  await runCommand('flutter', <String>['pub', 'add', 'intl:any']);

  final File packagesFile = File('$templateRoot/packages_to_add.json');
  if (packagesFile.existsSync()) {
    stdout.writeln('📦 Adding packages from packages_to_add.json...');
    final Map<String, dynamic> json =
        jsonDecode(packagesFile.readAsStringSync()) as Map<String, dynamic>;

    final List<String> dependencies = List<String>.from(
      json['dependencies'] ?? <String>[],
    );
    if (dependencies.isNotEmpty) {
      await runCommand('flutter', <String>['pub', 'add', ...dependencies]);
    }

    final List<String> devDependencies = List<String>.from(
      json['dev_dependencies'] ?? <String>[],
    );
    if (devDependencies.isNotEmpty) {
      await runCommand('flutter', <String>[
        'pub',
        'add',
        '--dev',
        ...devDependencies,
      ]);
    }
  }
}

/// Writes README.md from the template with the project name substituted.
void writeReadme(String templateRoot, String packageName) {
  final File readmeTemplate = File('$templateRoot/template-README.md');
  if (readmeTemplate.existsSync()) {
    stdout.writeln('📄 Setting up README.md from template...');
    final String readmeContent = readmeTemplate.readAsStringSync().replaceAll(
      '{PROJECT_NAME}',
      packageName,
    );
    File('README.md').writeAsStringSync(readmeContent);
  } else {
    stderr.writeln(
      '⚠️  Warning: template-README.md not found. Skipping README setup.',
    );
  }
}

/// Substitutes the package-name placeholder only in template-owned text paths
/// — never in SDK metadata, dependency caches, or unrelated platform files.
void replacePlaceholderInTemplateCopies(String packageName) {
  stdout.writeln(
    "✏️  Replacing placeholder package name '$templatePackageNamePlaceholder' "
    "with '$packageName' in template-owned files...",
  );
  for (final String root in placeholderRoots) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(root);
    if (type == FileSystemEntityType.notFound) {
      continue;
    }
    if (type == FileSystemEntityType.file) {
      _replacePlaceholderInFile(File(root), packageName);
      continue;
    }
    for (final FileSystemEntity entity in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        _replacePlaceholderInFile(entity, packageName);
      }
    }
  }
}

void _replacePlaceholderInFile(File file, String packageName) {
  const Set<String> extensions = <String>{'.dart', '.md', '.yaml', '.arb'};
  final int lastDotIndex = file.path.lastIndexOf('.');
  if (lastDotIndex == -1) {
    return;
  }
  final String extension = file.path.substring(lastDotIndex);
  if (!extensions.contains(extension)) {
    return;
  }
  final String content = file.readAsStringSync();
  if (content.contains(templatePackageNamePlaceholder)) {
    file.writeAsStringSync(
      content.replaceAll(templatePackageNamePlaceholder, packageName),
    );
  }
}

void copyDirectory(Directory source, Directory destination) {
  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }
  for (final FileSystemEntity entity in source.listSync()) {
    final String name = entity.path.split(Platform.pathSeparator).last;
    if (entity is Directory) {
      copyDirectory(entity, Directory('${destination.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${destination.path}/$name');
    }
  }
}
