import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../fitbit/application/fitbit_controller.dart';
import '../../routines/application/routine_controller.dart';

/// Shared application frame; owns no data or synchronization logic.
class DashboardFrame extends StatelessWidget {
  const DashboardFrame({
    required this.child,
    required this.fitbit,
    required this.routines,
    required this.selectedPage,
    required this.section,
    required this.onPage,
    required this.onSection,
    required this.onSearch,
    required this.onStatus,
    required this.onSettings,
    this.reviewLabel,
    super.key,
  });
  final Widget child;
  final FitbitController fitbit;
  final RoutineController routines;
  final int selectedPage;
  final String section;
  final ValueChanged<int> onPage;
  final ValueChanged<String> onSection;
  final VoidCallback onSearch, onStatus, onSettings;
  final String? reviewLabel;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (usesPhoneLayout(context)) return _phoneFrame(context);
      final expanded = box.maxWidth >= 1100;
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: AppColors.toolbar,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    // Con nove schede il nome dell'app trova posto solo sugli schermi larghi.
                    if (box.maxWidth >= 1560) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 180,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DopaDash',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                letterSpacing: -.1,
                                color: AppColors.text,
                              ),
                            ),
                            Text(
                              'La tua vita, in equilibrio',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(width: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _TopButton(
                              label: 'Monitoraggio',
                              icon: Icons.grid_view_outlined,
                              selected: selectedPage == 0,
                              onTap: () => onPage(0),
                            ),
                            _TopButton(
                              label: 'Organizzatore',
                              icon: Icons.sticky_note_2_outlined,
                              selected: selectedPage == 7,
                              onTap: () => onPage(7),
                            ),
                            _TopButton(
                              label: 'Quotidianità',
                              icon: Icons.wb_sunny_outlined,
                              selected: selectedPage == 8,
                              onTap: () => onPage(8),
                            ),
                            _TopButton(
                              label: 'Sport',
                              icon: Icons.fitness_center,
                              selected: selectedPage == 9,
                              onTap: () => onPage(9),
                            ),
                            _TopButton(
                              label: 'To Do',
                              icon: Icons.task_alt,
                              selected: selectedPage == 1,
                              onTap: () => onPage(1),
                            ),
                            _TopButton(
                              label: 'Borsa',
                              icon: Icons.work_outline,
                              selected: selectedPage == 2,
                              onTap: () => onPage(2),
                            ),
                            _TopButton(
                              label: 'Spese',
                              icon: Icons.account_balance_wallet_outlined,
                              selected: selectedPage == 3,
                              onTap: () => onPage(3),
                            ),
                            _TopButton(
                              label: 'Investimenti',
                              icon: Icons.trending_up,
                              selected: selectedPage == 4,
                              onTap: () => onPage(4),
                            ),
                            _TopButton(
                              label: 'Statistiche',
                              icon: Icons.bar_chart_outlined,
                              selected: selectedPage == 6,
                              onTap: () => onPage(6),
                            ),
                            _TopButton(
                              label: 'Vestiti',
                              icon: Icons.checkroom,
                              selected: selectedPage == 10,
                              onTap: () => onPage(10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (box.maxWidth >= 1250)
                      SizedBox(
                        width: 172,
                        height: 30,
                        child: OutlinedButton.icon(
                          onPressed: onSearch,
                          icon: const Icon(Icons.search, size: 16),
                          label: const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Cerca attività…',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textMuted,
                            side: BorderSide.none,
                            backgroundColor: AppColors.fill,
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: 'Cerca attività',
                        onPressed: onSearch,
                        icon: const Icon(Icons.search, size: 20),
                      ),
                    IconButton(
                      tooltip: 'Stato sincronizzazione',
                      onPressed: onStatus,
                      icon: const Icon(Icons.notifications_none, size: 21),
                    ),
                    IconButton(
                      tooltip: 'Account e impostazioni',
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined, size: 21),
                    ),
                    if (box.maxWidth > 700) ...[
                      const SizedBox(width: 12),
                      const CircleAvatar(
                        radius: 15,
                        backgroundColor: AppColors.fill,
                        child: Icon(
                          Icons.person_outline,
                          size: 19,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (reviewLabel != null)
                Container(
                  width: double.infinity,
                  color: AppColors.greenSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 5,
                  ),
                  child: Text(
                    reviewLabel!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.green,
                    ),
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    if (selectedPage != 7)
                      Container(
                        width: expanded ? 236 : 56,
                        decoration: const BoxDecoration(
                          color: AppColors.sidebar,
                          border: Border(
                            right: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Expanded(
                              child: Stack(
                                children: [
                                  SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        for (final entry in _sections(
                                          selectedPage,
                                        ))
                                          _SideButton(
                                            label: entry.$1,
                                            icon: entry.$2,
                                            expanded: expanded,
                                            selected: section == entry.$1,
                                            onTap: () => onSection(entry.$1),
                                          ),
                                        const Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            16,
                                            10,
                                            16,
                                            10,
                                          ),
                                          child: Divider(height: 1),
                                        ),
                                        _SideButton(
                                          label: 'Esporta dati',
                                          icon: Icons.file_download_outlined,
                                          expanded: expanded,
                                          selected: selectedPage == 5,
                                          onTap: () => onPage(5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selectedPage == 0 || selectedPage == 6)
                              ListenableBuilder(
                                listenable: Listenable.merge([
                                  fitbit,
                                  routines,
                                ]),
                                builder: (_, _) {
                                  final failed =
                                      fitbit.failure != null ||
                                      routines.syncError != null ||
                                      routines.loadError != null;
                                  final syncing =
                                      fitbit.isLoading ||
                                      routines.isLoading ||
                                      routines.isSaving;
                                  return Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      expanded ? 18 : 18,
                                      8,
                                      10,
                                      18,
                                    ),
                                    child: Column(
                                      children: [
                                        _StatusLine(
                                          expanded: expanded,
                                          icon: failed
                                              ? Icons.sync_problem
                                              : Icons.sync,
                                          title: syncing
                                              ? 'Sincronizzazione…'
                                              : failed
                                              ? 'Controlla connessione'
                                              : 'Dati aggiornati',
                                          detail: fitbit.day == null
                                              ? 'In attesa dei dati'
                                              : 'Ultimo dato ${fitbit.day!.date}',
                                          color: failed
                                              ? AppColors.warning
                                              : AppColors.green,
                                        ),
                                        const SizedBox(height: 15),
                                        _StatusLine(
                                          expanded: expanded,
                                          icon: Icons.watch_outlined,
                                          title:
                                              fitbit.status?.deviceName ??
                                              'Fitbit',
                                          detail: fitbit.isConnected
                                              ? 'Connesso'
                                              : 'Non connesso',
                                          color: fitbit.isConnected
                                              ? AppColors.green
                                              : AppColors.textMuted,
                                        ),
                                        const SizedBox(height: 15),
                                        _StatusLine(
                                          expanded: expanded,
                                          icon: Icons.favorite_outline,
                                          title: 'Google Health',
                                          detail: fitbit.isConnected
                                              ? 'Connesso'
                                              : 'Non connesso',
                                          color: fitbit.isConnected
                                              ? AppColors.green
                                              : AppColors.textMuted,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _phoneFrame(BuildContext context) {
    const destinations = [
      (0, 'Home', Icons.home_outlined),
      (8, 'Quotidiano', Icons.wb_sunny_outlined),
      (9, 'Sport', Icons.fitness_center),
      (7, 'Organizza', Icons.sticky_note_2_outlined),
      (1, 'To Do', Icons.task_alt),
    ];
    final selected = destinations.indexWhere((d) => d.$1 == selectedPage);
    final name = _pageName(selectedPage);
    return Scaffold(
      key: const ValueKey('phone-frame'),
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Material(
              color: Colors.white,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _phoneMenu(context, sections: true),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      section,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.expand_more,
                                    size: 17,
                                    color: AppColors.textMuted,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerca attività',
                      onPressed: onSearch,
                      icon: const Icon(Icons.search),
                    ),
                    IconButton(
                      tooltip: 'Apri sezioni',
                      onPressed: () => _phoneMenu(context, sections: true),
                      icon: const Icon(Icons.menu),
                    ),
                  ],
                ),
              ),
            ),
            if (reviewLabel != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  reviewLabel!,
                  style: const TextStyle(fontSize: 11, color: AppColors.green),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : Material(
              key: const ValueKey('phone-bottom-navigation'),
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Row(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        Expanded(
                          child: _PhoneDestination(
                            label: destinations[i].$2,
                            icon: destinations[i].$3,
                            selected: i == selected,
                            onTap: () => onPage(destinations[i].$1),
                          ),
                        ),
                      Expanded(
                        child: _PhoneDestination(
                          label: 'Altro',
                          icon: Icons.more_horiz,
                          selected: selected < 0,
                          onTap: () => _phoneMenu(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  void _phoneMenu(BuildContext context, {bool sections = false}) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .4,
        maxChildSize: .94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              sections
                  ? 'Sezioni · ${_pageName(selectedPage)}'
                  : 'Il tuo spazio',
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            if (sections) ...[
              for (final entry in _sections(selectedPage))
                ListTile(
                  leading: Icon(entry.$2),
                  title: Text(entry.$1),
                  selected: section == entry.$1,
                  selectedColor: AppColors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selectedTileColor: AppColors.greenSoft,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onSection(entry.$1);
                  },
                ),
              const Divider(height: 24),
            ],
            for (final entry in [
              (0, 'Monitoraggio', Icons.home_outlined),
              (7, 'Organizzatore', Icons.sticky_note_2_outlined),
              (8, 'Quotidianità', Icons.wb_sunny_outlined),
              (9, 'Sport', Icons.fitness_center),
              (1, 'To Do', Icons.task_alt),
              (6, 'Statistiche', Icons.bar_chart_outlined),
              (3, 'Spese', Icons.account_balance_wallet_outlined),
              (2, 'Borsa', Icons.work_outline),
              (4, 'Investimenti', Icons.trending_up),
              (10, 'Vestiti', Icons.checkroom),
              (5, 'Esporta dati', Icons.file_download_outlined),
            ])
              ListTile(
                leading: Icon(entry.$3),
                title: Text(entry.$2),
                selected: selectedPage == entry.$1,
                selectedColor: AppColors.green,
                onTap: () {
                  Navigator.pop(sheetContext);
                  onPage(entry.$1);
                },
              ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Stato sincronizzazione'),
              onTap: () {
                Navigator.pop(sheetContext);
                onStatus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Account e impostazioni'),
              onTap: () {
                Navigator.pop(sheetContext);
                onSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _pageName(int page) => switch (page) {
  1 => 'To Do',
  2 => 'Borsa',
  3 => 'Spese',
  4 => 'Investimenti',
  5 => 'Esporta dati',
  6 => 'Statistiche',
  7 => 'Organizzatore',
  8 => 'Quotidianità',
  9 => 'Sport',
  10 => 'Vestiti',
  _ => 'Monitoraggio',
};

class _PhoneDestination extends StatelessWidget {
  const _PhoneDestination({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? AppColors.greenSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? AppColors.green : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.green : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 17,
        color: selected ? AppColors.green : AppColors.textMuted,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: selected ? AppColors.selection : Colors.transparent,
        foregroundColor: selected ? AppColors.text : AppColors.textMuted,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
  );
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.label,
    required this.icon,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool expanded, selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 1),
    child: Tooltip(
      message: expanded ? '' : label,
      child: Material(
        color: selected ? AppColors.selection : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: AppColors.hover,
          child: Container(
            height: 32,
            padding: EdgeInsets.symmetric(horizontal: expanded ? 9 : 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.green),
                if (expanded) ...[
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.expanded,
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });
  final bool expanded;
  final IconData icon;
  final String title, detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$title · $detail',
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        if (expanded) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.text),
                ),
                const SizedBox(height: 1),
                Text(detail, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

List<(String, IconData)> _sections(int area) {
  final labels = switch (area) {
    7 => const <String>[],
    8 => [
      'Panoramica',
      'Cellulare',
      'Abitudini',
      'Emozioni',
      'Concentrazione',
      'Movimento',
      'Alimentazione',
    ],
    9 => ['Panoramica', 'Allenamento', 'Attività', 'Peso e misure', 'Foto'],
    10 => [
      'Panoramica',
      'Estate',
      'Mezza stagione',
      'Inverno',
      'Elegante',
      'Lavoro',
      'Casual',
      'Sportivo',
    ],
    1 => [
      'Panoramica',
      'Oggi',
      'Questa settimana',
      'Scadute',
      'Completate',
      'Posta',
    ],
    2 => [
      'Panoramica',
      'Mappa',
      'S&P 500',
      'Mercati',
      'ETF',
      'Azioni',
      'Crypto',
      'Watchlist',
      'Insight',
    ],
    3 => [
      'Panoramica',
      'Budget mensile',
      'Conti e fondi',
      'Riepilogo annuale',
      'Patrimonio',
      'Fonte Excel',
    ],
    4 => [
      'Panoramica',
      'Portafoglio',
      'ETF',
      'Azioni',
      'Crypto',
      'Allocazione',
      'Operazioni',
      'Storico',
    ],
    6 => [
      'Panoramica',
      'Sonno',
      'Cuore e recupero',
      'Attività',
      'Percezione',
      'Abitudini',
      'Cellulare',
      'Sport',
      'Esperimenti',
    ],
    _ => [
      'Panoramica',
      'Salute',
      'Organizzatore',
      'Routine',
      'Calendario',
      'Statistiche',
      'Attività personali',
      'Attività lavorative',
      'Attività lavoro personale',
      'Investimenti',
      'Posta',
    ],
  };
  return [
    for (final label in labels)
      (
        label,
        switch (label) {
          'Salute' => Icons.favorite_border,
          'Mappa' => Icons.grid_view_rounded,
          'S&P 500' => Icons.dashboard_outlined,
          'Sport' => Icons.fitness_center,
          'Cellulare' => Icons.smartphone,
          'Alimentazione' => Icons.restaurant,
          'Abitudini' => Icons.checklist_rounded,
          'Emozioni' => Icons.favorite_border,
          'Concentrazione' => Icons.center_focus_strong_outlined,
          'Movimento' => Icons.graphic_eq,
          'Allenamento' => Icons.fitness_center,
          'Peso e misure' => Icons.monitor_weight_outlined,
          'Foto' => Icons.photo_library_outlined,
          'Estate' => Icons.wb_sunny_outlined,
          'Mezza stagione' => Icons.cloud_outlined,
          'Inverno' => Icons.ac_unit,
          'Elegante' => Icons.diamond_outlined,
          'Lavoro' => Icons.work_outline,
          'Casual' => Icons.weekend_outlined,
          'Sportivo' => Icons.directions_run,
          'Organizzatore' => Icons.sticky_note_2_outlined,
          'Statistiche' => Icons.bar_chart_outlined,
          'Sonno' => Icons.bedtime_outlined,
          'Cuore e recupero' => Icons.favorite_border,
          'Attività' => Icons.directions_run,
          'Percezione' => Icons.sentiment_satisfied_alt,
          'Esperimenti' => Icons.science_outlined,
          'Calendario' => Icons.calendar_month_outlined,
          'Posta' => Icons.inbox_outlined,
          'Fonte Excel' => Icons.link,
          'Budget mensile' => Icons.speed_outlined,
          'Conti e fondi' => Icons.account_balance_wallet_outlined,
          'Routine' => Icons.verified_outlined,
          'Panoramica' => Icons.grid_view_outlined,
          'Investimenti' || 'Mercati' || 'Storico' => Icons.trending_up,
          'ETF' ||
          'Azioni' ||
          'Crypto' ||
          'Allocazione' => Icons.pie_chart_outline,
          'Portafoglio' => Icons.account_balance_wallet_outlined,
          _ => Icons.checklist,
        },
      ),
  ];
}
