import 'dart:async';
import 'dart:convert';

import 'browser_host.dart';

/// The browser tools Helmy gives its agents, on the page in their session's
/// Preview panel (which the user sees), or one in the background. Fast
/// because they work in text: a page is read as an outline with a short
/// ref on everything usable, several actions go in one call, and each call
/// waits for the page to settle and answers with the page as it is after.
/// Pictures only when asked for.
class BrowserTools {
  BrowserTools(this._host);
  final BrowserHost _host;

  static const names = [
    'browser_open',
    'browser_read',
    'browser_act',
    'browser_screenshot',
    'browser_logs',
    'browser_eval',
  ];

  static Map<String, Object?> _tool(
    String name,
    String title,
    String description, {
    Map<String, Object?> properties = const {},
    List<String> required = const [],
    bool readOnly = false,
  }) => {
    'name': name,
    'description': description,
    'inputSchema': {'type': 'object', 'properties': properties, 'required': required},
    'annotations': {'readOnlyHint': readOnly, 'title': title},
  };

  static final list = [
    _tool(
      'browser_open',
      'Open a page',
      'Opens an address in the panel beside the conversation, where the user sees '
          'it, and answers with the page read as text (see browser_read). Use it, and the '
          "other browser tools, for any web page or a local app's page (http://localhost:3000). "
          'Faster than any other browser: no browser starts, and pages are read as text.',
      properties: {
        'url': {'type': 'string', 'description': 'The address.'},
      },
      required: ['url'],
    ),
    _tool(
      'browser_read',
      'Read the page',
      'The page open now, as text: headings, text, and every link, button and field with a '
          'ref like [e12] to act on, its value and state. With find, only what matches: words '
          'in a name or text, or css:<selector>. Read rather than take a screenshot.',
      properties: {
        'find': {'type': 'string', 'description': 'Words to look for, or css:<selector>.'},
      },
      readOnly: true,
    ),
    _tool(
      'browser_act',
      'Use the page',
      'Does several steps in order on the page, then waits for it to settle and answers '
          'with the page as it is after. Put every step you already know in one call. Steps: '
          '{"do":"click","ref":"e5"}, {"do":"type","ref":"e6","text":"…"} (replaces the value; '
          '"replace":false adds to it), {"do":"press","key":"Enter"} (Enter, Tab, Escape, '
          'Backspace, an arrow; "ref" to press it in a field), {"do":"select","ref":"e7",'
          '"value":"…"}, {"do":"scroll","ref":"e8"} or {"do":"scroll","by":1} (screens), '
          '{"do":"back"}, {"do":"wait","ms":500}.',
      properties: {
        'steps': {
          'type': 'array',
          'items': {'type': 'object'},
          'description': 'The steps, in order.',
        },
      },
      required: ['steps'],
    ),
    _tool(
      'browser_screenshot',
      'Look at the page',
      'A picture of what shows of the page. Only when how it looks matters (layout, '
          'colors, an image): browser_read is faster for what it says and does.',
      readOnly: true,
    ),
    _tool(
      'browser_logs',
      "The page's errors",
      'Errors and warnings the page has written to its console since it loaded, and '
          'errors it threw: what to check when something on it does not work.',
      readOnly: true,
    ),
    _tool(
      'browser_eval',
      'Run a script in the page',
      "Runs JavaScript in the page and answers with its value (awaited if it's a promise). "
          'For what the other tools do not reach: a value in the page, a check across many '
          'elements.',
      properties: {
        'script': {'type': 'string', 'description': 'An expression; may be a promise.'},
      },
      required: ['script'],
    ),
  ];

