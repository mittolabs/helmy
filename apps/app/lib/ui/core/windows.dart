// Flutter's windowing is experimental: its API is internal, and the stable
// channel will not turn it on, so Helmy does (see enable). Found in the spike
// recorded in Mittolabs' docs/notes/helmy-tab-windows-spike.md.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/src/foundation/_features.dart' as features;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/repositories/settings_repository.dart';
import '../../data/services/desktop_service.dart';
import '../chat/view_models/chat_view_model.dart';
import '../chat/widgets/chat_screen.dart' show panelTabBody, panelTabLabel;
import 'ashlar/app.dart';
import 'ashlar/button.dart';
import 'ashlar/theme.dart';
import 'ashlar/tooltip.dart';
import 'helmy_look.dart';
import 'window_web_view.dart';

/// Helmy's windows, all drawn by one engine with Flutter's windowing: the
/// main one, and any panel tab moved into a window of its own. One engine,
/// so every window shares the app's state as it is, and a tab moves between
/// them whole (its key): a terminal's shell, a page, a device carry on.
class HelmyWindows extends ChangeNotifier {
  /// Turns Flutter's windowing on, once the binding is up: the stable channel
  /// refuses its build flag, so its switch is set here, and the windowing
  /// owner made again with it on. Recheck after every Flutter update.
  /// Where tabs can have windows of their own: macOS, where it was tried.
  /// On Linux the experimental windowing fails before the first frame (a
  /// GLX error, found 2026-11-10), and Windows is untried: one ordinary
  /// window there, and no "Move to a new window".
  static bool get supported => Platform.isMacOS;

  static void enable() {
    if (!supported) return;
    features.isWindowingEnabled = true;
    WidgetsBinding.instance.windowingOwner = createDefaultWindowingOwner();
  }

  /// The main window, titled "Helmy": the runner finds it by that title and
  /// gives it Helmy's look (HelmyWindow in MainFlutterWindow.swift).
  late final main = WindowController(
    size: const Size(1200, 800),
    title: 'Helmy',
    delegate: _MainWindow(),
  );

  /// Tabs in windows of their own, oldest first.
  final List<TabWindow> tabs = [];

  /// The windows, for runWidget: the main one with the app in it, then each
  /// tab's.
  Widget build(Widget app) => ViewCollection(
    views: [
      Window(controller: main, child: app),
      for (final w in tabs)
        Window(
          key: ObjectKey(w),
          controller: w.controller,
          child: _TabWindowApp(window: w),
        ),
      for (final w in presents)
        Window(
          key: ObjectKey(w),
          controller: w.controller,
          child: _PresentWindowApp(window: w),
        ),
    ],
  );

  /// Design screens presented in windows of their own, oldest first.
  final List<PresentWindow> presents = [];

