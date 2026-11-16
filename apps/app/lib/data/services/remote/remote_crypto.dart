import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// What a phone needs to reach Helmy on a computer: where (its addresses
/// and port, and its id on the relay), and the key every message between
/// them is sealed with. Shown on the computer as a QR code, never sent over
/// the network.
///
/// A code shown now is an offer: it carries a one-time [secret], not a key.
/// The phone and the computer agree on the key when it is used
/// ([PairingExchange]), and the code is spent, so a copy of it (a
/// screenshot, the link left in a browser's history) opens nothing.
class Pairing {
  const Pairing({
    required this.hosts,
    required this.port,
    required this.key,
    required this.name,
    this.device,
    this.secret,
    this.relay,
    this.relayUrl = defaultRelay,
  });

  /// This phone's id on the computer, with a key of its own: so the
  /// computer can tell phones apart and turn one away alone. Null for a
  /// pairing made before.
  final String? device;

  final List<String> hosts;
  final int port;

  /// 32 random bytes, base64url: AES-256-GCM's key. Empty in an offer.
  final String key;

  /// An offer's one-time secret: proves the phone was given the code, and
  /// salts the key agreed on. Null once paired.
  final String? secret;

  /// The computer's id on the relay; null when it is not reachable there.
  final String? relay;

  /// Where the relay is: its WebSocket address, before `/host` or `/ws`.
  /// Its page is the same address over HTTPS.
  final String relayUrl;

  /// The computer's name, to say what the phone is connected to.
  final String name;

  static const scheme = 'helmy-pair';

  /// Helmy Connect's relay.
  static const defaultRelay = 'wss://connect.helmy.ke';

  /// Whether this still has to be used to get a key.
  bool get isOffer => secret != null;

  /// The pairing an offer became: [key] agreed on, the secret spent.
  Pairing exchanged(String key) => Pairing(
    hosts: hosts,
    port: port,
    key: key,
    name: name,
    device: device,
    relay: relay,
    relayUrl: relayUrl,
  );

  /// As the QR code carries it.
  String get link => Uri(
    scheme: scheme,
    path: isOffer
        ? 'v3'
        : device == null
        ? 'v1'
        : 'v2',
    queryParameters: {
      'h': hosts.join(','),
      'p': '$port',
      if (!isOffer) 'k': key,
      'c': ?secret,
      'n': name,
      'd': ?device,
      'r': ?relay,
      if (relay != null && relayUrl != defaultRelay) 'u': relayUrl,
    },
  ).toString();

  /// The page a browser opens from the relay, over HTTPS.
  String get _relayPage => '${relayUrl.replaceFirst(RegExp(r'^ws'), 'http')}/';

  /// As the QR code carries it: a web address, so a phone with no app opens
  /// Helmy in its browser. With the relay, the page comes from connect.helmy.ke
  /// over HTTPS and reaches the computer from anywhere; without it, this
  /// computer serves it on the local network. The pairing rides after the
  /// `#`, which a browser keeps to itself. The app's scanner reads it the
  /// same.
  String get webLink => relay != null ? '$_relayPage#$link' : 'http://${hosts.first}:$port/#$link';

  /// The relay's address for a phone reaching this computer, with [query].
  Uri relaySocket(Map<String, String> query) =>
      Uri.parse('$relayUrl/ws').replace(queryParameters: {'h': relay!, ...query});

