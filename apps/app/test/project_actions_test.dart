import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/editors.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/project_actions.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/project_action.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('actions'));
  tearDown(() => dir.delete(recursive: true));

  void write(String name, String text) {
    File('${dir.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  List<String> commands() => [for (final a in findActions(dir.path)) a.command];

  group('actions are found in the project', () {
    test(
      'package.json scripts, the usual first, without install hooks, as its lockfile runs them',
      () {
        write(
          'package.json',
          jsonEncode({
            'scripts': {
              'format': 'prettier -w .',
              'postinstall': 'patch-package',
              'build': 'vite build',
              'pretest': 'tsc',
              'test': 'vitest',
              'dev': 'vite',
              'prepare': 'husky',
            },
          }),
        );
        expect(commands(), ['npm run dev', 'npm run test', 'npm run build', 'npm run format']);
        write('pnpm-lock.yaml', '');
        expect(commands().first, 'pnpm run dev');
        File('${dir.path}/pnpm-lock.yaml').deleteSync();
        write('yarn.lock', '');
        expect(commands().first, 'yarn dev');
        File('${dir.path}/yarn.lock').deleteSync();
        write('bun.lock', '');
        expect(commands().first, 'bun run dev');
        expect(findActions(dir.path).first.from, 'package.json');
      },
    );

    test('a broken package.json finds nothing rather than failing', () {
      write('package.json', '{ "scripts": ');
      expect(commands(), isEmpty);
    });

    test("Makefile targets, not variables, special targets or files", () {
      write('Makefile', '''
# Run from the repository root.
APP := apps/app
VERSION ?= 1
.PHONY: help setup app run test

help:
\t@echo help
setup:
\tgit config core.hooksPath .githooks
app:
\tcd \$(APP) && fvm flutter build macos
run: app
\topen it
test:
\tcd \$(APP) && fvm flutter test
build/out.o: src.c
\tcc
%.o: %.c
\tcc
sim-input:
\t./build.sh
''');
      expect(commands(), [
        'make run',
        'make test',
        'make help',
        'make setup',
        'make app',
        'make sim-input',
      ]);
    });

    test('justfile recipes, not settings or private ones', () {
      write('justfile', '''
set shell := ["zsh", "-c"]
alias b := build

default:
  just --list
build:
  cargo build
_helper:
  echo hidden
serve port='8080':
  python -m http.server {{port}}
''');
      expect(commands(), ['just serve', 'just build', 'just default']);
    });

    test('a Flutter app through fvm when it pins it, a Dart package without', () {
      write('.fvmrc', '{"flutter": "stable"}');
      write('app/pubspec.yaml', 'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n');
      Directory('${dir.path}/app/test').createSync();
      expect(
        [for (final a in findActions('${dir.path}/app')) a.command],
        ['fvm flutter run', 'fvm flutter test', 'fvm flutter analyze'],
      );
      File('${dir.path}/.fvmrc').deleteSync();
      write('pkg/pubspec.yaml', 'name: pkg\n');
      Directory('${dir.path}/pkg/bin').createSync();
      expect(
        [for (final a in findActions('${dir.path}/pkg')) a.command],
        ['dart run', 'dart analyze'],
      );
    });

    test('Rust, Go and Compose projects get their usual commands', () {
      write('Cargo.toml', '[package]');
      write('go.mod', 'module x');
      write('compose.yaml', 'services: {}');
      expect(commands(), [
        'cargo run', 'cargo test', 'cargo build', //
        'go test ./...', 'go build ./...',
        'docker compose up',
      ]);
      write('main.go', 'package main');
      expect(commands(), contains('go run .'));
    });

    test('a folder with nothing to run has no actions', () {
      write('notes.txt', 'hello');
      expect(commands(), isEmpty);
    });
  });

  group('the editor a project opens in', () {
    Editor app(String id, EditorKind kind, {DateTime? used}) =>
        Editor(id: id, name: id, path: '/Applications/$id.app', kind: kind, lastUsed: used);

    test('is the one chosen last, else the editor used most recently', () {
      final code = app('code', .editor, used: DateTime(2026, 10, 1));
      final cursor = app('cursor', .editor, used: DateTime(2026, 11, 3));
      final zed = app('zed', .editor);
      final term = app('term', .terminal, used: DateTime(2026, 11, 4));
      expect(defaultEditor([code, cursor, zed, term], null), cursor, reason: 'not the terminal');
      expect(defaultEditor([code, cursor, zed, term], 'zed'), zed);
      expect(defaultEditor([code, cursor, term], 'gone'), cursor);
      expect(defaultEditor([zed], null), zed, reason: 'none recorded: the first');
      expect(defaultEditor([term], null), term);
      expect(defaultEditor(const [], null), isNull);
    });

    test('Xcode and Android Studio are offered only for projects they open', () {
      final xcode = app('com.apple.dt.Xcode', .ide);
      final studio = app('com.google.android.studio', .ide);
      final code = app('code', .editor);
      final term = app('term', .terminal);
      expect(editorsFor(dir.path, [term, xcode, studio, code]), [code, term]);

      // A Flutter app: its iOS workspace, and its Android project.
      Directory('${dir.path}/ios/Runner.xcodeproj').createSync(recursive: true);
      Directory('${dir.path}/ios/Runner.xcworkspace').createSync();
      write('android/settings.gradle.kts', '');
      expect(editorsFor(dir.path, [term, xcode, studio, code]), [code, xcode, studio, term]);
      expect(ideProject(xcode.id, dir.path), '${dir.path}/ios/Runner.xcworkspace');
      expect(ideProject(studio.id, dir.path), '${dir.path}/android');
    });
  });

  test("a server's address is found in a terminal's colored output", () {
    // As Vite prints it: the port in bold.
    expect(
      localServerInText('  ➜  Local:   \x1B[36mhttp://localhost:\x1B[1m5173\x1B[22m/\x1B[39m\n'),
      'http://localhost:5173/',
    );
    expect(localServerInText('listening on 0.0.0.0:80'), isNull);
    expect(localServerInText('ready on http://0.0.0.0:3000'), 'http://localhost:3000');
  });

  test("the user's actions and chosen editor are kept with the settings", () {
    const s = AppSettings(
      editor: 'dev.zed.Zed',
      projects: {
        '/p': ProjectSettings(
          actions: [ProjectAction(name: 'setup', command: 'npm ci', onNewCopy: true)],
        ),
      },
    );
    final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
    expect(back.editor, 'dev.zed.Zed');
    expect(back.project('/p').actions.single, s.project('/p').actions.single);
    expect(back.project('/p').actions.single.own, isTrue);
  });

  test('actions run in a terminal tab of their own, afresh when run again', () async {
    write(
      'package.json',
      jsonEncode({
        'scripts': {'dev': 'vite', 'test': 'vitest'},
      }),
    );
    final storage = StorageService(root: () async => dir);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final created = (await sessions.create(cwd: dir.path) as Ok).value as Session;
    repo.of(created.id).loaded = true;
    final settings = FakeSettingsRepository();
    final vm = ChatViewModel(
      sessionId: created.id,
      sessions: sessions,
      conversations: repo,
      settings: settings,
    );
    addTearDown(vm.dispose);
    vm.refreshActions();
    expect([for (final a in vm.actions) a.name], ['dev', 'test']);

    final dev = vm.actions.first;
    vm.run(dev);
    final tab = vm.active!;
    expect((tab.kind, tab.action, tab.runs), (SidePanel.terminal, dev, 1));
    vm.actionEnded(tab, 1);
    expect(tab.exitCode, 1);

    // Again: the same tab, started afresh.
    vm.run(dev);
    expect(vm.tabs, [tab]);
    expect((tab.runs, tab.exitCode), (2, null));
    expect(vm.lastAction, dev);

    // Another: its own tab.
    vm.run(vm.actions[1]);
    expect(vm.tabs.length, 2);

    // One of the user's own, kept for the project, changed, then removed.
    await vm.saveAction(const ProjectAction(name: 'seed', command: 'npm run seed'));
    expect(vm.actions.last.name, 'seed');
    expect(settings.settings.project(dir.path).actions.single.command, 'npm run seed');
    await vm.saveAction(
      const ProjectAction(name: 'seed', command: 'node seed.js'),
      replacing: vm.actions.last,
    );
    expect(vm.actions.last.command, 'node seed.js');
    expect(vm.actions.length, 3);
    await vm.removeAction(vm.actions.last);
    expect(vm.actions.length, 2);
    expect(settings.settings.project(dir.path).actions, isEmpty);
  });
}
