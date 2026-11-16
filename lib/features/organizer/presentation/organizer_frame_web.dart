import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// L'Organizzatore è una pagina web autonoma (web/organizzatore/index.html):
/// qui viene mostrata dentro l'app così com'è, con i suoi dati nel browser.
Widget buildOrganizerFrame() => HtmlElementView.fromTagName(
  tagName: 'iframe',
  onElementCreated: (element) {
    final frame = element as web.HTMLIFrameElement;
    frame.src = 'organizzatore/index.html?embed=1';
    frame.title = 'Organizzatore';
    frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
  },
);

/// Una finestra di dialogo aperta sopra l'Organizzatore deve ricevere i clic
/// al posto della pagina incorporata: questo strato trasparente li intercetta.
Widget shieldFromEmbeddedFrame(Widget child) => Stack(
  fit: StackFit.expand,
  children: [
    HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (element) {
        (element as web.HTMLElement).style
          ..width = '100%'
          ..height = '100%';
      },
    ),
    child,
  ],
);

/// Una pagina del sito (per esempio la mappa dell'S&P 500) mostrata in un
/// riquadro dentro l'app.
Widget buildWebFrame(String source, String title) => HtmlElementView.fromTagName(
  key: ValueKey('frame-$source'),
  tagName: 'iframe',
  onElementCreated: (element) {
    final frame = element as web.HTMLIFrameElement;
    frame.src = source;
    frame.title = title;
    frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
  },
);
