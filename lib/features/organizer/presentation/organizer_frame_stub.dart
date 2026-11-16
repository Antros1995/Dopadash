import 'package:flutter/material.dart';

/// Fuori dal browser la pagina incorporata non è disponibile.
Widget buildOrganizerFrame() => const Center(
  child: Padding(
    padding: EdgeInsets.all(32),
    child: Text(
      'L’Organizzatore è disponibile aprendo l’app come sito locale.',
      textAlign: TextAlign.center,
    ),
  ),
);

Widget shieldFromEmbeddedFrame(Widget child) => child;

Widget buildWebFrame(String source, String title) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Text('$title è disponibile aprendo l’app come sito.'),
  ),
);
