import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/platform/image_pick.dart';
import '../../../core/presentation/mac_widgets.dart';
import '../../wardrobe/wardrobe_repository.dart';
import 'daily_widgets.dart';

/// Foto dei progressi. Restano nascoste: non vengono nemmeno scaricate finché
/// non si preme "Apri le foto". Una volta aperte si confrontano due date
/// fianco a fianco.
class ProgressPhotosCard extends StatefulWidget {
  const ProgressPhotosCard({
    required this.repository,
    required this.today,
    super.key,
  });
  final ProgressPhotoRepository repository;
  final DateTime today;
  @override
  State<ProgressPhotosCard> createState() => _ProgressPhotosCardState();
}

class _ProgressPhotosCardState extends State<ProgressPhotosCard> {
  bool _open = false, _loading = false, _busy = false;
  Object? _error;
  List<ProgressPhoto> _photos = const [];
  DateTime? _before, _after;

  static String label(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  List<DateTime> get _dates =>
      {for (final p in _photos) p.date}.toList()..sort();

  Future<void> _load({bool keepSelection = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final photos = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
        final dates = _dates;
        if (!keepSelection || !dates.contains(_before) || !dates.contains(_after)) {
          // Di partenza: la prima sessione contro l'ultima.
          _before = dates.isEmpty ? null : dates.first;
          _after = dates.isEmpty ? null : dates.last;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _toggle() {
    if (_open) {
      // Chiudendo si dimenticano anche le immagini già scaricate.
      setState(() {
        _open = false;
        _photos = const [];
      });
    } else {
      setState(() => _open = true);
      _load();
    }
  }

  Future<void> _add() async {
    final date = await showDatePicker(
      context: context,
      initialDate: widget.today,
      firstDate: DateTime(2020),
      lastDate: widget.today,
      helpText: 'Data delle foto',
    );
    if (date == null) return;
    final image = await pickImage(maxSide: 1600);
    if (image == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.add(date, image.bytes);
      await _load(keepSelection: true);
      if (mounted) setState(() => _after = DateTime(date.year, date.month, date.day));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(ProgressPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare questa foto?'),
        content: const Text('Sparisce anche dall’app per iPhone. Non si può annullare.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repository.delete(photo);
      await _load(keepSelection: true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _zoom(ProgressPhoto photo) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          InteractiveViewer(
            maxScale: 5,
            child: Image.network(photo.url, fit: BoxFit.contain),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              tooltip: 'Chiudi',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _column(String title, DateTime? selected, ValueChanged<DateTime> onChanged) {
    final dates = _dates;
    final photos = [
      for (final p in _photos)
        if (p.date == selected) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.fill,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime>(
                    value: selected,
                    isExpanded: true,
                    isDense: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                    items: [
                      for (final d in dates.reversed)
                        DropdownMenuItem(
                          value: d,
                          child: Text(
                            '${label(d)} · ${_photos.where((p) => p.date == d).length} foto',
                          ),
                        ),
                    ],
                    onChanged: (d) {
                      if (d != null) onChanged(d);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final photo in photos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => _zoom(photo),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Image.network(
                        photo.url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : Container(color: AppColors.surfaceMuted),
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.surfaceMuted,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.black.withValues(alpha: .5),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _delete(photo),
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(
                          Icons.delete_outline,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    final days = _before != null && _after != null
        ? _after!.difference(_before!).inDays.abs()
        : null;
    return DailySection(
      icon: Icons.photo_library_outlined,
      color: dailyPurple,
      title: 'Foto dei progressi',
      status: MacChip(_open ? '${_photos.length} foto' : '🔒 Nascoste'),
      action: TextButton(
        onPressed: _toggle,
        child: Text(_open ? 'Nascondi' : 'Apri le foto'),
      ),
      child: !_open
          ? const Text(
              'Le foto restano chiuse e non vengono scaricate finché non le apri. Dentro puoi confrontare due date fianco a fianco e aggiungerne di nuove.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          : _loading && _photos.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) DailyErrorBanner(onRetry: _load),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (canPickImages)
                      FilledButton.icon(
                        onPressed: _busy ? null : _add,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                        label: Text(_busy ? 'Carico…' : 'Aggiungi foto'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    MacChip('${dates.length} ${dates.length == 1 ? 'data' : 'date'}'),
                    if (days != null && days > 0)
                      MacChip('$days giorni tra le due', tone: dailyPurple),
                  ],
                ),
                const SizedBox(height: 12),
                if (dates.isEmpty)
                  const Text(
                    'Nessuna foto ancora. Aggiungi la prima: dalla seconda data in poi potrai confrontarle.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _column(
                          'PRIMA',
                          _before,
                          (d) => setState(() => _before = d),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _column(
                          'DOPO',
                          _after,
                          (d) => setState(() => _after = d),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}
