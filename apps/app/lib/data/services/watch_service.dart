import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'cli_locator.dart';

/// One moment of a watched video: when, and a picture of it.
typedef Frame = ({Duration at, String path});

/// What watching a video found: how long it is, its picture's size, frames
/// across it, and what is said in it (null when it has no sound, or the
/// words could not be made out here, with [heard] saying which).
class Watched {
  Watched({
    required this.length,
    required this.width,
    required this.height,
    required this.frames,
    required this.hasSound,
    this.transcript,
    this.heard,
  });

  final Duration length;
  final int width, height;
  final List<Frame> frames;
  final bool hasSound;

  /// What is said, in pieces from where each starts ("[0:50] ...").
  final String? transcript;

  /// Why there is no [transcript] when there is sound.
  final String? heard;
}

/// Watches a video for a model: frames spread across it, and its sound as
/// words. With ffmpeg; the words by this Mac's own recognizer, or whisper
/// where it is installed. Frames for the player's bar too.
class WatchService {
  WatchService(this._locator);
  final CliLocator _locator;

  static const _channel = MethodChannel('helmy/notify');

  /// Where frames and sound are put, one folder per file and its last change.
  Directory _workFor(String path) {
    final f = File(path);
    final key = '${path.hashCode.toUnsigned(32)}-${f.lastModifiedSync().millisecondsSinceEpoch}';
    return Directory('${Directory.systemTemp.path}/helmy-watch/$key')..createSync(recursive: true);
  }

  Future<String?> _tool(String name) => _locator.find(name);

  /// Why watching cannot work here, or null when it can.
  Future<String?> unavailableReason() async => await _tool('ffmpeg') == null
      ? 'Watching a video needs ffmpeg, which is not installed on this computer.'
      : null;

  /// How long [path] runs, its picture's size, and whether it has sound.
  Future<({Duration length, int width, int height, bool sound})?> probe(String path) async {
    final ffprobe = await _tool('ffprobe');
    if (ffprobe == null) return null;
    final r = await Process.run(ffprobe, [
      '-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path, //
    ]);
    if (r.exitCode != 0) return null;
    final j = jsonDecode('${r.stdout}') as Map;
    final streams = (j['streams'] as List).cast<Map>();
    final video = streams.where((s) => s['codec_type'] == 'video').firstOrNull;
    final seconds = double.tryParse('${(j['format'] as Map?)?['duration'] ?? ''}') ?? 0;
    return (
      length: Duration(milliseconds: (seconds * 1000).round()),
      width: (video?['width'] as num?)?.toInt() ?? 0,
      height: (video?['height'] as num?)?.toInt() ?? 0,
      sound: streams.any((s) => s['codec_type'] == 'audio'),
    );
  }

  /// [count] frames spread evenly across [path], each at most [width] wide.
  Future<List<Frame>> frames(String path, {int count = 12, int width = 768}) async {
    final ffmpeg = await _tool('ffmpeg');
    final info = await probe(path);
    if (ffmpeg == null || info == null || info.length == Duration.zero) return const [];
    final dir = _workFor(path);
    final ms = info.length.inMilliseconds;
    final out = <Frame>[];
    // A few at a time: each is one quick seek and one picture.
    for (var start = 0; start < count; start += 4) {
      final batch = [
        for (var i = start; i < count && i < start + 4; i++)
          () async {
            final at = Duration(milliseconds: (ms * (i + .5) / count).round());
            final file = '${dir.path}/w$width-$count-$i.jpg';
            if (!File(file).existsSync()) {
              await Process.run(ffmpeg, [
                '-v', 'error', '-ss', '${at.inMilliseconds / 1000}', '-i', path, //
                '-frames:v', '1', '-vf', 'scale=$width:-2', '-q:v', '4', '-y', file,
              ]);
            }
            return File(file).existsSync() ? (at: at, path: file) : null;
          }(),
      ];
      out.addAll((await Future.wait(batch)).nonNulls);
    }
    return out;
  }

  /// What is said in [path], in pieces with where each starts; null when the
  /// words cannot be made out here, with the reason.
  Future<({String? text, String? reason})> listen(String path, Duration length) async {
    final ffmpeg = await _tool('ffmpeg');
    if (ffmpeg == null) return (text: null, reason: 'ffmpeg is not installed');
    final dir = _workFor(path);
    final whisper = await _tool('whisper-cli');
    final onMac = Platform.isMacOS;
    if (!onMac && whisper == null) {
      return (text: null, reason: 'no speech recognizer here (install whisper-cli for one)');
    }
    // Pieces of 50 seconds: each recognized on its own, and stamped with
    // where it starts.
    const piece = 50;
    final pieces = (length.inSeconds / piece).ceil().clamp(1, 120);
    final said = StringBuffer();
    for (var i = 0; i < pieces; i++) {
      final wav = '${dir.path}/sound-$i.wav';
      if (!File(wav).existsSync()) {
        await Process.run(ffmpeg, [
          '-v', 'error', '-ss', '${i * piece}', '-t', '$piece', '-i', path, //
          '-vn', '-ac', '1', '-ar', '16000', '-y', wav,
        ]);
      }
      if (!File(wav).existsSync()) continue;
      String? text;
      try {
        if (onMac) {
          text = await _channel.invokeMethod<String>('transcribe', {'path': wav});
        } else {
          final r = await Process.run(whisper!, ['-nt', '-f', wav]);
          text = r.exitCode == 0 ? '${r.stdout}'.trim() : null;
        }
      } on PlatformException catch (e) {
        return (text: null, reason: e.message ?? 'speech recognition failed');
      } on MissingPluginException {
        return (text: null, reason: 'no speech recognizer here');
      }
      if (text != null && text.trim().isNotEmpty) {
        final m = i * piece ~/ 60, s = i * piece % 60;
        said.writeln('[$m:${s.toString().padLeft(2, '0')}] ${text.trim()}');
      }
    }
    final all = said.toString().trim();
    return (text: all.isEmpty ? '(no words could be made out)' : all, reason: null);
  }

  /// Watches [path]: frames across it (more for a longer one, up to
  /// [maxFrames]) and, when it has sound, its words.
  Future<Watched?> watch(String path, {int maxFrames = 16}) async {
    final info = await probe(path);
    if (info == null) return null;
    // About one every 5 seconds, at least 6, at most maxFrames.
    final count = (info.length.inSeconds / 5).round().clamp(6, maxFrames);
    final shots = frames(path, count: count);
    final words = info.sound
        ? listen(path, info.length)
        : Future.value((text: null, reason: null) as ({String? text, String? reason}));
    final (pictures, heard) = await (shots, words).wait;
    return Watched(
      length: info.length,
      width: info.width,
      height: info.height,
      frames: pictures,
      hasSound: info.sound,
      transcript: heard.text,
      heard: heard.reason,
    );
  }
}
