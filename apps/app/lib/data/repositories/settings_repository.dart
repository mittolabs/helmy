import 'package:flutter/foundation.dart';

import '../../domain/models/settings.dart';
import '../services/storage_service.dart';

/// The user's settings, from `settings.json`. Notifies when they change.
class SettingsRepository extends ChangeNotifier {
  new(this._storage);
  final StorageService _storage;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

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
