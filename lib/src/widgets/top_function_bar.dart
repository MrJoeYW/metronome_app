part of '../../main.dart';

/// 棣栭〉椤堕儴鍥涗釜鍔熻兘鍏ュ彛锛氭媿鍙枫€侀煶鑹层€佽皟闊冲櫒銆佸畾鏃跺櫒銆?/// 姣忎釜鍏ュ彛鍙墦寮€鎶藉眽锛屼笉鐩存帴鎶婂鏉傝缃爢鍦ㄩ椤点€?
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

/// 椤堕儴鍔熻兘鎸夐挳鐨勯€氱敤澶栬锛屼繚鎸佸浐瀹氶珮搴﹂伩鍏嶄笉鍚屾枃瀛楀鑷存姈鍔ㄣ€?
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

/// 棣栭〉杞婚噸鎷嶇紪杈戞潯銆?///
