import 'package:flutter/widgets.dart';

class NutritionElement extends StatelessWidget {
  const NutritionElement({required this.configuration, super.key});
  final String configuration;
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        'L’Alimentazione è disponibile aprendo l’app come sito.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
