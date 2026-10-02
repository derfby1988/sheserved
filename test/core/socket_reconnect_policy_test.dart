import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/services/socket_reconnect_policy.dart';

void main() {
  group('SocketReconnectPolicy', () {
    test('uses increasing delays and caps the retry interval', () {
      expect(
        SocketReconnectPolicy.delayForAttempt(0),
        const Duration(seconds: 5),
      );
      expect(
        SocketReconnectPolicy.delayForAttempt(1),
        const Duration(seconds: 15),
      );
      expect(
        SocketReconnectPolicy.delayForAttempt(2),
        const Duration(seconds: 30),
      );
      expect(
        SocketReconnectPolicy.delayForAttempt(20),
        const Duration(seconds: 30),
      );
    });
  });
}
