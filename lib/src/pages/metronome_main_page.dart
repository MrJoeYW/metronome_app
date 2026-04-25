part of '../../main.dart';

/// 顶层节拍器页面容器。
///
/// - 底部三页共享同一套 Start/Stop 状态。
/// - 首页按钮、WebView 悬浮按钮、倒计时结束都走同一条播放路径。
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

  // BottomNavigation 当前页：0 WebView，1 节拍器，2 设置。
  int _selectedTab = 1;
  final Set<int> _visitedTabs = {1};

  // 核心节拍配置，这些字段会组合成 MetronomeConfig 下发给 Android。
  int _bpm = 120;
  TimeSignature _signature = kTimeSignatures[3];
  List<BeatType> _beatPattern = _defaultBeatPattern(
    kTimeSignatures[3].beatsPerBar,
  );
  List<BeatRhythmType> _beatRhythms = _defaultBeatRhythms(
    kTimeSignatures[3].beatsPerBar,
  );
  SoundProfile _accentSound = SoundProfile.accent;
  SoundProfile _regularSound = SoundProfile.wood;
  VoiceMode _voiceMode = VoiceMode.off;
  SubdivisionType _subdivision = SubdivisionType.quarter;

  // 倒计时配置：timerDuration 是用户设置值，timerRemaining 是运行中的剩余值。
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
  Duration _todayPracticeDuration = Duration.zero;
  List<PracticeLog> _practiceLogs = const [];
  List<PracticeDaySummary> _practiceDaySummaries = const [];
  List<SavedMetronomePreset> _savedPresets = const [];
  String _webPageUrl = kDefaultWebPageUrl;

  /// 当前 Flutter 配置快照，MethodChannel start/configure 都使用它。
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
    beatRhythmTypes: _beatRhythms.map((type) => type.token).toList(),
  );

  /// 最近一次设置快照，用于 App 下次打开时恢复常用配置。
  PersistedSettings get _settingsSnapshot => PersistedSettings(
    lastBpm: _bpm,
    timeSignature: _signature.label,
    accentSoundId: _accentSound.token,
    normalSoundId: _regularSound.token,
    vocalMode: _voiceMode.token,
    subdivisionType: _subdivision.id,
    beatRhythmTypes: _beatRhythms.map((type) => type.token).toList(),
    webPageUrl: _webPageUrl,
  );

  Duration get _currentPracticeSessionDuration {
    final startedAt = _practiceSessionStart;
    if (startedAt == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(startedAt);
  }

  Duration get _visibleTodayPracticeDuration =>
      _todayPracticeDuration + _currentPracticeSessionDuration;

  List<PracticeDaySummary> get _visiblePracticeDaySummaries {
    final startedAt = _practiceSessionStart;
    if (startedAt == null) {
      return _practiceDaySummaries;
    }

    final sessionSeconds = _currentPracticeSessionDuration.inSeconds;
    if (sessionSeconds <= 0) {
      return _practiceDaySummaries;
    }

    final today = DateTime.now();
    final todayKey = _dayKey(today);
    final summaries = <PracticeDaySummary>[];
    var mergedToday = false;
    for (final summary in _practiceDaySummaries) {
      if (_dayKey(summary.date) == todayKey) {
        summaries.add(
          PracticeDaySummary(
            date: summary.date,
            totalSeconds: summary.totalSeconds + sessionSeconds,
            sessionCount: summary.sessionCount + 1,
          ),
        );
        mergedToday = true;
      } else {
        summaries.add(summary);
      }
    }
    if (!mergedToday) {
      summaries.add(
        PracticeDaySummary(
          date: DateTime(today.year, today.month, today.day),
          totalSeconds: sessionSeconds,
          sessionCount: 1,
        ),
      );
    }
    return summaries;
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
      unawaited(_refreshPracticeSummary());
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
      if (settings != null) {
        _webPageUrl = _normalizeWebPageUrl(settings.webPageUrl);
      }

      if (status != null) {
        _isPlaying = status.isRunning;
        _activeBeat = status.currentBeat;
      } else {
        _nativeEngineAvailable = false;
      }
    });

    await Future.wait([_refreshSavedPresets(), _refreshPracticeSummary()]);
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
    _beatRhythms = _beatRhythmsFromTokens(
      config.beatRhythmTypes,
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
    _beatRhythms = _beatRhythmsFromTokens(
      settings.beatRhythmTypes,
      _signature.beatsPerBar,
    );
    _accentSound = SoundProfile.fromToken(settings.accentSoundId);
    _regularSound = SoundProfile.fromToken(settings.normalSoundId);
    _voiceMode = VoiceMode.fromToken(settings.vocalMode);
    _subdivision = SubdivisionType.fromId(settings.subdivisionType);
    _webPageUrl = _normalizeWebPageUrl(settings.webPageUrl);
  }

  Future<void> _refreshPracticeSummary() async {
    final now = DateTime.now();
    final todayDuration = await _database.todayTotal(now);
    final logs = await _database.recentPracticeLogs(limit: 8);
    final summaries = await _database.dailyPracticeSummaries(
      start: now.subtract(const Duration(days: 370)),
      end: now,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _todayPracticeDuration = todayDuration;
      _practiceLogs = logs;
      _practiceDaySummaries = summaries;
    });
  }

  Future<List<PracticeLog>> _practiceLogsForDay(DateTime day) {
    return _database.practiceLogsForDay(day);
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

  Future<bool> _updateWebPageUrl(String rawUrl) async {
    final normalized = _normalizeWebPageUrl(rawUrl);
    if (normalized == _webPageUrl) {
      return false;
    }

    setState(() {
      _webPageUrl = normalized;
    });
    await _saveSettingsNow();
    return true;
  }

  String _normalizeWebPageUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return kDefaultWebPageUrl;
    }

    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
    final withScheme = hasScheme ? trimmed : 'https://$trimmed';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || parsed.host.trim().isEmpty) {
      return kDefaultWebPageUrl;
    }
    return parsed.toString();
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
      _beatRhythms = _resizeBeatRhythms(_beatRhythms, signature.beatsPerBar);
      _activeBeat = 0;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  /// 单拍轻重类型循环：Light -> Secondary -> Accent -> Rest -> Light。
  /// 改动后立即同步给原生层，Rest 才能在播放中即时静音。
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

  Future<void> _selectBeatRhythm(int index, BeatRhythmType rhythm) async {
    if (index < 0 || index >= _beatRhythms.length) {
      return;
    }
    if (_beatRhythms[index] == rhythm) {
      return;
    }

    setState(() {
      _beatRhythms = List<BeatRhythmType>.of(_beatRhythms);
      _beatRhythms[index] = rhythm;
    });
    HapticFeedback.selectionClick();
    _scheduleSettingsSave();
    await _syncConfiguration();
  }

  Future<void> _openBeatRhythmSheet(int index) async {
    if (index < 0 || index >= _beatPattern.length) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _BeatRhythmPickerSheet(
          beatNumber: index + 1,
          selected: _beatRhythms[index],
          onSelected: (rhythm) => _selectBeatRhythm(index, rhythm),
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
        beatRhythmTypes: _beatRhythms.map((type) => type.token).toList(),
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

  /// 恢复已保存配置，并立即同步给 Android 引擎。
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
      _beatRhythms = _beatRhythmsFromTokens(
        preset.beatRhythmTypes,
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

  Future<void> _openSavePresetDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _SavePresetDialog(),
    );

    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) {
      return;
    }
    await _saveCurrentPreset(trimmedName);
  }

  Future<void> _openLoadPresetSheet() async {
    final initialPresets = List<SavedMetronomePreset>.of(_savedPresets);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => _LoadPresetSheet(
        presets: initialPresets,
        onRestore: _restorePreset,
        onDelete: _deletePreset,
      ),
    );
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
                webPageUrl: _webPageUrl,
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
                final safePadding = MediaQuery.paddingOf(context);
                final verticalPadding = compact ? 34.0 : 40.0;
                final presetActionExtraHeight = 28.0;
                final layoutSafetyInset = 6.0;
                final fixedContentHeight =
                    64.0 + // top function bar
                    (compact ? 24.0 : 34.0) +
                    64.0 + // beat pattern bar
                    (compact ? 28.0 : 40.0) +
                    presetActionExtraHeight +
                    (compact ? 24.0 : 30.0) +
                    (compact ? 84.0 : 88.0) + // transport panel
                    layoutSafetyInset;
                final maxDialByHeight =
                    constraints.maxHeight -
                    safePadding.vertical -
                    verticalPadding -
                    fixedContentHeight;
                final pulse =
                    1 - Curves.easeOutCubic.transform(_pulseController.value);
                final dialSize = math.min(
                  math.min(
                    constraints.maxWidth - (horizontalPadding * 2),
                    compact ? 268.0 : 346.0,
                  ),
                  math.max(160.0, maxDialByHeight),
                );

                return ColoredBox(
                  color: AppPalette.background,
                  child: SafeArea(
                    bottom: true,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        12,
                        horizontalPadding,
                        compact ? 22 : 28,
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
                          SizedBox(height: compact ? 24 : 34),
                          BeatPatternBar(
                            beatPattern: _beatPattern,
                            beatRhythms: _beatRhythms,
                            activeBeat: _activeBeat,
                            isPlaying: _isPlaying,
                            onBeatTap: _cycleBeatType,
                            onBeatLongPress: _openBeatRhythmSheet,
                          ),
                          SizedBox(height: compact ? 28 : 40),
                          _BpmDialWithPresetActions(
                            bpm: _bpm,
                            min: kMinBpm,
                            max: kMaxBpm,
                            pulseAmount: pulse,
                            size: dialSize,
                            canLoad: _savedPresets.isNotEmpty,
                            onChanged: (value) =>
                                _updateBpm(value, resetTapTempoBuffer: true),
                            onTapTempo: () => unawaited(_handleTapTempo()),
                            onSave: _openSavePresetDialog,
                            onLoad: _openLoadPresetSheet,
                          ),
                          SizedBox(height: compact ? 24 : 30),
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
                );
              },
            ),
            if (_visitedTabs.contains(2))
              SettingsPage(
                todayPracticeDuration: _visibleTodayPracticeDuration,
                currentSessionDuration: _currentPracticeSessionDuration,
                currentSessionStartedAt: _practiceSessionStart,
                currentBpm: _bpm,
                practiceLogs: _practiceLogs,
                practiceDaySummaries: _visiblePracticeDaySummaries,
                onLoadPracticeLogsForDay: _practiceLogsForDay,
                webPageUrl: _webPageUrl,
                onWebPageUrlChanged: _updateWebPageUrl,
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
