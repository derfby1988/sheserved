import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../core/network/authenticated_http_client.dart';
import 'auth_service.dart';
import 'socket_auth_recovery_policy.dart';
import 'socket_auth_socket_factory.dart';
import 'socket_reconnect_policy.dart';

/// WebSocket Service for Real-time Communication
/// Self-hosted WebSocket Server Connection
class WebSocketService {
  static WebSocketService? _instance;
  IO.Socket? _socket;
  final String _serverUrl;
  bool _isConnected = false;
  bool _isEnabled = true; // Flag to enable/disable WebSocket
  int _connectionAttempts = 0;
  int _connectionErrorLogCount = 0;
  DateTime? _lastConnectionErrorLogAt;
  DateTime? _lastNotConnectedLogAt;
  static const int _maxConnectionAttempts = 3;
  static const int _socketReconnectionAttempts = 10;
  Timer? _heartbeatTimer;
  Timer? _authRetryTimer;
  Timer? _transportRetryTimer;
  int _transportRetryCount = 0;

  // socket.io bakes `auth` into the options at construction, so token changes
  // must rebuild the socket instead of relying on its internal reconnect.
  String? _userId;
  String? _authToken;
  String? _socketAuthToken;
  String? _socketUserId;
  String? _authRecoveryToken;
  String? _pendingAuthFailureCode;
  StreamSubscription<String?>? _tokenSub;
  bool _authUserLifecycleWatching = false;
  bool _connectionRequested = false;
  bool _handlingAuthFailure = false;
  bool _authRecoveryBlocked = false;
  int _preemptiveRefreshCount = 0;
  int _authRecoveryAttempts = 0;
  int _authRetryCount = 0;
  static const int _maxAuthRecoveries = 3;

  // Stream Controllers
  final _connectionController = StreamController<bool>.broadcast();
  final _locationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _callInviteController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _callAcceptController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _callRejectController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _webrtcSignalController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _emergencyChatController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Video Stream Controllers
  final _videoProgressController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _videoStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _videoInteractionController =
      StreamController<Map<String, dynamic>>.broadcast();

  final _emergencyNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _rescueIncomingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _incidentProfessionQuotaFilledController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _rescueCancelledController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _viewerCountController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _cumulativeViewerCountController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _donationStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _thaiMhungPhotoController =
      StreamController<Map<String, dynamic>>.broadcast();
  // Phase 6.12: Async Thai Mhung Face Blur completion event
  final _photoBlurCompleteController =
      StreamController<Map<String, dynamic>>.broadcast();
  // ✅ [Yield Way] Stream สำหรับรับการแจ้งเตือนให้ทาง
  final _yieldWayAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  // ✅ [Thumbnail] Stream สำหรับ Thumbnail อัปเดตแบบ Real-time (Recommendation #7)
  final _thumbnailUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  // ✅ [Phase 4] Emergency health sensor / dead-man switch events
  final _emergencyHealthSensorAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _emergencyHealthDeadManReminderController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _emergencyHealthDeadManTriggeredController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fitnessBookingAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _applicationNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters
  bool get isConnected => _isConnected;
  bool get isEnabled => _isEnabled;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get locationStream => _locationController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get callInviteStream =>
      _callInviteController.stream;
  Stream<Map<String, dynamic>> get callAcceptStream =>
      _callAcceptController.stream;
  Stream<Map<String, dynamic>> get callRejectStream =>
      _callRejectController.stream;
  Stream<Map<String, dynamic>> get webrtcSignalStream =>
      _webrtcSignalController.stream;
  Stream<Map<String, dynamic>> get emergencyChatStream =>
      _emergencyChatController.stream;

  // Video Getters
  Stream<Map<String, dynamic>> get videoProgressStream =>
      _videoProgressController.stream;
  Stream<Map<String, dynamic>> get videoStatusStream =>
      _videoStatusController.stream;
  Stream<Map<String, dynamic>> get videoInteractionStream =>
      _videoInteractionController.stream;
  IO.Socket? get socket => _socket;

  // Emergency Getters
  Stream<Map<String, dynamic>> get emergencyNotificationStream =>
      _emergencyNotificationController.stream;
  Stream<Map<String, dynamic>> get rescueIncomingStream =>
      _rescueIncomingController.stream;
  Stream<Map<String, dynamic>> get incidentProfessionQuotaFilledStream =>
      _incidentProfessionQuotaFilledController.stream;
  Stream<Map<String, dynamic>> get rescueCancelledStream =>
      _rescueCancelledController.stream;
  Stream<Map<String, dynamic>> get viewerCountStream =>
      _viewerCountController.stream;
  Stream<Map<String, dynamic>> get cumulativeViewerCountStream =>
      _cumulativeViewerCountController.stream;

  /// สถานะคำร้องบริจาคผ่านการอนุมัติเปลี่ยนสถานะแบบ Real-time
  Stream<Map<String, dynamic>> get donationStatusStream =>
      _donationStatusController.stream;

  /// ภาพไทยมุงใหม่เข้ามาแบบ Real-time ผ่าน WebSocket
  Stream<Map<String, dynamic>> get thaiMhungPhotoStream =>
      _thaiMhungPhotoController.stream;

  /// Phase 6.12: รับ event เมื่อ face blur เสร็จสิ้น (background async processing)
  Stream<Map<String, dynamic>> get photoBlurCompleteStream =>
      _photoBlurCompleteController.stream;

