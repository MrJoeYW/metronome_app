part of '../../main.dart';

/// 拍号抽屉：双滚轮选择拍数和音符时值，快捷拍型负责快速跳转常用组合。
class TimeSignatureSheet extends StatefulWidget {
  const TimeSignatureSheet({
    super.key,
    required this.initialSignature,
    required this.scrollController,
    required this.onConfirmed,
  });

  final TimeSignature initialSignature;
  final ScrollController scrollController;
  final ValueChanged<TimeSignature> onConfirmed;

  @override
  State<TimeSignatureSheet> createState() => _TimeSignatureSheetState();
}

class _TimeSignatureSheetState extends State<TimeSignatureSheet> {
  static const double _pickerItemExtent = 42;

  late int _beats;
  late int _noteValue;
  late final FixedExtentScrollController _beatsController;
  late final FixedExtentScrollController _noteValueController;

  @override
  void initState() {
    super.initState();
    _beats = widget.initialSignature.beatsPerBar;
    _noteValue = widget.initialSignature.noteValue;
    _beatsController = FixedExtentScrollController(initialItem: _beats - 1);
    _noteValueController = FixedExtentScrollController(
      initialItem: math.max(0, kNoteValues.indexOf(_noteValue)),
    );
  }

  @override
  void dispose() {
    _beatsController.dispose();
    _noteValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FunctionSheetFrame(
      title: 'Meter',
      scrollController: widget.scrollController,
      actionLabel: 'Apply',
      actionIcon: Icons.check_rounded,
      onAction: _applySignature,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsSectionTitle(title: 'Meter wheels'),
          const SizedBox(height: 10),
          MeterWheelPicker(
            beatsController: _beatsController,
            noteValueController: _noteValueController,
            pickerItemExtent: _pickerItemExtent,
            onBeatsChanged: (index) {
              setState(() {
                _beats = index + 1;
              });
            },
            onNoteValueChanged: (index) {
              setState(() {
                _noteValue = kNoteValues[index];
              });
            },
          ),
          const SizedBox(height: 18),
          _SettingsSectionTitle(title: 'Quick meters'),
          const SizedBox(height: 10),
          FiveAcrossOptions(
            children: [
              for (final signature in kTimeSignatures)
                CompactOptionButton(
                  label: signature.label,
                  selected:
                      _beats == signature.beatsPerBar &&
                      _noteValue == signature.noteValue,
                  onTap: () => _selectQuickSignature(signature),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _PreviewPanel(
            icon: Icons.grid_4x4_rounded,
            title: 'Current meter',
            value: '$_beats/$_noteValue',
            accent: AppPalette.secondary,
          ),
        ],
      ),
    );
  }

  void _selectQuickSignature(TimeSignature signature) {
    setState(() {
      _beats = signature.beatsPerBar;
      _noteValue = signature.noteValue;
    });
    _beatsController.animateToItem(
      signature.beatsPerBar - 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _noteValueController.animateToItem(
      kNoteValues.indexOf(signature.noteValue),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _applySignature() {
    widget.onConfirmed(
      TimeSignature(
        label: '$_beats/$_noteValue',
        beatsPerBar: _beats,
        noteValue: _noteValue,
        caption: 'Custom meter',
      ),
    );
    Navigator.of(context).pop();
  }
}

/// 音色抽屉。
///
/// 当前先提供 UI 选择和配置同步，真实音源替换可在原生层继续扩展。
class SoundPresetSheet extends StatefulWidget {
  const SoundPresetSheet({
    super.key,
    required this.accentSound,
    required this.regularSound,
    required this.voiceMode,
    required this.accentHaptics,
    required this.scrollController,
    required this.onAccentSoundChanged,
    required this.onRegularSoundChanged,
    required this.onVoiceModeChanged,
    required this.onAccentHapticsChanged,
  });

  final SoundProfile accentSound;
  final SoundProfile regularSound;
  final VoiceMode voiceMode;
  final bool accentHaptics;
  final ScrollController scrollController;
  final ValueChanged<SoundProfile> onAccentSoundChanged;
  final ValueChanged<SoundProfile> onRegularSoundChanged;
  final ValueChanged<VoiceMode> onVoiceModeChanged;
  final ValueChanged<bool> onAccentHapticsChanged;

  @override
  State<SoundPresetSheet> createState() => _SoundPresetSheetState();
}

class _SoundPresetSheetState extends State<SoundPresetSheet> {
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
    return _FunctionSheetFrame(
      title: 'Tone',
      scrollController: widget.scrollController,
      actionLabel: 'Done',
      actionIcon: Icons.check_rounded,
      onAction: () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsSectionTitle(title: 'Preset'),
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
          _SettingsSectionTitle(title: 'Accent layer'),
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
          _SettingsSectionTitle(title: 'Voice counting'),
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
              title: const Text('Accent haptic pulse'),
              value: _accentHaptics,
              activeThumbColor: AppPalette.primary,
              activeTrackColor: AppPalette.primary.withValues(alpha: 0.28),
              onChanged: (value) {
                setState(() {
                  _accentHaptics = value;
                });
                widget.onAccentHapticsChanged(value);
              },
            ),
          ),
          const SizedBox(height: 18),
          _PreviewPanel(
            icon: Icons.volume_up_rounded,
            title: 'Audition',
            value: 'UI reserved',
            subtitle: 'Real source logic is paused',
            accent: AppPalette.primary,
          ),
        ],
      ),
    );
  }
}

