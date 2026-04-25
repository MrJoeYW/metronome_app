part of '../../main.dart';

/// 濮ｅ繋閲?Cell 閺勫墽銇氶幏宥呭娇閺佹澘鐡ч敍宀€鏁ゆ妯哄閸滃矂顤侀懝鑼躲€冩潏?Accent/Secondary/Light/Rest閵?/// 閻愮懓鍤顏嗗箚缁鐎烽敍宀勬毐閹稿澧﹀鈧崡鏇熷缂傛牞绶０鍕殌闂堛垺婢橀妴?
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

/// 閸楁洑閲滈幏宥呯摍閻ㄥ嫬褰查悙鐟板毊閺岃京濮搁崡鏇炲帗閵?
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

/// 娴犲懐鏁ゆ禍搴㈡尡閺€鐐閻ㄥ嫬浜曢崹瀣Ν閹峰秶浼呯紒鍕閵?/// 缁楊兛绨╂潪顕€顩绘い闈涘嚒缁夊娅庢稉濠冩煙鏉╂稑瀹抽悘顖ょ礉濮濄倗绮嶆禒鑸垫畯閻ｆ瑧绮伴崥搴ｇ敾閸欘垵鍏橀惃鍕毈閸ㄥ濮搁幀浣哥潔缁€鎭掆偓?
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
