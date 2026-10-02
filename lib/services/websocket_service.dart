import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../core/network/authenticated_http_client.dart';
import 'auth_service.dart';

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
  static const int _maxConnectionAttempts = 3;
  static const int _socketReconnectionAttempts = 10;
  Timer? _heartbeatTimer;
  Timer? _authRetryTimer;

  // socket.io bakes `auth` into the options at construction, so token changes
  // must rebuild the socket instead of relying on its internal reconnect.
  String? _userId;
  String? _authToken;
  StreamSubscription<String?>? _tokenSub;
  bool _authUserLifecycleWatching = false;
  bool _connectionRequested = false;
  bool _handlingAuthFailure = false;
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
    _connectionAttempts = 0;
    _connectionErrorLogCount = 0;
    _lastConnectionErrorLogAt = null;
  }

  /// Connect to WebSocket Server
  Future<void> connect({String? userId, String? authToken}) async {
    if (!_isEnabled) {
      debugPrint('WebSocket is disabled');
      return;
    }
    authToken ??= AuthenticatedHttpClient.instance.accessToken;
    if (AppConfig.useBackendAuth && userId != null && authToken == null) {
      _errorController.add('Verified login required for realtime updates');
      disconnect();
      return;
    }
    _connectionRequested = true;
    _authRetryTimer?.cancel();
    _authRetryTimer = null;

    // socket.io bakes `auth` into the options at construction, so an existing
    // socket must never be reused once the identity/token we hold differs —
    // otherwise a refreshed token would never reach the handshake and the
    // connection would keep failing with the stale one.
    if (_socket != null && (authToken != _authToken || userId != _userId)) {
      _disposeSocket();
    }

    if (_isConnected) {
      debugPrint('WebSocket already connected');
      return;
    }

    if (_socket != null) {
      _socket!.connect();
      return;
    }

    // W3.5: remember the credentials this socket was created with so a
    // token rotation can rebuild the connection with the fresh token.
    _userId = userId;
    _authToken = authToken;
    _watchTokenLifecycle();
    _watchAuthUserLifecycle();

    // Check connection attempts to prevent infinite retry
    if (_connectionAttempts >= _maxConnectionAttempts) {
      debugPrint(
        'WebSocket: Max connection attempts reached. Call resetConnectionAttempts() to retry.',
      );
      _errorController.add(
        'Max connection attempts reached. Server may not be running.',
      );
      return;
    }

    _connectionAttempts++;

    try {
      _socket = IO.io(
        _serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect() // Changed to true for background resilience
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setReconnectionAttempts(_socketReconnectionAttempts)
            .setRandomizationFactor(0.5)
            .setAuth({'userId': userId, 'token': authToken})
            .build(),
      );

      final socket = _socket!;

      // Connection Events
      socket.onConnect((_) {
        if (!identical(_socket, socket)) return;
        debugPrint('WebSocket connected');
        _isConnected = true;
        _connectionAttempts = 0;
        _authRecoveryAttempts = 0;
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

      socket.onDisconnect((_) {
        if (!identical(_socket, socket)) return;
        debugPrint('WebSocket disconnected');
        _isConnected = false;
        _connectionController.add(false);
      });

      socket.onConnectError((error) {
        if (!identical(_socket, socket)) return;
        _isConnected = false;
        _connectionErrorLogCount++;
        final now = DateTime.now();
        final shouldLog =
            _connectionErrorLogCount <= 3 ||
            _lastConnectionErrorLogAt == null ||
            now.difference(_lastConnectionErrorLogAt!) >=
                const Duration(seconds: 30);
        if (shouldLog) {
          _lastConnectionErrorLogAt = now;
          debugPrint('WebSocket connection error: $error');
          debugPrint(
            'Tip: Make sure the WebSocket server is running (cd websocket-server && npm start)',
          );
        }
        _errorController.add('Connection error: $error');

        if (_isSocketAuthError(error)) {
          unawaited(_handleSocketAuthFailure(source: socket));
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
          unawaited(_handleSocketAuthFailure(source: socket));
        }
      });

      // เชื่อมต่อหลังจาก setup events แล้ว
      socket.connect();
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
      debugPrint('WebSocket not connected');
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
        disconnect();
        return;
      }
      if (token == _authToken) return;

      final userId = _userId;
      _authToken = token;
      _cancelAuthRetry(resetCount: true);
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
    _disposeSocket();
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

  void _scheduleAuthRetry() {
    if (_authRetryTimer != null ||
        !_connectionRequested ||
        !_isEnabled ||
        _userId == null ||
        _authToken == null) {
      return;
    }

    const delaysInSeconds = [5, 15, 30];
    final delayIndex = _authRetryCount < delaysInSeconds.length
        ? _authRetryCount
        : delaysInSeconds.length - 1;
    _authRetryCount++;
    _authRetryTimer = Timer(Duration(seconds: delaysInSeconds[delayIndex]), () {
      _authRetryTimer = null;
      if (!_connectionRequested || !_isEnabled) return;
      unawaited(_handleSocketAuthFailure());
    });
  }

  bool _isSocketAuthError(dynamic error) =>
      error.toString().contains('Authentication failed');

  Future<void> _handleSocketAuthFailure({IO.Socket? source}) async {
    if ((source != null && !identical(_socket, source)) ||
        _handlingAuthFailure) {
      return;
    }
    _handlingAuthFailure = true;
    final failedToken = _authToken;
    final failedUserId = _userId;
    try {
      if (failedToken == null) {
        disconnect();
        _errorController.add('Realtime updates require a valid login');
        return;
      }
      if (_authRecoveryAttempts >= _maxAuthRecoveries) {
        disconnect();
        _errorController.add(
          'Realtime updates unavailable — please log in again',
        );
        return;
      }

      final client = AuthenticatedHttpClient.instance;
      final result = await client.refreshTokens();
      final token = client.accessToken;
      if (result == TokenRefreshResult.refreshed &&
          token != null &&
          token != failedToken &&
          failedUserId == _userId) {
        _authRecoveryAttempts++;
      }
      if (failedToken != _authToken ||
          failedUserId != _userId ||
          (source != null && !identical(_socket, source))) {
        return;
      }

      switch (result) {
        case TokenRefreshResult.refreshed:
          if (token == null || token == failedToken) {
            _disposeSocket();
            _errorController.add(
              'Realtime updates temporarily unavailable; retrying',
            );
            _scheduleAuthRetry();
            return;
          }
          return;
        case TokenRefreshResult.rejected:
          _disposeSocket();
          if (AuthService.instance.currentUser != null) {
            try {
              await AuthService.instance.logout();
            } catch (_) {}
          }
          _errorController.add('Session expired — please log in again');
          return;
        case TokenRefreshResult.unavailable:
          _disposeSocket();
          _errorController.add(
            'Realtime authentication temporarily unavailable; retrying',
          );
          _scheduleAuthRetry();
          return;
        case TokenRefreshResult.missingRefreshToken:
          _disposeSocket();
          _errorController.add(
            'Realtime updates unavailable — please log in again',
          );
          return;
      }
    } catch (error) {
      _disposeSocket();
      _errorController.add(
        'Realtime authentication temporarily unavailable; retrying',
      );
      _scheduleAuthRetry();
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
    final socket = _socket;
    final wasConnected = _isConnected;
    _socket = null;
    _isConnected = false;
    if (socket != null) {
      socket.disconnect();
      socket.dispose();
      resetConnectionAttempts();
    }
    if (socket != null || wasConnected) _connectionController.add(false);
  }

  /// Disconnect from server and stop automatic recovery.
  void disconnect() {
    _connectionRequested = false;
    _cancelAuthRetry(resetCount: true);
    _authRecoveryAttempts = 0;
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
