import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/approvals.dart';
import 'package:helmy/data/services/engines/codex/codex_reducer.dart';
import 'package:helmy/domain/helmy_voice.dart';
import 'package:helmy/domain/models/chat_item.dart';

// Shapes from codex-cli 0.167.0's app-server, captured 2026-11-11 with
// apps._default.default_tools_approval_mode = "prompt".
Map<String, Object?> _started(String tool) => {
  'method': 'item/started',
  'params': {
    'item': {
      'type': 'mcpToolCall',
      'id': 'call-1',
      'server': 'codex_apps',
      'tool': tool,
      'status': 'inProgress',
    },
  },
};

Map<String, Object?> _asks(String tool, {required bool readOnly}) => {
  'id': 7,
  'method': 'mcpServer/elicitation/request',
  'params': {
    'threadId': 't',
    'turnId': 'u',
    'serverName': 'codex_apps',
    'mode': 'form',
    'message': 'Allow this?',
    '_meta': {
      'codex_approval_kind': 'mcp_tool_call',
      'tool_name': tool,
      'tool_annotations': {'readOnlyHint': readOnly, 'destructiveHint': false},
    },
  },
};

void main() {
  const folder = '/Users/sam/chats/one';

  test('a tool acting on an account becomes a prompt tied to its step', () {
    final items = <ChatItem>[];
    CodexReducer(items)
      ..apply(_started('sites.create_site'))
      ..apply(_asks('sites.create_site', readOnly: false));
    final p = items.whereType<PermissionPrompt>().single;
    expect(p.toolName, accountAction);
    expect(p.requestId, '7');
    expect(p.toolUseId, 'call-1');
    expect(p.input['readOnly'], isFalse);
  });

  test('a form that is not a tool approval is not a prompt', () {
    final asks = _asks('sites.create_site', readOnly: false);
    ((asks['params'] as Map)['_meta'] as Map).remove('codex_approval_kind');
    expect(CodexReducer.isToolApproval(asks), isFalse);
    final items = <ChatItem>[];
    CodexReducer(items).apply(asks);
    expect(items.whereType<PermissionPrompt>(), isEmpty);
  });

  test('looking at an account goes ahead; changing it is put to the person', () {
    PermissionPrompt p(bool readOnly) => PermissionPrompt(
      requestId: 'r',
      toolName: accountAction,
      input: {'tool': 'codex_apps.sites.create_site', 'readOnly': readOnly},
      suggestions: const [],
    );
    expect(Approvals.atOnce(p(true), folder)?.verdict, Verdict.allow);
    expect(Approvals.mustAsk(p(true), folder), isNull);
    expect(Approvals.mustAsk(p(false), folder), 'Let Sites create site on your account?');
  });

  test("a connection's apps read as the app, never the connection", () {
    expect(toolLabel('codex_apps.sites.create_site'), 'Sites: create site');
    expect(toolLabel('notion.search'), 'Notion: search');
  });

  test("running a script an assistant installed is asked as what it is", () {
    PermissionPrompt shell(String command) => PermissionPrompt(
      requestId: 'r',
      toolName: 'Bash',
      input: {'command': command},
      suggestions: const [],
    );
    expect(
      Approvals.mustAsk(
        shell('node /Users/sam/.codex/plugins/sites/scripts/register.mjs --name Rise'),
        folder,
      ),
      'Run a script an assistant installed? It can act on your accounts.',
    );
    expect(
      Approvals.mustAsk(shell('echo x > /Users/sam/.codex/config.toml'), folder),
      'Change files in Helmy’s or another assistant’s configuration folder?',
    );
    expect(Approvals.mustAsk(shell('cat /Users/sam/.codex/AGENTS.md'), folder), isNull);
  });
}
