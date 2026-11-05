import 'dart:convert';

import 'mac_actions.dart';
import 'mac_control.dart';

/// Helmy's Mac actions, as tools for the agent: done by Helmy itself, so
/// they work whatever sandbox the agent's commands run in. The agent is
/// told to use these rather than guess at shell commands for the same.
class MacTools {
  MacTools(this._mac, {this.control});
  final MacActions _mac;

  /// An agent using the screen, mouse and keyboard ([use]); null where it
  /// can't.
  final MacControl? control;

  /// Those the agent may use without asking: they look, or change something
  /// easily changed back.
  static const free = [
    'mac_status',
    'mac_awake',
    'mac_screen',
    'mac_sound',
    'mac_network',
    'mac_files',
  ];

  /// Those that ask first where the chat asks before acting: they end
  /// something (an app, a drive's connection, the session).
  static const asking = ['mac_quit', 'mac_eject', 'mac_power'];

  /// Using the screen, mouse and keyboard as a person does. Helmy asks the
  /// person itself, once per chat, so the connections are told to allow them.
  static const use = ['mac_see', 'mac_click', 'mac_drag', 'mac_scroll', 'mac_type', 'mac_key'];

  static const names = [...free, ...asking, ...use];

  static const _prefer =
      ' Use this rather than a shell command for the same: it is done by Helmy itself on this '
      "Mac, outside any sandbox, and works where commands can't.";

  static Map<String, Object?> _tool(
    String name,
    String title,
    String description,
    Map<String, Object?> properties, {
    List<String> required = const [],
    bool readOnly = false,
    bool destructive = false,
  }) => {
    'name': name,
    'description': '$description$_prefer',
    'inputSchema': {'type': 'object', 'properties': properties, 'required': required},
    'annotations': {'title': title, 'readOnlyHint': readOnly, 'destructiveHint': destructive},
  };

  static final list = [
    _tool(
      'mac_status',
      'Look at this Mac',
      "What is going on with this Mac, measured now. about: battery (level, charging, health, "
          'cycles), load (processor and memory, what works them hardest), energy (what uses the '
          'most), disk (free space), biggest (the biggest folders in folder, the home folder when '
          'left out; can take a minute), network (Wi-Fi and the local address), sound (volume, '
          'microphone, outputs), awake (whether Helmy is keeping it awake), apps (the open apps), '
          'drives (those that can be ejected).',
      {
        'about': {
          'type': 'string',
          'enum': [
            'battery',
            'load',
            'energy',
            'disk',
            'biggest',
            'network',
            'sound',
            'awake',
            'apps',
            'drives',
          ],
        },
        'folder': {'type': 'string', 'description': 'For biggest: the folder to measure.'},
      },
      required: ['about'],
      readOnly: true,
    ),
    _tool(
      'mac_awake',
      'Keep this Mac awake',
      'Keeps this Mac from sleeping: for minutes, or until a time (HH:MM, 24-hour, today or '
          'tomorrow), or until told to stop when neither is given. display false lets the screen '
          'go dark while the Mac keeps working. stop true lets it sleep again.',
      {
        'minutes': {'type': 'number'},
        'until': {'type': 'string', 'description': 'HH:MM, 24-hour.'},
        'display': {'type': 'boolean', 'description': 'Keep the screen on too; true unless said.'},
        'stop': {'type': 'boolean'},
      },
    ),
    _tool(
      'mac_screen',
      'Lock or darken the screen',
      'do: lock (locks the screen now), display_off (turns the display off; it locks too when '
          'the Mac asks for its password at once).',
      {
        'do': {
          'type': 'string',
          'enum': ['lock', 'display_off'],
        },
      },
      required: ['do'],
    ),
    _tool(
      'mac_sound',
      "This Mac's sound",
      'Changes the sound: volume (0 to 100), muted, mic_muted (the microphone), output (where '
          'sound plays, by name, such as AirPods), media (play_pause, next, previous: for '
          'whatever is playing). Give any of them together. mac_status about sound shows them.',
      {
        'volume': {'type': 'number'},
        'muted': {'type': 'boolean'},
        'mic_muted': {'type': 'boolean'},
        'output': {'type': 'string'},
        'media': {
          'type': 'string',
          'enum': ['play_pause', 'next', 'previous'],
        },
      },
    ),
    _tool(
      'mac_network',
      "This Mac's network",
      "do: speed_test (Apple's own, about 20 seconds: download, upload, responsiveness), "
          'wifi_on, wifi_off.',
      {
        'do': {
          'type': 'string',
          'enum': ['speed_test', 'wifi_on', 'wifi_off'],
        },
      },
      required: ['do'],
    ),
    _tool(
      'mac_files',
      'Finder',
      'hidden_files true shows hidden files in Finder, false hides them again. Finder restarts '
          'to take it, closing its windows.',
      {
        'hidden_files': {'type': 'boolean'},
      },
      required: ['hidden_files'],
    ),
    _tool(
      'mac_quit',
      'Quit an app',
      'Quits the open app called app. force true quits it at once without letting it save: only '
          'for an app that is not responding. mac_status about apps lists them.',
      {
        'app': {'type': 'string'},
        'force': {'type': 'boolean'},
      },
      required: ['app'],
      destructive: true,
    ),
    _tool(
      'mac_eject',
      'Eject drives',
      'Ejects every external drive and disk image that can be ejected.',
      {},
      destructive: true,
    ),
    _tool(
      'mac_power',
      'Sleep this Mac',
      'do: sleep (puts this Mac to sleep in two seconds).',
      {
        'do': {
          'type': 'string',
          'enum': ['sleep'],
        },
      },
      required: ['do'],
      destructive: true,
    ),
  ];

