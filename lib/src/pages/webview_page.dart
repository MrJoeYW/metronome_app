part of '../../main.dart';

class GuitarSocietyPage extends StatefulWidget {
  const GuitarSocietyPage({
    super.key,
    required this.webPageUrl,
    required this.isPlaying,
    required this.isBusy,
    required this.onTogglePlayback,
  });

  final String webPageUrl;
  final bool isPlaying;
  final bool isBusy;
  final VoidCallback onTogglePlayback;

  @override
  State<GuitarSocietyPage> createState() => _GuitarSocietyPageState();
}

class _GuitarSocietyPageState extends State<GuitarSocietyPage> {
  late final WebViewController _controller;
  var _isLoading = true;
  var _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
            });
            unawaited(_refreshNavigationState());
          },
        ),
      );
    _loadUrl(widget.webPageUrl);
  }

  @override
  void didUpdateWidget(covariant GuitarSocietyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.webPageUrl != widget.webPageUrl) {
      _loadUrl(widget.webPageUrl);
    }
  }

  Future<void> _loadUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl) ?? Uri.parse(kDefaultWebPageUrl);
    setState(() {
      _isLoading = true;
      _canGoBack = false;
    });
    await _controller.loadRequest(uri);
  }

  Future<void> _refreshNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    if (!mounted) {
      return;
    }
    setState(() {
      _canGoBack = canGoBack;
    });
  }

  Future<void> _goBack() async {
    final canGoBack = await _controller.canGoBack();
    if (canGoBack) {
      await _controller.goBack();
      await _refreshNavigationState();
      return;
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Already at the first page.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final transportColor = widget.isPlaying
        ? AppPalette.danger
        : AppPalette.primary;

    return ColoredBox(
      color: AppPalette.background,
      child: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const LinearProgressIndicator(
                color: AppPalette.primary,
                backgroundColor: AppPalette.surface,
              ),
            Positioned(
              left: 16,
              bottom: 18,
              child: Tooltip(
                message: 'Web page back',
                child: IconButton(
                  onPressed: _goBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: _canGoBack
                      ? AppPalette.textPrimary
                      : AppPalette.textSecondary,
                  style: IconButton.styleFrom(
                    backgroundColor: AppPalette.surface.withValues(alpha: 0.72),
                    side: BorderSide(
                      color: AppPalette.border.withValues(alpha: 0.64),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    fixedSize: const Size(48, 48),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 18,
              child: Opacity(
                opacity: widget.isBusy ? 0.48 : 0.78,
                child: FloatingActionButton.extended(
                  heroTag: 'web-metronome-transport',
                  onPressed: widget.isBusy ? null : widget.onTogglePlayback,
                  backgroundColor: transportColor.withValues(alpha: 0.82),
                  foregroundColor: AppPalette.background,
                  icon: Icon(
                    widget.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(widget.isPlaying ? 'Stop' : 'Start'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
