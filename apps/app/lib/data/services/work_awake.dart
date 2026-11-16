import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../repositories/conversation_repository.dart';

/// Starts a program that keeps this computer from sleeping; null where it
/// cannot be started.
typedef StartAwake = Future<Process?> Function(String executable, List<String> args);

/// Keeps this computer from going to sleep while a chat is working, so work
/// left running is still running when you come back: on macOS, Windows and
/// Linux alike. The screen may still turn off, and closing a laptop's lid
/// still sleeps it. Let go a little after the last chat stops, so a quick
/// pause between turns does not let it sleep mid-task.
class WorkAwake extends ChangeNotifier {
  WorkAwake(
    this._conversations, {
    required this.enabled,
    StartAwake? start,
    this.linger = const Duration(seconds: 30),
    String? os,
    int? self,
  }) : _start = start ?? _startProcess,
       _os = os ?? Platform.operatingSystem,
       _self = self ?? pid {
    _conversations.addListener(_check);
  }

  final ConversationRepository _conversations;

  /// Whether it is turned on, in Settings.
  final bool Function() enabled;

  final StartAwake _start;
  final String _os;
  final int _self;

  /// How long after the last chat stops it lets go.
  final Duration linger;

  Process? _process;
  Timer? _letGo;
  bool _starting = false;

  /// Whether it is keeping the computer awake now.
  bool get holding => _process != null;

  /// Why it cannot, on this computer; null when it can.
  String? trouble;

  /// Looks again: settings changed.
  void check() => _check();

  void _check() {
    final want = enabled() && _conversations.anyBusy;
    if (want) {
      _letGo?.cancel();
      _letGo = null;
      if (_process == null && !_starting) unawaited(_hold());
    } else if (_process != null || _starting) {
      _letGo ??= Timer(enabled() ? linger : Duration.zero, _release);
    }
  }

  /// How each system is kept awake, for as long as the program runs. Each
  /// also ends by itself if Helmy goes away without letting go.
  (String, List<String>)? get command => switch (_os) {
    // Idle sleep held off (not the display), until Helmy's process ends.
    'macos' => ('/usr/bin/caffeinate', ['-i', '-w', '$_self']),
    // Windows' own call for it, held by a PowerShell that ends with Helmy.
    // Sent encoded, so no quoting on the way can change it.
    'windows' => (
      'powershell',
      ['-NoProfile', '-NonInteractive', '-EncodedCommand', _encoded(windowsScript(_self))],
    ),
    // systemd's inhibitor lock, for as long as Helmy runs.
    'linux' => (
      'systemd-inhibit',
      [
        '--what=idle:sleep',
        '--who=Helmy',
        '--why=A chat is working',
        '--mode=block',
        'tail',
        '--pid=$_self',
        '-f',
        '/dev/null',
      ],
    ),
    _ => null,
  };

  /// What PowerShell runs on Windows: ES_CONTINUOUS | ES_SYSTEM_REQUIRED,
  /// held until Helmy's process [self] ends.
  static String windowsScript(int self) =>
      '''Add-Type -Name P -Namespace W -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[W.P]::SetThreadExecutionState([uint32]"0x80000001") | Out-Null
while (Get-Process -Id $self -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 30 }''';

  /// PowerShell's -EncodedCommand: UTF-16LE, base64.
  static String _encoded(String script) => base64.encode([
    for (final u in script.codeUnits) ...[u & 0xff, u >> 8],
  ]);

  Future<void> _hold() async {
    final c = command;
    if (c == null) return;
    _starting = true;
    try {
      final p = await _start(c.$1, c.$2);
      if (p == null) {
        trouble = switch (_os) {
          'linux' =>
            "This computer has no systemd-inhibit, so Helmy can't keep it awake while it works.",
          _ => "Helmy couldn't keep this computer awake while it works.",
        };
        notifyListeners();
        return;
      }
      trouble = null;
      _process = p;
      unawaited(
        p.exitCode.then((_) {
          if (identical(_process, p)) {
            _process = null;
            notifyListeners();
          }
        }),
      );
      notifyListeners();
    } finally {
      _starting = false;
    }
    // Changed while it started.
    _check();
  }

  void _release() {
    _letGo = null;
    if (enabled() && _conversations.anyBusy) return;
    final p = _process;
    _process = null;
    p?.kill();
    notifyListeners();
  }

  static Future<Process?> _startProcess(String executable, List<String> args) async {
    try {
      return await Process.start(executable, args, mode: ProcessStartMode.normal);
    } on ProcessException {
      return null;
    }
  }

  @override
  void dispose() {
    _conversations.removeListener(_check);
    _letGo?.cancel();
    _process?.kill();
    _process = null;
    super.dispose();
  }
}