  static const _xy = {
    'x': {'type': 'number', 'description': "Pixels from the left of mac_see's picture."},
    'y': {'type': 'number', 'description': "Pixels from the top of mac_see's picture."},
  };

  static const _after = ' Then mac_see shows what it did.';

  /// The tools for [use].
  static final useList = [
    _tool(
      'mac_see',
      "See this Mac's screen",
      "A picture of this Mac's main screen now, as the user sees it, with its size in pixels: "
          'the x and y the other mac_ tools take are in these pixels. Use it for apps and windows '
          'nothing else reaches (System Settings, a native app, a dialog); a page in the browser '
          'goes through the browser tools, files and commands through the shell. Look again after '
          'each action, since the screen changes. The user watches in the Device panel.',
      {},
      readOnly: true,
    ),
    _tool(
      'mac_click',
      'Click on this Mac',
      'Moves the pointer to x, y and clicks. button right for the menu a right-click opens; count '
          '2 for a double-click. The first time in a chat, Helmy asks the user to allow using the '
          'mouse and keyboard, and waits for them.$_after',
      {
        ..._xy,
        'button': {
          'type': 'string',
          'enum': ['left', 'right'],
        },
        'count': {'type': 'integer', 'minimum': 1, 'maximum': 3},
      },
      required: ['x', 'y'],
    ),
    _tool(
      'mac_drag',
      'Drag on this Mac',
      'Presses at x, y, moves to to_x, to_y and lets go: to move a window or a file, select '
          'text, or move a slider.$_after',
      {
        ..._xy,
        'to_x': {'type': 'number'},
        'to_y': {'type': 'number'},
      },
      required: ['x', 'y', 'to_x', 'to_y'],
    ),
    _tool(
      'mac_scroll',
      'Scroll on this Mac',
      'Scrolls what is under x, y: down (a positive amount) or up (negative), in lines; right '
          'or left with across.$_after',
      {
        ..._xy,
        'down': {'type': 'number', 'description': 'Lines; negative scrolls up.'},
        'across': {'type': 'number', 'description': 'Lines; negative scrolls left.'},
      },
      required: ['x', 'y'],
    ),
    _tool(
      'mac_type',
      'Type on this Mac',
      'Types text into whatever has focus, as the keyboard would. Click the field first.$_after',
      {
        'text': {'type': 'string'},
      },
      required: ['text'],
    ),
    _tool(
      'mac_key',
      'Press a key on this Mac',
      'Presses a key, with mods held: return, tab, space, delete, forwarddelete, escape, left, '
          'right, up, down, home, end, pageup, pagedown, f1 to f12, or a letter, digit or '
          r"punctuation key (- = [ ] ; ' , . / \ `). mods: cmd, shift, alt, ctrl. Shortcuts: key c "
          'with cmd copies, key tab with cmd switches apps, key space with cmd opens Spotlight.'
          '$_after',
      {
        'key': {'type': 'string'},
        'mods': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['cmd', 'shift', 'alt', 'ctrl'],
          },
        },
      },
      required: ['key'],
    ),
  ];

  /// Does tool [name] with [args] for [session]'s agent: an MCP tool result.
  Future<Map<String, Object?>> call(String name, Map args, [String? session]) async {
    if (use.contains(name)) return _use(name, args, session);
    Map<String, Object?> says(String text, {bool error = false}) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
      'isError': error,
    };
    try {
      return says(await _do(name, args));
    } on MacTrouble catch (t) {
      final fix = t.fix;
      return says(
        fix == null
            ? t.what
            : '${t.what} Tell the user, and give them this link, which opens the setting: '
                  '[Allow Accessibility]($fix). Then try again once they have.',
        error: true,
      );
    } on Object catch (e) {
      return says("That didn't work on this Mac: $e", error: true);
    }
  }

  Future<String> _do(String name, Map args) async {
    final m = _mac;
    bool? flag(String k) => args[k] is bool ? args[k] as bool : null;
    switch (name) {
      case 'mac_status':
        return switch ('${args['about']}') {
          'battery' => m.battery(),
          'load' => m.load(),
          'energy' => m.energy(),
          'disk' => m.disk(),
          'biggest' => m.biggest(args['folder'] as String?),
          'network' => m.network(),
          'sound' => m.sound(),
          'awake' => Future.value(m.awakeNow()),
          'apps' => m.apps(),
          'drives' => m.drives(),
          final a => throw MacTrouble('Nothing called "$a" to look at.'),
        };
      case 'mac_awake':
        if (flag('stop') == true) return m.stopAwake();
        final minutes = args['minutes'] as num?;
        final until = args['until'] as String?;
        return m.keepAwake(
          time: minutes == null ? null : Duration(seconds: (minutes * 60).round()),
          until: until == null ? null : _next(until),
          display: flag('display') ?? true,
        );
      case 'mac_screen':
        return switch ('${args['do']}') {
          'lock' => m.lock(),
          'display_off' => m.displayOff(),
          final d => throw MacTrouble('No "$d": lock or display_off.'),
        };
      case 'mac_sound':
        final said = <String>[
          if (args['output'] case final String o) await m.setOutput(o),
          if (args['volume'] case final num v) await m.setVolume(v.round()),
          if (flag('muted') case final mu?) await m.mute(mu),
          if (flag('mic_muted') case final mic?) await m.muteMic(mic),
          if (args['media'] case final String k) await m.media(k),
        ];
        return said.isEmpty ? m.sound() : said.join(' ');
      case 'mac_network':
        return switch ('${args['do']}') {
          'speed_test' => m.speedTest(),
          'wifi_on' => m.wifi(true),
          'wifi_off' => m.wifi(false),
          final d => throw MacTrouble('No "$d": speed_test, wifi_on or wifi_off.'),
        };
      case 'mac_files':
        return m.hiddenFiles(flag('hidden_files') ?? true);
      case 'mac_quit':
        final app = '${args['app'] ?? ''}'.trim();
        if (app.isEmpty) throw const MacTrouble('Say which app.');
        return m.quit(app, force: flag('force') ?? false);
      case 'mac_eject':
        return m.eject();
      case 'mac_power':
        return m.sleep();
    }
    throw MacTrouble('No tool $name.');
  }

  Future<Map<String, Object?>> _use(String name, Map args, String? session) async {
    Map<String, Object?> says(String text, {bool error = false}) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
      'isError': error,
    };
    final c = control;
    if (c == null) return says("This Mac's screen can't be used from here.", error: true);
    try {
      if (name == 'mac_see') {
        final s = await c.see(session);
        return {
          'content': [
            {
              'type': 'text',
              'text':
                  "This Mac's screen now, ${s.width} by ${s.height} pixels: give x and y in "
                  'these.',
            },
            {'type': 'image', 'mimeType': 'image/jpeg', 'data': base64Encode(s.jpeg)},
          ],
          'isError': false,
        };
      }
      // Without a chat, the ask has nowhere to show.
      final chat = session ?? '';
      num n(String k) => args[k] is num ? args[k] as num : 0;
      switch (name) {
        case 'mac_click':
          await c.act(chat, {
            'kind': args['button'] == 'right' ? 'right' : 'click',
            'x': n('x'),
            'y': n('y'),
            'count': (n('count').toInt()).clamp(1, 3),
          });
          return says('Clicked.');
        case 'mac_drag':
          await c.act(chat, {'kind': 'down', 'x': n('x'), 'y': n('y')});
          try {
            // Through the way, as a hand moves, so what is dragged follows.
            for (var i = 1; i <= 8; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 16));
              final f = i / 8;
              await c.act(chat, {
                'kind': 'drag',
                'x': n('x') + (n('to_x') - n('x')) * f,
                'y': n('y') + (n('to_y') - n('y')) * f,
              });
            }
          } on MacUseTrouble {
            // The person took over midway: the button is let go, whatever they do.
            await c
                .act(chat, {'kind': 'up', 'x': n('x'), 'y': n('y'), 'quiet': 0})
                .catchError((_) {});
            rethrow;
          }
          await c.act(chat, {'kind': 'up', 'x': n('to_x'), 'y': n('to_y')});
          return says('Dragged.');
        case 'mac_scroll':
          // A line is about ten pixels; the wheel's up is positive.
          await c.act(chat, {
            'kind': 'scroll',
            'x': n('x'),
            'y': n('y'),
            'dy': -n('down') * 10,
            'dx': -n('across') * 10,
          });
          return says('Scrolled.');
        case 'mac_type':
          await c.act(chat, {'kind': 'text', 'text': '${args['text'] ?? ''}'});
          return says('Typed.');
        case 'mac_key':
          await c.act(chat, {
            'kind': 'key',
            'key': '${args['key'] ?? ''}',
            'mods': [for (final m in (args['mods'] as List?) ?? const []) '$m'],
          });
          return says('Pressed.');
      }
      return says('No tool $name.', error: true);
    } on MacUseTrouble catch (t) {
      if (t.code == 'record') {
        return says(
          'Helmy needs the Screen Recording permission to see this Mac. Tell the user, and give '
          'them this link, which opens the setting: [Allow Screen Recording]'
          '(helmy://fix/allow-screen-recording). Then try again once they have.',
          error: true,
        );
      }
      return says(t.message, error: true);
    }
  }

  /// The next time it is [hhmm]: today, or tomorrow when that has passed.
  static DateTime _next(String hhmm, [DateTime? now]) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (m == null) throw MacTrouble('"$hhmm" is not a time like 18:30.');
    final n = now ?? DateTime.now();
    var t = DateTime(n.year, n.month, n.day, int.parse(m[1]!), int.parse(m[2]!));
    if (!t.isAfter(n)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// For tests.
  static DateTime nextAt(String hhmm, DateTime now) => _next(hhmm, now);
}