  /// Presents a design's screen in a window of its own: [url] is the canvas
  /// in its present mode, showing that screen and nothing else (Present, as
  /// Figma's opens a tab of its own). No browser bar: the screen is all there is.
  ///
  /// [device] (phone, tablet, desktop) keeps each its own place and size,
  /// as the Mac puts it back; [size] is held to the display.
  void present(Uri url, {required String title, required Size size, required String device}) {
    if (!supported) return;
    final display = WidgetsBinding.instance.platformDispatcher.displays.firstOrNull;
    if (display != null) {
      final room = display.size / display.devicePixelRatio;
      size = Size(
        size.width.clamp(360, room.width * 0.92),
        size.height.clamp(480, room.height * 0.9),
      );
    }
    final w = PresentWindow._(url: url, title: title);
    w.controller = WindowController(size: size, title: title, delegate: _PresentClosed(this, w));
    presents.add(w);
    // Once made: a Mac window like any (full screen, Split View, tiling).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Future<void>.delayed(
        const Duration(milliseconds: 60),
        () => DesktopService.tabWindowReady(title, atPointer: false, kind: 'present-$device'),
      ),
    );
    notifyListeners();
  }

  // A chat's view model, held while its page or a tab's window shows it: a
  // tab in a window outlives the page it came from, and the page, opened
  // again, finds the same model (its tabs, their state) rather than a new one.

  final _chats = <String, ({ChatViewModel vm, int holds})>{};

  /// [key]'s view model: the one held, else one made by [create]. Each hold
  /// is let go with [releaseChat].
  ChatViewModel holdChat(String key, ChatViewModel Function() create) {
    final kept = _chats[key];
    final vm = kept?.vm ?? create();
    _chats[key] = (vm: vm, holds: (kept?.holds ?? 0) + 1);
    return vm;
  }

  /// Lets go of one hold on [key]'s view model: disposed with the last.
  void releaseChat(String key) {
    final kept = _chats[key];
    if (kept == null) return;
    if (kept.holds > 1) {
      _chats[key] = (vm: kept.vm, holds: kept.holds - 1);
      return;
    }
    _chats.remove(key);
    kept.vm.dispose();
  }

  String? _keyOf(ChatViewModel vm) =>
      _chats.entries.where((e) => identical(e.value.vm, vm)).firstOrNull?.key;

  /// Moves [tab] of [vm]'s panel into a window of its own, beside the main
  /// one, titled with the tab and its chat.
  void moveOut(ChatViewModel vm, PanelTab tab, {bool atPointer = false}) {
    if (!supported) return;
    if (tab.windowed) return show(tab);
    final key = _keyOf(vm);
    if (key != null) holdChat(key, () => vm);
    final w = TabWindow._(vm: vm, tab: tab, chatKey: key);
    w.controller = WindowController(
      size: const Size(760, 620),
      title: w.title,
      delegate: _TabWindowClosed(this, w),
    );
    tab.windowed = true;
    tabs.add(w);
    // Once the window is made: a Mac window like any (full screen, Split
    // View, tiling), and, dragged out, where it was let go.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Future<void>.delayed(
        const Duration(milliseconds: 60),
        () => DesktopService.tabWindowReady(w.title, atPointer: atPointer, kind: tab.kind.name),
      ),
    );
    // The panel shows the next tab, or where this one went.
    vm.panelChanged();
    notifyListeners();
  }

  /// For looking while developing (HELMY_TAB_WINDOW): in the chat on
  /// screen, a tab of [kind] shown in the panel, then moved into a window of
  /// its own a few seconds later, as a person would; with [back], put back
  /// in the panel a few seconds after that.
  Future<void> moveOutForLook(SidePanel kind, {bool stay = false, bool back = false}) async {
    if (!supported) return;
    // Frames go on while Helmy is out of sight behind other windows, as
    // they would were it looked at.
    Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => SchedulerBinding.instance.scheduleForcedFrame(),
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    final vm = _chats.values.firstOrNull?.vm;
    if (vm == null) return;
    final tab = vm.show(kind);
    // HELMY_LOOK_URL: a page in it, for a Preview tab.
    if (Platform.environment['HELMY_LOOK_URL'] case final url? when kind == .preview) {
      vm.preview(url);
    }
    if (stay) return;
    await Future<void>.delayed(const Duration(seconds: 5));
    moveOut(vm, tab);
    if (!back) return;
    await Future<void>.delayed(const Duration(seconds: 5));
    putBack(tab);
  }

  /// Brings [tab]'s window to the front.
  void show(PanelTab tab) {
    for (final w in tabs) {
      if (identical(w.tab, tab)) w.controller.activate();
    }
  }

  /// Puts [tab] back in its chat's panel, and its window goes.
  void putBack(PanelTab tab) {
    final w = tabs.where((w) => identical(w.tab, tab)).firstOrNull;
    if (w == null) return;
    _drop(w);
    w.controller.destroy();
  }

  /// A presenting window closed: gone from the windows.
  void _dropPresent(PresentWindow w) {
    if (presents.remove(w)) notifyListeners();
  }

  /// [w] gone (put back, or its window closed): the tab is the panel's again.
  void _drop(TabWindow w) {
    if (!tabs.remove(w)) return;
    w.tab.windowed = false;
    w.vm.focus(w.tab);
    notifyListeners();
    final key = w.chatKey;
    // After this frame: the tab is drawn in the panel again first.
    if (key != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => releaseChat(key));
    }
  }

  @override
  void dispose() {
    for (final w in [...tabs]) {
      w.controller.destroy();
    }
    for (final w in [...presents]) {
      w.controller.destroy();
    }
    main.dispose();
    super.dispose();
  }
}

/// A panel tab in a window of its own.
class TabWindow {
  TabWindow._({required this.vm, required this.tab, required this.chatKey});
  final ChatViewModel vm;
  final PanelTab tab;

  /// The hold on [vm] this window has (HelmyWindows.holdChat).
  final String? chatKey;
  late final WindowController controller;

  /// "Terminal 1 · Connect Four": the tab, then its chat.
  String get title {
    final chat = vm.chatTitle ?? vm.session?.title ?? '';
    final tab = panelTabLabel(vm, this.tab);
    return chat.isEmpty ? tab : '$tab · $chat';
  }
}

