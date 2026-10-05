import 'package:socket_io_client/socket_io_client.dart' as socket_io_client;

class SocketAuthSocketFactory {
  static socket_io_client.Socket create({
    required String serverUrl,
    required String? userId,
    required String? token,
    required int reconnectionAttempts,
    bool autoConnect = true,
  }) {
    final options = socket_io_client.OptionBuilder()
        .enableForceNew()
        .setTransports(['websocket']);
    if (autoConnect) {
      options.enableAutoConnect();
    } else {
      options.disableAutoConnect();
    }
    options
        .enableReconnection()
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .setReconnectionAttempts(reconnectionAttempts)
        .setRandomizationFactor(0.5)
        .setAuth({'userId': userId, 'token': token});
    return socket_io_client.io(serverUrl, options.build());
  }
}
