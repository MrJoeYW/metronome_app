part of '../../main.dart';

/// 缁楊兛绨╂潪顕€鍣搁弸鍕倵閿涘本鎸遍弨鍓уЦ閹線娉︽稉顓炴躬鏉╂瑩鍣风粻锛勬倞閿?/// - 鎼存洟鍎寸€佃壈鍩呮稉澶愩€夐崗杈╂暏閸氬奔绔存總?Start/Stop 閻樿埖鈧降鈧?/// - 妫ｆ牠銆夐幐澶愭尦閵嗕箘ebView 閹剚璇為幐澶愭尦閵嗕礁鈧帟顓搁弮鍓佺波閺夌喖鍏樻导姘崇殶閻劌鎮撴稉鈧弶鈩冩尡閺€鎹愮熅瀵板嫨鈧?/// - Flutter 闁板秶鐤嗛柅姘崇箖 [MetronomeBridge] 閸氬本顒炵紒?Android 閸樼喓鏁撻懞鍌涘瀵洘鎼搁妴?
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

  // BottomNavigation 閻ㄥ嫬缍嬮崜宥夈€夐敍? 閸氬绮粈?WebView閵? 閼哄倹濯块崳銊ｂ偓? 鐠佸墽鐤嗛妴?
  int _selectedTab = 1;
  final Set<int> _visitedTabs = {1};

  // 閺嶇绺鹃懞鍌涘闁板秶鐤嗛妴鍌濈箹娴滄稑鐡у▓鍏哥窗缂佸嫬鎮庨幋?MetronomeConfig 娑撳褰傜紒?Android閵?
  int _bpm = 120;
  TimeSignature _signature = kTimeSignatures[3];
  List<BeatType> _beatPattern = _defaultBeatPattern(
    kTimeSignatures[3].beatsPerBar,
  );
  SoundProfile _accentSound = SoundProfile.accent;
  SoundProfile _regularSound = SoundProfile.wood;
  VoiceMode _voiceMode = VoiceMode.off;
  SubdivisionType _subdivision = SubdivisionType.quarter;

  // 閸婃帟顓搁弮鍫曞帳缂冾喓鈧繓timerDuration 閺勵垳鏁ら幋鐤啎缂冾喖鈧》绱漘timerRemaining 閺勵垵绻嶇悰灞艰厬閸撯晙缍戦崐绗衡偓?
  bool _timerEnabled = false;
  Duration _timerDuration = Duration.zero;
  Duration _timerRemaining = Duration.zero;

  // 鏉╂劘顢戦幀浣风瑢閸樼喓鏁撳鏇熸惛閻樿埖鈧降鈧倹澧嶉張澶嬫尡閺€鎯у弳閸欙綁鍏橀崣顏呮暭鏉╂瑩鍣烽敍宀勪缉閸忓秴顦挎い鐢告桨閻樿埖鈧焦绱撶粔姹団偓?
  bool _accentHaptics = true;
  bool _isPlaying = false;
  bool _nativeEngineAvailable = true;
  bool _isTransportBusy = false;
  bool _isFlushingPracticeSession = false;
  int _activeBeat = 0;
  DateTime? _practiceSessionStart;
  Duration _todayPracticeDuration = Duration.zero;
  List<PracticeLog> _practiceLogs = const [];
  List<SavedMetronomePreset> _savedPresets = const [];

  /// 瑜版挸澧?Flutter 闁板秶鐤嗚箛顐ゅ弾閿涘本澧嶉張?MethodChannel start/configure 闁垝濞囬悽銊ョ暊閵?
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

  /// 鏉炲鍣洪垾婊€绗傚▎陇顔曠純顔光偓婵嗘彥閻撗嶇礉閻劋绨?App 娑撳顐奸幍鎾崇磻閺冭埖浠径宥呯埗閻劑鍘ょ純顔衡偓?
  PersistedSettings get _settingsSnapshot => PersistedSettings(
    lastBpm: _bpm,
    timeSignature: _signature.label,
    accentSoundId: _accentSound.token,
    normalSoundId: _regularSound.token,
    vocalMode: _voiceMode.token,
    subdivisionType: _subdivision.id,
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
    final now = DateTime.now();
    final todayDuration = await _database.todayTotal(now);
    final logs = await _database.recentPracticeLogs(limit: 8);
    if (!mounted) {
      return;
    }
    setState(() {
      _todayPracticeDuration = todayDuration;
      _practiceLogs = logs;
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

  // 鐠佸墽鐤嗘穱婵嗙摠閸?1 缁夋帡妲婚幎鏍电礉闁灝鍘ら幏鏍уЗ BPM 閹存牞绻涚紒顓犲仯閹峰秴鐎烽弮鍫曨暥缁讳礁鍟撴惔鎾扁偓?
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

  /// 閸忋劌鐪幘顓熸杹瀵偓閸忕绱伴幍鈧張?UI 閸忋儱褰涢崪灞界暰閺冭泛娅掗懛顏勫З閸嬫粍顒涢柈鍊熻泲鏉╂瑩鍣烽妴?
  Future<void> _togglePlayback() async {
    await _setPlayback(!_isPlaying);
  }

  /// 鐎圭偤妾?Start/Stop 閹笛嗩攽閸戣姤鏆熼妴?  ///
  /// shouldStart=true 閺冭泛鎯庨崝?Android 閸撳秴褰撮張宥呭閿涙矤alse 閺冭泛浠犲銏℃箛閸斺€宠嫙缂佹挾鐣荤紒鍐х瘎鐠佹澘缍嶉妴?
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

  /// 閸楁洘濯挎潪濠氬櫢缁鐎峰顏嗗箚閿涙瓈ight -> Secondary -> Accent -> Rest -> Light閵?  /// 閺€鐟板З閸氬海鐝涢崚璇叉倱濮濄儳绮伴崢鐔烘晸鐏炲偊绱漅est 閹靛秷鍏橀崷銊︽尡閺€鍙ヨ厬閸楄櫕妞傞棃娆撶叾閵?
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

  /// 闂€鎸庡瘻閸楁洘濯块惃鍕暕閻ｆ瑧绱潏鎴︽桨閺夎￥鈧倸缍嬮崜宥呭涧鐏炴洜銇氱猾璇茬€烽崪宀€绮忛崚鍡楀窗娴ｅ稄绱濋崥搴ｇ敾閸欘垱澧跨仦鏇炲礋閹峰秶绮忛崚鍡愨偓?
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

  /// Apply 閸氬骸鎯庨崝?UI 閸婃帟顓搁弮璁圭幢瑜版帡娴傞弮鍫曗偓姘崇箖閸忋劌鐪幘顓熸杹鐠侯垰绶為崑婊勵剾閼哄倹濯块崳銊ｂ偓?
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

  /// 娴犲氦顔曠純顕€銆夐幁銏狀槻瀹歌弓绻氱€涙﹢鍘ょ純顕嗙礉楠炲墎鐝涢崡鍐叉倱濮濄儳绮?Android 瀵洘鎼搁妴?
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
                            SizedBox(height: compact ? 24 : 34),
                            BeatPatternBar(
                              beatPattern: _beatPattern,
                              activeBeat: _activeBeat,
                              isPlaying: _isPlaying,
                              onBeatTap: _cycleBeatType,
                              onBeatLongPress: _openBeatEditSheet,
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
                            SizedBox(height: compact ? 34 : 44),
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
                todayPracticeDuration: _visibleTodayPracticeDuration,
                currentSessionDuration: _currentPracticeSessionDuration,
                practiceLogs: _practiceLogs,
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
