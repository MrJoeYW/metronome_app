part of '../../main.dart';

/// 历史遗留的综合设置抽屉。
/// 当前主流程已经拆为顶部四个功能抽屉，保留此组件作为后续整合参考。
class MetronomeSettingsSheet extends StatefulWidget {
  const MetronomeSettingsSheet({
    super.key,
    required this.accentSound,
    required this.regularSound,
    required this.voiceMode,
    required this.accentHaptics,
    required this.todayPracticeDuration,
    required this.practiceLogs,
    required this.onAccentSoundChanged,
    required this.onRegularSoundChanged,
    required this.onVoiceModeChanged,
    required this.onAccentHapticsChanged,
  });

  final SoundProfile accentSound;
  final SoundProfile regularSound;
  final VoiceMode voiceMode;
  final bool accentHaptics;
  final Duration todayPracticeDuration;
  final List<PracticeLog> practiceLogs;
  final ValueChanged<SoundProfile> onAccentSoundChanged;
  final ValueChanged<SoundProfile> onRegularSoundChanged;
  final ValueChanged<VoiceMode> onVoiceModeChanged;
  final ValueChanged<bool> onAccentHapticsChanged;

  @override
  State<MetronomeSettingsSheet> createState() => _MetronomeSettingsSheetState();
}

class _MetronomeSettingsSheetState extends State<MetronomeSettingsSheet> {
  late SoundProfile _accentSound;
  late SoundProfile _regularSound;
  late VoiceMode _voiceMode;
  late bool _accentHaptics;

  @override
  void initState() {
    super.initState();
    _accentSound = widget.accentSound;
    _regularSound = widget.regularSound;
    _voiceMode = widget.voiceMode;
    _accentHaptics = widget.accentHaptics;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppPalette.surface,
            border: Border.all(color: AppPalette.border),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.84,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: AppPalette.border,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Session Settings',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppPalette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: AppPalette.surfaceVariant,
                          foregroundColor: AppPalette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Move sound, language, and haptics here so the main workspace stays focused on tempo.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.textSecondary,
                    ),
                  ),
                  _SettingsSectionTitle(title: 'Accent Sound'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final sound in SoundProfile.values)
                        _SettingsChoiceChip(
                          label: sound.label,
                          icon: sound.icon,
                          color: sound.color,
                          selected: _accentSound == sound,
                          onTap: () {
                            setState(() {
                              _accentSound = sound;
                            });
                            widget.onAccentSoundChanged(sound);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SettingsSectionTitle(title: 'Regular Sound'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final sound in SoundProfile.values)
                        _SettingsChoiceChip(
                          label: sound.label,
                          icon: sound.icon,
                          color: sound.color,
                          selected: _regularSound == sound,
                          onTap: () {
                            setState(() {
                              _regularSound = sound;
                            });
                            widget.onRegularSoundChanged(sound);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SettingsSectionTitle(title: 'Voice Counting'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final mode in VoiceMode.values)
                        _SettingsChoiceChip(
                          label: mode.label,
                          selected: _voiceMode == mode,
                          onTap: () {
                            setState(() {
                              _voiceMode = mode;
                            });
                            widget.onVoiceModeChanged(mode);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: AppPalette.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppPalette.border),
                    ),
                    child: SwitchListTile(
                      title: const Text('Accent Haptic Pulse'),
                      subtitle: const Text(
                        'Keep a short tactile cue on the downbeat.',
                      ),
                      value: _accentHaptics,
                      activeThumbColor: AppPalette.primary,
                      activeTrackColor: AppPalette.primary.withValues(
                        alpha: 0.28,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _accentHaptics = value;
                        });
                        widget.onAccentHapticsChanged(value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppPalette.textPrimary,
      ),
    );
  }
}

String _formatCompactDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
  return '${seconds}s';
}

String _formatHistoryDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

String _formatCalendarDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatCalendarMonth(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}.$month';
}

String _dayKey(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return _formatCalendarDate(normalized);
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

DateTime _addMonths(DateTime date, int monthOffset) {
  final zeroBasedMonth = date.month - 1 + monthOffset;
  final year = date.year + (zeroBasedMonth ~/ 12);
  final month = (zeroBasedMonth % 12) + 1;
  return DateTime(year, month);
}

List<DateTime> _monthCalendarDays(DateTime month) {
  final firstDay = DateTime(month.year, month.month);
  final leadingDays = firstDay.weekday - DateTime.monday;
  final start = firstDay.subtract(Duration(days: leadingDays));
  return [
    for (var index = 0; index < 42; index++) start.add(Duration(days: index)),
  ];
}

Color _practiceIntensityColor(int seconds) {
  if (seconds <= 0) {
    return AppPalette.surfaceVariant.withValues(alpha: 0.62);
  }
  if (seconds < 10 * 60) {
    return AppPalette.primary.withValues(alpha: 0.30);
  }
  if (seconds < 30 * 60) {
    return AppPalette.primary.withValues(alpha: 0.55);
  }
  if (seconds < 60 * 60) {
    return AppPalette.secondary.withValues(alpha: 0.72);
  }
  return AppPalette.secondary;
}

class _SettingsChoiceChip extends StatelessWidget {
  const _SettingsChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppPalette.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : AppPalette.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? accent : AppPalette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? accent : AppPalette.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected ? accent : AppPalette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
