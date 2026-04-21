import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _applyImmersiveMode();
  runApp(const MyApp());
}

Future<void> _applyImmersiveMode() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pulse Grid',
      theme: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF07111D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF19F0C1),
          secondary: Color(0xFF5ED7FF),
          surface: Color(0xFF0F1C2B),
        ),
        textTheme: base.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const MetronomeHomePage(),
    );
  }
}

class MetronomeHomePage extends StatefulWidget {
  const MetronomeHomePage({super.key});

  @override
  State<MetronomeHomePage> createState() => _MetronomeHomePageState();
}

class _MetronomeHomePageState extends State<MetronomeHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _practiceDayKey = 'practice_day_key';
  static const String _practiceAccumulatedMsKey = 'practice_accumulated_ms';
  static const String _practiceSessionStartMsKey = 'practice_session_start_ms';
  static const Duration _tapTempoTimeout = Duration(seconds: 2);
  static const int _tapTempoWindowSize = 6;
  static const double _tapTempoOutlierTolerance = 0.30;

  final MetronomeBridge _bridge = const MetronomeBridge();
  final TapTempoTracker _tapTempoTracker = TapTempoTracker(
    windowSize: _tapTempoWindowSize,
    timeout: _tapTempoTimeout,
    outlierTolerance: _tapTempoOutlierTolerance,
  );
  late final AnimationController _pulseController;
  StreamSubscription<BeatEvent>? _beatSubscription;
  SharedPreferences? _preferences;
  Timer? _practiceTicker;

  int _bpm = 120;
  TimeSignature _signature = kTimeSignatures[3];
  SoundProfile _accentSound = SoundProfile.accent;
  SoundProfile _regularSound = SoundProfile.wood;
  VoiceMode _voiceMode = VoiceMode.off;
  bool _accentHaptics = true;
  bool _isPlaying = false;
  bool _nativeEngineAvailable = true;
  bool _isTransportBusy = false;
  int _activeBeat = 0;
  int _cycleCount = 0;
  String _statusCopy = 'Native SoundPool engine ready';
  String _tapTempoHint = 'Tap tempo';
  Duration _storedPracticeDuration = Duration.zero;
  DateTime? _practiceSessionStart;

  MetronomeConfig get _config => MetronomeConfig(
    bpm: _bpm,
    beatsPerBar: _signature.beatsPerBar,
    timeSignature: _signature.label,
    accentSound: _accentSound.token,
    regularSound: _regularSound.token,
    vocalMode: _voiceMode.token,
    accentHaptics: _accentHaptics,
  );

  Duration get _todayPracticeDuration {
    final sessionStart = _practiceSessionStart;
    if (sessionStart == null) {
      return _storedPracticeDuration;
    }
    return _storedPracticeDuration + DateTime.now().difference(sessionStart);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _beatSubscription = _bridge.beatStream().listen(
      _handleBeat,
      onError: (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _nativeEngineAvailable = false;
          _statusCopy = 'Android native metronome service is unavailable';
        });
      },
    );
    unawaited(_applyImmersiveMode());
    unawaited(_bootstrap());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_applyImmersiveMode());
      unawaited(_restorePracticeState(isPlaying: _isPlaying));
    }
  }

  Future<void> _bootstrap() async {
    final preferences = await SharedPreferences.getInstance();
    final status = await _bridge.fetchStatus();
    if (!mounted) {
      return;
    }

    _preferences = preferences;

    if (status != null) {
      setState(() {
        _bpm = status.config.bpm;
        _signature = _signatureFromLabel(
          status.config.timeSignature,
          status.config.beatsPerBar,
        );
        _accentSound = SoundProfile.fromToken(status.config.accentSound);
        _regularSound = SoundProfile.fromToken(status.config.regularSound);
        _voiceMode = VoiceMode.fromToken(status.config.vocalMode);
        _accentHaptics = status.config.accentHaptics;
        _isPlaying = status.isRunning;
        _activeBeat = status.currentBeat;
        _cycleCount = status.cycleCount;
        _statusCopy = status.isRunning
            ? 'Foreground service is running'
            : 'Native SoundPool engine ready';
      });
    } else {
      setState(() {
        _nativeEngineAvailable = false;
        _statusCopy = 'Android native metronome service is unavailable';
      });
    }

    await _restorePracticeState(isPlaying: status?.isRunning ?? false);
    await _syncConfiguration();
  }

  Future<void> _restorePracticeState({required bool isPlaying}) async {
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }

    final now = DateTime.now();
    final todayKey = _dayKey(now);
    final storedDay = preferences.getString(_practiceDayKey);
    var accumulatedMs = preferences.getInt(_practiceAccumulatedMsKey) ?? 0;
    DateTime? sessionStart;
    final storedSessionMs = preferences.getInt(_practiceSessionStartMsKey);

    if (storedDay == todayKey && storedSessionMs != null) {
      sessionStart = DateTime.fromMillisecondsSinceEpoch(storedSessionMs);
    }

    if (storedDay != todayKey) {
      accumulatedMs = 0;
      sessionStart = isPlaying ? now : null;
    } else if (isPlaying && sessionStart == null) {
      sessionStart = now;
    } else if (!isPlaying && sessionStart != null) {
      accumulatedMs += now.difference(sessionStart).inMilliseconds;
      sessionStart = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _storedPracticeDuration = Duration(milliseconds: accumulatedMs);
      _practiceSessionStart = sessionStart;
    });

    _refreshPracticeTicker();
    await _persistPracticeState();
  }

  Future<void> _persistPracticeState() async {
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }

    await preferences.setString(_practiceDayKey, _dayKey(DateTime.now()));
    await preferences.setInt(
      _practiceAccumulatedMsKey,
      _storedPracticeDuration.inMilliseconds,
    );

    final sessionStart = _practiceSessionStart;
    if (sessionStart == null) {
      await preferences.remove(_practiceSessionStartMsKey);
      return;
    }

    await preferences.setInt(
      _practiceSessionStartMsKey,
      sessionStart.millisecondsSinceEpoch,
    );
  }

  void _refreshPracticeTicker() {
    _practiceTicker?.cancel();
    if (_practiceSessionStart == null) {
      return;
    }

    _practiceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _startPracticeSession() async {
    if (_practiceSessionStart != null) {
      _refreshPracticeTicker();
      return;
    }

    setState(() {
      _practiceSessionStart = DateTime.now();
    });
    _refreshPracticeTicker();
    await _persistPracticeState();
  }

  Future<void> _stopPracticeSession() async {
    final sessionStart = _practiceSessionStart;
    if (sessionStart == null) {
      _practiceTicker?.cancel();
      return;
    }

    setState(() {
      _storedPracticeDuration += DateTime.now().difference(sessionStart);
      _practiceSessionStart = null;
    });
    _practiceTicker?.cancel();
    await _persistPracticeState();
  }

  TimeSignature _signatureFromLabel(String label, int beatsPerBar) {
    for (final signature in kTimeSignatures) {
      if (signature.label == label || signature.beatsPerBar == beatsPerBar) {
        return signature;
      }
    }
    return kTimeSignatures[3];
  }

  void _handleBeat(BeatEvent event) {
    if (!mounted) {
      return;
    }
    _pulseController.forward(from: 0);
    setState(() {
      _activeBeat = event.beatIndex;
      _cycleCount = event.cycleCount;
    });
  }

  Future<void> _syncConfiguration() async {
    final ok = await _bridge.configure(_config);
    if (!mounted) {
      return;
    }
    setState(() {
      _nativeEngineAvailable = ok;
      if (!ok) {
        _statusCopy = 'Android native metronome service is unavailable';
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_isTransportBusy) {
      return;
    }

    final shouldStart = !_isPlaying;
    setState(() {
      _isTransportBusy = true;
      _statusCopy = shouldStart
          ? 'Starting foreground service...'
          : 'Stopping metronome...';
    });

    final ok = shouldStart
        ? await _bridge.start(_config)
        : await _bridge.stop();

    if (!mounted) {
      return;
    }

    if (ok && shouldStart) {
      await _startPracticeSession();
    } else if (ok) {
      await _stopPracticeSession();
    }

    setState(() {
      _isTransportBusy = false;
      _nativeEngineAvailable = ok;
      if (ok) {
        _isPlaying = shouldStart;
        if (shouldStart) {
          _activeBeat = 0;
          _statusCopy = 'Foreground service is running';
        } else {
          _statusCopy = 'Metronome stopped';
        }
      } else {
        _statusCopy = 'Launch failed. Run this on an Android device.';
      }
    });

    if (ok && shouldStart) {
      _pulseController.forward(from: 0);
    }
  }

  Future<void> _updateBpm(int value, {bool resetTapTempoBuffer = false}) async {
    final next = value.clamp(kMinBpm, kMaxBpm);
    if (next == _bpm) {
      if (resetTapTempoBuffer && _tapTempoTracker.sampleCount > 0) {
        setState(() {
          _tapTempoTracker.reset();
          _tapTempoHint = 'Tap tempo';
        });
      }
      return;
    }
    setState(() {
      _bpm = next;
      if (resetTapTempoBuffer) {
        _tapTempoTracker.reset();
        _tapTempoHint = 'Tap tempo';
      }
    });
    await _syncConfiguration();
  }

  Future<void> _handleTapTempo() async {
    final update = _tapTempoTracker.registerTap(DateTime.now());

    setState(() {
      _tapTempoHint = switch (update.state) {
        TapTempoState.primed => 'Tap again',
        TapTempoState.collecting => 'Averaging',
        TapTempoState.locked => 'Tracking live',
        TapTempoState.outlier => 'Ignored stray tap',
      };
    });

    final bpm = update.bpm;
    if (bpm == null) {
      return;
    }

    await _updateBpm(bpm, resetTapTempoBuffer: false);
  }

  Future<void> _updateSignature(TimeSignature signature) async {
    if (_signature == signature) {
      return;
    }
    setState(() {
      _signature = signature;
      _activeBeat = 0;
    });
    await _syncConfiguration();
  }

  Future<void> _updateAccentSound(SoundProfile sound) async {
    if (_accentSound == sound) {
      return;
    }
    setState(() {
      _accentSound = sound;
    });
    await _syncConfiguration();
  }

  Future<void> _updateRegularSound(SoundProfile sound) async {
    if (_regularSound == sound) {
      return;
    }
    setState(() {
      _regularSound = sound;
    });
    await _syncConfiguration();
  }

  Future<void> _updateVoiceMode(VoiceMode mode) async {
    if (_voiceMode == mode) {
      return;
    }
    setState(() {
      _voiceMode = mode;
    });
    await _syncConfiguration();
  }

  Future<void> _toggleAccentHaptics(bool enabled) async {
    setState(() {
      _accentHaptics = enabled;
    });
    await _syncConfiguration();
  }

  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) {
        return MetronomeSettingsSheet(
          accentSound: _accentSound,
          regularSound: _regularSound,
          voiceMode: _voiceMode,
          accentHaptics: _accentHaptics,
          onAccentSoundChanged: _updateAccentSound,
          onRegularSoundChanged: _updateRegularSound,
          onVoiceModeChanged: _updateVoiceMode,
          onAccentHapticsChanged: _toggleAccentHaptics,
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _beatSubscription?.cancel();
    _practiceTicker?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 760;
            final horizontalPadding = compact ? 16.0 : 20.0;
            final pulse =
                1 - Curves.easeOutCubic.transform(_pulseController.value);

            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF030811),
                    Color(0xFF0A1424),
                    Color(0xFF11263B),
                  ],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: -110,
                    right: -40,
                    child: _GlowBlob(
                      color: const Color(0xFF19F0C1).withValues(alpha: 0.12),
                      size: 250,
                    ),
                  ),
                  Positioned(
                    bottom: 36,
                    left: -60,
                    child: _GlowBlob(
                      color: const Color(0xFF5ED7FF).withValues(alpha: 0.10),
                      size: 230,
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        10,
                        horizontalPadding,
                        compact ? 14 : 18,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _GlassIconButton(
                                icon: Icons.tune_rounded,
                                tooltip: 'Open settings',
                                onTap: _openSettingsSheet,
                              ),
                              const Spacer(),
                              DailyPracticeTimer(
                                duration: _todayPracticeDuration,
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 12 : 18),
                          SizedBox(
                            height: compact ? 48 : 56,
                            child: BeatIndicatorStrip(
                              beatsPerBar: _signature.beatsPerBar,
                              activeBeat: _activeBeat,
                              isPlaying: _isPlaying,
                              pulseAmount: pulse,
                            ),
                          ),
                          SizedBox(height: compact ? 8 : 12),
                          Expanded(
                            child: Center(
                              child: BpmDial(
                                bpm: _bpm,
                                min: kMinBpm,
                                max: kMaxBpm,
                                pulseAmount: pulse,
                                tapTempoHint: _tapTempoHint,
                                tapTempoSampleCount:
                                    _tapTempoTracker.sampleCount,
                                size: math.min(
                                  constraints.maxWidth -
                                      (horizontalPadding * 2),
                                  compact ? 300 : 348,
                                ),
                                onChanged: (value) => _updateBpm(
                                  value,
                                  resetTapTempoBuffer: true,
                                ),
                                onTapTempo: () => unawaited(_handleTapTempo()),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 14),
                          TimeSignatureSelector(
                            selected: _signature,
                            onSelected: _updateSignature,
                          ),
                          SizedBox(height: compact ? 12 : 16),
                          _TransportPanel(
                            isPlaying: _isPlaying,
                            isBusy: _isTransportBusy,
                            statusCopy: _statusCopy,
                            activeBeat: _activeBeat,
                            bars: _cycleCount,
                            beatsPerBar: _signature.beatsPerBar,
                            hasNativeEngine: _nativeEngineAvailable,
                            compact: compact,
                            onTogglePlayback: _togglePlayback,
                          ),
                          if (!_nativeEngineAvailable) ...[
                            SizedBox(height: compact ? 8 : 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF241219,
                                ).withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF8F4155),
                                ),
                              ),
                              child: Text(
                                'Preview mode only. Low-latency playback, WakeLock, and audio focus need a real Android device.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.76),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class DailyPracticeTimer extends StatelessWidget {
  const DailyPracticeTimer({super.key, required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final label = _formatDuration(duration);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'TODAY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.42),
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              fontFeatures: const [ui.FontFeature.tabularFigures()],
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Icon(icon, color: Colors.white.withValues(alpha: 0.84)),
        ),
      ),
    );
  }
}

class BeatIndicatorStrip extends StatelessWidget {
  const BeatIndicatorStrip({
    super.key,
    required this.beatsPerBar,
    required this.activeBeat,
    required this.isPlaying,
    required this.pulseAmount,
  });

  final int beatsPerBar;
  final int activeBeat;
  final bool isPlaying;
  final double pulseAmount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < beatsPerBar; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _BeatNode(
                isAccent: index == 0,
                isActive: isPlaying && index == activeBeat,
                pulseAmount: pulseAmount,
              ),
            ),
          ),
      ],
    );
  }
}

