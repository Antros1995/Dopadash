import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class NutritionElement extends StatefulWidget {
  const NutritionElement({required this.configuration, super.key});
  final String configuration;
  @override
  State<NutritionElement> createState() => _NutritionElementState();
}

class _NutritionElementState extends State<NutritionElement> {
  web.HTMLElement? _element;

  @override
  void didUpdateWidget(covariant NutritionElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration != widget.configuration) {
      _element?.setAttribute('data-config', widget.configuration);
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'germoglio-diet',
    onElementCreated: (element) {
      final host = element as web.HTMLElement;
      _element = host;
      host
        ..setAttribute('data-config', widget.configuration)
        ..setAttribute('data-page', 'home');
      host.style
        ..width = '100%'
        ..height = '100%'
        ..display = 'block'
        ..overflow = 'auto';
    },
  );
}
