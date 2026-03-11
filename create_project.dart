import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty || args.any((arg) => arg == '--help' || arg == '-h')) {
    print('Usage: dart create_project.dart [--org=<organization>] [flutter_create_args] <project_name>');
    print('Example: dart create_project.dart --org=com.mycompany --platforms=android,ios my_new_app');
    return;
  }

  // 1. Parse Arguments
  String org = 'fr.yofardev';
  String? projectName;
  final flutterArgs = <String>[];

  for (final arg in args) {
    if (arg.startsWith('--org=')) {
      org = arg.substring(6);
    } else if (!arg.startsWith('-')) {
      projectName = arg;
      flutterArgs.add(arg);
    } else {
      flutterArgs.add(arg);
    }
  }

  if (projectName == null) {
    print('Error: Missing project name.');
    exit(1);
  }

  final scriptDir = File(Platform.script.toFilePath()).parent;
  final projectDir = Directory(projectName);

  print('🚀 Creating Flutter project \'$projectName\'...');
  print('   Organization: $org');

  // 2. Create the project
  await _runCommand('flutter', ['create', '--org', org, ...flutterArgs]);

  if (!projectDir.existsSync()) {
    print('Error: Project directory not created.');
    exit(1);
  }

  Directory.current = projectDir;

  // 3. Copy lib folder template
  print('📂 Copying \'lib\' folder from template...');
  final libDest = Directory('lib');
  if (libDest.existsSync()) libDest.deleteSync(recursive: true);
  _copyDirectory(Directory('${scriptDir.path}/lib'), libDest);

  // 4. Copy test folder template
  print('🧪 Copying \'test\' folder from template...');
  final testDest = Directory('test');
  if (testDest.existsSync()) testDest.deleteSync(recursive: true);
  _copyDirectory(Directory('${scriptDir.path}/test'), testDest);

  // 5. Copy scripts folder template
  print('📜 Copying \'scripts\' folder from template...');
  final scriptsDest = Directory('scripts');
  if (!scriptsDest.existsSync()) scriptsDest.createSync();
  _copyDirectory(Directory('${scriptDir.path}/scripts'), scriptsDest);
  
  // chmod +x scripts/*.sh on Unix-like systems
  if (!Platform.isWindows) {
    await _runCommand('chmod', ['+x', ...Directory('scripts').listSync().whereType<File>().map((e) => e.path).where((path) => path.endsWith('.sh'))]);
  }

  // 6. Copy .claude folder
  final claudeSource = Directory('${scriptDir.path}/.claude');
  if (claudeSource.existsSync()) {
    print('🤖 Copying \'.claude\' folder...');
    _copyDirectory(claudeSource, Directory('.claude'));
  }

  // 7. Copy analysis_options.yaml
  print('⚙️  Copying \'analysis_options.yaml\'...');
  File('${scriptDir.path}/analysis_options.yaml').copySync('analysis_options.yaml');

  // 8. Copy l10n.yaml
  final l10nSource = File('${scriptDir.path}/l10n.yaml');
  if (l10nSource.existsSync()) {
    print('🌐 Copying \'l10n.yaml\'...');
    l10nSource.copySync('l10n.yaml');
  }

  // 9. Copy .gitignore template
  final gitignoreTemplate = File('${scriptDir.path}/template-gitignore');
  if (gitignoreTemplate.existsSync()) {
    print('📋 Updating \'.gitignore\'...');
    final gitignoreFile = File('.gitignore');
    final content = gitignoreFile.readAsStringSync();
    gitignoreFile.writeAsStringSync('$content\n${gitignoreTemplate.readAsStringSync()}');
  }

  // 10. Copy Inter font files
  final fontSource = Directory('${scriptDir.path}/fonts');
  if (fontSource.existsSync()) {
    print('🔤 Setting up Inter font...');
    final fontDest = Directory('assets/fonts');
    if (!fontDest.existsSync()) fontDest.createSync(recursive: true);
    _copyDirectory(fontSource, fontDest);
  }

  // 11. Process pubspec.yaml
  print('🧹 Cleaning and configuring pubspec.yaml...');
  final pubspecFile = File('pubspec.yaml');
  var content = pubspecFile.readAsStringSync();

  // Remove comments
  content = content.split('\n')
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');

  // Add generate: true under flutter:
  if (!content.contains('generate: true')) {
    content = content.replaceFirst(RegExp(r'^flutter:', multiLine: true), 'flutter:\n  generate: true');
  }

  // Add assets under flutter:
  if (!content.contains('assets:')) {
    content = content.replaceFirst(RegExp(r'^flutter:', multiLine: true), 'flutter:\n  assets:\n    - assets/');
  }

  // Add fonts under flutter:
  if (!content.contains('fonts:') && Directory('assets/fonts').existsSync()) {
    const fontsConfig = '''
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
    
    content = content.replaceFirst(RegExp(r'^flutter:', multiLine: true), 'flutter:\n$fontsConfig');
  }

  pubspecFile.writeAsStringSync(content);

  // 12. Add localization packages
  print('🌐 Adding localization packages...');
  await _runCommand('flutter', ['pub', 'add', 'flutter_localizations', '--sdk=flutter']);
  await _runCommand('flutter', ['pub', 'add', 'intl:any']);

  // 13. Add packages from packages_to_add.json
  final packagesFile = File('${scriptDir.path}/packages_to_add.json');
  if (packagesFile.existsSync()) {
    print('📦 Adding packages from packages_to_add.json...');
    final json = jsonDecode(packagesFile.readAsStringSync());
    
    final deps = List<String>.from(json['dependencies'] ?? []);
    if (deps.isNotEmpty) {
      await _runCommand('flutter', ['pub', 'add', ...deps]);
    }

    final devDeps = List<String>.from(json['dev_dependencies'] ?? []);
    if (devDeps.isNotEmpty) {
      await _runCommand('flutter', ['pub', 'add', '--dev', ...devDeps]);
    }
  }

  // 14. Generate localization files
  print('🌐 Generating localization files...');
  await _runCommand('flutter', ['gen-l10n']);

  // 15. Setup README.md
  final readmeTemplate = File('${scriptDir.path}/template-README.md');
  if (readmeTemplate.existsSync()) {
    print('📄 Setting up README.md from template...');
    var readmeContent = readmeTemplate.readAsStringSync();
    readmeContent = readmeContent.replaceAll('{PROJECT_NAME}', projectName);
    File('README.md').writeAsStringSync(readmeContent);
  } else {
    print('⚠️  Warning: template-README.md not found. Skipping README setup.');
  }

  // 16. Replace placeholder package name
  print('✏️  Replacing placeholder package name \'my_flutter_app\' with \'$projectName\'...');
  _replaceInFiles(Directory.current, 'my_flutter_app', projectName);

  // 17. Run build_runner
  print('🔧 Running build_runner for code generation...');
  await _runCommand('dart', ['run', 'build_runner', 'build', '--delete-conflicting-outputs']);

  print('✅ Project setup complete!');

  // 18. Open in VS Code
  print('📝 Opening project in VS Code...');
  try {
    await Process.start('code', ['.'], mode: ProcessStartMode.detached);
  } catch (e) {
    print('⚠️  Could not open VS Code. Make sure \'code\' command is in your PATH.');
  }
}

Future<void> _runCommand(String command, List<String> arguments) async {
  final result = await Process.run(command, arguments, runInShell: true);
  if (result.exitCode != 0) {
    print('Error running $command ${arguments.join(' ')}:');
    print(result.stdout);
    print(result.stderr);
    exit(result.exitCode);
  }
}

void _copyDirectory(Directory source, Directory destination) {
  if (!destination.existsSync()) destination.createSync(recursive: true);
  for (var entity in source.listSync()) {
    if (entity is Directory) {
      final newDirectory = Directory('${destination.path}/${entity.path.split(Platform.pathSeparator).last}');
      _copyDirectory(entity, newDirectory);
    } else if (entity is File) {
      entity.copySync('${destination.path}/${entity.path.split(Platform.pathSeparator).last}');
    }
  }
}

void _replaceInFiles(Directory dir, String from, String to) {
  final extensions = {'.dart', '.md', '.yaml', '.arb'};
  for (var entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final lastDotIndex = entity.path.lastIndexOf('.');
      if (lastDotIndex == -1) continue;
      final ext = entity.path.substring(lastDotIndex);
      if (extensions.contains(ext)) {
        final content = entity.readAsStringSync();
        if (content.contains(from)) {
          entity.writeAsStringSync(content.replaceAll(from, to));
        }
      }
    }
  }
}
