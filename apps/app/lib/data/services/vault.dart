import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Where a secret belongs: a project's folder, or every project.
const sharedScope = 'shared';

/// Helmy's vault: secrets kept so agents never see them. The values live in
/// the login Keychain (through [_keychain]); only their names are on disk,
/// by scope, in [indexFile]. Agents get names, and a command run with them
/// (`vault_run`), never the values.
class Vault extends ChangeNotifier {
  Vault({required this.indexFile, required this._keychain});

  final File indexFile;
  final VaultKeychain _keychain;

  /// Names by scope (a project's folder, or [sharedScope]).
  Map<String, List<String>> _names = {};

  /// Projects whose .env files the person chose to keep as they are.
  Set<String> _keptEnv = {};

  /// A HashiCorp Vault to fetch secrets from, by reference; its token is in
  /// the Keychain.
  ({String address, String namespace})? hcVault;

  static const _hcToken = 'source|hcvault';

  Future<void> load() async {
    try {
      final j = jsonDecode(await indexFile.readAsString());
      if (j is Map) {
        _names = {
          for (final e in ((j['names'] as Map?) ?? const {}).entries)
            '${e.key}': [for (final n in (e.value as List? ?? const [])) '$n'],
        };
        _keptEnv = {for (final k in (j['keptEnv'] as List?) ?? const []) '$k'};
        if (j['hcVault'] case final Map h when '${h['address'] ?? ''}'.isNotEmpty) {
          hcVault = (address: '${h['address']}', namespace: '${h['namespace'] ?? ''}');
        }
      }
    } on Object {
      _names = {};
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await indexFile.parent.create(recursive: true);
    await indexFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'names': _names,
        'keptEnv': [..._keptEnv],
        if (hcVault case final h?) 'hcVault': {'address': h.address, 'namespace': h.namespace},
      }),
    );
  }

  /// Whether the person chose to keep [project]'s .env files as they are.
  bool keepsEnv(String project) => _keptEnv.contains(project);

  Future<void> keepEnv(String project) async {
    _keptEnv.add(project);
    await _save();
    notifyListeners();
  }

  /// Whether [name] can be a secret's name: as an environment variable's.
  static bool validName(String name) => RegExp(r'^[A-Z_][A-Z0-9_]{0,127}$').hasMatch(name);

  /// [name] made into one: upper case, other characters as `_`.
  static String nameFrom(String words) {
    final n = words.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    final s = n.replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'SECRET' : (RegExp(r'^[0-9]').hasMatch(s) ? '_$s' : s);
  }

  /// Every scope that has secrets, and their names.
  Map<String, List<String>> get all => {
    for (final e in _names.entries) e.key: [...e.value],
  };

  /// The names a chat in [project] can use: the project's, then the shared
  /// ones it does not have.
  List<String> namesFor(String project) {
    final own = _names[project] ?? const [];
    return [...own, ...(_names[sharedScope] ?? const []).where((n) => !own.contains(n))];
  }

  static String _account(String scope, String name) => '$scope|$name';

  /// Keeps [value] as [name] in [scope]; true once it reads back the same.
  Future<bool> put(String scope, String name, String value) async {
    if (!validName(name) || value.isEmpty) return false;
    final account = _account(scope, name);
    if (!await _keychain.set(account, value)) return false;
    if (await _keychain.get(account) != value) return false;
    final list = _names.putIfAbsent(scope, () => []);
    if (!list.contains(name)) list.add(name);
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> remove(String scope, String name) async {
    await _keychain.delete(_account(scope, name));
    _names[scope]?.remove(name);
    if (_names[scope]?.isEmpty ?? false) _names.remove(scope);
    await _save();
    notifyListeners();
  }

  /// The values a command in [project] runs with, by name: shared first,
  /// the project's over them. Never shown to an agent. One kept as a
  /// reference (`hcvault://path#key`) is fetched now, never stored; what
  /// could not be is said in [problems].
  Future<Map<String, String>> envFor(String project, {List<String>? problems}) async {
    final env = <String, String>{};
    for (final scope in [sharedScope, project]) {
      for (final name in _names[scope] ?? const <String>[]) {
        final v = await _keychain.get(_account(scope, name));
        if (v == null) continue;
        if (!v.startsWith(hcRef)) {
          env[name] = v;
          continue;
        }
        final got = await _fetchHc(v);
        if (got.value != null) {
          env[name] = got.value!;
        } else {
          problems?.add("$name couldn't be fetched from HashiCorp Vault: ${got.why}");
        }
      }
    }
    return env;
  }

  // HashiCorp Vault.

  /// How a reference to a secret in HashiCorp Vault begins.
  static const hcRef = 'hcvault://';

  /// Connects to the HashiCorp Vault at [address] with [token]: checked
  /// first (the token looks itself up), kept only if it works. Why not, or null.
  Future<String?> connectHcVault(String address, String token, {String namespace = ''}) async {
    final a = address.trim().replaceAll(RegExp(r'/+$'), '');
    if (!RegExp(r'^https?://').hasMatch(a)) {
      return 'Give its address, such as https://vault.example.com:8200.';
    }
    final check = await _hcGet(a, token.trim(), namespace.trim(), 'auth/token/lookup-self');
    if (check.json == null) return 'It answered no: ${check.why}';
    if (!await _keychain.set(_hcToken, token.trim())) {
      return "The token wasn't kept: the Keychain refused it.";
    }
    hcVault = (address: a, namespace: namespace.trim());
    await _save();
    notifyListeners();
    return null;
  }

  Future<void> disconnectHcVault() async {
    await _keychain.delete(_hcToken);
    hcVault = null;
    await _save();
    notifyListeners();
  }

  /// A reference's value; or why it could not be had.
  Future<({String? value, String why})> _fetchHc(String ref) async {
    final h = hcVault;
    if (h == null) return (value: null, why: 'it is not connected (Settings, Vault).');
    final token = await _keychain.get(_hcToken);
    if (token == null) return (value: null, why: 'its token is missing; connect it again.');
    final m = RegExp(r'^hcvault://([^#]+)#(.+)$').firstMatch(ref);
    if (m == null) {
      return (value: null, why: 'the reference should look like hcvault://secret/data/app#KEY.');
    }
    final got = await _hcGet(h.address, token, h.namespace, m[1]!);
    final json = got.json;
    if (json == null) return (value: null, why: got.why);
    // KV version 2 keeps the fields under data.data; version 1 under data.
    final data = json['data'];
    final fields = data is Map && data['data'] is Map ? data['data'] as Map : data;
    final v = fields is Map ? fields[m[2]] : null;
    return v == null ? (value: null, why: 'no field ${m[2]} at ${m[1]}.') : (value: '$v', why: '');
  }

  /// HttpClients made for HashiCorp Vault (a test gives its own).
  @visibleForTesting
  HttpClient Function() httpClient = HttpClient.new;

  Future<({Map<dynamic, dynamic>? json, String why})> _hcGet(
    String address,
    String token,
    String namespace,
    String path,
  ) async {
    final client = httpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('$address/v1/$path'));
      req.headers.set('X-Vault-Token', token);
      if (namespace.isNotEmpty) req.headers.set('X-Vault-Namespace', namespace);
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 403) return (json: null, why: 'the token was refused (403).');
      if (res.statusCode == 404) return (json: null, why: 'nothing at $path (404).');
      if (res.statusCode != 200) return (json: null, why: 'it answered ${res.statusCode}.');
      final j = jsonDecode(body);
      return j is Map ? (json: j, why: '') : (json: null, why: 'its answer was not understood.');
    } on Object catch (e) {
      return (json: null, why: "it couldn't be reached (${e.runtimeType}).");
    } finally {
      client.close(force: true);
    }
  }

  /// [text] with every value in [env] put as its name in brackets: what a
  /// command printed, before an agent reads it.
  static String redact(String text, Map<String, String> env) {
    var out = text;
    // Longest first, so a value inside another goes with the longer.
    final entries = env.entries.where((e) => e.value.length >= 4).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in entries) {
      out = out.replaceAll(e.value, '[${e.key}]');
    }
    return out;
  }
}