  /// A link read from a QR code or pasted (either form); null when it is not
  /// one.
  static Pairing? parse(String text) {
    var t = text.trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(t)) {
      final at = t.indexOf('#');
      if (at < 0) return null;
      t = t.substring(at + 1);
    }
    final uri = Uri.tryParse(t);
    if (uri == null || uri.scheme != scheme) return null;
    final q = uri.queryParameters;
    final port = int.tryParse(q['p'] ?? '');
    final hosts = (q['h'] ?? '').split(',').where((h) => h.isNotEmpty).toList();
    final relay = q['r'] == null || q['r']!.isEmpty ? null : q['r'];
    final device = q['d'] == null || q['d']!.isEmpty ? null : q['d'];
    final offer = uri.path == 'v3';
    final secret = offer ? q['c'] ?? '' : null;
    final key = offer ? '' : q['k'] ?? '';
    if (port == null || (hosts.isEmpty && relay == null)) return null;
    if (offer ? (!_isKey(secret!) || device == null) : !_isKey(key)) return null;
    return Pairing(
      hosts: hosts,
      port: port,
      key: key,
      name: q['n'] ?? 'Helmy',
      device: device,
      secret: secret,
      relay: relay,
      relayUrl: q['u'] ?? defaultRelay,
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

/// How a phone and the computer agree on the phone's key when its code is
/// used, so the key is never in the code. Each makes an X25519 key pair for
/// this once; the key is derived (HKDF-SHA256) from what they share, salted
/// with the code's secret. Each proves it holds the secret with an HMAC
/// over what it sent, so neither the relay nor anyone who did not see the
/// code can stand in for either. A copy of the code made afterwards, even
/// with every message recorded, cannot give the key.
abstract final class PairingExchange {
  static final _x = X25519();

  static Future<Mac> _proof(String secret, List<String> parts) => Hmac.sha256().calculateMac(
    utf8.encode(parts.join('|')),
    secretKey: SecretKey(base64Url.decode(base64Url.normalize(secret))),
  );

  static String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  static List<int> _bytes(String s) => base64Url.decode(base64Url.normalize(s));

  static Future<String> _derive(
    SimpleKeyPair mine,
    List<int> theirs,
    String secret,
    String device,
  ) async {
    final shared = await _x.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519),
    );
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: _bytes(secret),
      info: utf8.encode('helmy-pair-v3 $device'),
    );
    return _b64(await key.extractBytes());
  }

  /// The phone's first message for [offer], and what it needs to finish.
  static Future<({SimpleKeyPair pair, Map<String, Object?> message})> start(Pairing offer) async {
    final pair = await _x.newKeyPair();
    final pub = _b64((await pair.extractPublicKey()).bytes);
    final proof = await _proof(offer.secret!, ['phone', offer.device!, pub]);
    return (pair: pair, message: {'type': 'exchange', 'pub': pub, 'proof': _b64(proof.bytes)});
  }

  /// The computer's answer to a phone's [message] for [device], whose code
  /// has [secret], and the key agreed on; null when the phone did not prove
  /// it has the code.
  static Future<({Map<String, Object?> message, String key})?> answer(
    String secret,
    String device,
    Map<String, Object?> message,
  ) async {
    try {
      final phonePub = '${message['pub']}';
      final expected = await _proof(secret, ['phone', device, phonePub]);
      if (expected != Mac(_bytes('${message['proof']}'))) return null;
      final pair = await _x.newKeyPair();
      final pub = _b64((await pair.extractPublicKey()).bytes);
      final key = await _derive(pair, _bytes(phonePub), secret, device);
      final proof = await _proof(secret, ['computer', device, pub, phonePub]);
      return (message: {'type': 'exchanged', 'pub': pub, 'proof': _b64(proof.bytes)}, key: key);
    } on Object {
      return null;
    }
  }

  /// The key, from the computer's [answer] to what [started] sent; null when
  /// the computer did not prove it has the code.
  static Future<String?> finish(
    Pairing offer,
    ({SimpleKeyPair pair, Map<String, Object?> message}) started,
    Map<String, Object?> answer,
  ) async {
    try {
      final pub = '${answer['pub']}';
      final expected = await _proof(offer.secret!, [
        'computer',
        offer.device!,
        pub,
        '${started.message['pub']}',
      ]);
      if (expected != Mac(_bytes('${answer['proof']}'))) return null;
      return await _derive(started.pair, _bytes(pub), offer.secret!, offer.device!);
    } on Object {
      return null;
    }
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
