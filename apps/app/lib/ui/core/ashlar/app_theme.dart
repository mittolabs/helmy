// Your app's theme, written by `ashlar init`: change it here, or choose again with
// `ashlar apply`. Give it to [AshlarApp]: theme: appTheme, darkTheme: appDarkTheme.

import 'package:flutter/widgets.dart';

import 'palette.dart';
import 'theme.dart';

final appTheme = AshlarThemeData.from(
  brightness: Brightness.light,
  base: AshlarBase.neutral,
  style: AshlarStyle.standard,
);

final appDarkTheme = AshlarThemeData.from(
  brightness: Brightness.dark,
  base: AshlarBase.neutral,
  style: AshlarStyle.standard,
);
