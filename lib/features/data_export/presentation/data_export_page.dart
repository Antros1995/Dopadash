import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/presentation/app_card.dart';
import '../../../core/utils/date_formatters.dart';
import '../../fitbit/data/fitbit_repository.dart';
import '../../fitbit/domain/fitbit_day.dart';
import '../../routines/application/routine_controller.dart';
import '../../routines/domain/routine.dart';
import '../data/diet_export.dart';
import '../data/export_file_saver.dart';
import '../data/export_workbook_builder.dart';
import '../domain/export_selection.dart';

class DataExportPage extends StatefulWidget {
  const DataExportPage({
    required this.routines,
    required this.fitbitRepository,
    this.dietRepository,
    super.key,
  });

  final RoutineController routines;
  final FitbitRepository fitbitRepository;

  /// Stato della dieta (Alimentazione). Senza, la sezione non compare.
  final DietStateRepository? dietRepository;

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  late DateTime _start;
  late DateTime _end;
  final Set<FitbitExportField> _fitbitFields = FitbitExportField.values.toSet();
  late final Set<String> _routineIds;
  late final Set<DietExportPart> _dietParts = widget.dietRepository == null
      ? <DietExportPart>{}
      : DietExportPart.values.toSet();
  bool _exporting = false;
  int _completedDays = 0;
  int _totalDays = 0;
  String? _resultMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final today = dateOnly(DateTime.now());
    _end = today;
    _start = today.subtract(const Duration(days: 29));
    _routineIds = _routineOptions().map((item) => item.id).toSet();
  }

  List<RoutineDefinition> _routineOptions() {
    final byId = <String, RoutineDefinition>{};
    for (final definition in widget.routines.history) {
      final existing = byId[definition.id];
      final definitionDate = definition.validFrom ?? DateTime(1970);
      final existingDate = existing?.validFrom ?? DateTime(1970);
      if (existing == null || !definitionDate.isBefore(existingDate)) {
        byId[definition.id] = definition;
      }
    }
    final result = byId.values.toList()
      ..sort((left, right) => left.position.compareTo(right.position));
    return result;
  }

  Future<void> _pickStart() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Data iniziale dell’esportazione',
      cancelText: 'Annulla',
      confirmText: 'Conferma',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _start = dateOnly(selected);
      if (_end.isBefore(_start)) _end = _start;
    });
  }

  Future<void> _pickEnd() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Data finale dell’esportazione',
      cancelText: 'Annulla',
      confirmText: 'Conferma',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _end = dateOnly(selected);
      if (_start.isAfter(_end)) _start = _end;
    });
  }

  Future<void> _export() async {
    if (_fitbitFields.isEmpty && _routineIds.isEmpty && _dietParts.isEmpty) {
      setState(() => _errorMessage = 'Seleziona almeno un dato da esportare.');
      return;
    }
    final totalDays = _end.difference(_start).inDays + 1;
    setState(() {
      _exporting = true;
      _completedDays = 0;
      _totalDays = totalDays;
      _errorMessage = null;
      _resultMessage = null;
    });

    try {
      final fitbitDays = <DateTime, FitbitDay>{};
      if (_fitbitFields.isNotEmpty) {
        for (var offset = 0; offset < totalDays; offset++) {
          final date = _start.add(Duration(days: offset));
          final status = await widget.fitbitRepository.fetchDay(date);
          if (!status.isConnected && status.day == null) {
            throw StateError(
              'Fitbit non è collegato. Collegalo dalla Lavagna e riprova.',
            );
          }
          if (status.day case final day?) {
            fitbitDays[dateOnly(DateTime.parse(day.date))] = day;
          }
          if (mounted) setState(() => _completedDays = offset + 1);
        }
      }

      final routineEntries = _routineIds.isEmpty
          ? <DateTime, Map<String, RoutineEntry>>{}
          : await widget.routines.repository.fetchEntries(
              start: _start,
              endExclusive: _end.add(const Duration(days: 1)),
            );
      Map<String, dynamic>? dietState;
      if (_dietParts.isNotEmpty) {
        dietState = await widget.dietRepository?.fetchState();
        if (dietState == null) {
          throw StateError('Non ci sono ancora dati della dieta da esportare.');
        }
      }
      final sheetParts = _dietParts.difference({DietExportPart.backup});
      final locations = <String>[];
      if (_fitbitFields.isNotEmpty ||
          _routineIds.isNotEmpty ||
          sheetParts.isNotEmpty) {
        final bytes = const ExportWorkbookBuilder().build(
          ExportWorkbookInput(
            start: _start,
            end: _end,
            fitbitFields: Set.unmodifiable(_fitbitFields),
            fitbitDays: Map.unmodifiable(fitbitDays),
            routineIds: Set.unmodifiable(_routineIds),
            routineHistory: widget.routines.history,
            routineEntries: routineEntries,
            dietParts: Set.unmodifiable(sheetParts),
            dietState: sheetParts.isEmpty ? null : dietState,
          ),
        );
        final fileName =
            'monitoraggio_dati_${_fileDate(_start)}_${_fileDate(_end)}.xlsx';
        locations.add(await saveExportFile(bytes, fileName));
      }
      if (_dietParts.contains(DietExportPart.backup) && dietState != null) {
        locations.add(
          await saveExportFile(
            DietSheets.backup(dietState),
            'dieta_completa_${_fileDate(DateTime.now())}.json',
          ),
        );
      }
      if (mounted) {
        setState(() {
          _resultMessage = locations.length == 1
              ? 'File creato: ${locations.single}'
              : 'File creati: ${locations.join(' · ')}';
          _exporting = false;
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.routines,
      builder: (context, _) {
        final routines = _routineOptions();
        return LayoutBuilder(
          builder: (context, constraints) {
            final pagePadding = constraints.maxWidth < 600 ? 16.0 : 28.0;
            final twoColumns = constraints.maxWidth >= 980;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pagePadding, 24, pagePadding, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ExportHeader(),
                      const SizedBox(height: AppSpacing.lg),
                      _PeriodCard(
                        start: _start,
                        end: _end,
                        onStart: _exporting ? null : _pickStart,
                        onEnd: _exporting ? null : _pickEnd,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (twoColumns)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _fitbitSelection()),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(child: _routineSelection(routines)),
                          ],
                        )
                      else ...[
                        _fitbitSelection(),
                        const SizedBox(height: AppSpacing.lg),
                        _routineSelection(routines),
                      ],
                      if (widget.dietRepository != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _dietSelection(),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _ExportActionCard(
                        exporting: _exporting,
                        completedDays: _completedDays,
                        totalDays: _totalDays,
                        selectedCount:
                            _fitbitFields.length +
                            _routineIds.length +
                            _dietParts.length,
                        resultMessage: _resultMessage,
                        errorMessage: _errorMessage,
                        onExport: _export,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _fitbitSelection() => _SelectionCard(
    title: 'Dati orologio',
    subtitle: 'Scegli anche un singolo parametro oppure selezionali tutti.',
    icon: Icons.watch_outlined,
    allSelected: _fitbitFields.length == FitbitExportField.values.length,
    someSelected: _fitbitFields.isNotEmpty,
    onToggleAll: _exporting
        ? null
        : (selected) => setState(() {
            _fitbitFields
              ..clear()
              ..addAll(selected ? FitbitExportField.values : const []);
          }),
    children: [
      for (final field in FitbitExportField.values)
        _OptionCheckbox(
          label: field.label,
          selected: _fitbitFields.contains(field),
          onChanged: _exporting
              ? null
              : (selected) => setState(() {
                  if (selected) {
                    _fitbitFields.add(field);
                  } else {
                    _fitbitFields.remove(field);
                  }
                }),
        ),
    ],
  );

  Widget _dietSelection() => _SelectionCard(
    title: 'Alimentazione',
    subtitle:
        'Tutta la dieta: piani, pasti scelti, cibi fuori piano e calorie, per studiarla nel tempo.',
    icon: Icons.restaurant_outlined,
    allSelected: _dietParts.length == DietExportPart.values.length,
    someSelected: _dietParts.isNotEmpty,
    onToggleAll: _exporting
        ? null
        : (selected) => setState(() {
            _dietParts
              ..clear()
              ..addAll(selected ? DietExportPart.values : const []);
          }),
    children: [
      for (final part in DietExportPart.values)
        _OptionCheckbox(
          label: part.label,
          selected: _dietParts.contains(part),
          onChanged: _exporting
              ? null
              : (selected) => setState(() {
                  if (selected) {
                    _dietParts.add(part);
                  } else {
                    _dietParts.remove(part);
                  }
                }),
        ),
    ],
  );

  Widget _routineSelection(List<RoutineDefinition> routines) => _SelectionCard(
    title: 'Checklist e abitudini',
    subtitle: 'Palestra, alimentazione e tutte le altre voci della routine.',
    icon: Icons.fact_check_outlined,
    allSelected:
        routines.isNotEmpty &&
        routines.every((item) => _routineIds.contains(item.id)),
    someSelected: routines.any((item) => _routineIds.contains(item.id)),
    onToggleAll: _exporting
        ? null
        : (selected) => setState(() {
            if (selected) {
              _routineIds.addAll(routines.map((item) => item.id));
            } else {
              _routineIds.removeAll(routines.map((item) => item.id));
            }
          }),
    children: [
      for (final routine in routines)
        _OptionCheckbox(
          label: routine.name,
          selected: _routineIds.contains(routine.id),
          onChanged: _exporting
              ? null
              : (selected) => setState(() {
                  if (selected) {
                    _routineIds.add(routine.id);
                  } else {
                    _routineIds.remove(routine.id);
                  }
                }),
        ),
    ],
  );
}

class _ExportHeader extends StatelessWidget {
  const _ExportHeader();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.greenPale,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.green.withValues(alpha: .22)),
        ),
        child: const Icon(
          Icons.download_for_offline_outlined,
          color: AppColors.green,
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esporta dati',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Crea un file Excel scegliendo periodo, dati degli orologi e checklist.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.start,
    required this.end,
    required this.onStart,
    required this.onEnd,
  });

  final DateTime start;
  final DateTime end;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading(
          title: 'Periodo',
          subtitle: 'Sono incluse sia la data iniziale sia quella finale.',
          trailing: Icon(Icons.date_range_outlined, color: AppColors.green),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final controls = [
              _DateControl(label: 'Dal', date: start, onPressed: onStart),
              _DateControl(label: 'Al', date: end, onPressed: onEnd),
            ];
            return compact
                ? Column(
                    children: [
                      controls.first,
                      const SizedBox(height: AppSpacing.sm),
                      controls.last,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: controls.first),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: controls.last),
                    ],
                  );
          },
        ),
      ],
    ),
  );
}

