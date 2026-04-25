part of '../../main.dart';

/// 设置页当前只展示练习统计，不承载排行榜或配置管理。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.todayPracticeDuration,
    required this.currentSessionDuration,
    required this.practiceLogs,
  });

  final Duration todayPracticeDuration;
  final Duration currentSessionDuration;
  final List<PracticeLog> practiceLogs;

  @override
  Widget build(BuildContext context) {
    final loggedSeconds = practiceLogs.fold<int>(
      0,
      (total, log) => total + log.durationSeconds,
    );
    final averageBpm = practiceLogs.isEmpty
        ? '--'
        : (practiceLogs.fold<int>(0, (total, log) => total + log.averageBpm) /
                  practiceLogs.length)
              .round()
              .toString();

    return ColoredBox(
      color: AppPalette.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              'Practice Stats',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppPalette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: AppPalette.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Today',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppPalette.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _formatCompactDuration(todayPracticeDuration),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _PracticeMetricGrid(
                    items: [
                      _PracticeMetricData(
                        label: 'Current',
                        value: _formatCompactDuration(currentSessionDuration),
                        icon: Icons.play_circle_outline_rounded,
                      ),
                      _PracticeMetricData(
                        label: 'Recent',
                        value: practiceLogs.length.toString(),
                        icon: Icons.event_note_rounded,
                      ),
                      _PracticeMetricData(
                        label: 'Logged',
                        value: _formatCompactDuration(
                          Duration(seconds: loggedSeconds),
                        ),
                        icon: Icons.timer_outlined,
                      ),
                      _PracticeMetricData(
                        label: 'Avg BPM',
                        value: averageBpm,
                        icon: Icons.speed_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _PracticeHistoryPanel(
              todayDuration: todayPracticeDuration,
              logs: practiceLogs,
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeMetricData {
  const _PracticeMetricData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _PracticeMetricGrid extends StatelessWidget {
  const _PracticeMetricGrid({required this.items});

  final List<_PracticeMetricData> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.25,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppPalette.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppPalette.border),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: AppPalette.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppPalette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 已保存配置的列表项，展示配置摘要并提供恢复/删除操作。
class _SavedPresetTile extends StatelessWidget {
  const _SavedPresetTile({
    required this.preset,
    required this.onRestore,
    required this.onDelete,
  });

  final SavedMetronomePreset preset;
  final VoidCallback onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final beatSummary = preset.beatPattern
        .map((token) => BeatType.fromToken(token).shortLabel)
        .join(' ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preset.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppPalette.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${preset.bpm} BPM | ${preset.timeSignature} | $beatSummary',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restore',
            onPressed: onRestore,
            icon: const Icon(Icons.restore_rounded),
            color: AppPalette.primary,
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppPalette.danger,
          ),
        ],
      ),
    );
  }
}

/// 三页底部导航：WebView、节拍器、设置。
class BottomNavigation extends StatelessWidget {
  const BottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      height: 68,
      backgroundColor: AppPalette.surface,
      indicatorColor: AppPalette.primary.withValues(alpha: 0.16),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.public_rounded),
          label: '\u5409\u4ed6\u793e',
        ),
        NavigationDestination(
          icon: Icon(Icons.speed_rounded),
          label: '\u8282\u62cd\u5668',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_rounded),
          label: '\u8bbe\u7f6e',
        ),
      ],
    );
  }
}
