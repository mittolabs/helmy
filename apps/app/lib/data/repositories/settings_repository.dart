import 'package:flutter/foundation.dart';

import '../../domain/models/settings.dart';
import '../services/storage_service.dart';
import '../../domain/models/engine.dart';
import '../services/worktrees.dart';

/// The user's settings, from `settings.json`. Notifies when they change.
class SettingsRepository extends ChangeNotifier {
  new(this._storage);
  final StorageService _storage;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  /// What Helmy may do without asking in a new session in [folder]: its
  /// project's level, or the one for everywhere.
  Future<PermissionLevel> levelFor(String folder) async {
    final repo = await Worktrees().repoOf(folder);
    return (repo == null ? null : _settings.project(repo).level) ?? _settings.defaultLevel;
  }

  Future<void> load() async {
    final raw = await _storage.read('settings.json');
    if (raw is Map) _settings = AppSettings.fromJson(raw.cast<String, Object?>());
    notifyListeners();
  }

  Future<void> save(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _storage.write('settings.json', settings.toJson());
  }
}
