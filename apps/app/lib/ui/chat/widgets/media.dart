import 'dart:async';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../utils/format.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../../utils/platform.dart';
import 'player.dart';
import '../../core/file_actions.dart';

/// What an answer shows (`![words](where)`), by what it is.
enum MediaKind {
  /// Drawn inline.
  image,

  /// Played inline.
  video,
  audio,

  /// Read inline in a web view: a PDF, an HTML or SVG file, plain text.
  document,

  /// Previewed by Quick Look as a picture of its first page: a Word, Excel,
  /// PowerPoint, Pages, Numbers or Keynote file.
  quickLook,

  /// A web page, or a running app on this Mac: offered beside the
  /// conversation.
  page,
}

const _image = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'tif', 'tiff'};
const _video = {'mp4', 'mov', 'm4v'};
const _audio = {'mp3', 'm4a', 'wav', 'aac', 'aif', 'aiff', 'caf', 'flac'};
const _document = {'pdf', 'html', 'htm', 'svg', 'txt'};
const _quickLook = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'pages', 'numbers', 'key', 'rtf'};

/// Where a shown thing is: a file on this Mac (a full path, `~/`, `file://`,
/// or relative to [cwd]), or a web address.
({String? path, Uri? web}) locate(String where, String cwd) {
  final w = where.trim();
  if (w.startsWith('http://') || w.startsWith('https://')) {
    return (path: null, web: Uri.tryParse(w));
  }
  var path = w.startsWith('file://') ? Uri.decodeFull(w.substring(7)) : w;
  if (path.startsWith('~/')) path = '$homeDir${path.substring(1)}';
  if (!path.startsWith('/')) path = '$cwd/$path';
  return (path: path, web: null);
}

/// What [where] is, by its extension; a web address without one is a page.
/// Null for a file of a kind Helmy does not show.
MediaKind? kindOf(String where) {
  final w = where.trim();
  final bare = w.split(RegExp('[?#]')).first;
  final dot = bare.lastIndexOf('.');
  final slash = bare.lastIndexOf('/');
  final ext = dot > slash ? bare.substring(dot + 1).toLowerCase() : '';
  if (_image.contains(ext)) return .image;
  if (_video.contains(ext)) return .video;
  if (_audio.contains(ext)) return .audio;
  if (_document.contains(ext)) return .document;
  if (_quickLook.contains(ext)) return .quickLook;
  if (w.startsWith('http://') || w.startsWith('https://')) return .page;
  return null;
}

/// One shown thing in an answer: [where] it is and the [words] for it. A file
/// that is not there says so, rather than showing as broken.
class Media extends StatelessWidget {
  const Media({
    super.key,
    required this.where,
    required this.words,
    required this.cwd,
    required this.actions,
  });

  final String where;
  final String words;
  final String cwd;

  /// What it may do: open, reveal, preview beside the conversation, and the
  /// pictures of documents and videos. The screen's view model.
  final MediaActions actions;

  @override
  Widget build(BuildContext context) {
    final kind = kindOf(where);
    final at = locate(where, cwd);
    if (kind == null) {
      return _Missing(words: words, where: where, reason: 'Not something I can show');
    }
    if (at.path != null && !File(at.path!).existsSync()) {
      return _Missing(words: words, where: tildePath(at.path!), reason: 'Not found');
    }
    // Where this platform cannot play or read it in place (a player and a
    // web view are not on every one), it opens in its own app instead.
    final inPlace = switch (kind) {
      .video || .audio => playerHere,
      .document => webViewHere,
      _ => true,
    };
    final body = !inPlace
        ? _Elsewhere(kind: kind, words: words)
        : switch (kind) {
            .image => _Picture(path: at.path, web: at.web, words: words),
            .video => Player(
              path: at.path,
              web: at.web,
              words: words,
              video: true,
              actions: actions,
            ),
            .audio => Player(
              path: at.path,
              web: at.web,
              words: words,
              video: false,
              actions: actions,
            ),
            .document => _Document(path: at.path, web: at.web),
            .quickLook => _QuickLook(path: at.path!, actions: actions),
            .page => _PageCard(
              url: at.web!,
              words: words,
              onPreview: webViewHere ? actions.preview : null,
              actions: actions,
            ),
          };
    if (kind == .page) return body;
    return Column(
      crossAxisAlignment: .start,
      spacing: 6,
      children: [
        body,
        _Caption(
          actions: actions,
          words: words,
          path: at.path,
          web: at.web,
          onPreview: kind == .document && webViewHere
              ? () => actions.preview(at.web?.toString() ?? Uri.file(at.path!).toString())
              : null,
        ),
      ],
    );
  }
}

/// The words for a shown thing, and what can be done with it.
class _Caption extends StatelessWidget {
  const _Caption({required this.words, required this.actions, this.path, this.web, this.onPreview});
  final FileActions actions;
  final String words;
  final String? path;
  final Uri? web;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final desktop = actions;
    return Row(
      spacing: 4,
      children: [
        Flexible(
          child: Text(
            words.isNotEmpty ? words : (path != null ? tildePath(path!) : '$web'),
            maxLines: 1,
            overflow: .ellipsis,
            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
          ),
        ),
        if (onPreview != null)
          Button(
            variant: .ghost,
            size: .xs,
            onPressed: onPreview,
            child: const Text('Open beside'),
          ),
        if (path != null) ...[
          Button(
            variant: .ghost,
            size: .xs,
            onPressed: () => desktop.open(path!),
            child: const Text('Open'),
          ),
          Button(
            variant: .ghost,
            size: .xs,
            onPressed: () => desktop.reveal(path!),
            child: Text('Show in ${Desktop.current.fileManager}'),
          ),
        ] else if (web != null)
          Button(
            variant: .ghost,
            size: .xs,
            onPressed: () => desktop.open('$web'),
            child: const Text('Open in browser'),
          ),
      ],
    );
  }
}

