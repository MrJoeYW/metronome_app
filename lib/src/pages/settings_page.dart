part of '../../main.dart';

/// “我的”页：展示练习统计、练琴日历和社区页地址设置。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.todayPracticeDuration,
    required this.currentSessionDuration,
    required this.currentSessionStartedAt,
    required this.currentBpm,
    required this.practiceLogs,
    required this.practiceDaySummaries,
    required this.onLoadPracticeLogsForDay,
    required this.webPageUrl,
    required this.onWebPageUrlChanged,
  });

  final Duration todayPracticeDuration;
  final Duration currentSessionDuration;
  final DateTime? currentSessionStartedAt;
  final int currentBpm;
  final List<PracticeLog> practiceLogs;
  final List<PracticeDaySummary> practiceDaySummaries;
  final Future<List<PracticeLog>> Function(DateTime day)
  onLoadPracticeLogsForDay;
  final String webPageUrl;
  final Future<bool> Function(String url) onWebPageUrlChanged;

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
              '我的',
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
                        Icons.person_rounded,
                        color: AppPalette.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Today practice',
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
            _PracticeCalendarPanel(
              summaries: practiceDaySummaries,
              currentSessionStartedAt: currentSessionStartedAt,
              currentSessionDuration: currentSessionDuration,
              currentBpm: currentBpm,
              onLoadDayLogs: onLoadPracticeLogsForDay,
            ),
            const SizedBox(height: 22),
            _WebPageSettingsPanel(
              webPageUrl: webPageUrl,
              onChanged: onWebPageUrlChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeCalendarPanel extends StatefulWidget {
  const _PracticeCalendarPanel({
    required this.summaries,
    required this.currentSessionStartedAt,
    required this.currentSessionDuration,
    required this.currentBpm,
    required this.onLoadDayLogs,
  });

  final List<PracticeDaySummary> summaries;
  final DateTime? currentSessionStartedAt;
  final Duration currentSessionDuration;
  final int currentBpm;
  final Future<List<PracticeLog>> Function(DateTime day) onLoadDayLogs;

  @override
  State<_PracticeCalendarPanel> createState() => _PracticeCalendarPanelState();
}

class _PracticeCalendarPanelState extends State<_PracticeCalendarPanel> {
  static const int _initialMonthPage = 6000;
  late final PageController _pageController;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _pageController = PageController(initialPage: _initialMonthPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summaryByDay = {
      for (final summary in widget.summaries) _dayKey(summary.date): summary,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
                Icons.calendar_month_rounded,
                size: 20,
                color: AppPalette.secondary,
              ),
              const SizedBox(width: 10),
              Text(
                '练琴日历',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppPalette.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => _jumpByMonths(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              SizedBox(
                width: 92,
                child: Center(
                  child: Text(
                    _formatCalendarMonth(_visibleMonth),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => _jumpByMonths(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _CalendarWeekdayHeader(),
          const SizedBox(height: 8),
          SizedBox(
            height: 258,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) {
                setState(() {
                  _visibleMonth = _addMonths(
                    DateTime.now(),
                    page - _initialMonthPage,
                  );
                });
              },
              itemBuilder: (context, page) {
                final month = _addMonths(
                  DateTime.now(),
                  page - _initialMonthPage,
                );
                return _PracticeMonthGrid(
                  month: DateTime(month.year, month.month),
                  summaryByDay: summaryByDay,
                  onDayTap: (date) => _showDayDialog(context, date),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '少',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              for (final seconds in const [0, 300, 1200, 2400, 3600]) ...[
                _PracticeIntensitySwatch(seconds: seconds),
                const SizedBox(width: 5),
              ],
              const SizedBox(width: 3),
              Text(
                '多',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _jumpByMonths(int delta) {
    final page = (_pageController.page?.round() ?? _initialMonthPage) + delta;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showDayDialog(BuildContext context, DateTime date) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PracticeDayDialog(
        date: date,
        currentSessionStartedAt: widget.currentSessionStartedAt,
        currentSessionDuration: widget.currentSessionDuration,
        currentBpm: widget.currentBpm,
        loadLogs: () => widget.onLoadDayLogs(date),
      ),
    );
  }
}

class _CalendarWeekdayHeader extends StatelessWidget {
  const _CalendarWeekdayHeader();

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final label in _labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PracticeMonthGrid extends StatelessWidget {
  const _PracticeMonthGrid({
    required this.month,
    required this.summaryByDay,
    required this.onDayTap,
  });

  final DateTime month;
  final Map<String, PracticeDaySummary> summaryByDay;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final days = _monthCalendarDays(month);

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: days.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.88,
      ),
      itemBuilder: (context, index) {
        final date = days[index];
        return _PracticeCalendarDayCell(
          date: date,
          currentMonth: month,
          summary: summaryByDay[_dayKey(date)],
          onTap: onDayTap,
        );
      },
    );
  }
}

class _PracticeCalendarDayCell extends StatelessWidget {
  const _PracticeCalendarDayCell({
    required this.date,
    required this.currentMonth,
    required this.summary,
    required this.onTap,
  });

  final DateTime date;
  final DateTime currentMonth;
  final PracticeDaySummary? summary;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final seconds = summary?.totalSeconds ?? 0;
    final inCurrentMonth =
        date.year == currentMonth.year && date.month == currentMonth.month;
    final today = DateTime.now();
    final isToday = _isSameDay(date, today);
    final fill = _practiceIntensityColor(seconds);

    return Tooltip(
      message:
          '${_formatCalendarDate(date)} | ${_formatCompactDuration(Duration(seconds: seconds))}',
      child: InkWell(
        onTap: () => onTap(date),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: seconds == 0
                ? AppPalette.surfaceVariant.withValues(
                    alpha: inCurrentMonth ? 0.42 : 0.20,
                  )
                : fill.withValues(alpha: inCurrentMonth ? 0.78 : 0.38),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday
                  ? AppPalette.primary
                  : seconds == 0
                  ? AppPalette.border
                  : fill,
              width: isToday ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  date.day.toString(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: inCurrentMonth
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (seconds > 0)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: inCurrentMonth
                          ? AppPalette.textPrimary
                          : AppPalette.textSecondary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeIntensitySwatch extends StatelessWidget {
  const _PracticeIntensitySwatch({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: _practiceIntensityColor(seconds),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppPalette.border),
      ),
    );
  }
}

class _PracticeDayDialog extends StatelessWidget {
  const _PracticeDayDialog({
    required this.date,
    required this.currentSessionStartedAt,
    required this.currentSessionDuration,
    required this.currentBpm,
    required this.loadLogs,
  });

  final DateTime date;
  final DateTime? currentSessionStartedAt;
  final Duration currentSessionDuration;
  final int currentBpm;
  final Future<List<PracticeLog>> Function() loadLogs;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppPalette.surface,
      title: Text(_formatCalendarDate(date)),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<List<PracticeLog>>(
          future: loadLogs(),
          builder: (context, snapshot) {
            final logs = snapshot.data ?? const <PracticeLog>[];
            final includeCurrent =
                currentSessionStartedAt != null &&
                _isSameDay(currentSessionStartedAt!, date) &&
                currentSessionDuration.inSeconds > 0;
            final currentSeconds = includeCurrent
                ? currentSessionDuration.inSeconds
                : 0;
            final totalSeconds =
                logs.fold<int>(0, (total, log) => total + log.durationSeconds) +
                currentSeconds;
            final sessionCount = logs.length + (includeCurrent ? 1 : 0);

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PracticeDaySummaryRow(
                  label: 'Total',
                  value: _formatCompactDuration(
                    Duration(seconds: totalSeconds),
                  ),
                ),
                const SizedBox(height: 6),
                _PracticeDaySummaryRow(
                  label: 'Sessions',
                  value: sessionCount.toString(),
                ),
                const SizedBox(height: 14),
                if (sessionCount == 0)
                  Text(
                    '这一天还没有练习记录',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.textSecondary,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (includeCurrent)
                          _PracticeDayLogTile(
                            title: 'Current session',
                            duration: Duration(seconds: currentSeconds),
                            bpm: currentBpm,
                          ),
                        for (final log in logs)
                          _PracticeDayLogTile(
                            title: _formatHistoryDate(log.date),
                            duration: Duration(seconds: log.durationSeconds),
                            bpm: log.averageBpm,
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PracticeDaySummaryRow extends StatelessWidget {
  const _PracticeDaySummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppPalette.textPrimary,
            fontWeight: FontWeight.w900,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PracticeDayLogTile extends StatelessWidget {
  const _PracticeDayLogTile({
    required this.title,
    required this.duration,
    required this.bpm,
  });

  final String title;
  final Duration duration;
  final int bpm;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${_formatCompactDuration(duration)} | $bpm BPM',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textPrimary,
              fontWeight: FontWeight.w800,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebPageSettingsPanel extends StatefulWidget {
  const _WebPageSettingsPanel({
    required this.webPageUrl,
    required this.onChanged,
  });

  final String webPageUrl;
  final Future<bool> Function(String url) onChanged;

  @override
  State<_WebPageSettingsPanel> createState() => _WebPageSettingsPanelState();
}

class _WebPageSettingsPanelState extends State<_WebPageSettingsPanel> {
  late final TextEditingController _controller;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.webPageUrl);
  }

  @override
  void didUpdateWidget(covariant _WebPageSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.webPageUrl != widget.webPageUrl) {
      _controller.text = widget.webPageUrl;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
    });
    final changed = await widget.onChanged(_controller.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (!changed) {
        _controller.text = widget.webPageUrl;
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(changed ? 'Web page updated.' : 'Web page unchanged.'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Icon(Icons.public_rounded, color: AppPalette.secondary),
              const SizedBox(width: 10),
              Text(
                'Community page',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppPalette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            enabled: !_saving,
            style: const TextStyle(color: AppPalette.textPrimary),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Web address',
              hintText: kDefaultWebPageUrl,
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: 'Use default',
                onPressed: _saving
                    ? null
                    : () {
                        _controller.text = kDefaultWebPageUrl;
                      },
                icon: const Icon(Icons.restore_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onSubmitted: (_) => unawaited(_save()),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: Icon(
              _saving ? Icons.hourglass_top_rounded : Icons.save_rounded,
            ),
            label: Text(_saving ? 'Saving' : 'Save page'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
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
          label: 'Community',
        ),
        NavigationDestination(
          icon: Icon(Icons.speed_rounded),
          label: '\u8282\u62cd\u5668',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_rounded),
          label: '\u6211\u7684',
        ),
      ],
    );
  }
}
