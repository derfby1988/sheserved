import 'dart:async';
import 'package:flutter/material.dart';

class SessionTimerWidget extends StatefulWidget {
  final DateTime startedAt;
  final int sessionMinutes;
  final VoidCallback onExpire;

  const SessionTimerWidget({
    Key? key,
    required this.startedAt,
    required this.sessionMinutes,
    required this.onExpire,
  }) : super(key: key);

  @override
  State<SessionTimerWidget> createState() => _SessionTimerWidgetState();
}

class _SessionTimerWidgetState extends State<SessionTimerWidget> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _calculateRemaining());
  }

  void _calculateRemaining() {
    final now = DateTime.now().toUtc();
    final end = widget.startedAt.toUtc().add(Duration(minutes: widget.sessionMinutes));
    final diff = end.difference(now);

    if (diff.isNegative && !_expired) {
      setState(() {
        _remaining = Duration.zero;
        _expired = true;
      });
      _timer.cancel();
      widget.onExpire();
    } else if (!diff.isNegative) {
      setState(() {
        _remaining = diff;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_expired) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'หมดเวลา',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    }

    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    final isWarning = _remaining.inMinutes < 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isWarning ? Colors.orange : Colors.green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$minutes:$seconds',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
