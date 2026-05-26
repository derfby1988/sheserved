import 'dart:async';
import 'package:flutter/foundation.dart';

class SessionTimerController {
  final ValueNotifier<int> remainingSeconds = ValueNotifier(900);
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  Timer? _timer;
  final VoidCallback? onExpired;

  SessionTimerController({this.onExpired});

  void start() {
    if (isRunning.value) return;
    isRunning.value = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds.value > 0) {
        remainingSeconds.value--;
      } else {
        _timer?.cancel();
        isRunning.value = false;
        onExpired?.call();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    isRunning.value = false;
  }

  void dispose() {
    _timer?.cancel();
    remainingSeconds.dispose();
    isRunning.dispose();
  }
}
