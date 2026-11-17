import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/presentation/mac_widgets.dart';
import '../domain/daily_models.dart';
import '../../../core/i18n/i18n.dart';

/// Esito della finestra: [value] nullo significa "cancella il dato".
typedef ScreenTimeResult = ({ScreenTime? value});

/// Modifica del tempo al cellulare: totale e attività da non conteggiare
/// (per esempio Maps o Duolingo).
Future<ScreenTimeResult?> showScreenTimeDialog(
  BuildContext context,
  ScreenTime? current,
) => showDialog<ScreenTimeResult>(
  context: context,
  builder: (_) => _ScreenTimeDialog(current: current),
);

class _ScreenTimeDialog extends StatefulWidget {
  const _ScreenTimeDialog({required this.current});
  final ScreenTime? current;
  @override
  State<_ScreenTimeDialog> createState() => _ScreenTimeDialogState();
}

class _ScreenTimeDialogState extends State<_ScreenTimeDialog> {
  late final _total = TextEditingController(
    text: widget.current == null
        ? ''
        : formatMinutes(widget.current!.totalMinutes),
  );
  final _name = TextEditingController(), _time = TextEditingController();
  late final List<ScreenTimeExclusion> _exclusions = [
    ...?widget.current?.exclusions,
  ];
  String? _error;

  @override
  void dispose() {
    _total.dispose();
    _name.dispose();
    _time.dispose();
    super.dispose();
  }

  void _addExclusion() {
    final name = _name.text.trim(), minutes = parseMinutes(_time.text);
    if (name.isEmpty || minutes == null || minutes == 0) {
      setState(
        () => _error = tr(
          'Per escludere un’app servono nome e durata (es. 0:45).',
          'To exclude an app, give a name and a duration (e.g. 0:45).',
        ),
      );
      return;
    }
    setState(() {
      _error = null;
      _exclusions.add(
        ScreenTimeExclusion(
          id: 'excl_${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          minutes: minutes,
        ),
      );
      _name.clear();
      _time.clear();
    });
  }

  void _save() {
    final total = parseMinutes(_total.text);
    if (total == null) {
      setState(
        () => _error = tr(
          'Scrivi il totale in ore e minuti, per esempio 4:00.',
          'Write the total in hours and minutes, for example 4:00.',
        ),
      );
      return;
    }
    Navigator.pop<ScreenTimeResult>(context, (
      value: ScreenTime(totalMinutes: total, exclusions: _exclusions),
    ));
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: AppColors.fill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final total = parseMinutes(_total.text);
    final preview = total == null
        ? null
        : ScreenTime(totalMinutes: total, exclusions: _exclusions);
    return AlertDialog(
      title: Text(tr('Tempo al cellulare', 'Phone time')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Totale letto dal telefono', 'Total read from the phone'),
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _total,
                autofocus: widget.current == null,
                keyboardType: TextInputType.datetime,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                decoration: _decoration('04:00'),
              ),
              const SizedBox(height: 16),
              Text(
                tr('App da non conteggiare', 'Apps that don’t count'),
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              for (final exclusion in _exclusions)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exclusion.name,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    MacChip('− ${formatMinutes(exclusion.minutes)}'),
                    IconButton(
                      onPressed: () =>
                          setState(() => _exclusions.remove(exclusion)),
                      tooltip: tr(
                        'Togli ${exclusion.name}',
                        'Remove ${exclusion.name}',
                      ),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration(
                        tr('Nome, es. Maps', 'Name, e.g. Maps'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _time,
                      keyboardType: TextInputType.datetime,
                      onSubmitted: (_) => _addExclusion(),
                      decoration: _decoration('0:45'),
                    ),
                  ),
                  IconButton(
                    onPressed: _addExclusion,
                    tooltip: tr('Aggiungi esclusione', 'Add exclusion'),
                    icon: const Icon(Icons.add_circle, color: AppColors.green),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.danger,
                  ),
                )
              else if (preview != null)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    MacChip(
                      tr(
                        'conteggiate ${formatMinutes(preview.countedMinutes)}',
                        'counted ${formatMinutes(preview.countedMinutes)}',
                      ),
                      tone: AppColors.green,
                    ),
                    MacChip('${preview.medal.emoji} ${preview.medal.label}'),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () =>
                Navigator.pop<ScreenTimeResult>(context, (value: null)),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(tr('Cancella il dato', 'Clear the value')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Annulla', 'Cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Salva', 'Save'))),
      ],
    );
  }
}
