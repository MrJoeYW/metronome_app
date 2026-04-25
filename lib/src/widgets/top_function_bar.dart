part of '../../main.dart';

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

/// 顶部功能按钮的通用外观，保持固定高度以避免不同文字导致跳动。
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
