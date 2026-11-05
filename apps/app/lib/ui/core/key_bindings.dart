import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../utils/platform.dart';

/// The app's commands whose keys can be changed in Settings > Keyboard.
enum AppCommand {
  search('Search chats and run actions', 'K'),
  newChat('New chat', 'N'),
  newThread('New thread in this chat', 'N', shift: true),
  settings('Settings', ','),
  back('Back to where you were', '['),
  forward('Forward again', ']'),
  find('Find in this thread', 'F');

  const AppCommand(this.label, this._key, {this.shift = false});
  final String label;
  final String _key;
  final bool shift;

  /// Helmy's own keys for it, with this computer's command key.
  KeyBinding get standard => KeyBinding(key: _keyFor(_key), command: true, shift: shift);

  static LogicalKeyboardKey _keyFor(String k) => switch (k) {
    ',' => LogicalKeyboardKey.comma,
    '[' => LogicalKeyboardKey.bracketLeft,
    ']' => LogicalKeyboardKey.bracketRight,
    _ => LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + k.codeUnitAt(0) - 'A'.codeUnitAt(0)),
  };
}

/// A key with the modifiers held: the command key (⌘ on a Mac, Ctrl
/// elsewhere), Shift, Option or Alt.
@immutable
class KeyBinding {
  const KeyBinding({required this.key, this.command = false, this.shift = false, this.alt = false});

  final LogicalKeyboardKey key;
  final bool command, shift, alt;

  SingleActivator get activator => SingleActivator(
    key,
    meta: command && Desktop.current.commandIsMeta,
    control: command && !Desktop.current.commandIsMeta,
    shift: shift,
    alt: alt,
  );

  /// As this computer writes it: ⇧⌘N, or Ctrl+Shift+N.
  String get label {
    final k = key.keyLabel.length == 1 ? key.keyLabel.toUpperCase() : key.keyLabel;
    return Desktop.current.keys('${alt ? '⌥' : ''}${shift ? '⇧' : ''}${command ? '⌘' : ''}$k');
  }

  /// Kept as text: `cmd+shift:<key id>`.
  String get saved {
    final mods = [if (command) 'cmd', if (shift) 'shift', if (alt) 'alt'].join('+');
    return '$mods:${key.keyId}';
  }

  static KeyBinding? parse(String text) {
    final at = text.lastIndexOf(':');
    final id = int.tryParse(text.substring(at + 1));
    if (at < 0 || id == null) return null;
    final mods = text.substring(0, at).split('+');
    return KeyBinding(
      key: LogicalKeyboardKey(id),
      command: mods.contains('cmd'),
      shift: mods.contains('shift'),
      alt: mods.contains('alt'),
    );
  }

  /// The binding of a key pressed now, or null for a key that cannot be
  /// one: a modifier alone, or a plain letter that would only type.
  static KeyBinding? of(KeyEvent e) {
    final k = e.logicalKey;
    final modifiers = {
      LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight, //
      LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
    };
    if (modifiers.contains(k)) return null;
    final hw = HardwareKeyboard.instance;
    final command = Desktop.current.commandIsMeta ? hw.isMetaPressed : hw.isControlPressed;
    final fKey = k.keyId >= LogicalKeyboardKey.f1.keyId && k.keyId <= LogicalKeyboardKey.f12.keyId;
    if (!command && !hw.isAltPressed && !fKey) return null;
    return KeyBinding(key: k, command: command, shift: hw.isShiftPressed, alt: hw.isAltPressed);
  }

  @override
  bool operator ==(Object other) =>
      other is KeyBinding &&
      other.key == key &&
      other.command == command &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, command, shift, alt);
}

/// [command]'s keys: the user's, saved in [chosen], else Helmy's own.
KeyBinding bindingOf(AppCommand command, Map<String, String> chosen) {
  final saved = chosen[command.name];
  return (saved == null ? null : KeyBinding.parse(saved)) ?? command.standard;
}