  Map<String, Object?> _says(String text, {bool error = false}) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': error,
  };

  static const _noPage =
      'No page is open. browser_open opens one in the panel beside the conversation.';

  /// The reader and driver, in the page (again after the page has moved on).
  Future<void> _ready(PageDriver page) async {
    if (await page.eval('!!window.__helmyBrowse') == true) return;
    await page.eval('(() => { ${await BrowserHost.script()}\n; return true; })()');
  }

  /// The page loaded and settled, to read or act on.
  Future<void> _settle(PageDriver page) async {
    final until = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(until)) {
      try {
        if (await page.eval('document.readyState') == 'complete') break;
      } on Object {
        // Mid-navigation the page does not answer; it will.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    try {
      await _ready(page);
      await page.eval('window.__helmyBrowse.settled()');
    } on Object {
      // A page that will not run scripts (a PDF) is read as it is.
    }
  }

  Future<String> _read(PageDriver page, {String? find}) async {
    await _ready(page);
    if (find != null && find.trim().isNotEmpty) {
      final r = await page.eval('window.__helmyBrowse.find(${jsonEncode(find)})');
      if (r is Map && r['error'] != null) return '${r['error']}';
      final matches = (r is Map ? r['matches'] as List? : null) ?? const [];
      return matches.isEmpty
          ? 'Nothing on the page matches "$find".'
          : 'Matching "$find":\n${matches.join('\n')}';
    }
    final r = await page.eval('window.__helmyBrowse.snapshot()');
    if (r is! Map) return 'The page could not be read.';
    return '${r['title']} (${r['url']})\n\n${r['text']}';
  }

  /// One step; null when it went as asked, else what went wrong.
  Future<String?> _step(PageDriver page, Map step) async {
    final what = '${step['do']}';
    final ref = step['ref'] as String?;
    switch (what) {
      case 'back':
        await page.back();
        await _settle(page);
        return null;
      case 'wait':
        await Future<void>.delayed(
          Duration(milliseconds: ((step['ms'] as num?) ?? 500).clamp(0, 10000).toInt()),
        );
        return null;
    }
    await _ready(page);
    // Real input where the engine has it: a click at the element's middle,
    // typing and keys as from a keyboard.
    final click = page.click, type = page.typeText, press = page.press;
    if (click != null && ref != null && (what == 'click' || what == 'type' || what == 'press')) {
      final at = await page.eval('window.__helmyBrowse.point(${jsonEncode(ref)})');
      if (at is Map && at['error'] != null) return '${at['error']}';
      if (at is Map) {
        await click((at['x'] as num).toDouble(), (at['y'] as num).toDouble());
      }
    }
    if (what == 'click' && click != null && ref != null) return null;
    if (what == 'type' && type != null) {
      if (step['replace'] != false) {
        await page.eval(
          '(() => { const e = document.activeElement; if (e && e.select) e.select(); '
          'else if (e && e.isContentEditable) document.execCommand("selectAll"); })()',
        );
      }
      await type('${step['text'] ?? ''}');
      return null;
    }
    if (what == 'press' && press != null) {
      await press('${step['key'] ?? 'Enter'}');
      return null;
    }
    final r = await page.eval('window.__helmyBrowse.act(${jsonEncode(step)})');
    return r is Map && r['error'] != null ? '${r['error']}' : null;
  }

  /// One call: [name] with [args], for [session].
  Future<Map<String, Object?>> call(String name, Map args, String? session) async {
    try {
      if (name == 'browser_open') {
        final url = '${args['url'] ?? ''}'.trim();
        if (url.isEmpty) return _says('Give the address to open.', error: true);
        // Where the page was, to wait until it has really moved on: asked
        // for a new address, a page keeps answering as the old one a moment.
        String? before;
        try {
          before = '${await _host.pageFor(session)?.eval('location.href')}';
        } on Object {
          before = null;
        }
        final page = await _host.open(session, url);
        if (page == null) {
          return _says(
            "The page couldn't be opened: this session's conversation is not on screen, and "
            'no Chromium-based browser is installed to open it in the background. Ask the '
            'user to open this session in Helmy.',
            error: true,
          );
        }
        if (before != null) {
          final until = DateTime.now().add(const Duration(seconds: 10));
          while (DateTime.now().isBefore(until)) {
            try {
              if ('${await page.eval('location.href')}' != before) break;
            } on Object {
              // Mid-navigation the page does not answer: it is moving.
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        await _settle(page);
        return _says(await _read(page));
      }
      final page = _host.pageFor(session);
      if (page == null) return _says(_noPage, error: true);
      switch (name) {
        case 'browser_read':
          return _says(await _read(page, find: args['find'] as String?));
        case 'browser_act':
          final steps = (args['steps'] as List?)?.whereType<Map>().toList() ?? const [];
          if (steps.isEmpty) return _says('Give the steps to do.', error: true);
          for (final (i, step) in steps.indexed) {
            final wrong = await _step(page, step);
            if (wrong != null) {
              await _settle(page);
              return _says(
                'Step ${i + 1} (${step['do']}) did not go: $wrong'
                '${i > 0 ? ' The steps before it were done.' : ''}\n\n${await _read(page)}',
                error: true,
              );
            }
          }
          await _settle(page);
          return _says('Done.\n\n${await _read(page)}');
        case 'browser_screenshot':
          final png = await page.screenshot();
          if (png == null) return _says("A picture of the page couldn't be taken.", error: true);
          return {
            'content': [
              {'type': 'image', 'mimeType': 'image/png', 'data': base64Encode(png)},
            ],
            'isError': false,
          };
        case 'browser_logs':
          await _ready(page);
          final logs = await page.eval('window.__helmyBrowse.logs()');
          final lines = logs is List ? logs : const [];
          return _says(
            lines.isEmpty ? 'No errors or warnings since the page loaded.' : lines.join('\n'),
          );
        case 'browser_eval':
          final out = await page.eval('${args['script'] ?? 'undefined'}');
          return _says(const JsonEncoder.withIndent('  ').convert(out));
      }
      return _says('No such tool.', error: true);
    } on Object catch (e) {
      return _says('The page did not answer: $e', error: true);
    }
  }
}
