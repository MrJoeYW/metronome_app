part of '../../main.dart';

/// 閺冄呭閹峰秴褰块柅澶嬪閸忋儱褰涢敍灞肩箽閻ｆ瑧鏁ゆ禍搴″悑鐎硅绁寸拠鏇熷灗閺堫亝娼甸幏鍡楀瀻閺冭泛寮懓鍐︹偓?
class TimeSignatureSelector extends StatelessWidget {
  const TimeSignatureSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TimeSignature selected;
  final ValueChanged<TimeSignature> onSelected;

  @override
  Widget build(BuildContext context) {
    return _ControlChip(
      label: 'Time Signature',
      value: selected.label,
      icon: Icons.grid_4x4_rounded,
      accent: AppPalette.secondary,
      onTap: () => _openPicker(context),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<TimeSignature>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _SelectorSheet(
          title: 'Time Signature',
          children: [
            _SignatureGroup(
              title: 'Simple',
              signatures: const [
                TimeSignature(label: '2/4', beatsPerBar: 2, caption: 'March'),
                TimeSignature(label: '3/4', beatsPerBar: 3, caption: 'Waltz'),
                TimeSignature(label: '4/4', beatsPerBar: 4, caption: 'Common'),
              ],
              selected: selected,
            ),
            _SignatureGroup(
              title: 'Compound',
              signatures: const [
                TimeSignature(label: '6/8', beatsPerBar: 6, caption: 'Flow'),
              ],
              selected: selected,
            ),
            _SignatureGroup(
              title: 'Odd',
              signatures: const [
                TimeSignature(label: '5/4', beatsPerBar: 5, caption: 'Odd'),
              ],
              selected: selected,
            ),
          ],
        );
      },
    );

    if (picked != null) {
      onSelected(picked);
    }
  }
}

class _SignatureGroup extends StatelessWidget {
  const _SignatureGroup({
    required this.title,
    required this.signatures,
    required this.selected,
  });

  final String title;
  final List<TimeSignature> signatures;
  final TimeSignature selected;

  @override
  Widget build(BuildContext context) {
    return _SheetGroup(
      title: title,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final signature in signatures)
            _SheetChoiceChip(
              label: signature.label,
              caption: signature.caption,
              selected: signature.label == selected.label,
              accent: AppPalette.secondary,
              onTap: () => Navigator.of(context).pop(signature),
            ),
        ],
      ),
    );
  }
}

class _SelectorSheet extends StatelessWidget {
  const _SelectorSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppPalette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppPalette.textSecondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SheetChoiceChip extends StatelessWidget {
  const _SheetChoiceChip({
    required this.label,
    required this.caption,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String caption;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : AppPalette.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? accent : AppPalette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: selected ? accent : AppPalette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              caption,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubdivisionSelector extends StatelessWidget {
  const SubdivisionSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final SubdivisionType selected;
  final ValueChanged<SubdivisionType> onSelected;

  @override
  Widget build(BuildContext context) {
    return _ControlChip(
      label: 'Subdivision',
      value: selected.notation,
      icon: Icons.music_note_rounded,
      accent: AppPalette.primary,
      onTap: () => _openPicker(context),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<SubdivisionType>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _SelectorSheet(
          title: 'Subdivision',
          children: [
            _SheetGroup(
              title: 'Pulse',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final subdivision in SubdivisionType.values)
                    _SheetChoiceChip(
                      label: subdivision.notation,
                      caption: subdivision.label,
                      selected: selected == subdivision,
                      accent: AppPalette.primary,
                      onTap: () => Navigator.of(context).pop(subdivision),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (picked != null) {
      onSelected(picked);
    }
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: 0.40)),
              ),
              child: Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppPalette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