class _DateControl extends StatelessWidget {
  const _DateControl({
    required this.label,
    required this.date,
    required this.onPressed,
  });

  final String label;
  final DateTime date;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(54),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    child: Row(
      children: [
        const Icon(Icons.calendar_today_outlined, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$label ${capitalize(formatItalianDate(date))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.allSelected,
    required this.someSelected,
    required this.onToggleAll,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool allSelected;
  final bool someSelected;
  final ValueChanged<bool>? onToggleAll;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: title,
            subtitle: subtitle,
            trailing: Icon(icon, color: AppColors.green),
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            value: allSelected ? true : (someSelected ? null : false),
            tristate: true,
            onChanged: onToggleAll == null
                ? null
                : (value) => onToggleAll!(value != true || !allSelected),
            title: const Text(
              'Seleziona tutto',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.xs),
          for (final child in children) child,
        ],
      ),
    ),
  );
}

class _OptionCheckbox extends StatelessWidget {
  const _OptionCheckbox({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: selected,
    onChanged: onChanged == null ? null : (value) => onChanged!(value ?? false),
    title: Text(label, style: const TextStyle(fontSize: 13)),
    contentPadding: EdgeInsets.zero,
    dense: true,
    visualDensity: const VisualDensity(vertical: -1),
    controlAffinity: ListTileControlAffinity.leading,
  );
}

class _ExportActionCard extends StatelessWidget {
  const _ExportActionCard({
    required this.exporting,
    required this.completedDays,
    required this.totalDays,
    required this.selectedCount,
    required this.resultMessage,
    required this.errorMessage,
    required this.onExport,
  });