/// A frame for what is shown: rounded, bordered, at most [maxHeight] tall.
class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.maxHeight = 360, this.height});
  final Widget child;
  final double maxHeight;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      height: height,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: ClipRRect(borderRadius: .circular(t.radiusLg - 1), child: child),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({this.path, this.web, required this.words});
  final String? path;
  final Uri? web;
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    Widget broken(BuildContext context, Object _, StackTrace? _) => Padding(
      padding: const .all(12),
      child: Text(
        "This picture couldn't be shown.",
        style: t.text.sm.copyWith(color: t.colors.mutedForeground),
      ),
    );
    return Semantics(
      image: true,
      label: words,
      child: _Frame(
        child: path != null
            ? Image.file(File(path!), fit: .contain, errorBuilder: broken)
            : Image.network('$web', fit: .contain, errorBuilder: broken),
      ),
    );
  }
}

/// A PDF, an HTML or SVG file, or plain text, read in place.
class _Document extends StatefulWidget {
  const _Document({this.path, this.web});
  final String? path;
  final Uri? web;

  @override
  State<_Document> createState() => _DocumentState();
}

class _DocumentState extends State<_Document> {
  late final _c = WebViewController();

  @override
  void initState() {
    super.initState();
    unawaited(widget.path != null ? _c.loadFile(widget.path!) : _c.loadRequest(widget.web!));
  }

  @override
  Widget build(BuildContext context) =>
      _Frame(height: 420, maxHeight: 420, child: WebViewWidget(controller: _c));
}

/// A picture of an office document's first page, by Quick Look.
class _QuickLook extends StatelessWidget {
  const _QuickLook({required this.path, required this.actions});
  final String path;
  final MediaActions actions;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return FutureBuilder(
      future: actions.documentPicture(path),
      builder: (context, snap) {
        if (snap.connectionState != .done) {
          return const _Frame(height: 48, child: Center(child: Spinner(size: 16)));
        }
        final picture = snap.data;
        if (picture == null) {
          return _Frame(
            child: Padding(
              padding: const .all(12),
              child: Text(
                'No preview of this one. Open it to read it.',
                style: t.text.sm.copyWith(color: t.colors.mutedForeground),
              ),
            ),
          );
        }
        return _Frame(child: Image.file(File(picture), fit: .contain));
      },
    );
  }
}

/// A web page, or an app running on this Mac: what it is, and the way to open
/// it beside the conversation.
class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.url,
    required this.words,
    required this.onPreview,
    required this.actions,
  });
  final FileActions actions;
  final Uri url;
  final String words;

  /// Opens it beside the conversation; null where there is no web view, and
  /// it opens in the browser instead.
  final ValueChanged<String>? onPreview;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final local = const {'localhost', '127.0.0.1', '0.0.0.0'}.contains(url.host);
    return Container(
      padding: const .all(12),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Row(
        spacing: 12,
        children: [
          AshlarIcon(
            local ? AshlarIconsRoundedStroke.appWindow : AshlarIconsRoundedStroke.globe,
            size: 18,
            color: t.colors.mutedForeground,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  words.isNotEmpty
                      ? words
                      : (local ? 'Your app, running on ${Desktop.current.thisComputer}' : url.host),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: t.text.sm.copyWith(fontWeight: .w500),
                ),
                Text(
                  '$url',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                ),
              ],
            ),
          ),
          Button(
            variant: .outline,
            size: .sm,
            onPressed: onPreview != null ? () => onPreview!('$url') : () => actions.open('$url'),
            child: Text(onPreview != null ? 'Open beside' : 'Open in browser'),
          ),
        ],
      ),
    );
  }
}

/// A video, sound or document this platform cannot play or read in place:
/// what it is, with Open below it (in the caption).
class _Elsewhere extends StatelessWidget {
  const _Elsewhere({required this.kind, required this.words});
  final MediaKind kind;
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return _Frame(
      child: Padding(
        padding: const .all(12),
        child: Row(
          spacing: 10,
          children: [
            AshlarIcon(
              switch (kind) {
                .video => AshlarIconsRoundedStroke.video,
                .audio => AshlarIconsRoundedStroke.volume2,
                _ => AshlarIconsRoundedStroke.fileText,
              },
              size: 18,
              color: t.colors.mutedForeground,
            ),
            Expanded(
              child: Text(switch (kind) {
                .video => 'A video. Open it to play it.',
                .audio => 'A sound. Open it to play it.',
                _ => 'A document. Open it to read it.',
              }, style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown for something that cannot be: [reason], and where it was said to be.
class _Missing extends StatelessWidget {
  const _Missing({required this.words, required this.where, required this.reason});
  final String words;
  final String where;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Text(
      '$reason: ${words.isNotEmpty ? '$words, ' : ''}$where',
      style: t.text.sm.copyWith(color: t.colors.mutedForeground),
    );
  }
}
