import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One open text file. Saves refuse to replace changes made elsewhere.
class FileDocument extends ChangeNotifier {
  FileDocument(this.path);

  /// A snapshot already read by the caller, also used by preview harnesses.
  FileDocument.fromText(this.path, String content)
    : text = content,
      _saved = content,
      loaded = true;
  String path;
  String text = '';
  String _saved = '';
  String? error;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool loaded = false;
  bool saving = false;
  bool get dirty => path.isEmpty || text != _saved;

  Future<void> load() async {
    try {
      final file = File(path);
      if (await file.length() > 2 * 1024 * 1024) {
        throw const FormatException('This file is too large to edit here (2 MB maximum).');
      }
      final bytes = await file.readAsBytes();
      if (bytes.contains(0)) throw const FormatException('This file is not text.');
      text = _saved = utf8.decode(bytes);
      loaded = true;
      error = null;
    } on FormatException catch (e) {
      error = e.message;
    } on Object {
      error = 'This file could not be read. It may have moved or been deleted.';
    }
    notifyListeners();
  }

  void edit(String value) {
    text = value;
    notifyListeners();
  }

  void discard() {
    if (path.isEmpty) return;
    text = _saved;
    error = null;
    notifyListeners();
  }

  /// A draft becomes a real file only after a destination is chosen.
  Future<bool> saveAs(String destination) async {
    if (saving || !loaded) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final file = File(destination);
      if (await file.exists()) {
        error = 'A file already exists there. Choose a new name to keep its contents safe.';
        return false;
      }
      final writing = text;
      await file.writeAsString(writing, flush: true);
      path = destination;
      _saved = writing;
      return true;
    } on Object {
      error = 'This file could not be saved. Your draft is still here.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> save() async {
    if (!loaded || saving || !dirty) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final file = File(path);
      if (await file.readAsString() != _saved) {
        error = 'This file changed on disk. Your edits are kept here. Copy them before reloading.';
        return false;
      }
      final writing = text;
      await file.writeAsString(writing, flush: true);
      _saved = writing;
      return true;
    } on Object {
      error = 'This file could not be saved. Your edits are still here.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
