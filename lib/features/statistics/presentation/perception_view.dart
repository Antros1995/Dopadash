import 'mood_chart.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../application/body_statistics_controller.dart';
import '../domain/body_statistics.dart';
import '../domain/perception_statistics.dart';
import 'statistics_charts.dart';

class PerceptionView extends StatefulWidget {
  const PerceptionView({required this.controller, super.key});
  final BodyStatisticsController controller;

  @override
  State<PerceptionView> createState() => _PerceptionViewState();
}

class _PerceptionViewState extends State<PerceptionView> {
  int _page = 0;
  static const _pageSize = 15;
  String? _historyKey;
  BodyStatisticsController get c => widget.controller;

  List<PerceptionEntry> _entries(BodyRange range) => c.perceptions
      .where((e) => range.contains(e.date) && !e.date.isAfter(c.today))
      .toList();

  Widget _title(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 20, color: AppColors.green),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  Widget _stat(String label, String value, String detail, IconData icon) =>
      StatsPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: AppColors.green),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final range = c.range;
    final filterKey =
        '${statsKey(range.start)}-${statsKey(range.end)}-${c.perceptionEmotion}';
    if (_historyKey != filterKey) {
      _page = 0;
      _historyKey = filterKey;
    }
    final all = _entries(range);
    final selectedEmotion = c.perceptionEmotion == 'all'
        ? null
        : c.perceptionEmotion;
    final analysis = PerceptionAnalysis(all, emotion: selectedEmotion);
    final series = range.dates
        .map((d) => analysis.dailyMeans[statsKey(d)])
        .toList();
    final elapsed = range.dates.where((d) => !d.isAfter(c.today)).length;
    final summary = BodySummary(series, elapsed);
    final previousRange = c.comparisonRange;
    final previousAnalysis = previousRange == null
        ? null
        : PerceptionAnalysis(_entries(previousRange), emotion: selectedEmotion);
    final previous = previousRange?.dates
        .map((d) => previousAnalysis!.dailyMeans[statsKey(d)])
        .toList();
    final previousSummary = previousRange == null
        ? null
        : BodySummary(
            previous!,
            previousRange.dates.where((d) => !d.isAfter(c.today)).length,
          );
    final ranked = analysis.frequencies.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count != 0 ? count : a.key.compareTo(b.key);
      });
    final top = ranked.isEmpty
        ? null
        : PerceivedEmotion.parse(ranked.first.key);
    final tied =
        ranked.isNotEmpty &&
        ranked.where((e) => e.value == ranked.first.value).length > 1;
    final history =
        all
            .where(
              (e) => selectedEmotion == null || e.emotion == selectedEmotion,
            )
            .toList()
          ..sort((a, b) {
            final day = b.date.compareTo(a.date);
            return day != 0 ? day : b.recordedAt.compareTo(a.recordedAt);
          });
    final pageCount = math.max(1, (history.length / _pageSize).ceil());
    final page = math.min(_page, pageCount - 1);
    final emotionName = selectedEmotion == null
        ? 'Tutte le emozioni'
        : PerceivedEmotion.parse(selectedEmotion)?.label ?? selectedEmotion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatsPanel(
          tint: AppColors.greenPale,
          child: Wrap(
            spacing: 24,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SizedBox(
                width: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Come ti sei sentito',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Le emozioni del tuo diario, nel tempo. Intensità da 1 a 5, con l’energia e l’orario che hai registrato.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('perception-filter-${c.perceptionEmotion}'),
                  initialValue: c.perceptionEmotion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Emozione da analizzare',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('Tutte le emozioni'),
                    ),
                    for (final e in PerceivedEmotion.values)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.emoji} ${e.label}'),
                      ),
                    if (selectedEmotion != null &&
                        PerceivedEmotion.parse(selectedEmotion) == null)
                      DropdownMenuItem(
                        value: selectedEmotion,
                        child: Text(selectedEmotion),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      c.change(() => c.perceptionEmotion = value);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StatsGrid(
          columns: 4,
          minWidth: 210,
          children: [
            _stat(
              'Registrazioni',
              '${analysis.entries.length}',
              emotionName,
              Icons.edit_note_outlined,
            ),
            _stat(
              'Giorni osservati',
              '${summary.count} / $elapsed',
              '${(summary.coverage * 100).round()}% del periodo',
              Icons.calendar_today_outlined,
            ),
            _stat(
              'Intensità media',
              BodyMetric.calm.format(summary.mean),
              'Media delle medie giornaliere',
              Icons.insights_outlined,
            ),
            _stat(
              'Emozione più frequente',
              ranked.isEmpty
                  ? '—'
                  : tied
                  ? 'Più emozioni'
                  : top?.label ?? ranked.first.key,
              ranked.isEmpty
                  ? 'Nessuna valutazione disponibile'
                  : '${ranked.first.value} registrazioni${tied ? ' a pari merito' : ' · ${top?.emoji ?? '💭'}'}',
              Icons.sentiment_satisfied_alt,
            ),
          ],
        ),
        const SizedBox(height: 12),
        StatsGrid(
          minWidth: 380,
          children: [
            StatsPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _title('Intensità nel tempo', Icons.show_chart),
                  const SizedBox(height: 8),
                  Text(
                    '$emotionName · media giornaliera · scala 1–5',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  BodyChart(
                    key: const ValueKey('perception-intensity-chart'),
                    values: series,
                    labels: range.dates.map(shortStatsDate).toList(),
                    metric: BodyMetric.calm,
                    seriesLabel: 'Intensità · $emotionName',
                    previous: previous,
                    average: c.moving && summary.count >= 8,
                    bars: summary.count < 8,
                    pointDetails: [
                      for (final d in range.dates)
                        '${analysis.byDate[statsKey(d)]?.length ?? 0} registrazioni',
                    ],
                    height: 245,
                  ),
                  ChartLegend(
                    items: [
                      ('Media del giorno', AppColors.green),
                      if (c.moving && summary.count >= 8)
                        ('Media mobile 7 giorni', AppColors.text),
                      if (previousRange != null)
                        ('Periodo precedente', AppColors.textMuted),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${summary.coverageLabel}${previousRange == null ? '' : ' · periodo precedente: ${previousSummary!.coverageLabel}'}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1, color: AppColors.border),
                  ),
                  _title('Com’è andata la giornata', Icons.wb_sunny_outlined),
                  const SizedBox(height: 8),
                  const Text(
                    'Tutte le emozioni · positivo sopra lo zero, negativo sotto',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 10),
                  MoodChart(
                    dates: range.dates.toList(),
                    mood: dailyMood(all),
                    keyFor: statsKey,
                  ),
                ],
              ),
            ),
            StatsPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _title('Le emozioni del periodo', Icons.donut_small_outlined),
                  const SizedBox(height: 8),
                  Text(
                    '${analysis.entries.length} registrazioni con valutazione · $emotionName',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (ranked.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'Nessuna emozione registrata nel periodo.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  else
                    for (final item in ranked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${PerceivedEmotion.parse(item.key)?.emoji ?? '💭'} ${PerceivedEmotion.parse(item.key)?.label ?? item.key}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  '${item.value} · ${(item.value / analysis.entries.length * 100).round()}%',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: item.value / analysis.entries.length,
                              minHeight: 5,
                              borderRadius: BorderRadius.circular(4),
                              color: AppColors.green,
                              backgroundColor: AppColors.greenSoft,
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StatsPanel(
          tint: AppColors.greenPale,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title('Lettura del periodo', Icons.auto_graph_outlined),
              const SizedBox(height: 12),
              Text(
                summary.count == 0
                    ? 'Non ci sono valutazioni per questa selezione.'
                    : previousSummary == null
                    ? 'Intensità media ${BodyMetric.calm.format(summary.mean)} su ${summary.count} giorni osservati.'
                    : summary.count < 2 || previousSummary.count < 2
                    ? 'Per confrontare i periodi servono almeno 2 giorni con valutazioni in ciascuno (${previousSummary.count} prima, ${summary.count} nel periodo).'
                    : 'Intensità media ${BodyMetric.calm.format(summary.mean)}; ${BodyMetric.calm.format(summary.mean! - previousSummary.mean!, delta: true)} rispetto al riferimento (${previousSummary.count} e ${summary.count} giorni osservati).',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ogni giorno ha lo stesso peso. I giorni senza valutazione e “No dati” sono esclusi dalle medie. L’intensità descrive quanto senti un’emozione, non quanto stai bene; il confronto è descrittivo.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StatsPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title('Storico delle emozioni', Icons.history),
              const SizedBox(height: 8),
              const Text(
                'Dal diario personale · orari Europe/Rome',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nessuna registrazione per questa selezione.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              else ...[
                for (final entry
                    in history.skip(page * _pageSize).take(_pageSize))
                  _historyTile(entry),
                if (pageCount > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Registrazioni precedenti',
                        onPressed: page == 0
                            ? null
                            : () => setState(() => _page = page - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        '${page + 1} / $pageCount',
                        style: const TextStyle(fontSize: 12),
                      ),
                      IconButton(
                        tooltip: 'Altre registrazioni',
                        onPressed: page + 1 == pageCount
                            ? null
                            : () => setState(() => _page = page + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _historyTile(PerceptionEntry entry) {
    final time = romeWallTime(entry.recordedAt);
    return Container(
      key: ValueKey('perception-entry-${entry.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(entry.emoji, style: const TextStyle(fontSize: 25)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.emotion == 'no_data' ? 'No dati' : entry.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${shortStatsDate(entry.date)} ${entry.date.year} · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.hasRating ? 'Intensità ${entry.intensity.toStringAsFixed(0)}/5' : 'Nessuna valutazione'} · Energia ${entry.energyLabel.toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (entry.hasRating)
            Text(
              '${entry.intensity.toStringAsFixed(0)}/5',
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.green,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