/// Where values are kept: the login Keychain on a Mac.
abstract class VaultKeychain {
  Future<bool> set(String account, String value);
  Future<String?> get(String account);
  Future<bool> delete(String account);
}

/// A project's .env files and the secrets in them: found, and moved into the
/// vault, each line then naming its secret (`KEY=vault:KEY`) instead of
/// holding it. Frameworks that load .env leave a variable already set as it
/// is, so a command run with the vault's values gets the real ones.
abstract final class EnvSecrets {
  static final _line = RegExp(
    r'''^(\s*(?:export\s+)?)([A-Za-z_][A-Za-z0-9_]*)(\s*=\s*)(.*?)\s*$''',
  );
  static final _example = RegExp(
    r'\.(example|sample|template|dist|defaults?)$',
    caseSensitive: false,
  );

  /// The .env files at the top of [project] that still hold secrets, and
  /// how many each holds.
  static Map<File, int> find(String project) {
    final out = <File, int>{};
    final dir = Directory(project);
    if (!dir.existsSync()) return out;
    for (final e in dir.listSync(followLinks: false)) {
      final name = e.path.split('/').last;
      if (e is! File || !(name == '.env' || name.startsWith('.env.')) || _example.hasMatch(name)) {
        continue;
      }
      final n = _secretsIn(e).length;
      if (n > 0) out[e] = n;
    }
    return out;
  }

