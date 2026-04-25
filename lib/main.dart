import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'metronome_database.dart';

class AppPalette {
  static const background = Color(0xFF101418);
  static const surface = Color(0xFF1E252D);
  static const surfaceVariant = Color(0xFF252D36);
  static const primary = Color(0xFF4DA3FF);
  static const secondary = Color(0xFFFFB84D);
  static const textPrimary = Color(0xFFF4F6F8);
  static const textSecondary = Color(0xFF9AA4AF);
  static const border = Color(0xFF2D3742);
  static const danger = Color(0xFFFF5C5C);
}

/// App 启动入口：先锁定沉浸式系统 UI，再进入 Flutter 页面树。
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
        scaffoldBackgroundColor: AppPalette.background,
        colorScheme: const ColorScheme.dark(
          primary: AppPalette.primary,
          secondary: AppPalette.secondary,
          surface: AppPalette.surface,
          surfaceContainerHighest: AppPalette.surfaceVariant,
          error: AppPalette.danger,
          onPrimary: AppPalette.background,
          onSurface: AppPalette.textPrimary,
        ),
        textTheme: base.textTheme.apply(
          bodyColor: AppPalette.textPrimary,
          displayColor: AppPalette.textPrimary,
        ),
      ),
      home: const MetronomeMainPage(),
    );
  }
}

/// 顶层页面容器。
///
/// 第二轮重构后，播放状态集中在这里管理：
/// - 底部导航三页共用同一套 Start/Stop 状态。
/// - 首页按钮、WebView 悬浮按钮、倒计时结束都会调用同一条播放路径。
/// - Flutter 配置通过 [MetronomeBridge] 同步给 Android 原生节拍引擎。
class MetronomeMainPage extends StatefulWidget {
  const MetronomeMainPage({super.key});

  @override
  State<MetronomeMainPage> createState() => _MetronomeMainPageState();
}

