import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';

/// A picture by where it is: a file here, or, in a browser (Helmy in
/// Chrome), a `blob:` address of one fetched from the computer Helmy runs on.
ImageProvider pictureOf(String path) =>
    path.startsWith('blob:') ? NetworkImage(path) : FileImage(File(path));

/// Whether the picture at [path] is there to show. A browser has no files
/// of its own: only what it fetched.
bool pictureThere(String path) => path.startsWith('blob:') || (!kIsWeb && File(path).existsSync());