class _BeatNode extends StatelessWidget {
  const _BeatNode({
    required this.isAccent,
    required this.isActive,
    required this.pulseAmount,
  });

  final bool isAccent;
  final bool isActive;
  final double pulseAmount;

  @override
  Widget build(BuildContext context) {
    final baseColor = isAccent
        ? const Color(0xFF19F0C1)
        : const Color(0xFF5ED7FF);
    final activeAlpha = isActive ? (0.90 + (pulseAmount * 0.10)) : 0.18;
    final scale = isActive ? 0.98 + (pulseAmount * 0.18) : 0.82;

    return SizedBox.expand(
      child: Center(
        child: Transform.scale(
          scale: scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: isAccent ? 28 : 20,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: baseColor.withValues(alpha: activeAlpha),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        blurRadius: 18,
                        color: baseColor.withValues(
                          alpha: 0.46 + (pulseAmount * 0.16),
                        ),
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class BpmDial extends StatefulWidget {
  const BpmDial({
    super.key,
    required this.bpm,
    required this.min,
    required this.max,
    required this.pulseAmount,
    required this.tapTempoHint,
    required this.tapTempoSampleCount,
    required this.size,
    required this.onChanged,
    required this.onTapTempo,
  });

  final int bpm;
  final int min;
  final int max;
  final double pulseAmount;
  final String tapTempoHint;
  final int tapTempoSampleCount;
  final double size;
  final ValueChanged<int> onChanged;
  final VoidCallback onTapTempo;

  @override
  State<BpmDial> createState() => _BpmDialState();
}

class _BpmDialState extends State<BpmDial> with SingleTickerProviderStateMixin {
  static const double _dragSensitivity = 0.82;

  late final AnimationController _inertiaController;
  late final AnimationController _tapFlashController;
  double _displayBpm = 0;
  int _lastReportedBpm = 0;
  double? _lastAngle;
  Duration? _lastTimestamp;
  double _velocityBpmPerSecond = 0;
  bool _isDragging = false;
  bool _dragStartedOnRing = false;

  @override
  void initState() {
    super.initState();
    _displayBpm = widget.bpm.toDouble();
    _lastReportedBpm = widget.bpm;
    _inertiaController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (!_isDragging) {
          _setBpm(_inertiaController.value, notify: true);
        }
      });
    _tapFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void didUpdateWidget(covariant BpmDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging &&
        !_inertiaController.isAnimating &&
        oldWidget.bpm != widget.bpm) {
      _displayBpm = widget.bpm.toDouble();
      _lastReportedBpm = widget.bpm;
    }
  }

  @override
  void dispose() {
    _inertiaController.dispose();
    _tapFlashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        (_displayBpm - widget.min) / (widget.max - widget.min).toDouble();
    final centerButtonSize = _centerButtonSize;
    final flashProgress = Curves.easeOutCubic.transform(
      _tapFlashController.value,
    );
    final flashAlpha = (1 - flashProgress) * 0.36;
    final flashScale = 0.88 + (flashProgress * 0.42);

    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            onPanCancel: _handlePanCancel,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 52,
                    spreadRadius: 4 + (widget.pulseAmount * 6),
                    color: const Color(
                      0xFF19F0C1,
                    ).withValues(alpha: 0.08 + (widget.pulseAmount * 0.06)),
                  ),
                ],
              ),
              child: CustomPaint(
                painter: BpmDialPainter(
                  progress: progress.clamp(0, 1),
                  pulseAmount: widget.pulseAmount,
                  isDragging: _isDragging || _inertiaController.isAnimating,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Transform.scale(
              scale: flashScale,
              child: Container(
                width: centerButtonSize + 26,
                height: centerButtonSize + 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF19F0C1).withValues(alpha: flashAlpha),
                      const Color(
                        0xFF19F0C1,
                      ).withValues(alpha: flashAlpha * 0.28),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 42,
                      spreadRadius: 4,
                      color: const Color(
                        0xFF19F0C1,
                      ).withValues(alpha: flashAlpha * 0.9),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox.square(
            dimension: centerButtonSize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleCenterTap,
              onPanStart: (_) {},
              onPanUpdate: (_) {},
              onPanEnd: (_) {},
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(
                        0xFF102033,
                      ).withValues(alpha: 0.94 + (widget.pulseAmount * 0.03)),
                      const Color(0xFF07111D).withValues(alpha: 0.98),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 28,
                      color: const Color(0xFF000000).withValues(alpha: 0.18),
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compactCenter = constraints.maxWidth < 132;
                      final bpmFontSize = constraints.maxWidth * 0.28;

                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compactCenter ? 8 : 12,
                            vertical: compactCenter ? 10 : 14,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _displayBpm.round().toString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        fontSize: bpmFontSize,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -2.2,
                                        fontFeatures: const [
                                          ui.FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ),
                              SizedBox(height: compactCenter ? 2 : 4),
                              Text(
                                'BPM',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      fontSize: compactCenter ? 10 : 12,
                                      letterSpacing: compactCenter ? 2.1 : 2.8,
                                      color: Colors.white.withValues(
                                        alpha: 0.58,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              SizedBox(height: compactCenter ? 8 : 10),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compactCenter ? 8 : 10,
                                  vertical: compactCenter ? 5 : 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF19F0C1,
                                  ).withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF19F0C1,
                                    ).withValues(alpha: 0.26),
                                  ),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.touch_app_rounded,
                                        size: compactCenter ? 12 : 14,
                                        color: const Color(0xFF19F0C1),
                                      ),
                                      SizedBox(width: compactCenter ? 4 : 6),
                                      Text(
                                        'TAP TEMPO',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontSize: compactCenter
                                                  ? 10
                                                  : null,
                                              color: const Color(0xFF19F0C1),
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: compactCenter
                                                  ? 0.8
                                                  : 1.1,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePanStart(DragStartDetails details) {
    if (!_isPointOnRotationRing(details.localPosition)) {
      _dragStartedOnRing = false;
      _isDragging = false;
      _lastAngle = null;
      _lastTimestamp = null;
      _velocityBpmPerSecond = 0;
      return;
    }

    _inertiaController.stop();
    _dragStartedOnRing = true;
    _isDragging = true;
    _lastAngle = _angleForOffset(details.localPosition);
    _lastTimestamp = details.sourceTimeStamp;
    _velocityBpmPerSecond = 0;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_dragStartedOnRing) {
      return;
    }
    final angle = _angleForOffset(details.localPosition);
    final previousAngle = _lastAngle;
    if (previousAngle == null) {
      _lastAngle = angle;
      return;
    }

    final deltaAngle = _normalizeAngle(angle - previousAngle);
    final bpmDelta =
        (deltaAngle / (2 * math.pi)) *
        (widget.max - widget.min) *
        _dragSensitivity;
    _setBpm(_displayBpm + bpmDelta, notify: true);

    final timestamp = details.sourceTimeStamp;
    if (timestamp != null && _lastTimestamp != null) {
      final deltaSeconds =
          (timestamp - _lastTimestamp!).inMicroseconds /
          Duration.microsecondsPerSecond;
      if (deltaSeconds > 0) {
        final instantVelocity = bpmDelta / deltaSeconds;
        _velocityBpmPerSecond =
            (_velocityBpmPerSecond * 0.58) + (instantVelocity * 0.42);
      }
    }

    _lastAngle = angle;
    _lastTimestamp = timestamp;
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!_dragStartedOnRing) {
      return;
    }

    _isDragging = false;
    _dragStartedOnRing = false;
    _lastAngle = null;
    _lastTimestamp = null;

    final velocity = _velocityBpmPerSecond.clamp(-120.0, 120.0);
    if (velocity.abs() < 16) {
      _velocityBpmPerSecond = 0;
      return;
    }

    _inertiaController.value = _displayBpm;
    _inertiaController.animateWith(
      FrictionSimulation(0.18, _displayBpm, velocity),
    );
    _velocityBpmPerSecond = 0;
  }

  void _handlePanCancel() {
    _isDragging = false;
    _dragStartedOnRing = false;
    _lastAngle = null;
    _lastTimestamp = null;
    _velocityBpmPerSecond = 0;
  }

  void _setBpm(double value, {required bool notify}) {
    final clamped = value.clamp(widget.min.toDouble(), widget.max.toDouble());
    if ((clamped - value).abs() > 0.001) {
      _inertiaController.stop();
    }

    if ((_displayBpm - clamped).abs() < 0.001) {
      return;
    }

    setState(() {
      _displayBpm = clamped;
    });

    if (!notify) {
      return;
    }

    final rounded = clamped.round();
    if (rounded != _lastReportedBpm) {
      _lastReportedBpm = rounded;
      if (_isDragging) {
        unawaited(HapticFeedback.selectionClick());
      }
      widget.onChanged(rounded);
    }
  }

  void _handleCenterTap() {
    unawaited(HapticFeedback.lightImpact());
    _tapFlashController.forward(from: 0);
    widget.onTapTempo();
  }

  double _angleForOffset(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    return math.atan2(
      localPosition.dy - center.dy,
      localPosition.dx - center.dx,
    );
  }

  double get _centerButtonSize => widget.size * 0.48;

  bool _isPointOnRotationRing(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final distance = (localPosition - center).distance;
    final innerRadius = (_centerButtonSize / 2) + 10;
    final outerRadius = (widget.size / 2) + 8;
    return distance >= innerRadius && distance <= outerRadius;
  }

  double _normalizeAngle(double angle) {
    if (angle > math.pi) {
      return angle - (2 * math.pi);
    }
    if (angle < -math.pi) {
      return angle + (2 * math.pi);
    }
    return angle;
  }
}

class BpmDialPainter extends CustomPainter {
  const BpmDialPainter({
    required this.progress,
    required this.pulseAmount,
    required this.isDragging,
  });

  final double progress;
  final double pulseAmount;
  final bool isDragging;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.width / 2;
    final trackRadius = outerRadius - 30;
    final interactionAlpha = isDragging ? 1.0 : 0.72;
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    final outerPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF18324A).withValues(alpha: 0.96),
          const Color(0xFF08111B).withValues(alpha: 0.98),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius, outerPaint);

    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04 + (pulseAmount * 0.03));
    canvas.drawCircle(center, outerRadius - 20, innerPaint);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.08 + (0.03 * interactionAlpha));
    canvas.drawCircle(center, outerRadius - 1.4, rimPaint);

    final trackPaint = Paint()
      ..color = const Color(0xFF16324A).withValues(
        alpha: 0.86 + (0.08 * interactionAlpha),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: trackRadius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    final trackHighlightPaint = Paint()
      ..color = const Color(0xFF5ED7FF).withValues(
        alpha: 0.10 + (0.06 * interactionAlpha),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: trackRadius),
      startAngle,
      sweepAngle,
      false,
      trackHighlightPaint,
    );

    final progressPaint = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF5ED7FF), Color(0xFF19F0C1), Color(0xFF5ED7FF)],
      ).createShader(Rect.fromCircle(center: center, radius: trackRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: trackRadius),
      startAngle,
      sweepAngle * progress,
      false,
      progressPaint,
    );

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.11 + (0.05 * interactionAlpha))
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 60; i++) {
      final angle = startAngle + (sweepAngle * (i / 60));
      final isMajor = i % 5 == 0;
      final inner = trackRadius + (isMajor ? 7 : 10);
      final outer = trackRadius + (isMajor ? 22 : 17);
      final start = Offset(
        center.dx + math.cos(angle) * inner,
        center.dy + math.sin(angle) * inner,
      );
      final end = Offset(
        center.dx + math.cos(angle) * outer,
        center.dy + math.sin(angle) * outer,
      );
      canvas.drawLine(start, end, tickPaint);
    }

    final innerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = Colors.white.withValues(alpha: 0.08 + (0.03 * interactionAlpha));
    canvas.drawCircle(center, trackRadius - 24, innerRingPaint);

    final handleAngle = startAngle + (sweepAngle * progress);
    final handleCenter = Offset(
      center.dx + math.cos(handleAngle) * trackRadius,
      center.dy + math.sin(handleAngle) * trackRadius,
    );

    final glowPaint = Paint()
      ..color = const Color(
        0xFF19F0C1,
      ).withValues(alpha: 0.26 + (pulseAmount * 0.20) + (0.10 * interactionAlpha))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(
      handleCenter,
      21 + (pulseAmount * 4) + (interactionAlpha * 2),
      glowPaint,
    );

    final handlePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFDBFFFB), Color(0xFF19F0C1)],
      ).createShader(Rect.fromCircle(center: handleCenter, radius: 14));
    canvas.drawCircle(handleCenter, 13, handlePaint);
  }

  @override
  bool shouldRepaint(covariant BpmDialPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulseAmount != pulseAmount ||
        oldDelegate.isDragging != isDragging;
  }
}

