import 'dart:convert';

/// A real iPhone or iPad paired with this Mac, as Xcode's `devicectl` lists
/// it: reached over the cable or the network.
typedef Iphone = ({String id, String name, String os, bool wired});

/// An app on a real iPhone that its developer built and installed (the ones
/// worth launching from here), by bundle id and name.
typedef PhoneApp = ({String bundle, String name});

/// The paired iPhones and iPads in `devicectl list devices --json-output`.
/// One Apple no longer reaches (asleep, out of range) is left out.
List<Iphone> iphonesFrom(String json) {
  final Object? j;
  try {
    j = jsonDecode(json);
  } on FormatException {
    return const [];
  }
  final list = j is Map && j['result'] is Map ? (j['result'] as Map)['devices'] : null;
  if (list is! List) return const [];
  return [
    for (final d in list.whereType<Map>())
      if (_phone(d)) _iphone(d),
  ];
}

bool _phone(Map d) {
  final hw = d['hardwareProperties'];
  final conn = d['connectionProperties'];
  if (hw is! Map || conn is! Map) return false;
  final platform = '${hw['platform']}';
  return (platform == 'iOS' || platform == 'iPadOS') &&
      conn['pairingState'] == 'paired' &&
      conn['tunnelState'] != 'unavailable';
}

Iphone _iphone(Map d) {
  final props = d['deviceProperties'] as Map? ?? const {};
  final conn = d['connectionProperties'] as Map;
  return (
    id: '${d['identifier']}',
    // Apple's own apostrophe ("Mitto’s iPhone") is kept as the phone says it.
    name: '${props['name'] ?? (d['hardwareProperties'] as Map)['marketingName'] ?? 'iPhone'}',
    os: '${props['osVersionNumber'] ?? ''}',
    wired: conn['transportType'] == 'wired',
  );
}

/// The apps in `devicectl device info apps --json-output` that their
/// developer built: the ones a person tries from here. By name.
List<PhoneApp> phoneAppsFrom(String json) {
  final Object? j;
  try {
    j = jsonDecode(json);
  } on FormatException {
    return const [];
  }
  final list = j is Map && j['result'] is Map ? (j['result'] as Map)['apps'] : null;
  if (list is! List) return const [];
  final apps = [
    for (final a in list.whereType<Map>())
      if (a['builtByDeveloper'] == true && a['bundleIdentifier'] != null)
        (bundle: '${a['bundleIdentifier']}', name: '${a['name'] ?? a['bundleIdentifier']}'),
  ];
  apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return apps;
}

/// What `devicectl` said went wrong, as JSON (its `error`) or as text.
String _said(String output) {
  try {
    final j = jsonDecode(output);
    if (j is Map && j['error'] != null) return jsonEncode(j['error']);
  } on FormatException {
    // Text, as it printed it.
  }
  return output;
}

/// Why [name] would not do what was asked, from what `devicectl` said, and
/// what fixes it, in plain words. Apple's own reason comes last when it is
/// not one of the known ones.
String phoneTrouble(String name, String output) {
  final said = _said(output);
  final s = said.toLowerCase();
  if (s.contains('devicelocked') || s.contains('device is locked')) {
    return '$name is locked. Unlock it, then try again.';
  }
  if (s.contains('developer mode')) {
    return '$name has Developer Mode off. Turn it on in its Settings, under Privacy & '
        'Security, Developer Mode; it restarts. Then try again.';
  }
  if (s.contains('not paired') || s.contains('pairing')) {
    return "$name isn't paired with this Mac. Connect it with a cable and tap Trust on it.";
  }
  if (s.contains('applicationverificationfailed') ||
      s.contains('code signature') ||
      s.contains('provisioning profile') ||
      s.contains('not signed')) {
    return "$name won't install it: the app isn't signed for this iPhone. Build it for a "
        'device, with your team chosen under Signing in Xcode, then install it again.';
  }
  if (s.contains('unable to locate') ||
      s.contains('not installed') ||
      s.contains('no application') ||
      s.contains('the application could not be found')) {
    return "That app isn't on $name. Install it first.";
  }
  if (s.contains('timed out') ||
      s.contains('timeout') ||
      s.contains('unavailable') ||
      s.contains('could not connect') ||
      s.contains('connection')) {
    return "$name can't be reached. Wake it, and have it on this Mac's Wi-Fi or on the "
        'cable, then try again.';
  }
  final reason =
      RegExp(r'"NSLocalizedDescription":\{"string":"([^"]+)"').firstMatch(said)?[1] ??
      RegExp(r'NSLocalizedDescription\s*=\s*"?([^";\n]+)').firstMatch(said)?[1] ??
      said.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
  return reason.isEmpty ? "$name didn't do it." : "$name didn't do it: $reason";
}
