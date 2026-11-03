// Ashlar UI: Context Menu. Copied into your app by `ashlar add context-menu`; it is yours to
// change.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dropdown_menu.dart';
import 'popover.dart';

/// A menu that opens where [child] is right-clicked or long-pressed, or from the keyboard
/// with the menu key or Shift+F10 while something inside it has focus. Takes the same
/// items as a DropdownMenu. Text inside it cannot be selected: a right-click there is for
/// the menu. On the web it turns the browser's own menu off while shown,
/// when the app fills the page; a page that embeds Flutter in part of it must turn the
/// browser's menu off itself there.
///
/// ```dart
/// ContextMenu(
///   items: [
///     MenuItem(onPressed: back, shortcut: Text('⌘['), child: Text('Back')),
///     MenuItem(onPressed: reload, shortcut: Text('⌘R'), child: Text('Reload')),
///   ],
///   child: Container(height: 150, child: Center(child: Text('Right-click here'))),
/// )
/// ```
class ContextMenu extends StatefulWidget {
  const ContextMenu({
    super.key,
    required this.child,
    required this.items,
    this.width = 224,
  });

  /// What is right-clicked or long pressed to open the menu.
  final Widget child;

  /// [MenuItem], [MenuLabel] and [MenuSeparator], in order.
  final List<Widget> items;

  /// Its width, in logical pixels.
  final double width;

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

/// How many context menus are on screen, so the browser's menu comes back with the last.
int _shown = 0;

class _ContextMenuState extends State<ContextMenu> {
  final _menu = MenuController();

  @override
  void initState() {
    super.initState();
    // Flutter embedded in a page (a view, not the whole page) cannot turn the browser's
    // menu off and says so with an error; the menu still opens, so the error is dropped.
    if (kIsWeb && _shown++ == 0) {
      BrowserContextMenu.disableContextMenu().catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    if (kIsWeb && --_shown == 0) {
      BrowserContextMenu.enableContextMenu().catchError((Object _) {});
    }
    super.dispose();
  }

  void _openAt(Offset at) => _menu.open(position: at);

  @override
  Widget build(BuildContext context) => RawMenuAnchor(
    controller: _menu,
    overlayBuilder: (context, info) => PopoverPanel(
      info: info,
      width: widget.width,
      child: MenuList(children: widget.items),
    ),
    child: Builder(
      builder: (context) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.contextMenu): _OpenIntent(),
          SingleActivator(LogicalKeyboardKey.f10, shift: true): _OpenIntent(),
        },
        child: Actions(
          actions: {
            _OpenIntent: CallbackAction<_OpenIntent>(
              onInvoke: (_) {
                final box = context.findRenderObject()! as RenderBox;
                _openAt(box.size.center(Offset.zero));
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (d) => _openAt(d.localPosition),
            onLongPressStart: (d) => _openAt(d.localPosition),
            // A right-click or long press here is for the menu, so the text under it is
            // not selected as well.
            child: SelectionContainer.disabled(child: widget.child),
          ),
        ),
      ),
    ),
  );
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}
