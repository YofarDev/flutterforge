# General
- Use mcp context7 to fetch up-to-date library documentation when needed.
# Code Search
Use jcodemunch MCP for:
- Looking up any existing class, method, or function before writing new code
- Exploring unfamiliar parts of the codebase
- Searching for existing implementations before creating new ones
- Getting file/folder outlines instead of reading whole files
# Python
- Always use `uv` instead of `python` for running Python scripts and managing packages
- Use `uv run` instead of `python` for executing scripts
- Use `uv pip` or `uv add` for package management instead of `pip`
# Flutter
- `flutter pub add <package>` (never edit pubspec.yaml manually)
- Always specify type annotations
- `withOpacity()` is deprecated → use `.withValues(alpha: ...)`
- Use the custom `AppLogger()` to print
- **freezed v3**: Classes with factory constructors now require `sealed` or `abstract` keyword
- **Radio**: `groupValue` and `onChanged` are deprecated (after v3.32.0) → use a `RadioGroup` ancestor to manage group value instead
- Run `flutter analyze` once done, fix any errors
- To add a localization string, run `fstr $keyName "$stringFr" "$stringEn"`
- You can run `fimp`(no arguments) to auto-fix broken internal imports
- You can run `fdead` (no arguments) to find orphaned files
- There is a hook after a .dart edit : it automatically runs `dart fix --apply && dart format .`, so if you import a package without using it, it will be automatically removed.
- Read skill `flutter-architecture` whenever you add a feature or refactor.

@RTK.md