class TimeSignatureSelector extends StatelessWidget {
  const TimeSignatureSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TimeSignature selected;
  final ValueChanged<TimeSignature> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          for (var index = 0; index < kTimeSignatures.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: _SignatureButton(
                signature: kTimeSignatures[index],
                selected: selected == kTimeSignatures[index],
                onTap: () => onSelected(kTimeSignatures[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignatureButton extends StatelessWidget {
  const _SignatureButton({
    required this.signature,
    required this.selected,
    required this.onTap,
  });

  final TimeSignature signature;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? const Color(0xFF173946).withValues(alpha: 0.94)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: selected
                ? const Color(0xFF35E2BD).withValues(alpha: 0.75)
                : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    blurRadius: 18,
                    spreadRadius: 1,
                    color: const Color(0xFF19F0C1).withValues(alpha: 0.12),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            signature.label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.84),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportPanel extends StatelessWidget {
  const _TransportPanel({
    required this.isPlaying,
    required this.isBusy,
    required this.statusCopy,
    required this.activeBeat,
    required this.bars,
    required this.beatsPerBar,
    required this.hasNativeEngine,
    required this.compact,
    required this.onTogglePlayback,
  });

  final bool isPlaying;
  final bool isBusy;
  final String statusCopy;
  final int activeBeat;
  final int bars;
  final int beatsPerBar;
  final bool hasNativeEngine;
  final bool compact;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            blurRadius: 38,
            offset: const Offset(0, 20),
            color: const Color(0xFF000000).withValues(alpha: 0.18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFF183247).withValues(alpha: 0.92),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.09),
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                  color: const Color(0xFF000000).withValues(alpha: 0.14),
                ),
              ],
            ),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: isPlaying
                    ? const Color(0xFF112A3C)
                    : const Color(0xFF19F0C1),
                foregroundColor: isPlaying
                    ? Colors.white
                    : const Color(0xFF07111D),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: isBusy ? null : onTogglePlayback,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(
                isPlaying ? 'Stop Pulse' : 'Start Pulse',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 12 : 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'BEAT',
                  value: '${activeBeat + 1}/$beatsPerBar',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(label: 'BARS', value: '$bars'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: 'ENGINE',
                  value: hasNativeEngine ? 'LIVE' : 'PREVIEW',
                  accent: hasNativeEngine
                      ? const Color(0xFF19F0C1)
                      : const Color(0xFFFF8AA7),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          Text(
            statusCopy,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.58),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final resolvedAccent = accent ?? Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.44),
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: resolvedAccent.withValues(alpha: 0.92),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class MetronomeSettingsSheet extends StatefulWidget {
  const MetronomeSettingsSheet({
    super.key,
    required this.accentSound,
    required this.regularSound,
    required this.voiceMode,
    required this.accentHaptics,
    required this.onAccentSoundChanged,
    required this.onRegularSoundChanged,
    required this.onVoiceModeChanged,
    required this.onAccentHapticsChanged,
  });

  final SoundProfile accentSound;
  final SoundProfile regularSound;
  final VoiceMode voiceMode;
  final bool accentHaptics;
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                color: const Color(0xFF0C1826).withValues(alpha: 0.92),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
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
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Session Settings',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Move sound, language, and haptics here so the main workspace stays focused on tempo.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
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
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: SwitchListTile(
                      title: const Text('Accent Haptic Pulse'),
                      subtitle: const Text(
                        'Keep a short tactile cue on the downbeat.',
                      ),
                      value: _accentHaptics,
                      activeThumbColor: const Color(0xFF19F0C1),
                      activeTrackColor: const Color(
                        0xFF19F0C1,
                      ).withValues(alpha: 0.28),
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
        color: Colors.white.withValues(alpha: 0.90),
      ),
    );
  }
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
    final accent = color ?? const Color(0xFF19F0C1);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? accent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? accent : Colors.white.withValues(alpha: 0.74),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected ? accent : Colors.white.withValues(alpha: 0.78),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}

enum TapTempoState { primed, collecting, locked, outlier }

class TapTempoUpdate {
  const TapTempoUpdate({
    required this.state,
    required this.sampleCount,
    this.bpm,
  });

