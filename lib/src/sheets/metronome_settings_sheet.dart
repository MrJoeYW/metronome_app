part of '../../main.dart';

/// 缁楊兛绔存潪顕€浠愰悾娆戞畱缂佺厧鎮庣拋鍓х枂閹惰棄鐪介妴?/// 瑜版挸澧犳稉缁樼ウ缁嬪鍑￠弨閫涜礋妞ゅ爼鍎撮崶娑楅嚋閸旂喕鍏橀幎钘夌溄閿涘奔绻氶悾娆愵劃缂佸嫪娆㈡担婊€璐熼崢鍡楀蕉/閸氬海鐢婚弫鏉戞値閸欏倽鈧啨鈧?
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
                  const SizedBox(height: 18),
                  _PracticeHistoryPanel(
                    todayDuration: widget.todayPracticeDuration,
                    logs: widget.practiceLogs,
                  ),
                  const SizedBox(height: 18),
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

class _PracticeHistoryPanel extends StatelessWidget {
  const _PracticeHistoryPanel({
    required this.todayDuration,
    required this.logs,
  });

  final Duration todayDuration;
  final List<PracticeLog> logs;

  @override
  Widget build(BuildContext context) {
    final visibleLogs = logs.take(4).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 18,
                color: AppPalette.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Practice History',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppPalette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                _formatCompactDuration(todayDuration),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppPalette.primary,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleLogs.isEmpty)
            Text(
              'No sessions logged yet.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppPalette.textSecondary),
            )
          else
            for (final log in visibleLogs) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatHistoryDate(log.date),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppPalette.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${_formatCompactDuration(Duration(seconds: log.durationSeconds))} | ${log.averageBpm} BPM',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textPrimary,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
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
