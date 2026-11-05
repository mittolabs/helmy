import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// What a phone needs to reach Helmy on a Mac: where (its addresses and
/// port), and the key every message between them is sealed with. Shown on
/// the Mac as a QR code, never sent over the network.
class Pairing {
  const Pairing({
    required this.hosts,
    required this.port,
    required this.key,
    required this.name,
    this.device,
  });

  /// This phone's id on the Mac, with a key of its own: so the Mac can tell
  /// phones apart and turn one away alone. Null for a pairing made before.
  final String? device;

  final List<String> hosts;
  final int port;

  /// 32 random bytes, base64url: AES-256-GCM's key.
  final String key;

  /// The Mac's name, to say what the phone is connected to.
  final String name;

  static const scheme = 'helmy-pair';

  /// As the QR code carries it.
  String get link => Uri(
    scheme: scheme,
    path: device == null ? 'v1' : 'v2',
    queryParameters: {'h': hosts.join(','), 'p': '$port', 'k': key, 'n': name, 'd': ?device},
  ).toString();

  /// A link read from a QR code or pasted; null when it is not one.
  static Pairing? parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != scheme) return null;
    final q = uri.queryParameters;
    final port = int.tryParse(q['p'] ?? '');
    final key = q['k'] ?? '';
    final hosts = (q['h'] ?? '').split(',').where((h) => h.isNotEmpty).toList();
    if (port == null || hosts.isEmpty || !_isKey(key)) return null;
    final device = q['d'];
    return Pairing(
      hosts: hosts,
      port: port,
      key: key,
      name: q['n'] ?? 'Helmy',
      device: device == null || device.isEmpty ? null : device,
    );
  }

  static bool _isKey(String key) {
    try {
      return base64Url.decode(base64Url.normalize(key)).length == 32;
    } on FormatException {
      return false;
    }
  }

  /// A new phone's id: short, random, URL-safe.
  static String newDevice() {
    final r = Random.secure();
    return base64Url.encode([for (var i = 0; i < 9; i++) r.nextInt(256)]);
  }

  /// A new key: pairing again with it lets go of every phone paired before.
  static String newKey() {
    final r = Random.secure();
    return base64Url.encode([for (var i = 0; i < 32; i++) r.nextInt(256)]).replaceAll('=', '');
  }
}

/// Seals and opens messages with a pairing's key (AES-256-GCM, a fresh nonce
/// each time). Only someone with the key can read one, or write one that
/// opens: so opening the first message is also how a phone proves it paired.
class Sealer {
  Sealer(String key) : _key = SecretKey(base64Url.decode(base64Url.normalize(key)));

  final SecretKey _key;
  final _aes = AesGcm.with256bits();

  Future<String> seal(Map<String, Object?> message) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode(message)), secretKey: _key);
    return base64.encode(box.concatenation());
  }

  /// [bytes] sealed as they are: for what is large, such as a picture of
  /// the screen, sent as a binary message.
  Future<Uint8List> sealBytes(List<int> bytes) async =>
      Uint8List.fromList((await _aes.encrypt(bytes, secretKey: _key)).concatenation());

  /// The bytes in [sealed]; null when they do not open with this key.
  Future<Uint8List?> openBytes(List<int> sealed) async {
    try {
      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: _key));
    } on Object {
      return null;
    }
  }

  /// The message in [sealed]; null when it does not open with this key.
  Future<Map<String, Object?>?> open(String sealed) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64.decode(sealed),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final clear = await _aes.decrypt(box, secretKey: _key);
      final j = jsonDecode(utf8.decode(clear));
      return j is Map ? j.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }
}