  /// ✅ [Yield Way] การแจ้งเตือนให้ทางแบบ Real-time
  Stream<Map<String, dynamic>> get yieldWayAlertStream =>
      _yieldWayAlertController.stream;

  /// ✅ [Thumbnail] Thumbnail URL อัปเดตแบบ Real-time — TrendingPanel ใช้เพื่อรีเฟรชรูปพื้นหลังการ์ด (Recommendation #7)
  Stream<Map<String, dynamic>> get thumbnailUpdateStream =>
      _thumbnailUpdateController.stream;

  /// ✅ [Phase 4] Sensor anomaly alerts for emergency health
  Stream<Map<String, dynamic>> get emergencyHealthSensorAlertStream =>
      _emergencyHealthSensorAlertController.stream;

  /// ✅ [Phase 4] Dead-man reminder notifications
  Stream<Map<String, dynamic>> get emergencyHealthDeadManReminderStream =>
      _emergencyHealthDeadManReminderController.stream;

  /// ✅ [Phase 4] Dead-man trigger notifications
  Stream<Map<String, dynamic>> get emergencyHealthDeadManTriggeredStream =>
      _emergencyHealthDeadManTriggeredController.stream;
  Stream<Map<String, dynamic>> get fitnessBookingAlertStream =>
      _fitnessBookingAlertController.stream;
  Stream<Map<String, dynamic>> get applicationNotificationStream =>
      _applicationNotificationController.stream;

  void publishFitnessBookingAlert(Map<String, dynamic> alert) {
    _fitnessBookingAlertController.add(alert);
  }

  /// Notify the backend after an admin has reviewed an application.
  /// The server resolves the applicant from the application ID before
  /// persisting and delivering the notification.
  void sendApplicationReviewNotification({
    required String applicationId,
    required String status,
  }) {
    debugPrint(
      '[WebSocket] sendApplicationReviewNotification: app=$applicationId status=$status connected=$_isConnected socket=${_socket != null}',
    );
    if (!_isConnected || _socket == null) {
      debugPrint(
        '[WebSocket] sendApplicationReviewNotification SKIPPED — not connected',
      );
      return;
    }
    _socket!.emit('application-review-notification', {
      'applicationId': applicationId,
      'status': status,
    });
    debugPrint('[WebSocket] emit application-review-notification OK');
  }