  /// The name and value of each line in [f] that holds a secret.
  static Map<String, String> _secretsIn(File f) {
    final out = <String, String>{};
    try {
      if (f.lengthSync() > 512 * 1024) return out;
      for (final line in f.readAsLinesSync()) {
        if (line.trimLeft().startsWith('#')) continue;
        final m = _line.firstMatch(line);
        if (m == null) continue;
        final value = _unquote(m[4]!);
        if (value.isEmpty || value.startsWith('vault:')) continue;
        out[m[2]!] = value;
      }
    } on Object {
      // Unreadable: nothing found in it.
    }
    return out;
  }

  static String _unquote(String v) {
    final t = v.trim();
    if (t.length >= 2 && (t[0] == '"' || t[0] == "'") && t[t.length - 1] == t[0]) {
      return t.substring(1, t.length - 1);
    }
    // A comment after an unquoted value.
    final hash = t.indexOf(' #');
    return hash < 0 ? t : t.substring(0, hash).trim();
  }

  /// Moves the secrets in [files] into [vault] for [project]; a line changes
  /// only once its value reads back from the Keychain. How many moved, and
  /// the names that did not.
  static Future<({int moved, List<String> failed})> move(
    Vault vault,
    String project,
    Iterable<File> files,
  ) async {
    var moved = 0;
    final failed = <String>[];
    for (final f in files) {
      final secrets = _secretsIn(f);
      final kept = <String>{};
      for (final MapEntry(key: name, value: value) in secrets.entries) {
        if (await vault.put(project, name, value)) {
          kept.add(name);
          moved++;
        } else {
          failed.add(name);
        }
      }
      if (kept.isEmpty) continue;
      final lines = f.readAsLinesSync();
      final out = [
        for (final line in lines)
          if (_line.firstMatch(line) case final m?
              when kept.contains(m[2]) && !line.trimLeft().startsWith('#'))
            '${m[1]}${m[2]}${m[3]}vault:${m[2]}'
          else
            line,
      ];
      await f.writeAsString('${out.join('\n')}\n');
    }
    return (moved: moved, failed: failed);
  }
}

/// Something in a message that looks like a secret: what kind, and a name
/// to keep it under.
typedef SpottedSecret = ({String value, String kind, String name});

/// Secrets by their makers' own shapes, so a key pasted into a message is
/// caught before an assistant sees it. Only shapes with a known prefix, so
/// ordinary words are never taken for one.
abstract final class SecretSpotter {
  static final _shapes = <(RegExp, String, String)>[
    (
      RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----'),
      'A private key',
      'PRIVATE_KEY',
    ),
    (
      RegExp(r'\b(sk|rk)_(live|test)_[0-9A-Za-z]{16,}\b'),
      'A Stripe secret key',
      'STRIPE_SECRET_KEY',
    ),
    (RegExp(r'\bsk-ant-[0-9A-Za-z_-]{20,}'), 'An Anthropic API key', 'ANTHROPIC_API_KEY'),
    (RegExp(r'\bsk-(proj-)?[0-9A-Za-z_-]{20,}'), 'An OpenAI API key', 'OPENAI_API_KEY'),
    (
      RegExp(r'\b(ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{30,}\b|\bgithub_pat_[0-9A-Za-z_]{40,}'),
      'A GitHub token',
      'GITHUB_TOKEN',
    ),
    (RegExp(r'\bglpat-[0-9A-Za-z_-]{20,}'), 'A GitLab token', 'GITLAB_TOKEN'),
    (RegExp(r'\bxox[abprs]-[0-9A-Za-z-]{10,}'), 'A Slack token', 'SLACK_TOKEN'),
    (RegExp(r'\b(AKIA|ASIA)[0-9A-Z]{16}\b'), 'An AWS access key', 'AWS_ACCESS_KEY_ID'),
    (RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b'), 'A Google API key', 'GOOGLE_API_KEY'),
    (RegExp(r'\bhf_[0-9A-Za-z]{30,}\b'), 'A Hugging Face token', 'HF_TOKEN'),
    (RegExp(r'\bnpm_[0-9A-Za-z]{36}\b'), 'An npm token', 'NPM_TOKEN'),
    (RegExp(r'\bSG\.[0-9A-Za-z_-]{20,}\.[0-9A-Za-z_-]{20,}'), 'A SendGrid key', 'SENDGRID_API_KEY'),
    (RegExp(r'\b(re|rk)_[0-9A-Za-z]{20,}\b'), 'A Resend key', 'RESEND_API_KEY'),
    (
      RegExp(r'\beyJ[0-9A-Za-z_-]{10,}\.eyJ[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}'),
      'A signed token (JWT)',
      'TOKEN',
    ),
  ];

  /// The secrets in [text], each once, in the order found.
  static List<SpottedSecret> find(String text) {
    final out = <SpottedSecret>[];
    final seen = <String>{};
    for (final (re, kind, name) in _shapes) {
      for (final m in re.allMatches(text)) {
        final v = m[0]!;
        // One inside another already found (sk-ant- inside sk-): the longer stands.
        if (!seen.add(v) || out.any((o) => o.value.contains(v))) continue;
        out.add((value: v, kind: kind, name: name));
      }
    }
    return out;
  }
}
