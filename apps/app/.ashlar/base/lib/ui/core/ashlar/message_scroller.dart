// Ashlar UI: Message Scroller. Copied into your app by `ashlar add message-scroller`; it is
// yours to change.
//
// A conversation's scrolling, built on CustomScrollView from Flutter's widgets layer. It
// never moves the reader against their intent: a new turn starts near the top with room
// below for the answer to grow into, it follows a streamed answer only while the reader is
// at the end, and older messages loaded above do not move what is on screen.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'button.dart';

/// Where a [MessageScroller] opens.
enum MessageScrollStart {
  /// At the first message.
  start,

  /// At the very end.
  end,

  /// At the last anchored turn, with what came after it below: where a reader left off.
  /// The end when there is no anchor, or when the last turn fits on screen.
  lastAnchor,
}

/// A row of a [MessageScroller]: a message, a marker, a typing indicator.
@immutable
class MessageScrollerItem {
  const MessageScrollerItem({
    required this.id,
    required this.child,
    this.anchor = false,
  });

  /// Stays the same for the same row, so the scroller can find it and keep its place.
  final Object id;

  /// The row: a message, a marker, a typing indicator.
  final Widget child;

  /// Starts a turn: when one is added, it is brought near the top of the view, and the
  /// rows after it fill in below. Usually what the person sent.
  final bool anchor;
}

/// Moves a [MessageScroller] from outside it, and tells what it shows.
class MessageScrollerController extends ChangeNotifier {
  _MessageScrollerState? _state;

  /// Whether there is more to see above, or below.
  bool get canScrollStart => _state?._canStart ?? false;
  bool get canScrollEnd => _state?._canEnd ?? false;

  /// The anchored turn being read: the last one that has reached the top of the view.
  Object? get currentAnchor => _state?._currentAnchor;

  /// The rows on screen, top to bottom.
  List<Object> get visible => _state?._visible ?? const [];

  /// To the latest, and follows from there.
  void scrollToEnd() => _state?._toEnd(animate: true);

  void scrollToStart() => _state?._toStart();

  /// Brings the row with [id] to the top. False when there is no such row.
  bool scrollToMessage(Object id) => _state?._toMessage(id) ?? false;

  void _changed() => notifyListeners();
}

/// A conversation that scrolls the way people expect: [items] top to bottom, newest last.
///
/// ```dart
/// MessageScroller(
///   busy: streaming,
///   items: [
///     for (final m in messages)
///       MessageScrollerItem(id: m.id, anchor: m.fromMe, child: Message(...)),
///   ],
/// )
/// ```
class MessageScroller extends StatefulWidget {
  const MessageScroller({
    super.key,
    required this.items,
    this.controller,
    this.start = MessageScrollStart.lastAnchor,
    this.followEnd = true,
    this.previousPeek = 64,
    this.busy = false,
    this.gap = 32,
    this.padding = const EdgeInsets.all(16),
    this.showButton = true,
    this.semanticLabel = 'Messages',
  });

  /// The rows, oldest first.
  final List<MessageScrollerItem> items;

  /// Moves it from outside, and tells what it shows.
  final MessageScrollerController? controller;

  /// Where it opens: the start, the end, or the last anchored turn.
  final MessageScrollStart start;

  /// While the reader is at the end, it stays at the end as an answer grows. Scrolling away
  /// lets go; coming back, or the button, takes hold again.
  final bool followEnd;

  /// How much of the row before a new turn stays in view above it, so the conversation
  /// reads on rather than starting over.
  final double previousPeek;

  /// True while an answer streams in: screen readers hear it once it is finished, not
  /// word by word.
  final bool busy;

  /// Space between rows.
  final double gap;

  /// Room around the rows, inside the scrolling.
  final EdgeInsets padding;

  /// A button to the end, shown when there is more below.
  final bool showButton;

  /// What a screen reader calls the conversation.
  final String semanticLabel;

  @override
  State<MessageScroller> createState() => _MessageScrollerState();
}

class _MessageScrollerState extends State<MessageScroller> {
  final _scroll = ScrollController();
  final _keys = <Object, GlobalKey>{};
  final _centre = UniqueKey();

  /// The first row when the scroller opened. Rows put before it later grow upwards, so
  /// loading older messages leaves the view where it was.
  late Object? _first = widget.items.firstOrNull?.id;

