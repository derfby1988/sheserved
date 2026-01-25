import 'package:flutter/material.dart';
import 'websocket_service.dart';
import 'location_tracking_service.dart';

/// Test Widget for WebSocket Connection
/// ใช้สำหรับทดสอบการเชื่อมต่อ WebSocket และ Location Tracking
class TestWebSocketWidget extends StatefulWidget {
  const TestWebSocketWidget({super.key});

  @override
  State<TestWebSocketWidget> createState() => _TestWebSocketWidgetState();
}

class _TestWebSocketWidgetState extends State<TestWebSocketWidget> {
  // สำหรับ web platform ใช้ 127.0.0.1 แทน localhost
  // สำหรับ mobile device ใช้ IP address ของคอมพิวเตอร์
  final String _serverUrl = 'http://127.0.0.1:3000'; // Web: 127.0.0.1, Mobile: YOUR_COMPUTER_IP
  
  late final WebSocketService _webSocketService;
  late final LocationTrackingService _locationService;

  bool _isConnected = false;
  bool _isTracking = false;
  String _status = 'Not connected';
  List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    _webSocketService = WebSocketService(serverUrl: _serverUrl);
    _locationService = LocationTrackingService(webSocketService: _webSocketService);
    _setupListeners();
  }

  void _setupListeners() {
    // Listen to connection status
    _webSocketService.connectionStream.listen((connected) {
      setState(() {
        _isConnected = connected;
        _status = connected ? 'Connected' : 'Disconnected';
      });
      _addMessage('Connection: ${connected ? "Connected" : "Disconnected"}');
    });

    // Listen to location updates
    _webSocketService.locationStream.listen((data) {
      _addMessage('Location updated: ${data['userId']} - ${data['latitude']}, ${data['longitude']}');
    });

    // Listen to errors
    _webSocketService.errorStream.listen((error) {
      _addMessage('Error: $error');
    });
  }

  void _addMessage(String message) {
    setState(() {
      _messages.insert(0, '${DateTime.now().toString().substring(11, 19)}: $message');
      if (_messages.length > 20) {
        _messages.removeLast();
      }
    });
  }

  Future<void> _connect() async {
    _addMessage('Attempting to connect to $_serverUrl...');
    _addMessage('Make sure WebSocket Server is running on port 3000');
    
    try {
      // Reset connection attempts when user manually tries to connect
      _webSocketService.resetConnectionAttempts();
      await _webSocketService.connect(userId: 'test-user-${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      _addMessage('Failed to connect: $e');
      _addMessage('Check if server is running: npm start (in websocket-server folder)');
    }
  }

  Future<void> _startTracking() async {
    try {
      final hasPermission = await _locationService.checkPermissions();
      if (!hasPermission) {
        _addMessage('Location permission not granted');
        return;
      }

      await _locationService.startTracking(
        userId: 'test-user-${DateTime.now().millisecondsSinceEpoch}',
        updateInterval: const Duration(seconds: 10),
        distanceFilter: 10.0,
      );

      setState(() {
        _isTracking = true;
      });
      _addMessage('Location tracking started');
    } catch (e) {
      _addMessage('Failed to start tracking: $e');
    }
  }

  void _stopTracking() {
    _locationService.stopTracking();
    setState(() {
      _isTracking = false;
    });
    _addMessage('Location tracking stopped');
  }

  void _sendTestLocation() {
    _webSocketService.sendLocation(
      userId: 'test-user-123',
      latitude: 13.7563,
      longitude: 100.5018,
      accuracy: 10.0,
    );
    _addMessage('Sent test location: 13.7563, 100.5018');
  }

  void _disconnect() {
    _webSocketService.disconnect();
    _addMessage('Disconnected');
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    _webSocketService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebSocket Test'),
      ),
      body: Column(
        children: [
          // Status Card
          Container(
            padding: const EdgeInsets.all(16),
            color: _isConnected ? Colors.green.shade100 : Colors.red.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.check_circle : Icons.error,
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status: $_status',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('Tracking: ${_isTracking ? "Active" : "Inactive"}'),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!_isConnected) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Server: $_serverUrl',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '💡 Make sure WebSocket Server is running:\n   cd websocket-server && npm start',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isConnected ? null : _connect,
                  child: const Text('Connect'),
                ),
                ElevatedButton(
                  onPressed: _isConnected ? _disconnect : null,
                  child: const Text('Disconnect'),
                ),
                ElevatedButton(
                  onPressed: _isConnected && !_isTracking ? _startTracking : null,
                  child: const Text('Start Tracking'),
                ),
                ElevatedButton(
                  onPressed: _isTracking ? _stopTracking : null,
                  child: const Text('Stop Tracking'),
                ),
                ElevatedButton(
                  onPressed: _isConnected ? _sendTestLocation : null,
                  child: const Text('Send Test Location'),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Messages:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            _messages[index],
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