/// 调音器抽屉。
/// 通过 Android 原生 AudioRecord 和基频分析事件显示实时音高。
class TunerSheet extends StatefulWidget {
  const TunerSheet({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  State<TunerSheet> createState() => _TunerSheetState();
}

class _TunerSheetState extends State<TunerSheet> {
  final MetronomeBridge _bridge = const MetronomeBridge();
  StreamSubscription<TunerPitchEvent>? _subscription;
  TunerPitchEvent _event = const TunerPitchEvent(status: TunerStatus.idle);
  TunerReading? _stableReading;
  Timer? _clearReadingTimer;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _clearReadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FunctionSheetFrame(
      title: 'Tuner',
      scrollController: widget.scrollController,
      actionLabel: 'Done',
      actionIcon: Icons.check_rounded,
      onAction: () => Navigator.of(context).pop(),
      child: Column(
        children: [
          _TunerDisplay(
            event: _event,
            reading: _stableReading,
            onRequestPermission: _requestMicrophonePermission,
            isRequestingPermission: _isRequestingPermission,
          ),
          const SizedBox(height: 18),
          _PreviewPanel(
            icon: Icons.info_outline_rounded,
            title: 'Input',
            value: _event.status.label,
            subtitle: 'A4 = 440Hz',
            accent: const Color(0xFF7AD7A8),
          ),
        ],
      ),
    );
  }

  void _startListening() {
    _subscription?.cancel();
    _subscription = _bridge.tunerPitchStream().listen(
      (event) {
        if (!mounted) {
          return;
        }
        final reading = event.reading;
        setState(() {
          _event = event;
          if (reading != null) {
            _stableReading = reading;
          }
        });
        if (reading != null) {
          _clearReadingTimer?.cancel();
        } else if (event.status == TunerStatus.permissionDenied ||
            event.status == TunerStatus.error) {
          _clearReadingTimer?.cancel();
          setState(() {
            _stableReading = null;
          });
        } else {
          _scheduleReadingClear();
        }
      },
      onError: (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _event = const TunerPitchEvent(status: TunerStatus.error);
          _stableReading = null;
        });
      },
    );
  }

  void _scheduleReadingClear() {
    _clearReadingTimer?.cancel();
    _clearReadingTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _stableReading = null;
      });
    });
  }

  Future<void> _requestMicrophonePermission() async {
    if (_isRequestingPermission) {
      return;
    }
    setState(() {
      _isRequestingPermission = true;
    });
    final granted = await _bridge.requestMicrophonePermission();
    if (!mounted) {
      return;
    }
    setState(() {
      _isRequestingPermission = false;
      _event = TunerPitchEvent(
        status: granted ? TunerStatus.listening : TunerStatus.permissionDenied,
      );
      if (!granted) {
        _stableReading = null;
      }
    });
    if (granted) {
      _startListening();
    }
  }
}

/// 定时器抽屉。
/// Apply 后把定时配置交给首页状态，归零时由首页统一停止播放。
class TimerSheet extends StatefulWidget {
  const TimerSheet({
    super.key,
    required this.enabled,
    required this.duration,
    required this.scrollController,
    required this.onChanged,
  });

  final bool enabled;
  final Duration duration;
  final ScrollController scrollController;
  final void Function({required bool enabled, required Duration duration})
  onChanged;

  @override
  State<TimerSheet> createState() => _TimerSheetState();
}

class _TimerSheetState extends State<TimerSheet> {
  static const double _pickerItemExtent = 44;