  var _placed = false;
  var _following = true;

  /// While a new turn settles near the top: where it scrolls to, and the room kept below.
  double? _anchorAt;
  var _room = 0.0;

  var _canStart = false, _canEnd = false;
  Object? _currentAnchor;
  var _visible = const <Object>[];

  GlobalKey _key(Object id) => _keys.putIfAbsent(id, GlobalKey.new);

  ScrollPosition? get _position => _scroll.hasClients ? _scroll.position : null;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void didUpdateWidget(MessageScroller old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller!._state = null;
      widget.controller?._state = this;
    }
    final ids = {for (final i in widget.items) i.id};
    _keys.removeWhere((id, _) => !ids.contains(id));
    if (_first == null || !ids.contains(_first)) {
      _first = widget.items.firstOrNull?.id;
    }
    // A turn added at the end: bring it near the top once it is laid out.
    final before = {for (final i in old.items) i.id};
    final added = widget.items.where((i) => !before.contains(i.id)).toList();
    final anchor = added.lastWhere(
      (i) => i.anchor,
      orElse: () => const MessageScrollerItem(id: _none, child: SizedBox()),
    );
    if (anchor.id != _none &&
        widget.items.isNotEmpty &&
        widget.items.indexOf(anchor) >= widget.items.length - added.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _anchor(anchor.id));
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller!._state = null;
    _scroll.dispose();
    super.dispose();
  }

  /// The top of row [id] as a scroll offset, when it is built.
  double? _offsetOf(Object id) {
    final box = _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final position = _position;
    if (box == null || !box.attached || position == null) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset;
  }

  double? _heightOf(Object id) =>
      (_keys[id]?.currentContext?.findRenderObject() as RenderBox?)
          ?.size
          .height;

  void _open({bool again = false}) {
    final position = _position;
    if (!mounted || position == null) return;
    switch (widget.start) {
      case MessageScrollStart.start:
        position.jumpTo(position.minScrollExtent);
        _following = position.maxScrollExtent <= position.minScrollExtent;
      case MessageScrollStart.end:
        position.jumpTo(position.maxScrollExtent);
      case MessageScrollStart.lastAnchor:
        final last = widget.items.lastWhere(
          (i) => i.anchor,
          orElse: () => const MessageScrollerItem(id: _none, child: SizedBox()),
        );
        if (last.id == _none) {
          position.jumpTo(position.maxScrollExtent);
          break;
        }
        var at = _offsetOf(last.id);
        if (at == null && !again) {
          // Not built where the list starts: go to the end, near it, and look again.
          position.jumpTo(position.maxScrollExtent);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _open(again: true),
          );
          return;
        }
        at ??= position.maxScrollExtent;
        final fromAnchor =
            position.maxScrollExtent + position.viewportDimension - at;
        if (fromAnchor <= position.viewportDimension) {
          position.jumpTo(position.maxScrollExtent);
        } else {
          final index = widget.items.indexOf(last);
          final before = index > 0
              ? _heightOf(widget.items[index - 1].id) ?? 0
              : 0;
          final peek = before < widget.previousPeek
              ? before
              : widget.previousPeek;
          position.jumpTo(
            (at - peek - (index > 0 ? widget.gap : 0)).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
          _following = false;
        }
    }
    setState(() => _placed = true);
    _measure();
  }

  /// Brings a new turn near the top, keeping a slice of the row before it in view, and
  /// keeps room below it for what follows.
  void _anchor(Object id, [int tries = 0]) {
    final position = _position;
    if (!mounted || position == null) return;
    final at = _offsetOf(id);
    if (at == null) {
      // Below a long answer the new turn is not laid out yet: go to the end, where it is,
      // and place it once it is.
      if (tries < 3) {
        position.jumpTo(position.maxScrollExtent);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _anchor(id, tries + 1),
        );
      }
      return;
    }
    final index = widget.items.indexWhere((i) => i.id == id);
    final before = index > 0 ? _heightOf(widget.items[index - 1].id) ?? 0 : 0;
    final peek = before < widget.previousPeek ? before : widget.previousPeek;
    final target = (at - peek - (index > 0 ? widget.gap : 0)).clamp(
      position.minScrollExtent,
      double.infinity,
    );
    _anchorAt = target;
    _following = true;
    _fitRoom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = _position;
      if (!mounted || p == null || _anchorAt == null) return;
      p.animateTo(
        _anchorAt!.clamp(p.minScrollExtent, p.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// The room below a new turn: enough that it can sit near the top, shrinking as the
  /// answer fills it, gone once the answer is longer than the view.
  void _fitRoom() {
    final position = _position;
    final at = _anchorAt;
    if (position == null || at == null) return;
    final content =
        position.maxScrollExtent + position.viewportDimension - _room;
    final room = (at + position.viewportDimension - content).clamp(
      0.0,
      double.infinity,
    );
    if ((room - _room).abs() > .5) setState(() => _room = room);
    if (room == 0) _anchorAt = null;
  }

  bool _atEnd(ScrollMetrics m) => m.pixels >= m.maxScrollExtent - 2;

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth != 0) return false;
    _fitRoom();
    // Still at the end while an answer grows: stay there.
    if (_placed && widget.followEnd && _following && _anchorAt == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final p = _position;
        if (mounted && p != null && !_atEnd(p)) p.jumpTo(p.maxScrollExtent);
      });
    }
    _measureSoon();
    return false;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    // Dragged, wheeled or flung by the reader, not moved by the scroller itself.
    final byReader =
        n is UserScrollNotification ||
        (n is ScrollUpdateNotification &&
            _position?.userScrollDirection != ScrollDirection.idle);
    if (byReader) {
      // The reader moved: follow only if they came back to the end.
      _following = _atEnd(n.metrics);
      if (!_following) _anchorAt = null;
    }
    if (n is ScrollEndNotification && _atEnd(n.metrics)) _following = true;
    _measureSoon();
    return false;
  }

  var _measuring = false;

  /// Measures once the frame is laid out: rows come and go while it is.
  void _measureSoon() {
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (mounted) _measure();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// What can be scrolled to, which rows show, and which turn is being read.
  void _measure() {
    final position = _position;
    if (position == null || !position.hasContentDimensions) return;
    final canStart = position.pixels > position.minScrollExtent + 2;
    final canEnd = position.pixels < position.maxScrollExtent - 8;
    final visible = <Object>[];
    Object? anchor;
    for (final item in widget.items) {
      final at = _offsetOf(item.id), height = _heightOf(item.id);
      if (at == null || height == null) continue;
      if (item.anchor && at <= position.pixels + 1) anchor = item.id;
      if (at + height > position.pixels &&
          at < position.pixels + position.viewportDimension) {
        visible.add(item.id);
      }
    }
    if (canStart != _canStart ||
        canEnd != _canEnd ||
        anchor != _currentAnchor ||
        !_same(visible, _visible)) {
      final repaint = canEnd != _canEnd;
      _canStart = canStart;
      _canEnd = canEnd;
      _currentAnchor = anchor;
      _visible = visible;
      if (repaint && mounted) setState(() {});
      widget.controller?._changed();
    }
  }

  static bool _same(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _toEnd({required bool animate}) {
    final position = _position;
    if (position == null) return;
    _following = true;
    _anchorAt = null;
    if (_room > 0) setState(() => _room = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = _position;
      if (p == null) return;
      if (animate) {
        p.animateTo(
          p.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } else {
        p.jumpTo(p.maxScrollExtent);
      }
    });
  }

  void _toStart() {
    final position = _position;
    if (position == null) return;
    _following = false;
    _anchorAt = null;
    position.animateTo(
      position.minScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  bool _toMessage(Object id, [int tries = 0]) {
    final index = widget.items.indexWhere((i) => i.id == id);
    final position = _position;
    if (index < 0 || position == null) return false;
    // An explicit jump lets go of the end.
    _following = false;
    _anchorAt = null;
    final at = _offsetOf(id);
    if (at != null) {
      position.animateTo(
        at.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return true;
    }
    // Not built yet: go about where it is, then again once it is.
    if (tries < 4) {
      final firstAt = widget.items.indexWhere((i) => i.id == _first);
      final share = widget.items.length < 2
          ? 0.0
          : index / (widget.items.length - 1);
      final guess = firstAt <= 0
          ? position.minScrollExtent +
                share * (position.maxScrollExtent - position.minScrollExtent)
          : (index < firstAt
                ? position.minScrollExtent * (1 - index / firstAt)
                : position.maxScrollExtent *
                      ((index - firstAt) /
                          (widget.items.length - firstAt).clamp(1, 1 << 30)));
      position.jumpTo(
        guess.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _toMessage(id, tries + 1),
      );
    }
    return true;
  }

  Widget _row(MessageScrollerItem item, {required bool last}) => Padding(
    key: _key(item.id),
    padding: EdgeInsets.only(bottom: last ? 0 : widget.gap),
    // The newest row is heard when it arrives, once it has finished streaming.
    child: last
        ? Semantics(
            container: true,
            liveRegion: !widget.busy,
            child: item.child,
          )
        : item.child,
  );

  void _keyScroll(double by) {
    final p = _position;
    if (p == null) return;
    _following = false;
    p.animateTo(
      (p.pixels + by).clamp(p.minScrollExtent, p.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final split = items.indexWhere((i) => i.id == _first);
    final older = split <= 0
        ? const <MessageScrollerItem>[]
        : items.sublist(0, split);
    final newer = split <= 0 ? items : items.sublist(split);
    final page = _position?.viewportDimension ?? 400;
    final scroller = CustomScrollView(
      controller: _scroll,
      center: _centre,
      slivers: [
        // Older rows, grown upwards from the first one seen: nearest first.
        SliverPadding(
          padding: EdgeInsets.only(
            left: widget.padding.left,
            right: widget.padding.right,
            top: widget.padding.top,
          ),
          sliver: SliverList.builder(
            itemCount: older.length,
            itemBuilder: (context, i) =>
                _row(older[older.length - 1 - i], last: false),
          ),
        ),
        SliverPadding(
          key: _centre,
          padding: EdgeInsets.only(
            left: widget.padding.left,
            right: widget.padding.right,
            top: older.isEmpty ? widget.padding.top : 0,
            bottom: widget.padding.bottom,
          ),
          sliver: SliverList.builder(
            itemCount: newer.length,
            itemBuilder: (context, i) =>
                _row(newer[i], last: i == newer.length - 1),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: _room)),
      ],
    );
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      explicitChildNodes: true,
      child: FocusableActionDetector(
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              VoidCallbackIntent(() => _keyScroll(48)),
          const SingleActivator(LogicalKeyboardKey.arrowUp): VoidCallbackIntent(
            () => _keyScroll(-48),
          ),
          const SingleActivator(LogicalKeyboardKey.pageDown):
              VoidCallbackIntent(() => _keyScroll(page * .9)),
          const SingleActivator(LogicalKeyboardKey.pageUp): VoidCallbackIntent(
            () => _keyScroll(-page * .9),
          ),
          const SingleActivator(LogicalKeyboardKey.home): VoidCallbackIntent(
            _toStart,
          ),
          const SingleActivator(LogicalKeyboardKey.end): VoidCallbackIntent(
            () => _toEnd(animate: true),
          ),
        },
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: _onMetrics,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: Stack(
              children: [
                // Hidden until it is at its opening place, so it does not jump.
                Positioned.fill(
                  child: Opacity(opacity: _placed ? 1 : 0, child: scroller),
                ),
                if (widget.showButton)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: Center(
                      child: _EndButton(
                        shown: _canEnd,
                        onPressed: () => _toEnd(animate: true),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _none = Object();

/// The round button to the end: rises in when there is more below, out of the Tab order
/// and of what screen readers read when there is not.
class _EndButton extends StatelessWidget {
  const _EndButton({required this.shown, required this.onPressed});

  final bool shown;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !shown,
    child: ExcludeFocus(
      excluding: !shown,
      child: ExcludeSemantics(
        excluding: !shown,
        child: AnimatedSlide(
          offset: shown ? Offset.zero : const Offset(0, 1),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: shown ? 1 : .95,
              duration: const Duration(milliseconds: 200),
              child: Button(
                variant: ButtonVariant.outline,
                size: ButtonSize.iconSm,
                semanticLabel: 'Scroll to end',
                onPressed: onPressed,
                child: const AshlarIcon(AshlarIconsRoundedStroke.arrowDown),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
