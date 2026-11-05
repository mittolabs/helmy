import 'dart:async';

import 'package:helmy/utils/platform.dart';

/// Every test sees a Mac, the computer Helmy is for first, whatever runs it
/// (the CI runs Linux): keys, words and window buttons as on a Mac. A test
/// about another computer sets [Desktop.current] itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Desktop.current = Desktop.mac;
  await testMain();
}