  final TapTempoState state;
  final int sampleCount;
  final int? bpm;
}

class TapTempoTracker {
  TapTempoTracker({
    required this.windowSize,
    required this.timeout,
    required this.outlierTolerance,
  });

  final int windowSize;
  final Duration timeout;
  final double outlierTolerance;
  final List<int> _intervalsMs = <int>[];

  DateTime? _lastTapAt;
  int? _pendingIntervalMs;

  int get sampleCount {
    if (_lastTapAt == null) {
      return 0;
    }
    return math.min(_intervalsMs.length + 1, windowSize);
  }

  void reset() {
    _intervalsMs.clear();
    _lastTapAt = null;
    _pendingIntervalMs = null;
  }

  TapTempoUpdate registerTap(DateTime now) {
    final lastTapAt = _lastTapAt;
    if (lastTapAt == null || now.difference(lastTapAt) > timeout) {
      _intervalsMs.clear();
      _pendingIntervalMs = null;
      _lastTapAt = now;
      return const TapTempoUpdate(state: TapTempoState.primed, sampleCount: 1);
    }

    final intervalMs = now.difference(lastTapAt).inMilliseconds;
    _lastTapAt = now;

    if (intervalMs <= 0) {
      return TapTempoUpdate(
        state: TapTempoState.outlier,
        sampleCount: sampleCount,
      );
    }

    if (_intervalsMs.isEmpty) {
      _intervalsMs.add(intervalMs);
      _pendingIntervalMs = null;
      return TapTempoUpdate(
        state: TapTempoState.collecting,
        bpm: (60000 / intervalMs).round(),
        sampleCount: sampleCount,
      );
    }

    final averageIntervalMs = _intervalsMs.average;
    if (_isWithinTolerance(intervalMs, averageIntervalMs)) {
      _pendingIntervalMs = null;
      _acceptInterval(intervalMs);
      final nextBpm = (60000 / _intervalsMs.average).round();
      final state = _intervalsMs.length >= 2
          ? TapTempoState.locked
          : TapTempoState.collecting;
      return TapTempoUpdate(state: state, bpm: nextBpm, sampleCount: sampleCount);
    }

    final pendingIntervalMs = _pendingIntervalMs;
    if (pendingIntervalMs != null &&
        _isWithinTolerance(intervalMs, pendingIntervalMs.toDouble())) {
      _intervalsMs
        ..clear()
        ..add(pendingIntervalMs)
        ..add(intervalMs);
      _pendingIntervalMs = null;
      final nextBpm = (60000 / _intervalsMs.average).round();
      return TapTempoUpdate(
        state: TapTempoState.collecting,
        bpm: nextBpm,
        sampleCount: sampleCount,
      );
    }

    _pendingIntervalMs = intervalMs;
    return TapTempoUpdate(state: TapTempoState.outlier, sampleCount: sampleCount);
  }

