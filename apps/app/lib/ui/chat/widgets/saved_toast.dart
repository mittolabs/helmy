import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/services/desktop_service.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/toast.dart';
import '../../../utils/platform.dart';

/// "Saved", with the place it went and a way to open it or find it.
void showSavedToast(BuildContext context, String path, {String title = 'Saved'}) {
  final desktop = context.read<DesktopService>();
  late final ToastHandle toast;
  toast = showToast(
    context,
    title: title,
    description: tildePath(path),
    duration: const Duration(seconds: 8),
    action: Button(
      size: .sm,
      onPressed: () {
        desktop.open(path);
        toast.dismiss();
      },
      child: const Text('Open'),
    ),
    cancel: Button(
      size: .sm,
      variant: .outline,
      onPressed: () {
        desktop.reveal(path);
        toast.dismiss();
      },
      child: Text('Show in ${Desktop.current.fileManager}'),
    ),
  );
}
