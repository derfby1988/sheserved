import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class MiniVoicePlayer extends StatefulWidget {
  final String url;
  final bool isMe;
  const MiniVoicePlayer({super.key, required this.url, required this.isMe});

  @override
  State<MiniVoicePlayer> createState() => _MiniVoicePlayerState();
}

class _MiniVoicePlayerState extends State<MiniVoicePlayer> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted)
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isMe ? Colors.black87 : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async {
            if (_isPlaying) {
              await _audioPlayer.pause();
            } else {
              await _audioPlayer.play(UrlSource(widget.url));
            }
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (widget.isMe ? Colors.black : Colors.white).withOpacity(
                0.15,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: iconColor,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0.0,
                backgroundColor: iconColor.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _fmt(_isPlaying ? _position : _duration),
              style: TextStyle(fontSize: 9, color: iconColor.withOpacity(0.7)),
            ),
          ],
        ),
      ],
    );
  }
}