  void _acceptInterval(int intervalMs) {
    _intervalsMs.add(intervalMs);
    if (_intervalsMs.length > windowSize) {
      _intervalsMs.removeAt(0);
    }
  }

  bool _isWithinTolerance(int intervalMs, double baselineMs) {
    if (baselineMs <= 0) {
      return true;
    }
    final deviationRatio = (intervalMs - baselineMs).abs() / baselineMs;
    return deviationRatio <= outlierTolerance;
  }
}

extension on List<int> {
  double get average {
    if (isEmpty) {
      return 0;
    }
    final total = reduce((left, right) => left + right);
    return total / length;
  }
}

class TimeSignature {
  const TimeSignature({
    required this.label,
    required this.beatsPerBar,
    required this.caption,
  });

  final String label;
  final int beatsPerBar;
  final String caption;
}

const int kMinBpm = 30;
const int kMaxBpm = 240;

const List<TimeSignature> kTimeSignatures = [
  TimeSignature(label: '2/4', beatsPerBar: 2, caption: 'March feel'),
  TimeSignature(label: '3/4', beatsPerBar: 3, caption: 'Waltz flow'),
  TimeSignature(label: '4/4', beatsPerBar: 4, caption: 'Daily practice'),
  TimeSignature(label: '5/4', beatsPerBar: 5, caption: 'Odd-meter drive'),
  TimeSignature(label: '6/8', beatsPerBar: 6, caption: 'Compound groove'),
];

enum VoiceMode {
  off('off', 'Off', 'Clicks only'),
  english('english', 'English', 'One, two, three...'),
  chinese('chinese', 'Chinese', 'Yi, er, san...');

