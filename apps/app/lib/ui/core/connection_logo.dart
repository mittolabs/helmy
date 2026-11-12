import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'ashlar/theme.dart';

/// A connection's own logo, in one color like the rest of Helmy's icons:
/// Claude's for every Claude Code account, OpenAI's for Codex, Ollama's for
/// the model on this computer, Cursor's, Grok's, Antigravity's and OpenCode's,
/// and any other agent's as the ACP registry lists it
/// ([icon]). A generic mark where there is none.
class ConnectionLogo extends StatelessWidget {
  const ConnectionLogo(
    this.engineId, {
    super.key,
    this.icon,
    this.size = 16,
    this.color,
    this.brand = false,
  });

  /// In the maker's own color, where it has one (Claude's orange); the
  /// black-and-white marks (OpenAI, Cursor, Grok) stay in the text color.
  final bool brand;

  /// The maker's color for [engineId]'s logo; null for a black-and-white mark.
  static Color? brandColor(String engineId) => switch (engineId) {
    _ when engineId.startsWith('claude') => const Color(0xFFD97757),
    _ when engineId.startsWith('acp.antigravity-acp') => const Color(0xFF4285F4),
    _ => null,
  };

  final String engineId;

  /// An agent's icon, from the registry.
  final String? icon;
  final double size;
  final Color? color;

  /// The bundled logo for [engineId], if it has one.
  static String? assetFor(String engineId) => switch (engineId) {
    _ when engineId.startsWith('claude') => 'assets/logos/claude.svg',
    _ when engineId.startsWith('codex') => 'assets/logos/openai.svg',
    _ when engineId.contains('ollama') => 'assets/logos/ollama.svg',
    _ when engineId.startsWith('acp.cursor') => 'assets/logos/cursor.svg',
    _ when engineId.startsWith('acp.grok-build') => 'assets/logos/grok.svg',
    _ when engineId.startsWith('acp.antigravity-acp') => 'assets/logos/antigravity.svg',
    _ when engineId.startsWith('acp.opencode') => 'assets/logos/opencode.svg',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        (brand ? brandColor(engineId) : null) ??
        AshlarTheme.of(context).colors.foreground;
    final filter = ColorFilter.mode(c, BlendMode.srcIn);
    final fallback = AshlarIcon(AshlarIconsRoundedStroke.aiAgent, size: size, color: c);
    final asset = assetFor(engineId);
    final Widget logo;
    if (asset != null) {
      logo = SvgPicture.asset(asset, width: size, height: size, colorFilter: filter);
    } else if (icon case final url? when url.startsWith('https://')) {
      logo = SvgPicture.network(
        url,
        width: size,
        height: size,
        colorFilter: filter,
        placeholderBuilder: (_) => fallback,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      logo = fallback;
    }
    return Semantics(
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: logo),
    );
  }
}
