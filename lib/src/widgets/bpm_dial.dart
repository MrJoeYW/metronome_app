part of '../../main.dart';

/// BPM 閸﹀棛娲忛敍姘樆閸﹀牊瀚嬮崝銊ㄧ殶闁噦绱濇稉顓炵妇閻愮懓鍤?Tap Tempo閿涘奔鑵戣箛?+/- 閺€顖涘瘮瀵邦喛鐨熼崪宀勬毐閹稿绻涚拫鍐︹偓?
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
