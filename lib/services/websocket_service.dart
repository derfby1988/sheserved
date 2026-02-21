import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

/// WebSocket Service for Real-time Communication
/// Self-hosted WebSocket Server Connection
class WebSocketService {
  static WebSocketService? _instance;
  IO.Socket? _socket;
  final String _serverUrl;
  bool _isConnected = false;
  bool _isEnabled = true; // Flag to enable/disable WebSocket
  int _connectionAttempts = 0;
  static const int _maxConnectionAttempts = 3;
  
  // Stream Controllers
  final _connectionController = StreamController<bool>.broadcast();
  final _locationController = StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _callInviteController = StreamController<Map<String, dynamic>>.broadcast();
  final _callAcceptController = StreamController<Map<String, dynamic>>.broadcast();
  final _callRejectController = StreamController<Map<String, dynamic>>.broadcast();
  final _webrtcSignalController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isEnabled => _isEnabled;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get locationStream => _locationController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get callInviteStream => _callInviteController.stream;
  Stream<Map<String, dynamic>> get callAcceptStream => _callAcceptController.stream;
  Stream<Map<String, dynamic>> get callRejectStream => _callRejectController.stream;
  Stream<Map<String, dynamic>> get webrtcSignalStream => _webrtcSignalController.stream;
  
  WebSocketService._(this._serverUrl);
  
  /// Singleton instance
  factory WebSocketService({String? serverUrl}) {
    _instance ??= WebSocketService._(
      serverUrl ?? 'http://localhost:3000', // Default server URL
    );
    return _instance!;
  }
  
  /// Enable or disable WebSocket connection
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      disconnect();
    }
  }
  
  /// Reset connection attempts (call this when user manually tries to connect)
  void resetConnectionAttempts() {
    _connectionAttempts = 0;
  }
  
  /// Connect to WebSocket Server
  Future<void> connect({String? userId, String? authToken}) async {
    if (!_isEnabled) {
      debugPrint('WebSocket is disabled');
      return;
    }
    
    if (_isConnected) {
      debugPrint('WebSocket already connected');
      return;
    }
    
    // Check connection attempts to prevent infinite retry
    if (_connectionAttempts >= _maxConnectionAttempts) {
      debugPrint('WebSocket: Max connection attempts reached. Call resetConnectionAttempts() to retry.');
      _errorController.add('Max connection attempts reached. Server may not be running.');
      return;
    }
    
    _connectionAttempts++;
    
    try {
      _socket = IO.io(
        _serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect() // ปิด auto-connect เพื่อให้เชื่อมต่อเมื่อเรียก connect() เท่านั้น
            .disableReconnection() // ปิด auto-reconnect เพื่อไม่ให้ retry ตลอดเวลา
            .setAuth({'userId': userId, 'token': authToken})
            .build(),
      );
      
      // Connection Events
      _socket!.onConnect((_) {
        debugPrint('WebSocket connected');
        _isConnected = true;
        _connectionAttempts = 0; // Reset on successful connection
        _connectionController.add(true);
        
        // Send user info after connection
        if (userId != null) {
          _socket!.emit('user-connected', {'userId': userId});
        }
      });
      
      _socket!.onDisconnect((_) {
        debugPrint('WebSocket disconnected');
        _isConnected = false;
        _connectionController.add(false);
      });
      
      _socket!.onConnectError((error) {
        _isConnected = false;
        // แสดง error เฉพาะครั้งแรกหรือเมื่อมีการ subscribe error stream
        if (_connectionAttempts <= 1) {
          debugPrint('WebSocket connection error: $error');
          debugPrint('Tip: Make sure the WebSocket server is running (cd websocket-server && npm start)');
        }
        _errorController.add('Connection error: $error');
      });
      
      // Location Events
      _socket!.on('location-updated', (data) {
        debugPrint('Location updated: $data');
        _locationController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('typing-status', (data) {
        _typingController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('call-invite', (data) {
        _callInviteController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('call-accept', (data) {
        _callAcceptController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('call-reject', (data) {
        _callRejectController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('webrtc-signal', (data) {
        _webrtcSignalController.add(Map<String, dynamic>.from(data));
      });
      
      _socket!.on('error', (error) {
        if (kDebugMode) {
          debugPrint('WebSocket error: $error');
        }
        _errorController.add('Error: $error');
      });
      
      // เชื่อมต่อหลังจาก setup events แล้ว
      _socket!.connect();
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to connect WebSocket: $e');
      }
      _errorController.add('Failed to connect: $e');
    }
  }
  
  /// Send location update to server
  void sendLocation({
    required String userId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? heading,
  }) {
    if (!_isConnected || _socket == null) {
      debugPrint('WebSocket not connected');
      return;
    }
    
    final locationData = {
      'userId': userId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
      if (accuracy != null) 'accuracy': accuracy,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
    };
    
    _socket!.emit('location-update', locationData);
  }
  
  /// Subscribe to specific user's location
  void subscribeToUser(String userId) {
    if (!_isConnected || _socket == null) {
      debugPrint('WebSocket not connected');
      return;
    }
    
    _socket!.emit('subscribe-user', {'userId': userId});
  }
  
  /// Unsubscribe from user's location
  void unsubscribeFromUser(String userId) {
    if (!_isConnected || _socket == null) {
      debugPrint('WebSocket not connected');
      return;
    }
    
    _socket!.emit('unsubscribe-user', {'userId': userId});
  }
  
  /// Join a room (e.g., for group tracking)
  void joinRoom(String roomId) {
    if (!_isConnected || _socket == null) {
      debugPrint('WebSocket not connected');
      return;
    }
    
    _socket!.emit('join-room', {'roomId': roomId});
  }
  
  /// Leave a room
  void leaveRoom(String roomId) {
    if (!_isConnected || _socket == null) {
      debugPrint('WebSocket not connected');
      return;
    }
    
    _socket!.emit('leave-room', {'roomId': roomId});
  }

  /// Send typing status to a room
  void sendTypingStatus(String roomId, String userId, bool isTyping) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('typing', {
      'roomId': roomId,
      'userId': userId,
      'isTyping': isTyping,
    });
  }

  /// Send call invitation
  void sendCallInvite(String roomId, String callerId, String callerName, String? callerAvatar) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('call-invite', {
      'roomId': roomId,
      'callerId': callerId,
      'callerName': callerName,
      'callerAvatar': callerAvatar,
    });
  }

  /// Accept call
  void acceptCall(String roomId, String calleeId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('call-accept', {
      'roomId': roomId,
      'calleeId': calleeId,
    });
  }

  /// Reject or end call
  void rejectCall(String roomId, String userId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('call-reject', {
      'roomId': roomId,
      'userId': userId,
    });
  }

  /// Send WebRTC signaling data
  void sendWebRTCSignal(String roomId, Map<String, dynamic> signalData) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('webrtc-signal', {
      'roomId': roomId,
      'signal': signalData,
    });
  }
  
  /// Disconnect from server
  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
      _connectionController.add(false);
    }
  }
  
  /// Dispose resources
  void dispose() {
    disconnect();
    _connectionController.close();
    _locationController.close();
    _errorController.close();
    _typingController.close();
    _callInviteController.close();
    _callAcceptController.close();
    _callRejectController.close();
    _webrtcSignalController.close();
  }
}
