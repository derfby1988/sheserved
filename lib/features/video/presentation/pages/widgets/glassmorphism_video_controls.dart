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

  @override
  Widget build(BuildContext context) {
    if (widget.controller == null || !widget.controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final isPlaying = widget.controller!.value.isPlaying;
    final volume = widget.controller!.value.volume;

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
                    isPlaying ? widget.controller!.pause() : widget.controller!.play();
                  },
                ),
                _buildDivider(),
                _buildControlButton(
                  icon: volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  onTap: () {
                    widget.controller!.setVolume(volume > 0 ? 0.0 : 1.0);
                  },
                ),
                _buildDivider(),
                _buildControlButton(
                  icon: Icons.replay_10_rounded,
                  onTap: () {
                    final newPos = widget.controller!.value.position - const Duration(seconds: 10);
                    widget.controller!.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
                  },
                ),
                _buildDivider(),
                _buildControlButton(
                  icon: Icons.forward_10_rounded,
                  onTap: () {
                    final newPos = widget.controller!.value.position + const Duration(seconds: 10);
                    widget.controller!.seekTo(newPos);
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