/// The main window's close button: hidden while chats keep working (the Dock
/// icon brings it back), closed (and the app with it) when the setting is
/// off.
class _MainWindow with WindowControllerDelegate {
  @override
  void onWindowCloseRequested(WindowController controller) {
    if (DesktopService.keepRunning) {
      DesktopService.hideMainWindow();
    } else {
      controller.destroy();
    }
  }
}

/// A design's screen presented in a window of its own.
class PresentWindow {
  PresentWindow._({required this.url, required this.title});
  final Uri url;

  /// "Helmy site · Home": the design, then the screen.
  final String title;
  late final WindowController controller;
}

/// A presenting window closed: it is gone.
class _PresentClosed with WindowControllerDelegate {
  _PresentClosed(this.windows, this.window);
  final HelmyWindows windows;
  final PresentWindow window;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    windows._dropPresent(window);
  }
}

/// A presenting window: the screen, and nothing of Helmy around it.
class _PresentWindowApp extends StatefulWidget {
  const _PresentWindowApp({required this.window});
  final PresentWindow window;

  @override
  State<_PresentWindowApp> createState() => _PresentWindowAppState();
}

class _PresentWindowAppState extends State<_PresentWindowApp> {
  final _page = WebViewController();

  @override
  void initState() {
    super.initState();
    unawaited(_page.setJavaScriptMode(JavaScriptMode.unrestricted));
    // No setBackgroundColor: on macOS the WebKit plugin throws from it (setOpaque is
    // iOS only), which turned the whole window into an error. The black is drawn below.
    unawaited(_page.loadRequest(widget.window.url));
  }

  @override
  Widget build(BuildContext context) {
    final look = helmyLook(context.watch<SettingsRepository>().settings);
    return AshlarApp(
      title: widget.window.title,
      theme: look.light,
      darkTheme: look.dark,
      themeMode: look.mode,
      builder: look.builder,
      home: ColoredBox(
        color: const Color(0xFF000000),
        child: WindowWebView(controller: _page),
      ),
    );
  }
}

/// A tab's window closed: the tab goes back to its chat's panel.
class _TabWindowClosed with WindowControllerDelegate {
  _TabWindowClosed(this.windows, this.window);
  final HelmyWindows windows;
  final TabWindow window;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    windows._drop(window);
  }
}

/// A tab's window: Helmy's look (as the main window's, always), a bar with
/// the way back, and the tab as it was in the panel.
class _TabWindowApp extends StatelessWidget {
  const _TabWindowApp({required this.window});
  final TabWindow window;

  @override
  Widget build(BuildContext context) {
    final look = helmyLook(context.watch<SettingsRepository>().settings);
    return AshlarApp(
      title: window.title,
      theme: look.light,
      darkTheme: look.dark,
      themeMode: look.mode,
      builder: look.builder,
      home: ListenableBuilder(
        listenable: window.vm,
        builder: (context, _) {
          final t = AshlarTheme.of(context);
          return ColoredBox(
            color: t.colors.background,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Container(
                  height: 40,
                  padding: const .symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.colors.border)),
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      // Its grip: dragged back over Helmy's window, the tab
                      // goes home to its chat's panel.
                      Draggable<PanelTab>(
                        data: window.tab,
                        feedback: _Grip(label: window.title, lifted: true),
                        childWhenDragging: const _Grip(label: ''),
                        onDragEnd: (_) async {
                          if (await DesktopService.pointerOverMain() && context.mounted) {
                            context.read<HelmyWindows>().putBack(window.tab);
                          }
                        },
                        child: const _Grip(label: ''),
                      ),
                      Expanded(
                        child: Text(
                          window.title,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: t.text.sm.copyWith(fontWeight: .w500),
                        ),
                      ),
                      Button(
                        variant: .ghost,
                        size: .sm,
                        leading: const AshlarIcon(AshlarIconsRoundedStroke.panelRight, size: 14),
                        onPressed: () => context.read<HelmyWindows>().putBack(window.tab),
                        child: const Text('Put back'),
                      ),
                    ],
                  ),
                ),
                Expanded(child: panelTabBody(window.vm, window.tab, active: true)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// What a tab's window is dragged back by: its handle, and while dragging,
/// the tab's name riding with the pointer.
class _Grip extends StatelessWidget {
  const _Grip({required this.label, this.lifted = false});
  final String label;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final handle = Tooltip(
      message: 'Drag onto Helmy to put it back',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: const .all(4),
          child: AshlarIcon(
            AshlarIconsRoundedStroke.gripVertical,
            size: 16,
            color: c.mutedForeground,
          ),
        ),
      ),
    );
    if (!lifted) return handle;
    return Container(
      padding: const .symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.popover,
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Text(label, style: t.text.sm.copyWith(color: c.foreground)),
    );
  }
}
