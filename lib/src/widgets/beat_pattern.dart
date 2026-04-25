part of '../../main.dart';

/// 轻重拍编辑条。每个 Cell 表示一拍，可循环切换 Accent/Secondary/Light/Rest。
/// 播放时会高亮当前拍，Rest 拍会在原生层静音。
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

/// 单个拍点格子，显示拍号并响应点击/长按。
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