  /// Ask the backend to re-publish the persisted `app_notifications` rows for
  /// a venue booking (requested/decided/cancelled/slot_changed). The server
  /// resolves recipients from the database — the same client→server→client
  /// path the Fitness Buddies join-approval flow uses — so delivery does not
  /// depend on the pg_notify LISTEN bridge being alive.
  void sendVenueBookingNotification({required String bookingId}) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('venue-booking-notification', {'bookingId': bookingId});
  }

  WebSocketService._(this._serverUrl);

  /// Singleton instance
  factory WebSocketService({String? serverUrl}) {
    _instance ??= WebSocketService._(
      serverUrl ??
          AppConfig.websocketUrl, // ใช้ค่าจาก Config เป็นหลักแทน localhost
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
    resetTransportConnectionAttempts();
    resetAuthRecovery();
  }

  void resetTransportConnectionAttempts() {
    _connectionAttempts = 0;
    _connectionErrorLogCount = 0;
    _lastConnectionErrorLogAt = null;
  }

  void resetAuthRecovery() {
    _authRecoveryAttempts = 0;
    _authRecoveryToken = null;
    _authRecoveryBlocked = false;
    _pendingAuthFailureCode = null;
    _cancelAuthRetry(resetCount: true);
  }

  void _logConnectionError(String message, {bool showServerTip = false}) {
    _connectionErrorLogCount++;
    final now = DateTime.now();
    final shouldLog =
        _connectionErrorLogCount <= 3 ||
        _lastConnectionErrorLogAt == null ||
        now.difference(_lastConnectionErrorLogAt!) >=
            const Duration(seconds: 30);
    if (!shouldLog) return;
    _lastConnectionErrorLogAt = now;
    debugPrint(message);
    if (showServerTip) {
      debugPrint(
        'Tip: Make sure the WebSocket server is running (cd websocket-server && npm start)',
      );
    }
  }

  void _logNotConnected() {
    final now = DateTime.now();
    if (_lastNotConnectedLogAt != null &&
        now.difference(_lastNotConnectedLogAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastNotConnectedLogAt = now;
    debugPrint(
      'WebSocket not connected (requested=$_connectionRequested, enabled=$_isEnabled, socket=${_socket != null})',
    );
  }

  /// Connect to WebSocket Server
  Future<void> connect({String? userId, String? authToken}) async {
    if (!_isEnabled || _authRecoveryBlocked) return;
    final client = AuthenticatedHttpClient.instance;
    if (AppConfig.useBackendAuth && client.accessToken != null) {
      authToken = client.accessToken;
    }
    authToken ??= client.accessToken;
    if (AppConfig.useBackendAuth &&
        userId != null &&
        (authToken == null || authToken.trim().isEmpty)) {
      debugPrint(
        'WebSocket: refusing backend-auth connection without an access token',
      );
      _errorController.add('Verified login required for realtime updates');
      disconnect();
      return;
    }
    if (_authRetryTimer != null) {
      if (authToken == _authToken) return;
      _cancelAuthRetry(resetCount: true);
    }
    _connectionRequested = true;
    _userId = userId;
    _watchTokenLifecycle();
    _watchAuthUserLifecycle();

    final action = SocketAuthRecoveryPolicy.connectionAction(
      backendAuthRequired: AppConfig.useBackendAuth && userId != null,
      accessToken: authToken,
      hasSocket: _socket != null,
      socketAuthToken: _socketAuthToken,
      socketUserId: _socketUserId,
      requestedUserId: userId,
    );
    if (action == SocketConnectionAction.stopWithError) {
      _errorController.add('Verified login required for realtime updates');
      disconnect();
      return;
    }
    if (_socket != null &&
        _socket!.connected &&
        _socketAuthToken == authToken &&
        _socketUserId == userId) {
      return;
    }
    if (action == SocketConnectionAction.refreshThenRebuild) {
      if (!SocketAuthRecoveryPolicy.canAttemptRecovery(
        _authRecoveryAttempts,
        maximum: _maxAuthRecoveries,
      )) {
        _blockAuthRecovery(
          'Realtime authentication recovery paused; log in again or retry manually',
        );
        return;
      }
      _authRecoveryAttempts++;
      final tokenBeforeRefresh = authToken;
      _preemptiveRefreshCount++;
      TokenRefreshResult refreshResult;
      try {
        refreshResult = await client.refreshTokens();
      } finally {
        _preemptiveRefreshCount--;
      }
      if (refreshResult == TokenRefreshResult.rejected) {
        _errorController.add('Session expired — please log in again');
        if (AuthService.instance.currentUser != null) {
          await AuthService.instance.logout();
        }
        return;
      }
      if (refreshResult == TokenRefreshResult.missingRefreshToken) {
        _blockAuthRecovery('Realtime updates require logging in again');
        return;
      }
      if (!_connectionRequested || !_isEnabled || _userId != userId) return;
      if (refreshResult == TokenRefreshResult.unavailable) {
        _scheduleAuthRetry(reconnect: true);
        return;
      }
      authToken = client.accessToken;
      if (authToken == null || authToken == tokenBeforeRefresh) {
        _blockAuthRecovery(
          'Realtime authentication recovery paused; the access token did not change',
        );
        return;
      }
      _authRecoveryToken = authToken;
      _authToken = authToken;
      _cancelAuthRetry(resetCount: true);
    }

    if (action == SocketConnectionAction.rebuild ||
        (_socket != null &&
            (_socketAuthToken != authToken || _socketUserId != userId))) {
      _disposeSocket();
    }
    _cancelTransportRetry();
    _authToken = authToken;

    if (_socket != null) {
      if (!_socket!.connected) _socket!.connect();
      return;
    }

    if (_connectionAttempts >= _maxConnectionAttempts) {
      debugPrint(
        'WebSocket: initial connection limit reached; scheduling recovery',
      );
      _errorController.add(
        'Initial connection attempts exhausted; retry scheduled',
      );
      _scheduleTransportRetry(reason: 'initial connection attempts exhausted');
      return;
    }

    _connectionAttempts++;

    try {
      _socket = SocketAuthSocketFactory.create(
        serverUrl: _serverUrl,
        userId: userId,
        token: authToken,
        reconnectionAttempts: _socketReconnectionAttempts,
      );
      _socketAuthToken = authToken;
      _socketUserId = userId;

      final socket = _socket!;

      // Connection Events
      socket.onConnect((_) {
        if (!identical(_socket, socket)) return;
        debugPrint('WebSocket connected');
        _isConnected = true;
        _connectionAttempts = 0;
        _cancelTransportRetry(resetCount: true);
        _lastNotConnectedLogAt = null;
        _authRecoveryAttempts = 0;
        _authRecoveryToken = null;
        _authRecoveryBlocked = false;
        _pendingAuthFailureCode = null;
        _authRetryCount = 0;
        _authRetryTimer?.cancel();
        _authRetryTimer = null;
        _connectionController.add(true);

        // Start heartbeat to keep connection alive in background
        _startHeartbeat();

        // Send user info after connection
        if (userId != null) {
          final user = AuthService.instance.currentUser;
          socket.emit('user-connected', {
            'userId': userId,
            // ✅ [Yield Way] ส่ง settings สำหรับ Server คัดกรองการให้ทาง
            'isThaiMhungEnabled': user?.isThaiMhungEnabled ?? false,
            'isYieldWayEnabled': user?.isYieldWayEnabled ?? false,
            'yieldWayRadius': user?.yieldWayRadius ?? 1000,
            // GPS ล่าสุด (ถ้ามี) — Server จะอัพเดตอีกครั้งเมื่อได้ location-update
            'latitude': null,
            'longitude': null,
          });
        }
      });

      socket.onDisconnect((reason) {
        if (!identical(_socket, socket)) return;
        debugPrint('WebSocket disconnected: $reason');
        _isConnected = false;
        _connectionController.add(false);
        if (reason == 'io server disconnect') {
          _scheduleTransportRetry(reason: 'server disconnected the socket');
        }
      });

      socket.onReconnectError((error) {
        if (!identical(_socket, socket)) return;
        _logConnectionError('WebSocket reconnect error: $error');
      });

      socket.onReconnectFailed((_) {
        if (!identical(_socket, socket)) return;
        _scheduleTransportRetry(
          reason: 'Socket.IO automatic reconnection attempts exhausted',
        );
      });

      socket.onConnectError((error) {
        if (!identical(_socket, socket)) return;
        _isConnected = false;
        _logConnectionError(
          'WebSocket connection error: $error',
          showServerTip: true,
        );
        _errorController.add('Connection error: $error');

        if (_isSocketAuthError(error)) {
          final reasonCode = _socketAuthErrorCode(error);
          _pendingAuthFailureCode = reasonCode;
          unawaited(
            _handleSocketAuthFailure(source: socket, reasonCode: reasonCode),
          );
        }
      });

      // Location Events
      _socket!.on('location-updated', (data) {
        // debugPrint('Location updated: $data'); // Removed to reduce terminal noise
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

      // Video Events
      _socket!.on('video-progress', (data) {
        _videoProgressController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('video-status', (data) {
        _videoStatusController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('video-interaction', (data) {
        _videoInteractionController.add(Map<String, dynamic>.from(data));
      });

      // Emergency Event
      _socket!.on('emergency-notification', (data) {
        // debugPrint('Emergency notification received: $data'); // Reduced logging
        _emergencyNotificationController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('rescue-incoming', (data) {
        debugPrint('Rescue incoming notification received: $data');
        _rescueIncomingController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('incident-profession-quota-filled', (data) {
        _incidentProfessionQuotaFilledController.add(
          Map<String, dynamic>.from(data),
        );
      });

      _socket!.on('rescue-cancelled', (data) {
        _rescueCancelledController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('viewer-count', (data) {
        _viewerCountController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('cumulative-viewer-count', (data) {
        _cumulativeViewerCountController.add(Map<String, dynamic>.from(data));
      });

      _socket!.on('emergency-chat-message', (data) {
        _emergencyChatController.add(Map<String, dynamic>.from(data));
      });

      // Donation Status Events
      _socket!.on('donation-request-status-updated', (data) {
        debugPrint(
          'WebSocket: donation-request-status-updated received: $data',
        );
        _donationStatusController.add(Map<String, dynamic>.from(data));
      });

      // Thai Mhung Photo Events
      _socket!.on('new-thaimhung-photo', (data) {
        debugPrint('WebSocket: new-thaimhung-photo received: $data');
        _thaiMhungPhotoController.add(Map<String, dynamic>.from(data));
      });

      // Phase 6.12: Photo Blur Complete Event
      _socket!.on('photo-blur-complete', (data) {
        debugPrint('WebSocket: photo-blur-complete received: $data');
        _photoBlurCompleteController.add(Map<String, dynamic>.from(data));
      });

      // ✅ [Yield Way] รับการแจ้งเตือนให้ทางจาก Server (คัดกรองแล้วโดย route-based filter)
      _socket!.on('yield-way-alert', (data) {
        debugPrint('[Yield Way] Alert received: $data');
        _yieldWayAlertController.add(Map<String, dynamic>.from(data));
      });

      // ✅ [Thumbnail] รับการอัปเดต Thumbnail URL แบบ Real-time — TrendingPanel
      _socket!.on('thumbnail-updated', (data) {
        debugPrint('[Thumbnail] thumbnail-updated received: $data');
        _thumbnailUpdateController.add(Map<String, dynamic>.from(data));
      });

      // ✅ [Phase 4] Sensor anomaly alerts / dead-man switch notifications
      _socket!.on('emergency-health-sensor-alert', (data) {
        debugPrint(
          '[EmergencyHealth] emergency-health-sensor-alert received: $data',
        );
        _emergencyHealthSensorAlertController.add(
          Map<String, dynamic>.from(data),
        );
      });

      _socket!.on('emergency-health-dead-man-reminder', (data) {
        debugPrint(
          '[EmergencyHealth] emergency-health-dead-man-reminder received: $data',
        );
        _emergencyHealthDeadManReminderController.add(
          Map<String, dynamic>.from(data),
        );
      });

      _socket!.on('emergency-health-dead-man-triggered', (data) {
        debugPrint(
          '[EmergencyHealth] emergency-health-dead-man-triggered received: $data',
        );
        _emergencyHealthDeadManTriggeredController.add(
          Map<String, dynamic>.from(data),
        );
      });

      _socket!.on('fitness-booking-status', (data) {
        _fitnessBookingAlertController.add(Map<String, dynamic>.from(data));
      });
      _socket!.on('fitness_booking_status', (data) {
        _fitnessBookingAlertController.add(Map<String, dynamic>.from(data));
      });
      _socket!.on('application-notification', (data) {
        _applicationNotificationController.add(Map<String, dynamic>.from(data));
      });

      socket.on('session-revoked', (_) {
        if (!identical(_socket, socket)) return;
        unawaited(_handleServerSessionRevoked(socket));
      });

      socket.on('error', (error) {
        if (!identical(_socket, socket)) return;
        if (kDebugMode) {
          debugPrint('WebSocket error: $error');
        }
        _errorController.add('Error: $error');
        if (_isSocketAuthError(error)) {
          final reasonCode = _socketAuthErrorCode(error);
          _pendingAuthFailureCode = reasonCode;
          unawaited(
            _handleSocketAuthFailure(source: socket, reasonCode: reasonCode),
          );
        } else if (!socket.connected && !_isConnected) {
          _scheduleTransportRetry(reason: 'Socket.IO handshake was rejected');
        }
      });

      // เชื่อมต่อหลังจาก setup events แล้ว
      socket.connect();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to connect WebSocket: $e');
      }
      _errorController.add('Failed to connect: $e');
      _scheduleTransportRetry(reason: 'socket initialization failed');
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
      _logNotConnected();
      return;
    }

    final locationData = {
      'userId': userId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': AppConfig.thailandNow.toIso8601String(),
      if (accuracy != null) 'accuracy': accuracy,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
    };

    _socket!.emit('location-update', locationData);
  }

  /// Subscribe to specific user's location
  void subscribeToUser(String userId) {
    if (!_isConnected || _socket == null) {
      _logNotConnected();
      return;
    }

    _socket!.emit('subscribe-user', {'userId': userId});
  }

  /// Unsubscribe from user's location
  void unsubscribeFromUser(String userId) {
    if (!_isConnected || _socket == null) {
      _logNotConnected();
      return;
    }

    _socket!.emit('unsubscribe-user', {'userId': userId});
  }

  /// Join a room (e.g., for group tracking)
  void joinRoom(String roomId) {
    if (!_isConnected || _socket == null) {
      _logNotConnected();
      return;
    }

    _socket!.emit('join-room', {'roomId': roomId});
  }

  /// Leave a room
  void leaveRoom(String roomId) {
    if (!_isConnected || _socket == null) {
      _logNotConnected();
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
  void sendCallInvite(
    String roomId,
    String callerId,
    String callerName,
    String? callerAvatar,
  ) {
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
    _socket!.emit('call-accept', {'roomId': roomId, 'calleeId': calleeId});
  }

  /// Reject or end call
  void rejectCall(String roomId, String userId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('call-reject', {'roomId': roomId, 'userId': userId});
  }

  /// Send WebRTC signaling data
  void sendWebRTCSignal(String roomId, Map<String, dynamic> signalData) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('webrtc-signal', {'roomId': roomId, 'signal': signalData});
  }

  /// Send Emergency Alert to Volunteers
  void sendEmergencyAlert({
    required String userId,
    required String categoryId,
    String? videoId,
    String? type,
    String? text,
    bool isThaiMhungEnabled = false,
    String? incidentId, // ✅ สำหรับเชื่อมโยงภาพไทยมุงกับเหตุการณ์หลัก
  }) {
    if (!_isConnected || _socket == null) {
      _logNotConnected();
      return;
    }

    _socket!.emit('emergency-alert', {
      'userId': userId,
      'categoryId': categoryId,
      'videoId': videoId,
      'type': type,
      'text': text,
      'isThaiMhungEnabled': isThaiMhungEnabled,
      'incidentId': incidentId, // ✅ ส่ง incidentId ไปยัง server
    });
    debugPrint(
      'Sent emergency alert for category: $categoryId, incidentId: $incidentId, thaiMhung: $isThaiMhungEnabled',
    );
  }

  /// Create emergency health release session on the Node.js server.
  Future<Map<String, dynamic>?> createEmergencyHealthReleaseSession({
    required String patientId,
    required String incidentId,
    String? videoId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.localApiUrl}/api/emergency-health/sessions'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'patientId': patientId,
              'incidentId': incidentId,
              'videoId': videoId ?? incidentId,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return Map<String, dynamic>.from(decoded as Map);
      }

      debugPrint(
        'WebSocketService: createEmergencyHealthReleaseSession failed '
        '(${response.statusCode}): ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint(
        'WebSocketService: createEmergencyHealthReleaseSession error: $e',
      );
      return null;
    }
  }

  /// Fetch emergency health data for a responder who has a valid access token.
  Future<Map<String, dynamic>?> getIncidentHealthData({
    required String incidentId,
    required String responderId,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.localApiUrl}/api/emergency-health/$incidentId?responderId=$responderId',
            ),
            headers: const {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return Map<String, dynamic>.from(decoded as Map);
      }

      if (response.statusCode == 403) {
        debugPrint('WebSocketService: getIncidentHealthData access denied');
        return null;
      }

      debugPrint(
        'WebSocketService: getIncidentHealthData failed '
        '(${response.statusCode}): ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('WebSocketService: getIncidentHealthData error: $e');
      return null;
    }
  }

  /// Revoke all active emergency health sessions and tokens for a patient.
  Future<Map<String, dynamic>?> revokeEmergencyHealthSessions({
    required String patientId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.localApiUrl}/api/emergency-health/revoke'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'patientId': patientId}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return Map<String, dynamic>.from(decoded as Map);
      }

      debugPrint(
        'WebSocketService: revokeEmergencyHealthSessions failed '
        '(${response.statusCode}): ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('WebSocketService: revokeEmergencyHealthSessions error: $e');
      return null;
    }
  }

  /// Send Rescue Status Update (Feedback loop)
  void sendRescueStatusUpdate({
    required String videoId,
    required String volunteerId,
    required String status,
    String? victimId,
    String? responseId,
  }) {
    if (!_isConnected || _socket == null) return;

    _socket!.emit('rescue-status-update', {
      'videoId': videoId,
      'volunteerId': volunteerId,
      'status': status,
      'victimId': victimId,
      'responseId': responseId,
    });
    debugPrint('Sent rescue status update: $status for video: $videoId');
  }

  /// Join Emergency Chat Room
  void joinEmergencyChat(String videoId, String userId, String role) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('join-emergency-chat', {
      'videoId': videoId,
      'userId': userId,
      'role': role,
    });
  }

  /// Leave Emergency Chat Room
  void leaveEmergencyChat(String videoId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('leave-emergency-chat', {'videoId': videoId});
  }

  /// สั่งให้ Server ย้ายข้อความแชทไปกองเก็บที่ Archive (ใช้เมื่อจบเหตุการณ์)
  void archiveEmergencyChat(String videoId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('archive-chat', {'videoId': videoId});
  }

  /// Send Emergency Chat Message
  void sendEmergencyChatMessage({
    required String videoId,
    required String userId,
    required String role,
    required String userName,
    required String content,
    String? profileImageUrl,
    String? professionName,
    String? replyToId,
    String? replyToContent,
    String? replyToUserName,
  }) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('send-emergency-message', {
      'videoId': videoId,
      'userId': userId,
      'role': role,
      'userName': userName,
      'content': content,
      'profileImageUrl': profileImageUrl,
      'professionName': professionName,
      'replyToId': replyToId,
      'replyToContent': replyToContent,
      'replyToUserName': replyToUserName,
    });
  }

  void _watchTokenLifecycle() {
    _tokenSub ??= AuthenticatedHttpClient.instance.tokenChanges.listen((token) {
      if (token == null) {
        _authToken = null;
        _authRecoveryToken = null;
        _authRecoveryBlocked = false;
        _authRecoveryAttempts = 0;
        _cancelAuthRetry(resetCount: true);
        disconnect();
        return;
      }
      if (token == _authToken) return;

      final userId = _userId;
      _authToken = token;
      if (_authRecoveryBlocked && token != _authRecoveryToken) {
        _authRecoveryBlocked = false;
      }
      _cancelAuthRetry(resetCount: true);
      _cancelTransportRetry(resetCount: true);
      if (_handlingAuthFailure) {
        _authRecoveryToken = token;
        return;
      }
      if (_preemptiveRefreshCount > 0 || _authRecoveryBlocked) return;
      if (_connectionRequested && _isEnabled && userId != null) {
        _disposeSocket();
        unawaited(connect(userId: userId, authToken: token));
      }
    });
  }

  void _watchAuthUserLifecycle() {
    if (_authUserLifecycleWatching) return;
    AuthService.instance.addListener(_handleAuthUserChanged);
    _authUserLifecycleWatching = true;
  }

  void _handleAuthUserChanged() {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == _userId) return;

    final shouldReconnect =
        _connectionRequested && userId != null && _isEnabled;
    _cancelAuthRetry(resetCount: true);
    _cancelTransportRetry(resetCount: true);
    _disposeSocket();
    _authRecoveryAttempts = 0;
    _authRecoveryToken = null;
    _authRecoveryBlocked = false;
    _pendingAuthFailureCode = null;
    _userId = userId;
    _authToken = AuthenticatedHttpClient.instance.accessToken;

    if (userId == null) {
      _connectionRequested = false;
      _authToken = null;
      return;
    }
    if (shouldReconnect) {
      unawaited(connect(userId: userId, authToken: _authToken));
    }
  }

  void _cancelAuthRetry({bool resetCount = false}) {
    _authRetryTimer?.cancel();
    _authRetryTimer = null;
    if (resetCount) _authRetryCount = 0;
  }

  void _cancelTransportRetry({bool resetCount = false}) {
    _transportRetryTimer?.cancel();
    _transportRetryTimer = null;
    if (resetCount) _transportRetryCount = 0;
  }

  void _scheduleTransportRetry({required String reason}) {
    final userId = _userId;
    if (_transportRetryTimer != null ||
        !_connectionRequested ||
        !_isEnabled ||
        (AppConfig.useBackendAuth &&
            userId != null &&
            AuthService.instance.currentUser?.id != userId)) {
      return;
    }

    final delay = SocketReconnectPolicy.delayForAttempt(_transportRetryCount);
    _transportRetryCount++;
    debugPrint(
      'WebSocket reconnect scheduled: $reason; retry in ${delay.inSeconds}s',
    );
    _errorController.add('Realtime connection unavailable; retry scheduled');
    _transportRetryTimer = Timer(delay, () {
      _transportRetryTimer = null;
      if (!_connectionRequested ||
          !_isEnabled ||
          _isConnected ||
          _userId != userId) {
        return;
      }
      if (AppConfig.useBackendAuth &&
          userId != null &&
          AuthService.instance.currentUser?.id != userId) {
        return;
      }

      final latestToken = AuthenticatedHttpClient.instance.accessToken;
      if (AppConfig.useBackendAuth &&
          userId != null &&
          (latestToken == null || latestToken.trim().isEmpty)) {
        debugPrint(
          'WebSocket reconnect stopped: backend access token unavailable',
        );
        disconnect();
        return;
      }

      final token = AppConfig.useBackendAuth ? latestToken : _authToken;
      _disposeSocket();
      _connectionAttempts = 0;
      unawaited(connect(userId: userId, authToken: token));
    });
  }

  void _scheduleAuthRetry({bool reconnect = false, String? reasonCode}) {
    if (_authRetryTimer != null ||
        !_connectionRequested ||
        !_isEnabled ||
        _userId == null ||
        _authToken == null ||
        _authRecoveryBlocked) {
      return;
    }
    if (!SocketAuthRecoveryPolicy.canAttemptRecovery(
      _authRecoveryAttempts,
      maximum: _maxAuthRecoveries,
    )) {
      _blockAuthRecovery(
        'Realtime authentication recovery paused; log in again or retry manually',
      );
      return;
    }

    final delay = SocketReconnectPolicy.delayForAttempt(_authRetryCount);
    _authRetryCount++;
    _authRetryTimer = Timer(delay, () {
      _authRetryTimer = null;
      if (!_connectionRequested || !_isEnabled || _authRecoveryBlocked) return;
      if (reconnect) {
        unawaited(
          connect(
            userId: _userId,
            authToken:
                AuthenticatedHttpClient.instance.accessToken ?? _authToken,
          ),
        );
      } else {
        unawaited(_handleSocketAuthFailure(reasonCode: reasonCode));
      }
    });
  }

  bool _isSocketAuthError(dynamic error) =>
      error.toString().contains('Authentication failed') ||
      _socketAuthErrorCode(error) != null;

  String? _socketAuthErrorCode(dynamic error) {
    dynamic data;
    if (error is Map) data = error['data'];
    if (data == null) {
      try {
        data = (error as dynamic).data;
      } catch (_) {}
    }
    if (data is Map && data['code'] is String) {
      return data['code'] as String;
    }
    final text = error.toString();
    const codes = [
      'token_expired',
      'token_not_active',
      'malformed_token',
      'unknown_kid',
      'unsupported_algorithm',
      'wrong_token_type',
      'invalid_signature',
      'session_revoked',
      'user_inactive',
      'user_not_found',
      'verified_login_required',
      'auth_backend_unavailable',
    ];
    for (final code in codes) {
      if (text.contains(code)) return code;
    }
    return null;
  }

  void _blockAuthRecovery(String message) {
    _authRecoveryBlocked = true;
    _pendingAuthFailureCode = null;
    _cancelAuthRetry();
    _cancelTransportRetry();
    _disposeSocket();
    _errorController.add(message);
  }

  Future<void> _handleSocketAuthFailure({
    IO.Socket? source,
    String? reasonCode,
  }) async {
    if (_authRecoveryBlocked ||
        (source != null && !identical(_socket, source)) ||
        _handlingAuthFailure) {
      return;
    }
    _handlingAuthFailure = true;
    final failedToken = _socketAuthToken ?? _authToken;
    final failedUserId = _userId;
    final code = reasonCode ?? _pendingAuthFailureCode;
    _pendingAuthFailureCode = code;
    try {
      final action = SocketAuthRecoveryPolicy.authFailureAction(
        code: code,
        refreshedTokenRejected:
            failedToken != null && failedToken == _authRecoveryToken,
      );
      if (action == SocketAuthFailureAction.stopWithError) {
        _blockAuthRecovery(
          'Realtime rejected a refreshed access token; retry paused until login or manual retry',
        );
        return;
      }
      if (action == SocketAuthFailureAction.logout) {
        _connectionRequested = false;
        _cancelAuthRetry(resetCount: true);
        _cancelTransportRetry(resetCount: true);
        _disposeSocket();
        if (AuthService.instance.currentUser != null) {
          await AuthService.instance.logout();
        }
        _errorController.add('Session expired — please log in again');
        return;
      }
      if (!SocketAuthRecoveryPolicy.canAttemptRecovery(
        _authRecoveryAttempts,
        maximum: _maxAuthRecoveries,
      )) {
        _blockAuthRecovery(
          'Realtime authentication recovery paused; log in again or retry manually',
        );
        return;
      }
      _authRecoveryAttempts++;
      if (action == SocketAuthFailureAction.retryWithoutRefresh) {
        _disposeSocket();
        _scheduleAuthRetry(reconnect: true, reasonCode: code);
        return;
      }
      if (failedToken == null) {
        disconnect();
        _errorController.add('Realtime updates require a valid login');
        return;
      }

      debugPrint(
        'WebSocket: handshake authentication rejected; refreshing tokens',
      );
      final client = AuthenticatedHttpClient.instance;
      final result = await client.refreshTokens();
      debugPrint('WebSocket: token refresh result=${result.name}');
      final token = client.accessToken;
      if (failedUserId != _userId ||
          !_connectionRequested ||
          !_isEnabled ||
          (source != null && !identical(_socket, source))) {
        return;
      }

      switch (result) {
        case TokenRefreshResult.refreshed:
          if (token == null || token == failedToken) {
            _blockAuthRecovery(
              'Realtime authentication recovery paused; the access token did not change',
            );
            return;
          }
          _authRecoveryToken = token;
          _authToken = token;
          _pendingAuthFailureCode = null;
          _cancelAuthRetry(resetCount: true);
          _cancelTransportRetry(resetCount: true);
          _disposeSocket();
          unawaited(connect(userId: failedUserId, authToken: token));
          return;
        case TokenRefreshResult.rejected:
          _connectionRequested = false;
          _disposeSocket();
          if (AuthService.instance.currentUser != null) {
            await AuthService.instance.logout();
          }
          _errorController.add('Session expired — please log in again');
          return;
        case TokenRefreshResult.unavailable:
          _disposeSocket();
          _errorController.add(
            'Realtime authentication temporarily unavailable; retry scheduled',
          );
          _scheduleAuthRetry(reasonCode: code);
          return;
        case TokenRefreshResult.missingRefreshToken:
          _blockAuthRecovery('Realtime updates require logging in again');
          return;
      }
    } catch (_) {
      _disposeSocket();
      _errorController.add(
        'Realtime authentication temporarily unavailable; retry scheduled',
      );
      _scheduleAuthRetry(reasonCode: code);
    } finally {
      _handlingAuthFailure = false;
    }
  }

  Future<void> _handleServerSessionRevoked(IO.Socket source) async {
    if (!identical(_socket, source)) return;
    disconnect();
    try {
      await AuthenticatedHttpClient.instance.clearTokens();
    } catch (_) {}
    if (AuthService.instance.currentUser != null) {
      try {
        await AuthService.instance.logout();
      } catch (_) {}
    }
    _errorController.add('Session expired — please log in again');
  }

  void _disposeSocket() {
    _stopHeartbeat();
    _cancelTransportRetry();
    final socket = _socket;
    final wasConnected = _isConnected;
    _socket = null;
    _socketAuthToken = null;
    _socketUserId = null;
    _isConnected = false;
    _connectionAttempts = 0;
    if (socket != null) {
      socket.disconnect();
      socket.dispose();
    }
    if (socket != null || wasConnected) _connectionController.add(false);
  }

  /// Disconnect from server and stop automatic recovery.
  void disconnect() {
    _connectionRequested = false;
    _cancelAuthRetry(resetCount: true);
    _cancelTransportRetry(resetCount: true);
    _userId = null;
    _authToken = null;
    _disposeSocket();
  }

  /// Start a custom heartbeat ping
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_isConnected && _socket != null) {
        _socket!.emit('ping-heartbeat', {
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  /// Stop the heartbeat ping
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Dispose resources
  /// Join a video room to receive interactions
  void joinVideoRoom(String videoId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('join-room', {'roomId': 'video-$videoId'});
  }

  /// Leave a video room
  void leaveVideoRoom(String videoId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('leave-room', {'roomId': 'video-$videoId'});
  }

  /// Record one video open as a cumulative view.
  void recordVideoView(String videoId) {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || !_isConnected || _socket == null) return;
    _socket!.emit('video-interaction', {
      'videoId': videoId,
      'userId': userId,
      'type': 'view',
      'value': 0,
    });
  }

  /// Send a video interaction (like, gift)
  void sendVideoInteraction(
    String videoId,
    String userId,
    String type, {
    int value = 0,
  }) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('video-interaction', {
      'videoId': videoId,
      'userId': userId,
      'type': type,
      'value': value,
    });
  }

  /// ✅ [Yield Way] ส่ง Route Polyline ของจิตอาสาเมื่อกดรับเหตุ
  void sendVolunteerRoute({
    required String videoId,
    required String responseId,
    required String encodedPolyline,
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('volunteer-route', {
      'videoId': videoId,
      'responseId': responseId,
      'encodedPolyline': encodedPolyline,
      'fromLat': fromLat,
      'fromLng': fromLng,
      'toLat': toLat,
      'toLng': toLng,
    });
    debugPrint('[Yield Way] Sent volunteer route for video $videoId');
  }

  /// ✅ [Yield Way] แจ้งเตือนผู้ใช้บนเส้นทางให้ทาง (เรียกจาก Admin/Server หรือ Flutter โดยตรง)
  void requestYieldWayNotification({
    required String videoId,
    required String responseId,
  }) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('request-yield-way-notification', {
      'videoId': videoId,
      'responseId': responseId,
    });
  }

  /// Dispose resources
  void dispose() {
    _tokenSub?.cancel();
    _tokenSub = null;
    if (_authUserLifecycleWatching) {
      AuthService.instance.removeListener(_handleAuthUserChanged);
      _authUserLifecycleWatching = false;
    }
    disconnect();
    _connectionController.close();
    _locationController.close();
    _errorController.close();
    _typingController.close();
    _callInviteController.close();
    _callAcceptController.close();
    _callRejectController.close();
    _webrtcSignalController.close();
    _videoProgressController.close();
    _videoStatusController.close();
    _videoInteractionController.close();
    _emergencyNotificationController.close();
    _rescueIncomingController.close();
    _incidentProfessionQuotaFilledController.close();
    _rescueCancelledController.close();
    _viewerCountController.close();
    _emergencyChatController.close();
    _thaiMhungPhotoController.close();
    _emergencyHealthSensorAlertController.close();
    _emergencyHealthDeadManReminderController.close();
    _emergencyHealthDeadManTriggeredController.close();
    _applicationNotificationController.close();
  }

  /// Send rescue status update
  void updateRescueStatus({
    required String videoId,
    required String volunteerId,
    required String status,
    required String responseId,
    String? victimId,
  }) {
    if (!_isConnected || _socket == null) return;

    _socket!.emit('rescue-status-update', {
      'videoId': videoId,
      'volunteerId': volunteerId,
      'victimId': victimId,
      'status': status,
      'responseId': responseId,
    });
  }
}
