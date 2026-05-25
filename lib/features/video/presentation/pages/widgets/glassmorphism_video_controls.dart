import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class GlassmorphismVideoControls extends StatefulWidget {
  final VideoPlayerController? controller;

  const GlassmorphismVideoControls({super.key, this.controller});

  @override
  State<GlassmorphismVideoControls> createState() => _GlassmorphismVideoControlsState();
}

class _GlassmorphismVideoControlsState extends State<GlassmorphismVideoControls> {
  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(GlassmorphismVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  bool _isControllerReady() {
    final controller = widget.controller;
    if (controller == null) return false;
    try {
      return controller.value.isInitialized;
    } catch (_) {
      return false;
    }
  }

  T? _safeValue<T>(T Function(VideoPlayerController controller) reader) {
    final controller = widget.controller;
    if (controller == null) return null;
    try {
      return reader(controller);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isControllerReady()) {
      return const SizedBox.shrink();
    }

    final isPlaying = _safeValue((controller) => controller.value.isPlaying) ?? false;
    final volume = _safeValue((controller) => controller.value.volume) ?? 1.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildControlButton(
                  icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  onTap: () {
                    final controller = widget.controller;
                    if (controller == null) return;
                    try {
                      isPlaying ? controller.pause() : controller.play();
                    } catch (_) {}
                  },
                ),
                _buildDivider(),
                _buildControlButton(
                  icon: volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  onTap: () {
                    final controller = widget.controller;
                    if (controller == null) return;
                    try {
                      controller.setVolume(volume > 0 ? 0.0 : 1.0);
                    } catch (_) {}
                  },
                ),
                _buildDivider(),
                _buildControlButton(
                  icon: Icons.replay_10_rounded,
                  onTap: () {
                    final controller = widget.controller;
                    if (controller == null) return;
                    try {
                      final newPos = controller.value.position - const Duration(seconds: 10);
                      controller.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
                    } catch (_) {}
                  },
                ),
                _buildDivider(),
                _buildControlButton(
                  icon: Icons.forward_10_rounded,
                  onTap: () {
                    final controller = widget.controller;
                    if (controller == null) return;
                    try {
                      final newPos = controller.value.position + const Duration(seconds: 10);
                      controller.seekTo(newPos);
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.white.withValues(alpha: 0.2),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      color: Colors.white.withValues(alpha: 0.2),
      margin: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}
