import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps the desktop layout unchanged; includes phones rotated to landscape.
bool usesPhoneLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final phonePlatform =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  return size.width < 700 ||
      (phonePlatform && size.width < 1000 && size.shortestSide < 600);
}

EdgeInsets pageInsets(BuildContext context, EdgeInsets desktop) =>
    usesPhoneLayout(context)
    ? EdgeInsets.fromLTRB(12, 12, 12, desktop.bottom)
    : desktop;
