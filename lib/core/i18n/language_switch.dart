import 'package:flutter/material.dart';

import '../storage/key_value_store_factory.dart';
import 'i18n.dart';

/// Italiano / English toggle. Each language name is written in that language,
/// so anyone can find their own.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({this.onBeforeChange, super.key});

  /// Runs before the switch, e.g. to close the dialog that holds it: the whole
  /// interface is rebuilt in the new language right after.
  final VoidCallback? onBeforeChange;

  @override
  Widget build(BuildContext context) => SegmentedButton<AppLanguage>(
    showSelectedIcon: false,
    segments: [
      for (final language in AppLanguage.values)
        ButtonSegment(value: language, label: Text(language.label)),
    ],
    selected: {appLanguage.value},
    onSelectionChanged: (selection) {
      final language = selection.first;
      if (language == appLanguage.value) return;
      onBeforeChange?.call();
      setAppLanguage(language, createKeyValueStore());
    },
  );
}