  const VoiceMode(this.token, this.label, this.caption);

  final String token;
  final String label;
  final String caption;

  static VoiceMode fromToken(String token) {
    for (final mode in values) {
      if (mode.token == token) {
        return mode;
      }
    }
    return VoiceMode.off;
  }
}

enum SoundProfile {
  accent(
    'accent',
    'Accent',
    'Sharper lead click for the downbeat',
    Color(0xFF19F0C1),
    Icons.flash_on_rounded,
  ),
  mechanical(
    'mechanical',
    'Mechanical',
    'Hard and crisp with strong attack',
    Color(0xFFFFC857),
    Icons.precision_manufacturing_rounded,
  ),
  electronic(
    'electronic',
    'Electronic',
    'Bright electronic pulse for EDM practice',
    Color(0xFF5ED7FF),
    Icons.graphic_eq_rounded,
  ),
  wood(
    'wood',
    'Wood',
    'Warm wooden tap for daily sessions',
    Color(0xFFFF8A65),
    Icons.music_note_rounded,
  );

  const SoundProfile(
    this.token,
    this.label,
    this.description,
    this.color,
    this.icon,
  );

  final String token;
  final String label;
  final String description;
  final Color color;
  final IconData icon;

  static SoundProfile fromToken(String token) {
    for (final profile in values) {
      if (profile.token == token) {
        return profile;
      }
    }
    return SoundProfile.accent;
  }
}

class MetronomeConfig {
  const MetronomeConfig({
    required this.bpm,
    required this.beatsPerBar,
    required this.timeSignature,
    required this.accentSound,
    required this.regularSound,
    required this.vocalMode,
    required this.accentHaptics,
  });

