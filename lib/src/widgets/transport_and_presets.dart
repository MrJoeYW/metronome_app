part of '../../main.dart';

class TransportPanel extends StatelessWidget {
  const TransportPanel({
    super.key,
    required this.isPlaying,
    required this.isBusy,
    required this.compact,
    required this.onTogglePlayback,
  });

  final bool isPlaying;
  final bool isBusy;
  final bool compact;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppPalette.surface,
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              backgroundColor: isPlaying
                  ? AppPalette.danger
                  : AppPalette.primary,
              foregroundColor: AppPalette.background,
              disabledBackgroundColor: AppPalette.surfaceVariant,
              disabledForegroundColor: AppPalette.textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: isBusy ? null : onTogglePlayback,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              isPlaying ? 'Stop' : 'Start',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppPalette.background,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BpmDialWithPresetActions extends StatelessWidget {
  const _BpmDialWithPresetActions({
    required this.bpm,
    required this.min,
    required this.max,
    required this.pulseAmount,
    required this.size,
    required this.canLoad,
    required this.onChanged,
    required this.onTapTempo,
    required this.onSave,
    required this.onLoad,
  });

  final int bpm;
  final int min;
  final int max;
  final double pulseAmount;
  final double size;
  final bool canLoad;
  final ValueChanged<int> onChanged;
  final VoidCallback onTapTempo;
  final VoidCallback onSave;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final actionTop = size * 0.86;

    return SizedBox(
      width: size,
      height: size + 28,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        alignment: Alignment.topCenter,
        children: [
          BpmDial(
            bpm: bpm,
            min: min,
            max: max,
            pulseAmount: pulseAmount,
            size: size,
            onChanged: onChanged,
            onTapTempo: onTapTempo,
          ),
          Positioned(
            left: 0,
            top: actionTop,
            child: _DialCornerAction(
              icon: Icons.bookmark_add_outlined,
              tooltip: 'Save configuration',
              onPressed: onSave,
            ),
          ),
          Positioned(
            right: 0,
            top: actionTop,
            child: _DialCornerAction(
              icon: Icons.folder_open_rounded,
              tooltip: 'Load configuration',
              onPressed: canLoad ? onLoad : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialCornerAction extends StatelessWidget {
  const _DialCornerAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 24),
          style: IconButton.styleFrom(
            backgroundColor: AppPalette.surface.withValues(alpha: 0.92),
            foregroundColor: AppPalette.textPrimary,
            disabledForegroundColor: AppPalette.textSecondary,
            side: BorderSide(
              color: onPressed == null
                  ? AppPalette.border.withValues(alpha: 0.55)
                  : AppPalette.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

class _LoadPresetSheet extends StatefulWidget {
  const _LoadPresetSheet({
    required this.presets,
    required this.onRestore,
    required this.onDelete,
  });

  final List<SavedMetronomePreset> presets;
  final Future<void> Function(SavedMetronomePreset preset) onRestore;
  final Future<void> Function(SavedMetronomePreset preset) onDelete;

  @override
  State<_LoadPresetSheet> createState() => _LoadPresetSheetState();
}

class _LoadPresetSheetState extends State<_LoadPresetSheet> {
  late List<SavedMetronomePreset> _presets;
  final Set<int> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    _presets = List<SavedMetronomePreset>.of(widget.presets);
  }

  Future<void> _deletePreset(SavedMetronomePreset preset) async {
    final id = preset.id;
    if (id == null || _deletingIds.contains(id)) {
      return;
    }

    setState(() {
      _deletingIds.add(id);
    });

    await widget.onDelete(preset);
    if (!mounted) {
      return;
    }

    setState(() {
      _presets = _presets.where((item) => item.id != id).toList();
      _deletingIds.remove(id);
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${preset.name}".'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.78;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SizedBox(
          height: sheetHeight,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppPalette.surface,
              border: Border.all(color: AppPalette.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: AppPalette.border,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'Load configuration',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppPalette.textPrimary,
                        fontWeight: FontWeight.w800,
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
                const SizedBox(height: 12),
                Expanded(
                  child: _presets.isEmpty
                      ? Center(
                          child: Text(
                            'No saved configurations yet.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppPalette.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _presets.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final preset = _presets[index];
                            final deleting =
                                preset.id != null &&
                                _deletingIds.contains(preset.id);
                            return _SavedPresetTile(
                              preset: preset,
                              onRestore: () {
                                Navigator.of(context).pop();
                                unawaited(widget.onRestore(preset));
                              },
                              onDelete: deleting
                                  ? null
                                  : () => unawaited(_deletePreset(preset)),
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

class _SavePresetDialog extends StatefulWidget {
  const _SavePresetDialog();

  @override
  State<_SavePresetDialog> createState() => _SavePresetDialogState();
}

class _SavePresetDialogState extends State<_SavePresetDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      backgroundColor: AppPalette.surface,
      title: const Text('Save configuration'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(color: AppPalette.textPrimary),
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Configuration name',
          labelStyle: TextStyle(color: AppPalette.textSecondary),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
