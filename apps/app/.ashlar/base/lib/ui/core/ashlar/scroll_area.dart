// Ashlar UI: Scroll Area. Copied into your app by `ashlar add scroll-area`; it is yours to
// change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Scrolls [child] with a thin scrollbar in the theme's colours, shown while the pointer
/// is over it and while it scrolls, in place of the platform's.
///
/// With [child], everything in it is built at once: right for a page or a short list.
/// For a long list use [ScrollArea.builder], which builds only the rows on screen.
///
/// ```dart
/// SizedBox(height: 300, child: ScrollArea(child: Column(children: tags)))
/// ```
class ScrollArea extends StatefulWidget {
  const ScrollArea({
    super.key,
    required Widget this.child,
    this.axis = Axis.vertical,
    this.controller,
    this.padding,
  }) : itemCount = null,
       itemBuilder = null,
       itemExtent = null;

  /// A long list, built a row at a time as it scrolls into view: only what is on screen
  /// exists. Use it for anything that can run to hundreds of rows. [itemExtent], when
  /// every row is one height, makes scrolling a long way cheaper still.
  ///
  /// ```dart
  /// ScrollArea.builder(itemCount: orders.length, itemExtent: 40, itemBuilder: (context, i) => OrderRow(orders[i]))
  /// ```
  const ScrollArea.builder({
    super.key,
    required int this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
    this.itemExtent,
    this.axis = Axis.vertical,
    this.controller,
    this.padding,
  }) : child = null;

  /// What scrolls.
  final Widget? child;

  /// How many items there are, for a list built as it scrolls.
  final int? itemCount;

  /// Builds an item, by its number.
  final IndexedWidgetBuilder? itemBuilder;

  /// Each item's height, when they are all the same: faster to scroll.
  final double? itemExtent;

  /// Horizontal lays it out across; vertical, down.
  final Axis axis;

  /// Its scroll position, to read or move from outside.
  final ScrollController? controller;

  /// Room around the content, inside the scrolling.
  final EdgeInsetsGeometry? padding;

  @override
  State<ScrollArea> createState() => _ScrollAreaState();
}

class _ScrollAreaState extends State<ScrollArea> {
  ScrollController? _own;
  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());
  bool _hovered = false;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ScrollConfiguration(
        // The platform's own scrollbar is replaced by the one below.
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: RawScrollbar(
          controller: _controller,
          thumbVisibility: _hovered,
          thumbColor: c.border,
          thickness: 8,
          radius: const Radius.circular(4),
          crossAxisMargin: 1,
          mainAxisMargin: 1,
          interactive: true,
          child: widget.itemBuilder == null
              ? SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: widget.axis,
                  padding: widget.padding,
                  child: widget.child,
                )
              : ListView.builder(
                  controller: _controller,
                  scrollDirection: widget.axis,
                  padding: widget.padding,
                  itemCount: widget.itemCount,
                  itemExtent: widget.itemExtent,
                  itemBuilder: widget.itemBuilder!,
                ),
        ),
      ),
    );
  }
}
