# Specular

The full product and technical specification is in `SPEC.md`. Read it before making changes and follow its decisions. If a change conflicts with the spec, raise it with the user instead of silently diverging.

## Conventions

- Language: Dart / Flutter. Targets: Linux, Windows, Android.
- Keep `lib/core/` free of Flutter and platform imports so it stays unit-testable.
- New item types, storage backends and change notifiers go through the interfaces described in SPEC.md §7.
- After changing drift tables in `lib/data/local_db/`, run `dart run build_runner build` and commit the generated `*.g.dart` file.
- Run `flutter analyze` and `flutter test` before considering a task done.
- Code, comments, commit messages and docs are written in English.