  final int bpm;
  final int beatsPerBar;
  final String timeSignature;
  final String accentSound;
  final String regularSound;
  final String vocalMode;
  final bool accentHaptics;

  Map<String, dynamic> toMap() {
    return {
      'bpm': bpm,
      'beatsPerBar': beatsPerBar,
      'timeSignature': timeSignature,
      'accentSound': accentSound,
      'regularSound': regularSound,
      'vocalMode': vocalMode,
      'accentHaptics': accentHaptics,
    };
  }

  factory MetronomeConfig.fromMap(Map<dynamic, dynamic> map) {
    return MetronomeConfig(
      bpm: (map['bpm'] as int?) ?? 120,
      beatsPerBar: (map['beatsPerBar'] as int?) ?? 4,
      timeSignature: (map['timeSignature'] as String?) ?? '4/4',
      accentSound: (map['accentSound'] as String?) ?? SoundProfile.accent.token,
      regularSound: (map['regularSound'] as String?) ?? SoundProfile.wood.token,
      vocalMode: (map['vocalMode'] as String?) ?? VoiceMode.off.token,
      accentHaptics: (map['accentHaptics'] as bool?) ?? true,
    );
  }
}

class MetronomeStatus {
  const MetronomeStatus({
    required this.isRunning,
    required this.currentBeat,
    required this.cycleCount,
    required this.config,
  });

