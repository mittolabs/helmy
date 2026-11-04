import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

/// The computer Helmy runs on, and how its own words and keys go there:
/// "Show in Finder" on a Mac is "Show in File Explorer" on Windows, ⌘N is
/// Ctrl+N. Everything platform-specific in what people see or press asks here.
enum Desktop {
  mac,
  windows,
  linux;

  /// The one running now. Set [current] in a test to see another.
  static Desktop current = Platform.isWindows
      ? windows
      : Platform.isLinux
      ? linux
      : mac;

  /// Its file manager, by name.
  String get fileManager => switch (this) {
    mac => 'Finder',
    windows => 'File Explorer',
    linux => 'Files',
  };

  /// "this Mac", or "this computer".
  String get thisComputer => this == mac ? 'this Mac' : 'this computer';

  /// Where a running app's icon sits.
  String get appBar => switch (this) {
    mac => 'the Dock',
    windows => 'the taskbar',
    linux => 'the dock or taskbar',
  };

  /// The key most shortcuts are made with: ⌘ on a Mac, Ctrl elsewhere.
  bool get commandIsMeta => this == mac;

  /// Shortcuts as they are written here: written the Mac's way (`⌘N`,
  /// `⇧⌘Enter`, "⌘1 to ⌘9"), each becomes `Ctrl+N`, `Ctrl+Shift+Enter`
  /// off a Mac.
  String keys(String mac) {
    if (this == Desktop.mac) return mac;
    return mac.replaceAllMapped(RegExp(r'([⇧⌥⌘]+)([^\s/)]+)'), (m) {
      final mods = m[1]!;
      return [
        if (mods.contains('⌘')) 'Ctrl',
        if (mods.contains('⌥')) 'Alt',
        if (mods.contains('⇧')) 'Shift',
        m[2]!,
      ].join('+');
    });
  }

  /// [key] with this computer's command key (and [shift]), for a shortcut.
  SingleActivator shortcut(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(key, meta: commandIsMeta, control: !commandIsMeta, shift: shift);

  /// Whether this computer's command key is held now.
  bool get commandHeld => commandIsMeta
      ? HardwareKeyboard.instance.isMetaPressed
      : HardwareKeyboard.instance.isControlPressed;

  /// Whether pictures of documents can be made here (Quick Look, on a Mac).
  bool get documentPictures => this == mac;
}

/// Whether this platform has the embedded web view (WebKit on Apple's
/// systems, Android's own): pages and PDFs open inside Helmy. Elsewhere they
/// open in their own app.
bool get webViewHere => Platform.isMacOS || Platform.isIOS || Platform.isAndroid;

/// Whether video and sound play inside Helmy here. Elsewhere they open in
/// their own app.
bool get playerHere => Platform.isMacOS || Platform.isIOS || Platform.isAndroid;

/// Fixed-width fonts, the platform's first: Menlo on a Mac, Consolas on
/// Windows, Roboto Mono or the system's own elsewhere. With
/// `fontFamily: 'monospace'`, as Ashlar's code blocks do.
const monoFonts = ['Menlo', 'Consolas', 'Roboto Mono', 'monospace'];

/// The user's home folder: HOME, or USERPROFILE on Windows.
String get homeDir => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

/// [command] run by this computer's shell: the user's login shell on a Mac
/// or Linux (zsh when it says none), PowerShell on Windows.
(String, List<String>) shellFor(String command) => Desktop.current == .windows
    ? ('powershell', ['-NoProfile', '-Command', command])
    : (Platform.environment['SHELL'] ?? '/bin/zsh', ['-lc', command]);
