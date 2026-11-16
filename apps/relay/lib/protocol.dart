/// What a computer and the relay say to each other, shared by both: the
/// relay (`relay.dart`) and Helmy on the computer (its `relay_host.dart`).
///
/// A computer keeps one WebSocket open to the relay. It proves which
/// computer it is by signing the relay's challenge with its own Ed25519 key;
/// its id is made from that key, so nobody else can take it. Every phone
/// connected through the relay is a channel on that one socket, each binary
/// message being one [Frame].
///
/// The relay never sees what is said: Helmy seals every message between a
/// phone and the computer with a key the relay never has.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// What a frame carries.
enum FrameKind {
  /// Relay to computer: a phone connected. The payload is its query, as JSON.
  open(1),

  /// A text message, either way.
  text(2),

  /// A binary message, either way.
  binary(3),

  /// The channel closed, either way. The payload is the close code (two
  /// bytes) and the reason.
  close(4);

  const FrameKind(this.code);
  final int code;

  static FrameKind? of(int code) =>
      values.where((k) => k.code == code).firstOrNull;
}

/// One message on a computer's socket: [kind], the [channel] (one phone's
/// connection) and its [payload].
class Frame {
  const Frame(this.kind, this.channel, this.payload);

  final FrameKind kind;
  final int channel;
  final Uint8List payload;

  factory Frame.text(int channel, String text) =>
      Frame(FrameKind.text, channel, Uint8List.fromList(utf8.encode(text)));

  factory Frame.close(int channel, int code, String reason) {
    final r = utf8.encode(reason);
    final p = Uint8List(2 + r.length)
      ..[0] = code >> 8
      ..[1] = code & 0xff
      ..setRange(2, 2 + r.length, r);
    return Frame(FrameKind.close, channel, p);
  }

  factory Frame.open(int channel, Map<String, String> query) => Frame(
    FrameKind.open,
    channel,
    Uint8List.fromList(utf8.encode(jsonEncode(query))),
  );

  /// As it goes on the socket: kind (1 byte), channel (4 bytes, big-endian),
  /// then the payload.
  Uint8List encode() {
    final out = Uint8List(5 + payload.length);
    ByteData.sublistView(out)
      ..setUint8(0, kind.code)
      ..setUint32(1, channel);
    out.setRange(5, out.length, payload);
    return out;
  }

  /// The frame in [bytes]; null when they are not one.
  static Frame? decode(List<int> bytes) {
    if (bytes.length < 5) return null;
    final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final view = ByteData.sublistView(b);
    final kind = FrameKind.of(view.getUint8(0));
    if (kind == null) return null;
    return Frame(kind, view.getUint32(1), Uint8List.sublistView(b, 5));
  }

  String get text => utf8.decode(payload, allowMalformed: true);

  /// A close frame's code and reason.
  ({int code, String reason}) get closing => payload.length < 2
      ? (code: 1000, reason: '')
      : (
          code: (payload[0] << 8) | payload[1],
          reason: utf8.decode(payload.sublist(2), allowMalformed: true),
        );

  /// An open frame's query.
  Map<String, String> get query {
    try {
      final j = jsonDecode(text);
      return j is Map
          ? {for (final e in j.entries) '${e.key}': '${e.value}'}
          : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// How a computer's id is made from its public key: the first 16 bytes of
/// its SHA-256, base64url without padding (22 characters).
Future<String> hostId(List<int> publicKey) async {
  final hash = await Sha256().hash(publicKey);
  return base64Url.encode(hash.bytes.sublist(0, 16)).replaceAll('=', '');
}

/// What a computer signs to prove it holds its key: the relay's challenge,
/// so a signature cannot be used twice.
List<int> challengeText(String nonce) => utf8.encode('helmy-relay-host:$nonce');

/// Close codes the relay uses on a phone's socket, so the phone can say why.
abstract final class RelayClose {
  /// The computer is not connected to the relay.
  static const offline = 4404;

  /// The computer has as many phones connected as it may.
  static const busy = 4429;

  /// The computer used more than its share of the relay today.
  static const overQuota = 4430;

  /// The relay has as many computers connected as it can take.
  static const full = 4503;

  /// Another connection proved it is the same computer.
  static const replaced = 4000;
}