  final bool isRunning;
  final int currentBeat;
  final int cycleCount;
  final MetronomeConfig config;

  factory MetronomeStatus.fromMap(Map<dynamic, dynamic> map) {
    return MetronomeStatus(
      isRunning: (map['isRunning'] as bool?) ?? false,
      currentBeat: (map['currentBeat'] as int?) ?? 0,
      cycleCount: (map['cycleCount'] as int?) ?? 0,
      config: MetronomeConfig.fromMap(
        Map<dynamic, dynamic>.from(
          (map['config'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
        ),
      ),
    );
  }
}

class BeatEvent {
  const BeatEvent({
    required this.beatIndex,
    required this.beatsPerBar,
    required this.cycleCount,
  });

  final int beatIndex;
  final int beatsPerBar;
  final int cycleCount;

  factory BeatEvent.fromMap(Map<dynamic, dynamic> map) {
    return BeatEvent(
      beatIndex: (map['beatIndex'] as int?) ?? 0,
      beatsPerBar: (map['beatsPerBar'] as int?) ?? 4,
      cycleCount: (map['cycleCount'] as int?) ?? 0,
    );
  }
}

class MetronomeBridge {
  const MetronomeBridge();

  static const MethodChannel _controlChannel = MethodChannel(
    'metronome/control',
  );
  static const EventChannel _beatChannel = EventChannel(
    'metronome/beat_events',
  );

  Stream<BeatEvent> beatStream() {
    return _beatChannel.receiveBroadcastStream().map((dynamic event) {
      return BeatEvent.fromMap(Map<dynamic, dynamic>.from(event as Map));
    });
  }

  Future<bool> configure(MetronomeConfig config) async {
    return _invokeBool('configure', config.toMap());
  }

  Future<bool> start(MetronomeConfig config) async {
    return _invokeBool('start', config.toMap());
  }

  Future<bool> stop() async {
    return _invokeBool('stop');
  }

  Future<MetronomeStatus?> fetchStatus() async {
    try {
      final result = await _controlChannel.invokeMapMethod<dynamic, dynamic>(
        'getStatus',
      );
      if (result == null) {
        return null;
      }
      return MetronomeStatus.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> _invokeBool(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      final result = await _controlChannel.invokeMethod<bool>(
        method,
        arguments,
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
