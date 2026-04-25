part of '../../main.dart';

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
