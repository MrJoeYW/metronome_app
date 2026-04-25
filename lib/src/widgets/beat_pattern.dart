part of '../../main.dart';

/// 轻重拍编辑条。每个 Cell 表示一拍，可循环切换 Accent/Secondary/Light/Rest。
/// 播放时会高亮当前拍，Rest 拍会在原生层静音。
class BeatPatternBar extends StatelessWidget {
  const BeatPatternBar({
    super.key,
    required this.beatPattern,
    required this.beatRhythms,
    required this.activeBeat,
    required this.isPlaying,
    required this.onBeatTap,
    required this.onBeatLongPress,
  });

  final List<BeatType> beatPattern;
  final List<BeatRhythmType> beatRhythms;
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
                  rhythm: index < beatRhythms.length
                      ? beatRhythms[index]
                      : BeatRhythmType.quarter,
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

/// 单个拍点格子，显示拍号并响应点击/长按。
class BeatPatternCell extends StatelessWidget {
  const BeatPatternCell({
    super.key,
    required this.index,
    required this.type,
    required this.rhythm,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  final int index;
  final BeatType type;
  final BeatRhythmType rhythm;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${index + 1}: ${type.label} / ${rhythm.label}',
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: type == BeatType.rest
                        ? AppPalette.textSecondary
                        : AppPalette.background,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 1),
                SizedBox(
                  height: 10,
                  width: 34,
                  child: _RhythmGlyph(
                    rhythm: rhythm,
                    color: type == BeatType.rest
                        ? AppPalette.textSecondary
                        : AppPalette.background.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BeatRhythmPickerSheet extends StatelessWidget {
  const _BeatRhythmPickerSheet({
    required this.beatNumber,
    required this.selected,
    required this.onSelected,
  });

  final int beatNumber;
  final BeatRhythmType selected;
  final Future<void> Function(BeatRhythmType rhythm) onSelected;

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.68;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SizedBox(
          height: sheetHeight,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'Beat $beatNumber rhythm',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppPalette.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GridView.builder(
                    itemCount: BeatRhythmType.values.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 108,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.98,
                        ),
                    itemBuilder: (context, index) {
                      final rhythm = BeatRhythmType.values[index];
                      final isSelected = rhythm == selected;
                      return _BeatRhythmOption(
                        rhythm: rhythm,
                        selected: isSelected,
                        onTap: () async {
                          await onSelected(rhythm);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BeatRhythmOption extends StatelessWidget {
  const _BeatRhythmOption({
    required this.rhythm,
    required this.selected,
    required this.onTap,
  });

  final BeatRhythmType rhythm;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: rhythm.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? AppPalette.primary.withValues(alpha: 0.18)
                : AppPalette.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppPalette.primary : AppPalette.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 42,
                width: double.infinity,
                child: _RhythmGlyph(
                  rhythm: rhythm,
                  color: selected ? AppPalette.primary : AppPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                rhythm.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RhythmGlyph extends StatelessWidget {
  const _RhythmGlyph({required this.rhythm, required this.color});

  final BeatRhythmType rhythm;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        rhythm.assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return CustomPaint(painter: _RhythmGlyphPainter(rhythm, color));
        },
      ),
    );
  }
}

class _RhythmGlyphPainter extends CustomPainter {
  const _RhythmGlyphPainter(this.rhythm, this.color);

  final BeatRhythmType rhythm;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(1.2, size.shortestSide * 0.075);
    final notePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final slots = rhythm.slotCount;
    final xs = _slotPositions(size.width, slots);
    final headY = size.height * 0.70;
    final stemTop = size.height * 0.23;
    final headW = math.max(3.6, size.width * (slots >= 4 ? 0.085 : 0.105));
    final headH = math.max(2.6, size.height * 0.18);
    final soundSlots = rhythm.soundSlots.toSet();

    for (var slot = 0; slot < slots; slot++) {
      final x = xs[slot];
      if (soundSlots.contains(slot)) {
        _drawNote(
          canvas,
          x,
          headY,
          stemTop,
          headW,
          headH,
          notePaint,
          linePaint,
        );
      } else {
        _drawRest(canvas, x, size, linePaint);
      }
    }

    final noteXs = [
      for (var slot = 0; slot < slots; slot++)
        if (soundSlots.contains(slot)) xs[slot],
    ];
    if (noteXs.length > 1) {
      final beamY = stemTop + size.height * 0.02;
      final left = noteXs.first + headW * 0.55;
      final right = noteXs.last + headW * 0.55;
      final beamPaint = Paint()
        ..color = color
        ..strokeWidth = math.max(2.2, size.height * 0.10)
        ..strokeCap = StrokeCap.square;
      canvas.drawLine(Offset(left, beamY), Offset(right, beamY), beamPaint);
      if (slots >= 4) {
        canvas.drawLine(
          Offset(left, beamY + size.height * 0.13),
          Offset(right, beamY + size.height * 0.13),
          beamPaint..strokeWidth = math.max(1.8, size.height * 0.075),
        );
      }
    }

    if (rhythm == BeatRhythmType.dottedEighthSixteenth) {
      _drawDot(canvas, xs.first + headW * 1.5, headY, notePaint, size);
    } else if (rhythm == BeatRhythmType.sixteenthDottedEighth) {
      _drawDot(canvas, xs[1] + headW * 1.5, headY, notePaint, size);
    }

    if (rhythm.isTriplet) {
      _drawTripletMark(canvas, size, linePaint);
    }
  }

  List<double> _slotPositions(double width, int slots) {
    return switch (slots) {
      1 => [width * 0.50],
      2 => [width * 0.35, width * 0.65],
      3 => [width * 0.24, width * 0.50, width * 0.76],
      _ => [width * 0.18, width * 0.39, width * 0.60, width * 0.81],
    };
  }

  void _drawNote(
    Canvas canvas,
    double x,
    double headY,
    double stemTop,
    double headW,
    double headH,
    Paint notePaint,
    Paint linePaint,
  ) {
    canvas.save();
    canvas.translate(x, headY);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: headW, height: headH),
      notePaint,
    );
    canvas.restore();
    canvas.drawLine(
      Offset(x + headW * 0.48, headY),
      Offset(x + headW * 0.48, stemTop),
      linePaint,
    );
  }

  void _drawRest(Canvas canvas, double x, Size size, Paint linePaint) {
    final path = Path()
      ..moveTo(x - size.width * 0.035, size.height * 0.34)
      ..quadraticBezierTo(
        x + size.width * 0.045,
        size.height * 0.39,
        x - size.width * 0.025,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        x - size.width * 0.080,
        size.height * 0.56,
        x + size.width * 0.030,
        size.height * 0.62,
      );
    canvas.drawPath(path, linePaint);
  }

  void _drawDot(Canvas canvas, double x, double y, Paint paint, Size size) {
    canvas.drawCircle(
      Offset(x, y - size.height * 0.02),
      size.height * 0.035,
      paint,
    );
  }

  void _drawTripletMark(Canvas canvas, Size size, Paint linePaint) {
    final top = size.height * 0.08;
    final left = size.width * 0.22;
    final right = size.width * 0.78;
    canvas.drawLine(Offset(left, top), Offset(right, top), linePaint);
    canvas.drawLine(
      Offset(left, top),
      Offset(left, top + size.height * 0.08),
      linePaint,
    );
    canvas.drawLine(
      Offset(right, top),
      Offset(right, top + size.height * 0.08),
      linePaint,
    );

    final paragraphBuilder =
        ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: math.max(8, size.height * 0.28),
              fontWeight: FontWeight.w800,
            ),
          )
          ..addText('3');
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.width));
    canvas.drawParagraph(paragraph, Offset(0, 0));
  }

  @override
  bool shouldRepaint(covariant _RhythmGlyphPainter oldDelegate) {
    return oldDelegate.rhythm != rhythm || oldDelegate.color != color;
  }
}

/// 轻量拍点指示条，用于在播放时展示当前拍位置。
/// 目前首页主视觉已经由 Cell 承担，这个组件保留给后续布局复用。
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
