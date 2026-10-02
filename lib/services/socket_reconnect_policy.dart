class SocketReconnectPolicy {
  static const _delays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  static Duration delayForAttempt(int attempt) {
    if (attempt <= 0) return _delays.first;
    return _delays[attempt < _delays.length ? attempt : _delays.length - 1];
  }
}
