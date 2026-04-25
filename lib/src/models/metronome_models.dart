part of '../../main.dart';

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
  rest('rest', 'Rest', 'R', Color(0xFF2A2F35), 28);

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
  quarter(0, 'Quarter notes', '1/4'),
  eighth(1, 'Eighth notes', '1/8'),
  sixteenth(2, 'Sixteenth notes', '1/16'),
  triplets(3, 'Triplets', '3'),
  frontEightBackSixteen(4, 'Eighth + two sixteenths', '1/8+1/16'),
  backEightFrontSixteen(5, 'Two sixteenths + eighth', '1/16+1/8'),
  dotted(6, 'Dotted eighth + sixteenth', 'dotted');

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

enum BeatRhythmType {
  quarter('quarter', '四分音符', '♩', 1, [0], 'assets/images/subdivision-1.webp'),
  eighthPair('eighth_pair', '两个八分音符', '♫', 2, [
    0,
    1,
  ], 'assets/images/subdivision-2.webp'),
  eighthRest('eighth_rest', '八分音符 + 休止', '♪ 休', 2, [
    0,
  ], 'assets/images/subdivision-3.webp'),
  restEighth('rest_eighth', '休止 + 八分音符', '休 ♪', 2, [
    1,
  ], 'assets/images/subdivision-3.webp'),
  triplet(
    'eighth_triplet',
    '三连音',
    '3',
    3,
    [0, 1, 2],
    'assets/images/subdivision-4.webp',
    true,
  ),
  tripletRestFirst(
    'triplet_rest_first',
    '休止后三连音',
    '休 3',
    3,
    [1, 2],
    'assets/images/subdivision-5.webp',
    true,
  ),
  tripletRestMiddle(
    'triplet_rest_middle',
    '中间休止三连音',
    '3 休',
    3,
    [0, 2],
    'assets/images/subdivision-6.webp',
    true,
  ),
  tripletRestLast(
    'triplet_rest_last',
    '末尾休止三连音',
    '3 休',
    3,
    [0, 1],
    'assets/images/subdivision-7.webp',
    true,
  ),
  sixteenthFour('sixteenth_four', '四个十六分音符', '♬', 4, [
    0,
    1,
    2,
    3,
  ], 'assets/images/subdivision-8.webp'),
  dottedEighthSixteenth(
    'dotted_eighth_sixteenth',
    '附点八分 + 十六分',
    '♪.♬',
    4,
    [0, 3],
    'assets/images/subdivision-9.webp',
  ),
  sixteenthDottedEighth(
    'sixteenth_dotted_eighth',
    '十六分 + 附点八分',
    '♬♪.',
    4,
    [0, 1],
    'assets/images/subdivision-10.webp',
  );

  const BeatRhythmType(
    this.token,
    this.label,
    this.notation,
    this.slotCount,
    this.soundSlots,
    this.assetPath, [
    this.isTriplet = false,
  ]);

  final String token;
  final String label;
  final String notation;
  final int slotCount;
  final List<int> soundSlots;
  final String assetPath;
  final bool isTriplet;

  static BeatRhythmType fromToken(String token) {
    final alias = switch (token) {
      'whole' || 'half' || 'dotted_half' || 'dotted_quarter' => 'quarter',
      'eighth' => 'eighth_pair',
      'sixteenth' || 'thirty_second' => 'sixteenth_four',
      'dotted_eighth' || 'dotted' => 'dotted_eighth_sixteenth',
      'sixteenth_triplet' => 'eighth_triplet',
      'front_eight_back_sixteen' => 'dotted_eighth_sixteenth',
      'front_sixteen_back_eight' => 'sixteenth_dotted_eighth',
      _ => token,
    };
    for (final type in values) {
      if (type.token == alias) {
        return type;
      }
    }
    return BeatRhythmType.quarter;
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

List<BeatRhythmType> _defaultBeatRhythms(int beatsPerBar) {
  return [
    for (var index = 0; index < beatsPerBar; index++) BeatRhythmType.quarter,
  ];
}

List<BeatRhythmType> _resizeBeatRhythms(
  List<BeatRhythmType> current,
  int beatsPerBar,
) {
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
      BeatRhythmType.quarter,
  ];
}

List<BeatRhythmType> _beatRhythmsFromTokens(
  List<String> tokens,
  int beatsPerBar,
) {
  if (tokens.isEmpty) {
    return _defaultBeatRhythms(beatsPerBar);
  }
  return _resizeBeatRhythms(
    tokens.map(BeatRhythmType.fromToken).toList(),
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

/// Flutter -> Android 的完整节拍器配置载荷。
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
    required this.beatRhythmTypes,
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
  final List<String> beatRhythmTypes;

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
      'beatRhythmTypes': beatRhythmTypes,
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
      beatRhythmTypes:
          (map['beatRhythmTypes'] as List<dynamic>?)
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
