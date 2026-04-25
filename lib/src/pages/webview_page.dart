part of '../../main.dart';

/// 左侧 WebView 页面。
///
/// WebView 内右下角的浮动 Start/Stop 和首页按钮共享同一个播放状态。
class GuitarSocietyPage extends StatefulWidget {
  const GuitarSocietyPage({
    super.key,
    required this.isPlaying,
    required this.isBusy,
    required this.onTogglePlayback,
  });

  final bool isPlaying;
  final bool isBusy;
  final VoidCallback onTogglePlayback;

  @override
  State<GuitarSocietyPage> createState() => _GuitarSocietyPageState();
}

class _GuitarSocietyPageState extends State<GuitarSocietyPage> {
  late final WebViewController _controller;
  var _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.jitashe.org/'));
  }

  @override
  Widget build(BuildContext context) {
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
              right: 16,
              bottom: 18,
              child: FloatingActionButton.extended(
                heroTag: 'web-metronome-transport',
                onPressed: widget.isBusy ? null : widget.onTogglePlayback,
                backgroundColor: widget.isPlaying
                    ? AppPalette.danger
                    : AppPalette.primary,
                foregroundColor: AppPalette.background,
                icon: Icon(
                  widget.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(widget.isPlaying ? 'Stop' : 'Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
