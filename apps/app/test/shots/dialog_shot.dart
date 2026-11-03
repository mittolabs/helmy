import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:helmy/ui/core/helmy_dialog.dart';

/// The delete dialog, for `ashlar shot`.
class DeleteDialogShot extends StatelessWidget {
  const DeleteDialogShot({super.key});

  @override
  Widget build(BuildContext context) => HelmyDialog(
    title: 'Delete this session?',
    body: '"New session in mitto" and its conversation leave Helmy. Files in the folder stay as they are.',
    destructive: true,
    icon: AshlarIconsRoundedStroke.trash,
    actions: [
      DialogButton('Cancel', onPressed: () {}),
      DialogButton('Delete', main: true, destructive: true, onPressed: () {}),
    ],
  );
}
