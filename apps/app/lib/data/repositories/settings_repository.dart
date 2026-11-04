import 'package:flutter/foundation.dart';

import '../../domain/models/settings.dart';
import '../services/storage_service.dart';

/// The user's settings, from `settings.json`. Notifies when they change.
/// Everything the user can set, and saving it.
abstract class SettingsRepository extends ChangeNotifier {
  AppSettings get settings;
  Future<void> load();
  Future<void> save(AppSettings settings);
}

class SettingsRepositoryLocal extends SettingsRepository {
  new(this._storage);
  final StorageService _storage;

  AppSettings _settings = const AppSettings();
  @override
  AppSettings get settings => _settings;

  @override
  Future<void> load() async {
    final raw = await _storage.read('settings.json');
    if (raw is Map) _settings = AppSettings.fromJson(raw.cast<String, Object?>());
    notifyListeners();
  }

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _storage.write('settings.json', settings.toJson());
  }
}
