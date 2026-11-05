import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// What a phone needs to reach Helmy on a Mac: where (its addresses and
/// port), and the key every message between them is sealed with. Shown on
/// the Mac as a QR code, never sent over the network.
class Pairing {
  const Pairing({required this.hosts, required this.port, required this.key, required this.name});

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
    path: 'v1',
    queryParameters: {'h': hosts.join(','), 'p': '$port', 'k': key, 'n': name},
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
    return Pairing(hosts: hosts, port: port, key: key, name: q['n'] ?? 'Helmy');
  }

  static bool _isKey(String key) {
    try {
      return base64Url.decode(base64Url.normalize(key)).length == 32;
    } on FormatException {
      return false;
    }
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