  final bool exporting;
  final int completedDays;
  final int totalDays;
  final int selectedCount;
  final String? resultMessage;
  final String? errorMessage;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.table_view_outlined, color: AppColors.green),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$selectedCount elementi selezionati',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('export-data-button'),
              onPressed: exporting ? null : onExport,
              icon: exporting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(exporting ? 'Preparazione…' : 'Scarica Excel'),
            ),
          ],
        ),
        if (exporting) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: totalDays == 0 ? null : completedDays / totalDays,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Lettura dati orologio: $completedDays di $totalDays giorni',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
        if (resultMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          _StatusMessage(
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.green,
            message: resultMessage!,
          ),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          _StatusMessage(
            icon: Icons.error_outline_rounded,
            color: AppColors.danger,
            message: errorMessage!,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Il file viene creato sul dispositivo. I dati sanitari non vengono inviati a servizi aggiuntivi.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(message, style: TextStyle(color: color)),
      ),
    ],
  );
}

String _fileDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}'
    '${value.month.toString().padLeft(2, '0')}'
    '${value.day.toString().padLeft(2, '0')}';

String _friendlyError(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is FitbitFailure) {
    return switch (error.kind) {
      FitbitFailureKind.sessionExpired =>
        'Sessione scaduta. Accedi di nuovo e riprova.',
      FitbitFailureKind.notAllowed => 'Accesso ai dati Fitbit non consentito.',
      FitbitFailureKind.unavailable => 'Fitbit non risponde. Riprova tra poco.',
      FitbitFailureKind.invalidResponse =>
        'I dati Fitbit ricevuti non sono validi.',
    };
  }
  return 'Esportazione non riuscita. Riprova.';
}