class _MetronomeMainPageState extends State<MetronomeMainPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _tapTempoTimeout = Duration(seconds: 2);
  static const int _tapTempoWindowSize = 6;
  static const double _tapTempoOutlierTolerance = 0.30;

  final MetronomeBridge _bridge = const MetronomeBridge();
  final MetronomeDatabase _database = MetronomeDatabase.instance;
  final TapTempoTracker _tapTempoTracker = TapTempoTracker(
    windowSize: _tapTempoWindowSize,
    timeout: _tapTempoTimeout,
    outlierTolerance: _tapTempoOutlierTolerance,
  );
  late final AnimationController _pulseController;
  StreamSubscription<BeatEvent>? _beatSubscription;
  Timer? _practiceTicker;
  Timer? _settingsSaveDebounce;
  Timer? _countdownTicker;

  // BottomNavigation 的当前页：0 吉他社 WebView、1 节拍器、2 设置。
  int _selectedTab = 1;
  final Set<int> _visitedTabs = {1};

  // 核心节拍配置。这些字段会组合成 MetronomeConfig 下发给 Android。
  int _bpm = 120;
  TimeSignature _signature = kTimeSignatures[3];
  List<BeatType> _beatPattern = _defaultBeatPattern(
    kTimeSignatures[3].beatsPerBar,
  );
  SoundProfile _accentSound = SoundProfile.accent;
  SoundProfile _regularSound = SoundProfile.wood;
  VoiceMode _voiceMode = VoiceMode.off;
  SubdivisionType _subdivision = SubdivisionType.quarter;

  // 倒计时配置。_timerDuration 是用户设置值，_timerRemaining 是运行中剩余值。
  bool _timerEnabled = false;
  Duration _timerDuration = Duration.zero;
  Duration _timerRemaining = Duration.zero;

  // 运行态与原生引擎状态。所有播放入口都只改这里，避免多页面状态漂移。
  bool _accentHaptics = true;
  bool _isPlaying = false;
  bool _nativeEngineAvailable = true;
  bool _isTransportBusy = false;
  bool _isFlushingPracticeSession = false;
  int _activeBeat = 0;
  DateTime? _practiceSessionStart;
  List<SavedMetronomePreset> _savedPresets = const [];

  /// 当前 Flutter 配置快照，所有 MethodChannel start/configure 都使用它。
  MetronomeConfig get _config => MetronomeConfig(
    bpm: _bpm,
    beatsPerBar: _signature.beatsPerBar,
    noteValue: _signature.noteValue,
    timeSignature: _signature.label,
    accentSound: _accentSound.token,
    regularSound: _regularSound.token,
    vocalMode: _voiceMode.token,
    accentHaptics: _accentHaptics,
    subdivisionType: _subdivision.id,
    beatTypes: _beatPattern.map((type) => type.token).toList(),
  );

  /// 轻量“上次设置”快照，用于 App 下次打开时恢复常用配置。
  PersistedSettings get _settingsSnapshot => PersistedSettings(
    lastBpm: _bpm,
    timeSignature: _signature.label,
    accentSoundId: _accentSound.token,
    normalSoundId: _regularSound.token,
    vocalMode: _voiceMode.token,
    subdivisionType: _subdivision.id,
  );

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
      unawaited(_refreshSavedPresets());
      if (_isPlaying && _practiceSessionStart == null) {
        unawaited(_startPracticeSession());
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_flushPracticeSession(continueIfPlaying: _isPlaying));
      unawaited(_saveSettingsNow());
    }
  }

  Future<void> _bootstrap() async {
    final settings = await _database.loadSettings();
    final status = await _bridge.fetchStatus();
    if (!mounted) {
      return;
    }

    setState(() {
      if (status?.isRunning == true) {
        _applyConfig(status!.config);
      } else if (settings != null) {
        _applyPersistedSettings(settings);
      }

      if (status != null) {
        _isPlaying = status.isRunning;
        _activeBeat = status.currentBeat;
      } else {
        _nativeEngineAvailable = false;
      }
    });

    await _refreshSavedPresets();
    if (status?.isRunning == true) {
      await _startPracticeSession();
    }
    unawaited(_saveSettingsNow());
    await _syncConfiguration();
  }

  void _applyConfig(MetronomeConfig config) {
    _bpm = config.bpm;
    _signature = _signatureFromLabel(
      config.timeSignature,
      config.beatsPerBar,
      noteValue: config.noteValue,
    );
    _beatPattern = _beatPatternFromTokens(
      config.beatTypes,
      _signature.beatsPerBar,
    );
    _accentSound = SoundProfile.fromToken(config.accentSound);
    _regularSound = SoundProfile.fromToken(config.regularSound);
    _voiceMode = VoiceMode.fromToken(config.vocalMode);
    _accentHaptics = config.accentHaptics;
    _subdivision = SubdivisionType.fromId(config.subdivisionType);
  }

  void _applyPersistedSettings(PersistedSettings settings) {
    _bpm = settings.lastBpm.clamp(kMinBpm, kMaxBpm).toInt();
    _signature = _signatureFromLabel(settings.timeSignature, 4);
    _beatPattern = _resizeBeatPattern(_beatPattern, _signature.beatsPerBar);
    _accentSound = SoundProfile.fromToken(settings.accentSoundId);
    _regularSound = SoundProfile.fromToken(settings.normalSoundId);
    _voiceMode = VoiceMode.fromToken(settings.vocalMode);
    _subdivision = SubdivisionType.fromId(settings.subdivisionType);
  }

  Future<void> _refreshPracticeSummary() async {
    final presets = await _database.loadSavedPresets();
    if (!mounted) {
      return;
    }
    setState(() {
      _savedPresets = presets;
    });
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
  }

  Future<void> _stopPracticeSession() async {
    await _flushPracticeSession(continueIfPlaying: false);
  }

  Future<void> _flushPracticeSession({required bool continueIfPlaying}) async {
    if (_isFlushingPracticeSession) {
      return;
    }

    final sessionStart = _practiceSessionStart;
    if (sessionStart == null) {
      _practiceTicker?.cancel();
      return;
    }

    _isFlushingPracticeSession = true;
    final now = DateTime.now();
    final elapsed = now.difference(sessionStart);
    final durationSeconds = elapsed.inSeconds;

    if (mounted) {
      setState(() {
        _practiceSessionStart = continueIfPlaying ? now : null;
      });
    } else {
      _practiceSessionStart = continueIfPlaying ? now : null;
    }

    if (continueIfPlaying) {
      _refreshPracticeTicker();
    } else {
      _practiceTicker?.cancel();
    }

    try {
      await _database.addPracticeLog(
        date: now,
        durationSeconds: durationSeconds,
        averageBpm: _bpm,
      );
      await _refreshPracticeSummary();
    } finally {
      _isFlushingPracticeSession = false;
    }
  }

  TimeSignature _signatureFromLabel(
    String label,
    int beatsPerBar, {
    int? noteValue,
  }) {
    final parsed = _parseSignatureLabel(label);
    for (final signature in kTimeSignatures) {
      if (signature.label == label) {
        return signature;
      }
    }
    if (parsed == null) {
      for (final signature in kTimeSignatures) {
        if (signature.beatsPerBar == beatsPerBar) {
          return signature;
        }
      }
    }
    return TimeSignature(
      label: parsed?.label ?? '$beatsPerBar/${noteValue ?? 4}',
      beatsPerBar: (parsed?.beatsPerBar ?? beatsPerBar).clamp(1, 16).toInt(),
      noteValue: (parsed?.noteValue ?? noteValue ?? 4).clamp(1, 32).toInt(),
      caption: 'Custom meter',
    );
  }

  void _handleBeat(BeatEvent event) {
    if (!mounted) {
      return;
    }
    _pulseController.forward(from: 0);
    setState(() {
      _activeBeat = event.beatIndex;
    });
  }

  Future<void> _syncConfiguration() async {
    final ok = await _bridge.configure(_config);
    if (!mounted) {
      return;
    }
    setState(() {
      _nativeEngineAvailable = ok;
    });
  }

  // 设置保存做 1 秒防抖，避免拖动 BPM 或连续点拍型时频繁写库。
  void _scheduleSettingsSave() {
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(const Duration(seconds: 1), () {
      unawaited(_saveSettingsNow());
    });
  }

  Future<void> _saveSettingsNow() async {
    _settingsSaveDebounce?.cancel();
    await _database.saveSettings(_settingsSnapshot);
  }

  /// 全局播放开关：所有 UI 入口和定时器自动停止都走这里。
  Future<void> _togglePlayback() async {
    await _setPlayback(!_isPlaying);
  }

  /// 实际 Start/Stop 执行函数。
  ///
  /// shouldStart=true 时启动 Android 前台服务；false 时停止服务并结算练习记录。
  Future<void> _setPlayback(bool shouldStart) async {
    if (_isTransportBusy) {
      return;
    }
    if (shouldStart == _isPlaying) {
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isTransportBusy = true;
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
        }
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
        _tapTempoTracker.reset();
      }
      return;
    }
    setState(() {
      _bpm = next;
      if (resetTapTempoBuffer) {
        _tapTempoTracker.reset();
      }
    });
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  Future<void> _handleTapTempo() async {
    final update = _tapTempoTracker.registerTap(DateTime.now());
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
      _beatPattern = _resizeBeatPattern(_beatPattern, signature.beatsPerBar);
      _activeBeat = 0;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  /// 单拍轻重类型循环：Light -> Secondary -> Accent -> Rest -> Light。
  /// 改动后立刻同步给原生层，Rest 才能在播放中即时静音。
  void _cycleBeatType(int index) {
    if (index < 0 || index >= _beatPattern.length) {
      return;
    }
    setState(() {
      _beatPattern = List<BeatType>.of(_beatPattern);
      _beatPattern[index] = _beatPattern[index].next;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    unawaited(_syncConfiguration());
  }

  /// 长按单拍的预留编辑面板。当前只展示类型和细分占位，后续可扩展单拍细分。
  Future<void> _openBeatEditSheet(int index) async {
    if (index < 0 || index >= _beatPattern.length) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        final type = _beatPattern[index];
        return _FunctionSheetFrame(
          title: 'Beat ${index + 1}',
          scrollController: ScrollController(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewPanel(
                icon: Icons.tune_rounded,
                title: 'Current type',
                value: type.label,
                accent: type.color,
              ),
              const SizedBox(height: 16),
              _PreviewPanel(
                icon: Icons.graphic_eq_rounded,
                title: 'Subdivision',
                value: 'Reserved',
                subtitle: 'Per-beat controls are coming',
                accent: AppPalette.primary,
              ),
              const SizedBox(height: 18),
              _SheetActionButton(
                label: 'Confirm',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateAccentSound(SoundProfile sound) async {
    if (_accentSound == sound) {
      return;
    }
    setState(() {
      _accentSound = sound;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  Future<void> _updateRegularSound(SoundProfile sound) async {
    if (_regularSound == sound) {
      return;
    }
    setState(() {
      _regularSound = sound;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  Future<void> _updateVoiceMode(VoiceMode mode) async {
    if (_voiceMode == mode) {
      return;
    }
    setState(() {
      _voiceMode = mode;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  Future<void> _toggleAccentHaptics(bool enabled) async {
    setState(() {
      _accentHaptics = enabled;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  void _setTimer({required bool enabled, required Duration duration}) {
    setState(() {
      _timerEnabled = enabled;
      _timerDuration = enabled ? duration : Duration.zero;
      _timerRemaining = enabled ? duration : Duration.zero;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    if (enabled) {
      _startCountdown();
    } else {
      _stopCountdown(clearRemaining: true);
    }
  }

  /// Apply 后启动 UI 倒计时；归零时通过全局播放路径停止节拍器。
  void _startCountdown() {
    _countdownTicker?.cancel();
    if (!_timerEnabled || _timerRemaining <= Duration.zero) {
      return;
    }

    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final next = _timerRemaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _stopCountdown(clearRemaining: true);
        if (_isPlaying) {
          unawaited(_setPlayback(false));
        }
        return;
      }
      setState(() {
        _timerRemaining = next;
      });
    });
  }

  void _stopCountdown({required bool clearRemaining}) {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _timerEnabled = clearRemaining ? false : _timerEnabled;
      _timerRemaining = clearRemaining ? Duration.zero : _timerRemaining;
    });
  }

  Future<void> _refreshSavedPresets() async {
    final presets = await _database.loadSavedPresets();
    if (!mounted) {
      return;
    }
    setState(() {
      _savedPresets = presets;
    });
  }

  Future<void> _saveCurrentPreset(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return;
    }

    await _database.savePreset(
      SavedMetronomePreset(
        id: null,
        name: trimmedName,
        bpm: _bpm,
        timeSignature: _signature.label,
        beatsPerBar: _signature.beatsPerBar,
        noteValue: _signature.noteValue,
        beatPattern: _beatPattern.map((type) => type.token).toList(),
        subdivisionType: _subdivision.id,
        timerEnabled: _timerEnabled,
        timerSeconds: _timerRemaining.inSeconds > 0
            ? _timerRemaining.inSeconds
            : _timerDuration.inSeconds,
        accentSoundId: _accentSound.token,
        normalSoundId: _regularSound.token,
        vocalMode: _voiceMode.token,
      ),
    );
    await _refreshSavedPresets();
  }

  /// 从设置页恢复已保存配置，并立即同步给 Android 引擎。
  Future<void> _restorePreset(SavedMetronomePreset preset) async {
    final nextSignature = TimeSignature(
      label: preset.timeSignature,
      beatsPerBar: preset.beatsPerBar,
      noteValue: preset.noteValue,
      caption: 'Saved meter',
    );
    final nextDuration = Duration(seconds: preset.timerSeconds);

    setState(() {
      _bpm = preset.bpm.clamp(kMinBpm, kMaxBpm).toInt();
      _signature = nextSignature;
      _beatPattern = _beatPatternFromTokens(
        preset.beatPattern,
        nextSignature.beatsPerBar,
      );
      _subdivision = SubdivisionType.fromId(preset.subdivisionType);
      _timerEnabled = preset.timerEnabled && nextDuration > Duration.zero;
      _timerDuration = _timerEnabled ? nextDuration : Duration.zero;
      _timerRemaining = _timerDuration;
      _accentSound = SoundProfile.fromToken(preset.accentSoundId);
      _regularSound = SoundProfile.fromToken(preset.normalSoundId);
      _voiceMode = VoiceMode.fromToken(preset.vocalMode);
      _selectedTab = 1;
    });

    if (_timerEnabled) {
      _startCountdown();
    } else {
      _countdownTicker?.cancel();
      _countdownTicker = null;
    }
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  Future<void> _deletePreset(SavedMetronomePreset preset) async {
    final id = preset.id;
    if (id == null) {
      return;
    }
    await _database.deletePreset(id);
    await _refreshSavedPresets();
  }

  Future<void> _openFunctionSheet(_FunctionSheet sheet) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.36,
          maxChildSize: 0.90,
          expand: false,
          builder: (context, scrollController) {
            return switch (sheet) {
              _FunctionSheet.signature => TimeSignatureSheet(
                initialSignature: _signature,
                scrollController: scrollController,
                onConfirmed: _updateSignature,
              ),
              _FunctionSheet.sound => SoundPresetSheet(
                accentSound: _accentSound,
                regularSound: _regularSound,
                voiceMode: _voiceMode,
                accentHaptics: _accentHaptics,
                scrollController: scrollController,
                onAccentSoundChanged: _updateAccentSound,
                onRegularSoundChanged: _updateRegularSound,
                onVoiceModeChanged: _updateVoiceMode,
                onAccentHapticsChanged: _toggleAccentHaptics,
              ),
              _FunctionSheet.tuner => TunerSheet(
                scrollController: scrollController,
              ),
              _FunctionSheet.timer => TimerSheet(
                enabled: _timerEnabled,
                duration: _timerEnabled ? _timerRemaining : _timerDuration,
                scrollController: scrollController,
                onChanged: _setTimer,
              ),
            };
          },
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _beatSubscription?.cancel();
    _practiceTicker?.cancel();
    _countdownTicker?.cancel();
    unawaited(_flushPracticeSession(continueIfPlaying: _isPlaying));
    unawaited(_saveSettingsNow());
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppPalette.background,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        bottomNavigationBar: BottomNavigation(
          selectedIndex: _selectedTab,
          onDestinationSelected: (index) {
            setState(() {
              _selectedTab = index;
              _visitedTabs.add(index);
            });
          },
        ),
        body: IndexedStack(
          index: _selectedTab,
          children: [
            if (_visitedTabs.contains(0))
              GuitarSocietyPage(
                isPlaying: _isPlaying,
                isBusy: _isTransportBusy,
                onTogglePlayback: _togglePlayback,
              )
            else
              const SizedBox.shrink(),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 740;
                final horizontalPadding = compact ? 16.0 : 20.0;
                final pulse =
                    1 - Curves.easeOutCubic.transform(_pulseController.value);
                final dialSize = math.min(
                  constraints.maxWidth - (horizontalPadding * 2),
                  compact ? 268.0 : 346.0,
                );

                return ColoredBox(
                  color: AppPalette.background,
                  child: SafeArea(
                    bottom: true,
                    child: SingleChildScrollView(
                      physics: compact
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        12,
                        horizontalPadding,
                        compact ? 22 : 28,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              constraints.maxHeight -
                              MediaQuery.paddingOf(context).vertical -
                              (compact ? 26 : 30),
                        ),
                        child: Column(
                          children: [
                            TopFunctionBar(
                              signatureLabel: _signature.label,
                              soundLabel: _regularSound.label,
                              timerLabel: _timerEnabled
                                  ? _formatTimerDuration(_timerRemaining)
                                  : null,
                              onSignatureTap: () =>
                                  _openFunctionSheet(_FunctionSheet.signature),
                              onSoundTap: () =>
                                  _openFunctionSheet(_FunctionSheet.sound),
                              onTunerTap: () =>
                                  _openFunctionSheet(_FunctionSheet.tuner),
                              onTimerTap: () =>
                                  _openFunctionSheet(_FunctionSheet.timer),
                            ),
                            SizedBox(height: compact ? 22 : 30),
                            BeatPatternBar(
                              beatPattern: _beatPattern,
                              activeBeat: _activeBeat,
                              isPlaying: _isPlaying,
                              onBeatTap: _cycleBeatType,
                              onBeatLongPress: _openBeatEditSheet,
                            ),
                            SizedBox(height: compact ? 24 : 34),
                            BpmDial(
                              bpm: _bpm,
                              min: kMinBpm,
                              max: kMaxBpm,
                              pulseAmount: pulse,
                              size: dialSize,
                              onChanged: (value) =>
                                  _updateBpm(value, resetTapTempoBuffer: true),
                              onTapTempo: () => unawaited(_handleTapTempo()),
                            ),
                            SizedBox(height: compact ? 24 : 34),
                            TransportPanel(
                              isPlaying: _isPlaying,
                              isBusy: _isTransportBusy,
                              compact: compact,
                              onTogglePlayback: _togglePlayback,
                            ),
                            if (!_nativeEngineAvailable) ...[
                              SizedBox(height: compact ? 18 : 24),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppPalette.danger.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppPalette.danger.withValues(
                                      alpha: 0.36,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Preview mode only. Low-latency playback, WakeLock, and audio focus need a real Android device.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppPalette.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_visitedTabs.contains(2))
              SettingsPage(
                presets: _savedPresets,
                onSavePreset: _saveCurrentPreset,
                onRestorePreset: _restorePreset,
                onDeletePreset: _deletePreset,
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

enum _FunctionSheet { signature, sound, tuner, timer }

/// 首页顶部四个功能入口：拍号、音色、调音器、定时器。
/// 每个入口只打开抽屉，不直接把复杂设置堆在首页。
class TopFunctionBar extends StatelessWidget {
  const TopFunctionBar({
    super.key,
    required this.signatureLabel,
    required this.soundLabel,
    required this.timerLabel,
    required this.onSignatureTap,
    required this.onSoundTap,
    required this.onTunerTap,
    required this.onTimerTap,
  });

  final String signatureLabel;
  final String soundLabel;
  final String? timerLabel;
  final VoidCallback onSignatureTap;
  final VoidCallback onSoundTap;
  final VoidCallback onTunerTap;
  final VoidCallback onTimerTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FunctionButton(
            label: 'Meter',
            value: signatureLabel,
            icon: Icons.grid_4x4_rounded,
            accent: AppPalette.secondary,
            onTap: onSignatureTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FunctionButton(
            label: 'Tone',
            value: soundLabel,
            icon: Icons.graphic_eq_rounded,
            accent: AppPalette.primary,
            onTap: onSoundTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FunctionButton(
            label: 'Tuner',
            value: 'Dev',
            icon: Icons.tune_rounded,
            accent: const Color(0xFF7AD7A8),
            onTap: onTunerTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FunctionButton(
            label: 'Timer',
            value: timerLabel ?? '--',
            icon: Icons.timer_rounded,
            accent: const Color(0xFFFF7A90),
            onTap: onTimerTap,
          ),
        ),
      ],
    );
  }
}

/// 顶部功能按钮的通用外观，保持固定高度避免不同文字导致抖动。
class FunctionButton extends StatelessWidget {
  const FunctionButton({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppPalette.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppPalette.textPrimary,
                    fontWeight: FontWeight.w900,
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

/// 首页轻重拍编辑条。
///
/// 每个 Cell 显示拍号数字，用高度和颜色表达 Accent/Secondary/Light/Rest。
/// 点击循环类型，长按打开单拍编辑预留面板。
class BeatPatternBar extends StatelessWidget {
  const BeatPatternBar({
    super.key,
    required this.beatPattern,
    required this.activeBeat,
    required this.isPlaying,
    required this.onBeatTap,
    required this.onBeatLongPress,
  });

  final List<BeatType> beatPattern;
  final int activeBeat;
  final bool isPlaying;
  final ValueChanged<int> onBeatTap;
  final ValueChanged<int> onBeatLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < beatPattern.length; index++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: beatPattern.length > 12 ? 2 : 4,
                ),
                child: BeatPatternCell(
                  index: index,
                  type: beatPattern[index],
                  isActive: isPlaying && activeBeat == index,
                  onTap: () => onBeatTap(index),
                  onLongPress: () => onBeatLongPress(index),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个拍子的可点击柱状单元。
class BeatPatternCell extends StatelessWidget {
  const BeatPatternCell({
    super.key,
    required this.index,
    required this.type,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  final int index;
  final BeatType type;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${index + 1}: ${type.label}',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: type.barHeight,
          constraints: const BoxConstraints(minHeight: 18),
          decoration: BoxDecoration(
            color: type.color.withValues(
              alpha: type == BeatType.rest ? 0.28 : 0.92,
            ),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isActive ? AppPalette.textPrimary : type.color,
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: type.color.withValues(alpha: 0.26),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: type == BeatType.rest
                    ? AppPalette.textSecondary
                    : AppPalette.background,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 仅用于播放时的微型节拍灯组件。
/// 第二轮首页已移除上方进度灯，此组件暂留给后续可能的小型状态展示。
class BeatIndicatorStrip extends StatelessWidget {
  const BeatIndicatorStrip({
    super.key,
    required this.beatsPerBar,
    required this.beatPattern,
    required this.activeBeat,
    required this.isPlaying,
    required this.pulseAmount,
  });

  final int beatsPerBar;
  final List<BeatType> beatPattern;
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
                type: index < beatPattern.length
                    ? beatPattern[index]
                    : BeatType.light,
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
    required this.type,
    required this.isActive,
    required this.pulseAmount,
  });

  final BeatType type;
  final bool isActive;
  final double pulseAmount;

  @override
  Widget build(BuildContext context) {
    final baseColor = type.color;
    final activeAlpha = isActive ? (0.86 + (pulseAmount * 0.10)) : 0.22;
    final scale = isActive ? 0.98 + (pulseAmount * 0.10) : 0.82;

    return SizedBox.expand(
      child: Center(
        child: Transform.scale(
          scale: scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: type == BeatType.accent ? 28 : 20,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: baseColor.withValues(alpha: activeAlpha),
              border: Border.all(
                color: isActive ? baseColor : AppPalette.border,
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// BPM 圆盘：外圈拖动调速，中心点击 Tap Tempo，中心 +/- 支持微调和长按连调。
class BpmDial extends StatefulWidget {
  const BpmDial({
    super.key,
    required this.bpm,
    required this.min,
    required this.max,
    required this.pulseAmount,
    required this.size,
    required this.onChanged,
    required this.onTapTempo,
  });

  final int bpm;
  final int min;
  final int max;
  final double pulseAmount;
  final double size;
  final ValueChanged<int> onChanged;
  final VoidCallback onTapTempo;

  @override
  State<BpmDial> createState() => _BpmDialState();
}

class _BpmDialState extends State<BpmDial> with TickerProviderStateMixin {
  static const double _dragSensitivity = 0.62;

  late final AnimationController _inertiaController;
  late final AnimationController _tapFlashController;
  double _displayBpm = 0;
  int _lastReportedBpm = 0;
  double? _lastAngle;
  Duration? _lastTimestamp;
  double _velocityBpmPerSecond = 0;
  bool _isDragging = false;
  bool _dragStartedOnRing = false;
  Timer? _stepTimer;

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
    _stepTimer?.cancel();
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
    final flashAlpha = (1 - flashProgress) * 0.72;

    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _handlePanStart,
              onPanUpdate: _handlePanUpdate,
              onPanEnd: _handlePanEnd,
              onPanCancel: _handlePanCancel,
              child: SizedBox.expand(
                child: CustomPaint(
                  painter: BpmDialPainter(
                    progress: progress.clamp(0, 1),
                    pulseAmount: widget.pulseAmount,
                    isDragging: _isDragging || _inertiaController.isAnimating,
                  ),
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
                  color: AppPalette.surface,
                  border: Border.all(color: AppPalette.border),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 14,
                      color: Colors.black.withValues(alpha: 0.24),
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.08),
                              radius: 0.95,
                              colors: [
                                AppPalette.primary.withValues(
                                  alpha: flashAlpha * 0.18,
                                ),
                                AppPalette.primary.withValues(
                                  alpha: flashAlpha * 0.10,
                                ),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compactCenter = constraints.maxWidth < 132;
                            final bpmFontSize = constraints.maxWidth * 0.32;

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
                                              letterSpacing: 0,
                                              color: AppPalette.textPrimary,
                                              fontFeatures: const [
                                                ui.FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                    ),
                                    SizedBox(height: compactCenter ? 2 : 4),
                                    Text(
                                      'BPM',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontSize: compactCenter ? 10 : 12,
                                            letterSpacing: 0,
                                            color: AppPalette.textSecondary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    SizedBox(height: compactCenter ? 2 : 4),
                                    Text(
                                      _tempoMarking(_displayBpm.round()),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: AppPalette.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    SizedBox(height: compactCenter ? 6 : 8),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _BpmStepButton(
                                          icon: Icons.remove_rounded,
                                          onTap: () => _stepBpm(-1),
                                          onLongPressStart: () =>
                                              _startStepping(-1),
                                          onLongPressEnd: _stopStepping,
                                        ),
                                        const SizedBox(width: 14),
                                        _BpmStepButton(
                                          icon: Icons.add_rounded,
                                          onTap: () => _stepBpm(1),
                                          onLongPressStart: () =>
                                              _startStepping(1),
                                          onLongPressEnd: _stopStepping,
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: compactCenter ? 6 : 8),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: compactCenter ? 8 : 10,
                                        vertical: compactCenter ? 5 : 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppPalette.surfaceVariant,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppPalette.primary.withValues(
                                            alpha: 0.48,
                                          ),
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
                                              color: AppPalette.primary,
                                            ),
                                            SizedBox(
                                              width: compactCenter ? 4 : 6,
                                            ),
                                            Text(
                                              'TAP TEMPO',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    fontSize: compactCenter
                                                        ? 10
                                                        : null,
                                                    color: AppPalette.primary,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0,
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
                    ],
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

  void _stepBpm(int delta) {
    _inertiaController.stop();
    _setBpm(_displayBpm + delta, notify: true);
    unawaited(HapticFeedback.selectionClick());
  }

  void _startStepping(int delta) {
    _stepTimer?.cancel();
    _stepBpm(delta);
    _stepTimer = Timer.periodic(const Duration(milliseconds: 92), (_) {
      _stepBpm(delta);
    });
  }

  void _stopStepping() {
    _stepTimer?.cancel();
    _stepTimer = null;
  }

  double _angleForOffset(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    return math.atan2(
      localPosition.dy - center.dy,
      localPosition.dx - center.dx,
    );
  }

  double get _centerButtonSize => widget.size * 0.58;

  bool _isPointOnRotationRing(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final distance = (localPosition - center).distance;
    final innerRadius = (_centerButtonSize / 2) + 12;
    final outerRadius = (widget.size / 2) - 2;
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

class _BpmStepButton extends StatelessWidget {
  const _BpmStepButton({
    required this.icon,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      onLongPressCancel: onLongPressEnd,
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: AppPalette.surfaceVariant,
          foregroundColor: AppPalette.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
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
    final trackRadius = outerRadius - 32;
    final interactionAlpha = isDragging ? 1.0 : 0.74;
    const startAngle = -math.pi / 2;
    const sweepAngle = math.pi * 2;

    final outerPaint = Paint()..color = AppPalette.surface;
    canvas.drawCircle(center, outerRadius, outerPaint);

    final outerBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppPalette.border;
    canvas.drawCircle(center, outerRadius - 1, outerBorderPaint);

    final trackPaint = Paint()
      ..color = AppPalette.surfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, trackRadius, trackPaint);

    final progressPaint = Paint()
      ..color = AppPalette.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: trackRadius),
      startAngle,
      sweepAngle * progress,
      false,
      progressPaint,
    );

    final tickPaint = Paint()
      ..color = AppPalette.textSecondary.withValues(
        alpha: 0.28 + (0.08 * interactionAlpha),
      )
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 72; i++) {
      final angle = startAngle + (sweepAngle * (i / 72));
      final isMajor = i % 6 == 0;
      final inner = trackRadius + (isMajor ? 8 : 10);
      final outer = trackRadius + (isMajor ? 23 : 17);
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
      ..strokeWidth = 1.4
      ..color = AppPalette.border;
    canvas.drawCircle(center, trackRadius - 20, innerRingPaint);

    final handleAngle = startAngle + (sweepAngle * progress);
    final handleCenter = Offset(
      center.dx + math.cos(handleAngle) * trackRadius,
      center.dy + math.sin(handleAngle) * trackRadius,
    );

    final handlePaint = Paint()..color = AppPalette.textPrimary;
    canvas.drawCircle(handleCenter, 10.5, handlePaint);

    final handleBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppPalette.primary;
    canvas.drawCircle(handleCenter, 12.5, handleBorderPaint);
  }

  @override
  bool shouldRepaint(covariant BpmDialPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulseAmount != pulseAmount ||
        oldDelegate.isDragging != isDragging;
  }
}

/// 旧版拍号选择入口，保留用于兼容测试或未来拆分时参考。
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
    return _ControlChip(
      label: 'Time Signature',
      value: selected.label,
      icon: Icons.grid_4x4_rounded,
      accent: AppPalette.secondary,
      onTap: () => _openPicker(context),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<TimeSignature>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _SelectorSheet(
          title: 'Time Signature',
          children: [
            _SignatureGroup(
              title: 'Simple',
              signatures: const [
                TimeSignature(label: '2/4', beatsPerBar: 2, caption: 'March'),
                TimeSignature(label: '3/4', beatsPerBar: 3, caption: 'Waltz'),
                TimeSignature(label: '4/4', beatsPerBar: 4, caption: 'Common'),
              ],
              selected: selected,
            ),
            _SignatureGroup(
              title: 'Compound',
              signatures: const [
                TimeSignature(label: '6/8', beatsPerBar: 6, caption: 'Flow'),
              ],
              selected: selected,
            ),
            _SignatureGroup(
              title: 'Odd',
              signatures: const [
                TimeSignature(label: '5/4', beatsPerBar: 5, caption: 'Odd'),
              ],
              selected: selected,
            ),
          ],
        );
      },
    );

    if (picked != null) {
      onSelected(picked);
    }
  }
}

class _SignatureGroup extends StatelessWidget {
  const _SignatureGroup({
    required this.title,
    required this.signatures,
    required this.selected,
  });

  final String title;
  final List<TimeSignature> signatures;
  final TimeSignature selected;

  @override
  Widget build(BuildContext context) {
    return _SheetGroup(
      title: title,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final signature in signatures)
            _SheetChoiceChip(
              label: signature.label,
              caption: signature.caption,
              selected: signature.label == selected.label,
              accent: AppPalette.secondary,
              onTap: () => Navigator.of(context).pop(signature),
            ),
        ],
      ),
    );
  }
}

class _SelectorSheet extends StatelessWidget {
  const _SelectorSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppPalette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppPalette.textSecondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SheetChoiceChip extends StatelessWidget {
  const _SheetChoiceChip({
    required this.label,
    required this.caption,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String caption;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: selected ? accent : AppPalette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              caption,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubdivisionSelector extends StatelessWidget {
  const SubdivisionSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final SubdivisionType selected;
  final ValueChanged<SubdivisionType> onSelected;

  @override
  Widget build(BuildContext context) {
    return _ControlChip(
      label: 'Subdivision',
      value: selected.notation,
      icon: Icons.music_note_rounded,
      accent: AppPalette.primary,
      onTap: () => _openPicker(context),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<SubdivisionType>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _SelectorSheet(
          title: 'Subdivision',
          children: [
            _SheetGroup(
              title: 'Pulse',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final subdivision in SubdivisionType.values)
                    _SheetChoiceChip(
                      label: subdivision.notation,
                      caption: subdivision.label,
                      selected: selected == subdivision,
                      accent: AppPalette.primary,
                      onTap: () => Navigator.of(context).pop(subdivision),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (picked != null) {
      onSelected(picked);
    }
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: 0.40)),
              ),
              child: Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppPalette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class TransportPanel extends StatelessWidget {
  const TransportPanel({
    super.key,
    required this.isPlaying,
    required this.isBusy,
    required this.compact,
    required this.onTogglePlayback,
  });

  final bool isPlaying;
  final bool isBusy;
  final bool compact;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppPalette.surface,
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              backgroundColor: isPlaying
                  ? AppPalette.danger
                  : AppPalette.primary,
              foregroundColor: AppPalette.background,
              disabledBackgroundColor: AppPalette.surfaceVariant,
              disabledForegroundColor: AppPalette.textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: isBusy ? null : onTogglePlayback,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              isPlaying ? 'Stop' : 'Start',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppPalette.background,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 拍号抽屉。
///
/// 双滚轮分别选择拍数和音符时值，快捷拍型负责快速跳转常用组合。
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
/// 第二轮需求要求暂不扩展真实音源逻辑，因此这里主要作为 UI 入口和现有音色字段编辑。
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
/// 通过 Android 原生 AudioRecord 事件流显示真实麦克风识别结果。
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
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
        setState(() {
          _event = event;
        });
      },
      onError: (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _event = const TunerPitchEvent(status: TunerStatus.error);
        });
      },
    );
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
    });
    if (granted) {
      _startListening();
    }
  }
}

/// 定时器抽屉。
/// Apply 后会启动首页状态中的倒计时，倒计时归零自动停止全局节拍器。
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
    required this.onRequestPermission,
    required this.isRequestingPermission,
  });

  final TunerPitchEvent event;
  final VoidCallback onRequestPermission;
  final bool isRequestingPermission;

  @override
  Widget build(BuildContext context) {
    final reading = event.reading;

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
              '需要麦克风权限',
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
          ] else if (reading == null) ...[
            Icon(
              event.status == TunerStatus.error
                  ? Icons.warning_rounded
                  : Icons.mic_rounded,
              size: 42,
              color: event.status == TunerStatus.error
                  ? AppPalette.danger
                  : const Color(0xFF7AD7A8),
            ),
            const SizedBox(height: 12),
            Text(
              event.status == TunerStatus.error ? '麦克风不可用' : 'Listening',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              event.status == TunerStatus.noSignal
                  ? 'No stable pitch detected'
                  : 'Play a single note near the microphone',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            Text(
              reading.noteName,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${reading.frequency.toStringAsFixed(1)}Hz  |  ${reading.centsText}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            _TunerNeedle(cents: reading.cents),
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

/// 吉他社网页页签。
/// WebView 内右下角的浮动 Start/Stop 和首页按钮共享同一个播放状态。
class GuitarSocietyPage extends StatefulWidget {
  const GuitarSocietyPage({
    super.key,
    required this.isPlaying,
    required this.isBusy,
    required this.onTogglePlayback,
  });

  final bool isPlaying;
  final bool isBusy;
  final VoidCallback onTogglePlayback;

  @override
  State<GuitarSocietyPage> createState() => _GuitarSocietyPageState();
}

class _GuitarSocietyPageState extends State<GuitarSocietyPage> {
  late final WebViewController _controller;
  var _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.jitashe.org/'));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppPalette.background,
      child: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const LinearProgressIndicator(
                color: AppPalette.primary,
                backgroundColor: AppPalette.surface,
              ),
            Positioned(
              right: 16,
              bottom: 18,
              child: FloatingActionButton.extended(
                heroTag: 'web-metronome-transport',
                onPressed: widget.isBusy ? null : widget.onTogglePlayback,
                backgroundColor: widget.isPlaying
                    ? AppPalette.danger
                    : AppPalette.primary,
                foregroundColor: AppPalette.background,
                icon: Icon(
                  widget.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(widget.isPlaying ? 'Stop' : 'Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置页：负责命名保存、恢复和删除本地节拍器配置。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.presets,
    required this.onSavePreset,
    required this.onRestorePreset,
    required this.onDeletePreset,
  });

  final List<SavedMetronomePreset> presets;
  final ValueChanged<String> onSavePreset;
  final ValueChanged<SavedMetronomePreset> onRestorePreset;
  final ValueChanged<SavedMetronomePreset> onDeletePreset;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppPalette.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: AppPalette.textPrimary),
              decoration: InputDecoration(
                labelText: 'Configuration name',
                labelStyle: const TextStyle(color: AppPalette.textSecondary),
                filled: true,
                fillColor: AppPalette.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppPalette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppPalette.border),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                widget.onSavePreset(_nameController.text);
                _nameController.clear();
                FocusScope.of(context).unfocus();
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save current configuration'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 22),
            _SettingsSectionTitle(title: 'Saved configurations'),
            const SizedBox(height: 10),
            if (widget.presets.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.border),
                ),
                child: Text(
                  'No saved configurations yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
              )
            else
              for (final preset in widget.presets) ...[
                _SavedPresetTile(
                  preset: preset,
                  onRestore: () => widget.onRestorePreset(preset),
                  onDelete: () => widget.onDeletePreset(preset),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
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
  final VoidCallback onDelete;

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

/// 三页底部导航：吉他社、节拍器、设置。
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
        NavigationDestination(icon: Icon(Icons.public_rounded), label: '吉他社'),
        NavigationDestination(icon: Icon(Icons.speed_rounded), label: '节拍器'),
        NavigationDestination(icon: Icon(Icons.settings_rounded), label: '设置'),
      ],
    );
  }
}

/// 第一轮遗留的综合设置抽屉。
/// 当前主流程已改为顶部四个功能抽屉，保留此组件作为历史/后续整合参考。
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

enum TapTempoState { primed, collecting, locked, outlier }

/// Tap Tempo 的一次计算结果。
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

/// 纯 Dart Tap Tempo 算法，便于 widget_test 直接验证。
/// 负责超时重置、异常间隔剔除、滑动平均和快速变速适配。
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
      return TapTempoUpdate(
        state: state,
        bpm: nextBpm,
        sampleCount: sampleCount,
      );
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
    return TapTempoUpdate(
      state: TapTempoState.outlier,
      sampleCount: sampleCount,
    );
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

/// 拍号模型。noteValue 是分母，例如 6/8 的 noteValue 为 8。
class TimeSignature {
  const TimeSignature({
    required this.label,
    required this.beatsPerBar,
    required this.caption,
    this.noteValue = 4,
  });

  final String label;
  final int beatsPerBar;
  final String caption;
  final int noteValue;

  @override
  bool operator ==(Object other) {
    return other is TimeSignature &&
        other.beatsPerBar == beatsPerBar &&
        other.noteValue == noteValue &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(label, beatsPerBar, noteValue);
}

/// 单拍类型。token 会传给 Android 原生层，Rest 代表整拍静音。
enum BeatType {
  accent('accent', 'Accent', 'A', AppPalette.secondary, 56),
  secondary('secondary', 'Secondary', 'S', AppPalette.primary, 42),
  light('light', 'Light', 'L', Color(0xFF1F7A7A), 28),
  rest('rest', 'Rest', 'R', Color(0xFF2A2F35), 20);

  const BeatType(
    this.token,
    this.label,
    this.shortLabel,
    this.color,
    this.barHeight,
  );

  final String token;
  final String label;
  final String shortLabel;
  final Color color;
  final double barHeight;

  BeatType get next {
    return switch (this) {
      BeatType.light => BeatType.secondary,
      BeatType.secondary => BeatType.accent,
      BeatType.accent => BeatType.rest,
      BeatType.rest => BeatType.light,
    };
  }

  static BeatType fromToken(String token) {
    for (final type in values) {
      if (type.token == token) {
        return type;
      }
    }
    return BeatType.light;
  }
}

enum SubdivisionType {
  quarter(0, 'Quarter notes', '♩'),
  eighth(1, 'Eighth notes', '♪'),
  sixteenth(2, 'Sixteenth notes', '♬'),
  triplets(3, 'Triplets', '♪3'),
  frontEightBackSixteen(4, 'Eighth + two sixteenths', '♪♬'),
  backEightFrontSixteen(5, 'Two sixteenths + eighth', '♬♪'),
  dotted(6, 'Dotted eighth + sixteenth', '♪.');

  const SubdivisionType(this.id, this.label, this.notation);

  final int id;
  final String label;
  final String notation;

  static SubdivisionType fromId(int id) {
    for (final subdivision in values) {
      if (subdivision.id == id) {
        return subdivision;
      }
    }
    return SubdivisionType.quarter;
  }
}

const int kMinBpm = 10;
const int kMaxBpm = 400;
const List<int> kNoteValues = [1, 2, 4, 8, 16, 32];

const List<TimeSignature> kTimeSignatures = [
  TimeSignature(label: '2/4', beatsPerBar: 2, caption: 'March feel'),
  TimeSignature(label: '3/4', beatsPerBar: 3, caption: 'Waltz flow'),
  TimeSignature(label: '4/4', beatsPerBar: 4, caption: 'Daily practice'),
  TimeSignature(label: '5/4', beatsPerBar: 5, caption: 'Odd-meter drive'),
  TimeSignature(label: '6/8', beatsPerBar: 6, caption: 'Compound groove'),
];

List<BeatType> _defaultBeatPattern(int beatsPerBar) {
  return [
    for (var index = 0; index < beatsPerBar; index++)
      index == 0 ? BeatType.accent : BeatType.light,
  ];
}

List<BeatType> _resizeBeatPattern(List<BeatType> current, int beatsPerBar) {
  final nextLength = beatsPerBar.clamp(1, 16).toInt();
  if (current.length == nextLength) {
    return current;
  }
  if (current.length > nextLength) {
    return current.take(nextLength).toList();
  }
  return [
    ...current,
    for (var index = current.length; index < nextLength; index++)
      index == 0 ? BeatType.accent : BeatType.light,
  ];
}

List<BeatType> _beatPatternFromTokens(List<String> tokens, int beatsPerBar) {
  if (tokens.isEmpty) {
    return _defaultBeatPattern(beatsPerBar);
  }
  return _resizeBeatPattern(
    tokens.map(BeatType.fromToken).toList(),
    beatsPerBar,
  );
}

_ParsedSignature? _parseSignatureLabel(String label) {
  final match = RegExp(r'^(\d{1,2})/(\d{1,2})$').firstMatch(label.trim());
  if (match == null) {
    return null;
  }
  final beats = int.tryParse(match.group(1)!);
  final noteValue = int.tryParse(match.group(2)!);
  if (beats == null || noteValue == null) {
    return null;
  }
  return _ParsedSignature(
    label: '$beats/$noteValue',
    beatsPerBar: beats.clamp(1, 16).toInt(),
    noteValue: noteValue.clamp(1, 32).toInt(),
  );
}

class _ParsedSignature {
  const _ParsedSignature({
    required this.label,
    required this.beatsPerBar,
    required this.noteValue,
  });

  final String label;
  final int beatsPerBar;
  final int noteValue;
}

String _formatTimerDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _tempoMarking(int bpm) {
  if (bpm < 40) {
    return 'Grave';
  }
  if (bpm < 60) {
    return 'Largo';
  }
  if (bpm < 76) {
    return 'Adagio';
  }
  if (bpm < 108) {
    return 'Andante';
  }
  if (bpm < 120) {
    return 'Moderato';
  }
  if (bpm < 168) {
    return 'Allegro';
  }
  if (bpm < 200) {
    return 'Presto';
  }
  return 'Prestissimo';
}

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

/// 当前内置 SoundPool 音色 token。
enum SoundProfile {
  accent(
    'accent',
    'Accent',
    'Sharper lead click for the downbeat',
    AppPalette.secondary,
    Icons.flash_on_rounded,
  ),
  mechanical(
    'mechanical',
    'Mechanical',
    'Hard and crisp with strong attack',
    AppPalette.secondary,
    Icons.precision_manufacturing_rounded,
  ),
  electronic(
    'electronic',
    'Electronic',
    'Bright electronic pulse for EDM practice',
    AppPalette.primary,
    Icons.graphic_eq_rounded,
  ),
  wood(
    'wood',
    'Wood',
    'Warm wooden tap for daily sessions',
    Color(0xFFD9A06B),
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

/// Flutter -> Android 的完整节拍配置载荷。
class MetronomeConfig {
  const MetronomeConfig({
    required this.bpm,
    required this.beatsPerBar,
    required this.noteValue,
    required this.timeSignature,
    required this.accentSound,
    required this.regularSound,
    required this.vocalMode,
    required this.accentHaptics,
    required this.subdivisionType,
    required this.beatTypes,
  });

  final int bpm;
  final int beatsPerBar;
  final int noteValue;
  final String timeSignature;
  final String accentSound;
  final String regularSound;
  final String vocalMode;
  final bool accentHaptics;
  final int subdivisionType;
  final List<String> beatTypes;

  Map<String, dynamic> toMap() {
    return {
      'bpm': bpm,
      'beatsPerBar': beatsPerBar,
      'noteValue': noteValue,
      'timeSignature': timeSignature,
      'accentSound': accentSound,
      'regularSound': regularSound,
      'vocalMode': vocalMode,
      'accentHaptics': accentHaptics,
      'subdivisionType': subdivisionType,
      'beatTypes': beatTypes,
    };
  }

  factory MetronomeConfig.fromMap(Map<dynamic, dynamic> map) {
    return MetronomeConfig(
      bpm: (map['bpm'] as int?) ?? 120,
      beatsPerBar: (map['beatsPerBar'] as int?) ?? 4,
      noteValue: (map['noteValue'] as int?) ?? 4,
      timeSignature: (map['timeSignature'] as String?) ?? '4/4',
      accentSound: (map['accentSound'] as String?) ?? SoundProfile.accent.token,
      regularSound: (map['regularSound'] as String?) ?? SoundProfile.wood.token,
      vocalMode: (map['vocalMode'] as String?) ?? VoiceMode.off.token,
      accentHaptics: (map['accentHaptics'] as bool?) ?? true,
      subdivisionType: (map['subdivisionType'] as int?) ?? 0,
      beatTypes:
          (map['beatTypes'] as List<dynamic>?)
              ?.map((value) => value.toString())
              .toList() ??
          const [],
    );
  }
}

/// Android getStatus 返回的运行状态快照。
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

/// Android EventChannel 推送的每次节拍事件。
class BeatEvent {
  const BeatEvent({
    required this.beatIndex,
    required this.beatsPerBar,
    required this.cycleCount,
    required this.subdivisionIndex,
    required this.subdivisionSlots,
    required this.isSilent,
  });

  final int beatIndex;
  final int beatsPerBar;
  final int cycleCount;
  final int subdivisionIndex;
  final int subdivisionSlots;
  final bool isSilent;

  factory BeatEvent.fromMap(Map<dynamic, dynamic> map) {
    return BeatEvent(
      beatIndex: (map['beatIndex'] as int?) ?? 0,
      beatsPerBar: (map['beatsPerBar'] as int?) ?? 4,
      cycleCount: (map['cycleCount'] as int?) ?? 0,
      subdivisionIndex: (map['subdivisionIndex'] as int?) ?? 0,
      subdivisionSlots: (map['subdivisionSlots'] as int?) ?? 1,
      isSilent: (map['isSilent'] as bool?) ?? false,
    );
  }
}

enum TunerStatus {
  idle('Idle'),
  listening('Listening'),
  noSignal('No signal'),
  permissionDenied('Permission needed'),
  error('Unavailable');

  const TunerStatus(this.label);

  final String label;

  static TunerStatus fromToken(String token) {
    return switch (token) {
      'listening' => TunerStatus.listening,
      'noSignal' => TunerStatus.noSignal,
      'permissionDenied' => TunerStatus.permissionDenied,
      'error' => TunerStatus.error,
      _ => TunerStatus.idle,
    };
  }
}

class TunerReading {
  const TunerReading({
    required this.frequency,
    required this.noteName,
    required this.cents,
  });

  final double frequency;
  final String noteName;
  final double cents;

  String get centsText {
    if (cents.abs() < 0.5) {
      return '0 cents';
    }
    final sign = cents > 0 ? '+' : '';
    return '$sign${cents.toStringAsFixed(0)} cents';
  }
}

class TunerPitchEvent {
  const TunerPitchEvent({
    required this.status,
    this.frequency,
    this.clarity,
    this.rms,
  });

  final TunerStatus status;
  final double? frequency;
  final double? clarity;
  final double? rms;

  TunerReading? get reading {
    final value = frequency;
    if (value == null || value <= 0) {
      return null;
    }
    final midi = 69 + 12 * math.log(value / 440.0) / math.ln2;
    final nearestMidi = midi.round();
    final cents = (midi - nearestMidi) * 100;
    final octave = (nearestMidi ~/ 12) - 1;
    final note = kNoteNames[nearestMidi % 12];
    return TunerReading(
      frequency: value,
      noteName: '$note$octave',
      cents: cents,
    );
  }

  factory TunerPitchEvent.fromMap(Map<dynamic, dynamic> map) {
    return TunerPitchEvent(
      status: TunerStatus.fromToken((map['status'] as String?) ?? 'idle'),
      frequency: (map['frequency'] as num?)?.toDouble(),
      clarity: (map['clarity'] as num?)?.toDouble(),
      rms: (map['rms'] as num?)?.toDouble(),
    );
  }
}

const List<String> kNoteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// MethodChannel/EventChannel 的薄封装，隔离 Flutter UI 和 Android 平台调用。
class MetronomeBridge {
  const MetronomeBridge();

  static const MethodChannel _controlChannel = MethodChannel(
    'metronome/control',
  );
  static const EventChannel _beatChannel = EventChannel(
    'metronome/beat_events',
  );
  static const EventChannel _tunerChannel = EventChannel('tuner/pitch_events');

  Stream<BeatEvent> beatStream() {
    return _beatChannel.receiveBroadcastStream().map((dynamic event) {
      return BeatEvent.fromMap(Map<dynamic, dynamic>.from(event as Map));
    });
  }

  Stream<TunerPitchEvent> tunerPitchStream() {
    return _tunerChannel.receiveBroadcastStream().map((dynamic event) {
      return TunerPitchEvent.fromMap(Map<dynamic, dynamic>.from(event as Map));
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

  Future<bool> requestMicrophonePermission() async {
    return _invokeBool('requestMicrophonePermission');
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