  late bool _enabled;
  late int _minutes;
  late final FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    _minutes = math
        .max(1, widget.duration.inMinutes == 0 ? 5 : widget.duration.inMinutes)
        .clamp(1, 999)
        .toInt();
    _minuteController = FixedExtentScrollController(initialItem: _minutes - 1);
  }

  @override
  void dispose() {
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FunctionSheetFrame(
      title: 'Timer',
      scrollController: widget.scrollController,
      actionLabel: 'Apply',
      actionIcon: Icons.check_rounded,
      onAction: _applyTimer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: 268,
              child: SegmentedButton<bool>(
                style: const ButtonStyle(
                  fixedSize: WidgetStatePropertyAll(Size(132, 44)),
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('Off')),
                  ButtonSegment(value: true, label: Text('Countdown')),
                ],
                selected: {_enabled},
                onSelectionChanged: (values) {
                  setState(() {
                    _enabled = values.first;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 18),
          _SettingsSectionTitle(title: 'Duration'),
          const SizedBox(height: 10),
          FiveAcrossOptions(
            children: [
              for (final value in const [1, 3, 5, 10, 15])
                CompactOptionButton(
                  label: '${value}m',
                  selected: _minutes == value,
                  onTap: () => _selectPresetMinutes(value),
                ),
            ],
          ),
          const SizedBox(height: 16),
          MinuteWheelPicker(
            controller: _minuteController,
            itemExtent: _pickerItemExtent,
            onChanged: (index) {
              setState(() {
                _enabled = true;
                _minutes = index + 1;
              });
            },
          ),
          const SizedBox(height: 18),
          _PreviewPanel(
            icon: Icons.timer_rounded,
            title: 'Remaining',
            value: _enabled
                ? _formatTimerDuration(Duration(minutes: _minutes))
                : '--:--',
            accent: const Color(0xFFFF7A90),
          ),
        ],
      ),
    );
  }

  void _selectPresetMinutes(int value) {
    setState(() {
      _enabled = true;
      _minutes = value;
    });
    _minuteController.animateToItem(
      value - 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _applyTimer() {
    widget.onChanged(
      enabled: _enabled,
      duration: Duration(minutes: _minutes),
    );
    Navigator.of(context).pop();
  }
}

class _FunctionSheetFrame extends StatelessWidget {
  const _FunctionSheetFrame({
    required this.title,
    required this.scrollController,
    required this.child,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String title;
  final ScrollController scrollController;
  final Widget child;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.border),
          ),
          child: ListView(
            controller: scrollController,
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
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (onAction != null)
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: Icon(actionIcon ?? Icons.check_rounded, size: 18),
                      label: Text(actionLabel ?? 'Apply'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.icon,
    required this.title,
    required this.value,
    required this.accent,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle == null ? value : '$value  $subtitle',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppPalette.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TunerDisplay extends StatelessWidget {
  const _TunerDisplay({
    required this.event,
    required this.reading,
    required this.onRequestPermission,
    required this.isRequestingPermission,
  });

  final TunerPitchEvent event;
  final TunerReading? reading;
  final VoidCallback onRequestPermission;
  final bool isRequestingPermission;

  @override
  Widget build(BuildContext context) {
    final displayReading = reading;
    final hasReading = displayReading != null;
    final noteName = displayReading?.noteName ?? '--';
    final frequencyText = displayReading == null
        ? '-- Hz'
        : '${displayReading.frequency.toStringAsFixed(1)} Hz';
    final centsText = displayReading?.centsText ?? '0 cents';
    final helperText = switch (event.status) {
      TunerStatus.noSignal => 'Waiting for a stable single note',
      TunerStatus.listening || TunerStatus.idle => 'Play a single note',
      _ => event.status.label,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        children: [
          if (event.status == TunerStatus.permissionDenied) ...[
            const Icon(
              Icons.mic_off_rounded,
              size: 42,
              color: AppPalette.danger,
            ),
            const SizedBox(height: 12),
            Text(
              'Microphone permission needed',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isRequestingPermission ? null : onRequestPermission,
              icon: const Icon(Icons.mic_rounded),
              label: Text(isRequestingPermission ? 'Requesting' : 'Enable mic'),
            ),
          ] else if (event.status == TunerStatus.error) ...[
            const Icon(
              Icons.warning_rounded,
              size: 42,
              color: AppPalette.danger,
            ),
            const SizedBox(height: 12),
            Text(
              'Tuner unavailable',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check microphone access and try again',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Text(
                noteName,
                key: ValueKey(noteName),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: hasReading
                      ? AppPalette.textPrimary
                      : AppPalette.textSecondary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Text(
                '$frequencyText  |  $centsText',
                key: ValueKey('$frequencyText-$centsText'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _TunerNeedle(cents: displayReading?.cents ?? 0),
            const SizedBox(height: 12),
            Text(
              helperText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TunerNeedle extends StatelessWidget {
  const _TunerNeedle({required this.cents});

  final double cents;

  @override
  Widget build(BuildContext context) {
    final normalized = (cents / 50).clamp(-1.0, 1.0);

    return SizedBox(
      height: 72,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final centerX = width / 2;
          final needleX = centerX + normalized * (width / 2 - 14);

          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                right: 0,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppPalette.background,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppPalette.border),
                  ),
                ),
              ),
              Positioned(
                left: centerX - 1,
                top: 12,
                bottom: 12,
                child: Container(width: 2, color: const Color(0xFF7AD7A8)),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                left: needleX - 8,
                top: 8,
                child: Container(
                  width: 16,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cents.abs() <= 5
                        ? const Color(0xFF7AD7A8)
                        : AppPalette.secondary,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: _TunerScaleLabel(label: 'Flat'),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: _TunerScaleLabel(label: 'Sharp'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TunerScaleLabel extends StatelessWidget {
  const _TunerScaleLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppPalette.textSecondary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class FiveAcrossOptions extends StatelessWidget {
  const FiveAcrossOptions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        final itemWidth = math.max(
          48.0,
          (constraints.maxWidth - spacing * 4) / 5,
        );
        return Wrap(
          spacing: spacing,
          runSpacing: 8,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class CompactOptionButton extends StatelessWidget {
  const CompactOptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppPalette.primary : AppPalette.border;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppPalette.primary.withValues(alpha: 0.14)
              : AppPalette.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? AppPalette.primary : AppPalette.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class MeterWheelPicker extends StatelessWidget {
  const MeterWheelPicker({
    super.key,
    required this.beatsController,
    required this.noteValueController,
    required this.pickerItemExtent,
    required this.onBeatsChanged,
    required this.onNoteValueChanged,
  });

  final FixedExtentScrollController beatsController;
  final FixedExtentScrollController noteValueController;
  final double pickerItemExtent;
  final ValueChanged<int> onBeatsChanged;
  final ValueChanged<int> onNoteValueChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: AppPalette.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: _LabeledCupertinoWheel(
                  label: 'Beats',
                  accent: AppPalette.primary,
                  controller: beatsController,
                  itemExtent: pickerItemExtent,
                  itemCount: 16,
                  displayBuilder: (index) => '${index + 1}',
                  onChanged: onBeatsChanged,
                ),
              ),
              Container(width: 1, color: AppPalette.border),
              Expanded(
                child: _LabeledCupertinoWheel(
                  label: 'Value',
                  accent: AppPalette.primary,
                  controller: noteValueController,
                  itemExtent: pickerItemExtent,
                  itemCount: kNoteValues.length,
                  displayBuilder: (index) => '${kNoteValues[index]}',
                  onChanged: onNoteValueChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MinuteWheelPicker extends StatelessWidget {
  const MinuteWheelPicker({
    super.key,
    required this.controller,
    required this.itemExtent,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final double itemExtent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 196,
      decoration: BoxDecoration(
        color: AppPalette.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Stack(
        children: [
          _LabeledCupertinoWheel(
            label: 'Minutes',
            accent: const Color(0xFFFF7A90),
            controller: controller,
            itemExtent: itemExtent,
            itemCount: 999,
            displayBuilder: (index) => '${index + 1}',
            suffix: 'min',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _LabeledCupertinoWheel extends StatelessWidget {
  const _LabeledCupertinoWheel({
    required this.label,
    required this.controller,
    required this.itemExtent,
    required this.itemCount,
    required this.displayBuilder,
    required this.onChanged,
    required this.accent,
    this.suffix,
  });

  final String label;
  final FixedExtentScrollController controller;
  final double itemExtent;
  final int itemCount;
  final String Function(int index) displayBuilder;
  final String? suffix;
  final ValueChanged<int> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        Expanded(
          child: CupertinoPicker.builder(
            scrollController: controller,
            itemExtent: itemExtent,
            squeeze: 1.04,
            diameterRatio: 1.18,
            useMagnifier: true,
            magnification: 1.08,
            backgroundColor: Colors.transparent,
            selectionOverlay: _WheelSelectionOverlay(accent: accent),
            childCount: itemCount,
            onSelectedItemChanged: onChanged,
            itemBuilder: (context, index) {
              return Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayBuilder(index),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppPalette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                    if (suffix != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        suffix!,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppPalette.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WheelSelectionOverlay extends StatelessWidget {
  const _WheelSelectionOverlay({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.symmetric(
            horizontal: BorderSide(color: accent.withValues(alpha: 0.34)),
          ),
        ),
      ),
    );
  }
}
