import 'dart:async';
import 'package:flutter/foundation.dart';

class ProfessionsRefreshController {
  Timer? _timer;
  final VoidCallback onRefresh;

  ProfessionsRefreshController({required this.onRefresh});

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => onRefresh());
  }

  void dispose() {
    _timer?.cancel();
  }
}
