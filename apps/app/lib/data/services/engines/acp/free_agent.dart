import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../domain/models/settings.dart';
import 'acp_registry.dart';

/// The connection that answers on day one, with no account: OpenCode, on
/// its free models whose makers keep nothing (opencodeProfile). Its id is
/// the one Best at gives quick questions to.
const freeAgentId = 'acp.opencode';

/// Installs OpenCode from the agent registry into Helmy's own folder, as
/// Settings does; the account to keep. Throws when the registry or the
/// download does not answer.
Future<ConnectionAccount> installFreeAgent(void Function(int got, int total) progress) =>
    installAgent('opencode', progress: progress);

/// Installs agent [registryId] (opencode, cursor, grok-build, antigravity-acp)
/// from the agent registry into Helmy's own folder; the account to keep, as
/// `acp.<registryId>`. Throws when the registry or the download does not
/// answer, or it is not offered for this computer.
Future<ConnectionAccount> installAgent(
  String registryId, {
  void Function(int got, int total)? progress,
}) async {
  final all = await AcpRegistry().list();
  final listing = all?.where((l) => l.id == registryId && l.runsHere).firstOrNull;
  if (listing == null) {
    throw const AcpInstallTrouble(
      "The list of agents (cdn.agentclientprotocol.com) didn't answer. Check the internet "
      'connection and try again.',
    );
  }
  final root = '${(await getApplicationSupportDirectory()).path}/agents';
  final launch = await AcpRegistry.install(listing, root: root, progress: progress);
  // Downloaded into Helmy's folder (a path, on any system), not fetched by npx.
  final own = File(launch.command).isAbsolute;
  return ConnectionAccount(
    id: 'acp.$registryId',
    kind: 'acp',
    name: listing.name,
    folder: own ? '$root/${listing.id}' : '',
    made: own,
    command: launch.command,
    args: launch.args,
    agentId: listing.id,
    icon: listing.icon,
  );
}
