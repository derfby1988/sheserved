part of '../emergency_live_page.dart';

extension EmergencyWebSocketLogic on _EmergencyLivePageState {
  Future<void> _ensureWebSocketConnected() async {
    final ws = WebSocketService();
    final userId = ServiceLocator.instance.currentUser?.id;
    if (userId != null && !ws.isConnected) {
      ws.resetConnectionAttempts();
      await ws.connect(userId: userId);
    }
  }

  Future<void> _loadDeadManCheckinState() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;

    if (mounted) {
      setState(() => _isDeadManLoading = true);
    }

    try {
      final checkin = await ServiceLocator.instance.emergencyDeadManRepository.fetchCheckin(userId);
      if (!mounted) return;
      setState(() {
        _deadManCheckin = checkin;
      });
    } catch (e) {
      debugPrint('[EmergencyHealth] Failed to load dead-man state: $e');
    } finally {
      if (mounted) {
        setState(() => _isDeadManLoading = false);
      }
    }
  }

  Future<void> _checkInNow() async {
    final userId = AuthService.instance.userId;
    if (userId == null || _isDeadManCheckingIn) return;

    setState(() => _isDeadManCheckingIn = true);
    try {
      await ServiceLocator.instance.emergencyDeadManRepository.updateCheckInTimestamp(userId: userId);
      await _loadDeadManCheckinState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เช็กอินเรียบร้อยแล้ว'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[EmergencyHealth] Dead-man check-in failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เช็กอินไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeadManCheckingIn = false);
      }
    }
  }

  Widget _buildDeadManCheckInChip() {
    final checkin = _deadManCheckin;
    final lastCheckInText = checkin?.lastCheckInAt != null
        ? DateFormat('dd/MM HH:mm').format(checkin!.lastCheckInAt!.toLocal())
        : 'ยังไม่เคยเช็กอิน';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _isDeadManLoading || _isDeadManCheckingIn ? null : _checkInNow,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.teal.shade700.withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withOpacity(0.25),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isDeadManLoading || _isDeadManCheckingIn)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              else
                const Icon(Icons.verified_user_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isDeadManCheckingIn ? 'กำลังเช็กอิน...' : 'เช็กอินตอนนี้',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'SukhumvitSet',
                    ),
                  ),
                  Text(
                    'ล่าสุด: $lastCheckInText',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: 11,
                      fontFamily: 'SukhumvitSet',
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.touch_app, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _setupWebSocketStreams() {
    final ws = WebSocketService();
    _connectionSub?.cancel();
    _connectionSub = ws.connectionStream.listen((connected) { if (mounted) setState(() => _isConnected = connected); });

    // Video Interaction & Viewer Count (Always listen, filter by _currentVideoId)
    _interactionSub?.cancel();
    _interactionSub = ws.videoInteractionStream.listen((data) {
      if (_currentVideoId != null && data['videoId'] == _currentVideoId) {
        if (mounted) {
          setState(() {
            // ✅ 'like' count is handled via 'like-count-updated' event (see socket listener below)
            // Do NOT increment here to avoid double-counting with HTTP toggle
            if (data['type'] == 'yield-way-updated') {
              _yieldWayCount = (data['count'] as num?)?.toInt() ?? 0;
              _yieldWayNotifiedCount = (data['notifiedCount'] as num?)?.toInt() ?? 0; // ✅ รับค่าจำนวนที่แจ้งเตือนไปจาก Server
              if (data['triggerAnimation'] == true) {
                _triggerYieldPulse();
              }
            }
            if (data['type'] == 'gift') {
              // ✅ อัปเดตยอดตาม requestId ถ้ามี (ไม่ใช้ตัวแปรเดียวอีกต่อไป)
              final reqId = data['requestId']?.toString();
              final amount = (data['value'] as num?)?.toDouble() ?? 0.0;
              if (reqId != null && reqId.isNotEmpty) {
                _requestTotals[reqId] = (_requestTotals[reqId] ?? 0) + amount;
              }
            }
          });
        }
      }
    });

    // ✅ [Support Analytics] Real-time like count from other users
    ws.socket?.on('like-count-updated', (data) {
      if (!mounted) return;
      final Map<String, dynamic> payload =
          (data is Map) ? Map<String, dynamic>.from(data) : {};
      if (payload['videoId'] == _currentVideoId) {
        setState(() {
          _likeCount = (payload['count'] as num?)?.toInt() ?? _likeCount;
          _likeTrigger++; // ✅ Force chart refresh on remote like events
        });
      }
    });

    _viewerCountSub?.cancel();
    _viewerCountSub = ws.viewerCountStream.listen((data) {
      if (_currentVideoId != null && data['videoId'] == _currentVideoId) {
        if (mounted) setState(() => _viewerCount = data['count'] ?? 0);
      }
    });

    _progressSub?.cancel();
    _progressSub = ws.videoProgressStream.listen((data) {
      if (_currentVideoId != null && data['videoId'] == _currentVideoId && data['location'] != null) {
        final loc = data['location'];
        final point = LatLng(loc['lat'], loc['lng']);
        if (mounted) setState(() { _routePoints.add(point); });
      }
    });

    if (_currentVideoId != null) {
      _subscribeToVideoEvents(_currentVideoId!);
    }

    _emergencySub?.cancel();
    _emergencySub = ws.emergencyNotificationStream.listen((data) {
      final currentUserId = AuthService.instance.userId?.toString();
      final reporterId = data['userId']?.toString() ?? data['senderId']?.toString();
      final bool isSelfReport = (reporterId != null && currentUserId != null) && (reporterId.trim() == currentUserId.trim());
      if (mounted && data['videoId'] != _currentVideoId && !isSelfReport) {
        setState(() { _highlightVideoId = data['videoId']; });
        _loadTrendingVideos();
      } else { 
        _loadTrendingVideos(); 
      }

      // ✅ ถ้าเป็นไทยมุงแจ้งภาพในเหตุการณ์ที่กำลังเปิดอยู่ ให้รีโหลด Gallery
      if (data['type'] == 'photo' && data['incidentId'] == _currentVideoId) {
        _loadGalleryPhotos();
      }
    });

    _rescueIncomingSub?.cancel();
    _rescueIncomingSub = ws.rescueIncomingStream.listen((data) {
      if (mounted) {
         final status = data['status'];
         String msg = '';
         if (status == 'accepted') { msg = 'กู้ภัยกำลังเดินทางมาหาคุณ...'; _loadResponders(); }
         else if (status == 'arrived') msg = 'กู้ภัยเดินทางมาถึงที่เกิดเหตุแล้ว!';
         else if (status == 'resolved') msg = 'ภารกิจของกู้ภัยเสร็จสิ้น!';
         
         if (msg.isNotEmpty) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
             content: Row(children: [
               const Icon(Icons.airport_shuttle, color: Colors.white), 
               const SizedBox(width: 8), 
               Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)))
             ]), 
             backgroundColor: status == 'resolved' ? Colors.green : Colors.blueAccent, 
             duration: const Duration(seconds: 5), 
             behavior: SnackBarBehavior.floating,
           ));
         }
      }
    });

    _locationSub?.cancel();
    _locationSub = ws.locationStream.listen((data) {
      if (!mounted) return;
      final String? userId = data['userId'];
      if (userId == null) return;
      setState(() {
        bool found = false;
        for (int i = 0; i < _responders.length; i++) {
          if (_responders[i]['userId'] == userId) {
            _responders[i]['latitude'] = data['latitude'];
            _responders[i]['longitude'] = data['longitude'];
            found = true;
            break;
          }
        }
        if (!found) {
          _responders.add({
            'userId': userId,
            'latitude': data['latitude'],
            'longitude': data['longitude'],
            'fullName': data['fullName'] ?? 'Responder',
          });
        }
      });
    });

    _yieldWayAlertSub?.cancel();
    _yieldWayAlertSub = ws.yieldWayAlertStream.listen((data) {
      if (mounted) {
        _showYieldWayDialog(data);
      }
    });

    _emergencyHealthSensorAlertSub?.cancel();
    _emergencyHealthSensorAlertSub = ws.emergencyHealthSensorAlertStream.listen((data) {
      if (!mounted) return;
      _showEmergencyHealthSensorAlert(data);
    });

    _emergencyHealthDeadManReminderSub?.cancel();
    _emergencyHealthDeadManReminderSub = ws.emergencyHealthDeadManReminderStream.listen((data) {
      if (!mounted) return;
      _showEmergencyHealthDeadManReminder(data);
    });

    _emergencyHealthDeadManTriggeredSub?.cancel();
    _emergencyHealthDeadManTriggeredSub = ws.emergencyHealthDeadManTriggeredStream.listen((data) {
      if (!mounted) return;
      _showEmergencyHealthDeadManTriggered(data);
    });

    // ✅ [Phase 3a] Listen for emergency health data release broadcast
    ws.socket?.on('emergency-health-released', (data) {
      if (!mounted) return;
      final payload = (data is Map) ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (payload['incidentId']?.toString() == _currentVideoId) {
        _handleEmergencyHealthReleased(payload);
      }
    });
  }

  void _subscribeToVideoEvents(String videoId) {
    final ws = WebSocketService();
    ws.joinVideoRoom(videoId);
    
    // Supabase subscription (one-time or per video)
    _supabaseInteractionSub?.unsubscribe();
    _supabaseInteractionSub = ServiceLocator.instance.videoRepository.subscribeToInteractions(videoId, (payload) {
       if (mounted && _currentVideoId == videoId) { 
         setState(() { 
           // ✅ Supabase fallback: only update if we're offline or count hasn't been set by socket
           // Do NOT increment blindly — like count is controlled by 'like-count-updated' event
           // This ensures no double-counting between WebSocket and Supabase realtime
         }); 
       }
    });
  }

  Future<void> _maybeStartEmergencyHealthReleaseSession({
    required String videoId,
  }) async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;

    try {
      final settings = await ServiceLocator.instance.emergencyHealthSettingsRepository.fetchSettings(userId);
      if (settings == null || !settings.isEnabled || settings.consentGivenAt == null) {
        debugPrint('[EmergencyHealth] Auto-release is disabled or consent missing for user=$userId');
        return;
      }

      final ws = WebSocketService();
      final result = await ws.createEmergencyHealthReleaseSession(
        patientId: userId,
        incidentId: videoId,
        videoId: videoId,
      );

      if (!mounted || result == null) return;

      final session = result['session'];
      if (session is! Map) return;

      _bindEmergencyHealthSession(Map<String, dynamic>.from(session));
    } catch (e) {
      debugPrint('[EmergencyHealth] Failed to start release session: $e');
    }
  }

  void _bindEmergencyHealthSession(Map<String, dynamic> session) {
    final sessionId = session['id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;

    _emergencyHealthSession = session;

    final status = session['status']?.toString();
    if (status != 'counting') {
      _handleEmergencyHealthSessionUpdate(session);
      return;
    }

    _startEmergencyHealthCountdown(session);

    _emergencyHealthSessionSub?.unsubscribe();
    _emergencyHealthSessionSub = Supabase.instance.client
        .channel('eh_session_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'emergency_health_release_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: sessionId,
          ),
          callback: (payload) {
            final updated = payload.newRecord;
            if (updated is Map<String, dynamic>) {
              _handleEmergencyHealthSessionUpdate(updated);
            } else if (updated is Map) {
              _handleEmergencyHealthSessionUpdate(Map<String, dynamic>.from(updated));
            }
          },
        )
        .subscribe();

    if (!_hasPlayedEmergencyHealthAlert) {
      _hasPlayedEmergencyHealthAlert = true;
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }

    if (mounted) {
      setState(() {
        _isEmergencyHealthPanicVisible = true;
      });
    }
  }

  void _handleEmergencyHealthSessionUpdate(Map<String, dynamic> updatedSession) {
    _emergencyHealthSession = updatedSession;
    final status = updatedSession['status']?.toString();

    if (status == 'counting') {
      _startEmergencyHealthCountdown(updatedSession);
      if (mounted) {
        setState(() => _isEmergencyHealthPanicVisible = true);
      }
      return;
    }

    _stopEmergencyHealthCountdown();
    _emergencyHealthSessionSub?.unsubscribe();
    _emergencyHealthSessionSub = null;
    _hasPlayedEmergencyHealthAlert = false;
    if (mounted) {
      setState(() => _isEmergencyHealthPanicVisible = false);
    }

    if (!mounted) return;

    if (status == 'cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ยกเลิกการปลดล็อกข้อมูลสุขภาพแล้ว'),
          backgroundColor: Colors.grey,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (status == 'released') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ถึงเวลาปลดล็อกข้อมูลสุขภาพแล้ว'),
          backgroundColor: Colors.deepOrange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _startEmergencyHealthCountdown(Map<String, dynamic> session) {
    _stopEmergencyHealthCountdown();

    final triggeredAt = DateTime.tryParse(session['triggered_at']?.toString() ?? '');
    final delayMinutes = int.tryParse(session['release_delay_minutes']?.toString() ?? '') ?? 5;
    final dueAt = triggeredAt != null
        ? triggeredAt.add(Duration(minutes: delayMinutes))
        : DateTime.now().add(Duration(minutes: delayMinutes));

    void refreshCountdown() {
      final remaining = dueAt.difference(DateTime.now()).inSeconds;
      _emergencyHealthCountdownSeconds = remaining > 0 ? remaining : 0;
      if (mounted) {
        setState(() {
          _isEmergencyHealthPanicVisible = true;
        });
      }
    }

    refreshCountdown();
    _emergencyHealthCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      refreshCountdown();
      if (_emergencyHealthCountdownSeconds <= 0) {
        _emergencyHealthCountdownTimer?.cancel();
        _emergencyHealthCountdownTimer = null;
      }
    });
  }

  void _stopEmergencyHealthCountdown() {
    _emergencyHealthCountdownTimer?.cancel();
    _emergencyHealthCountdownTimer = null;
    _emergencyHealthCountdownSeconds = 0;
  }

  Future<void> _cancelEmergencyHealthSession() async {
    final sessionId = _emergencyHealthSession?['id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;

    final userId = AuthService.instance.userId;
    if (userId == null) return;

    try {
      await Supabase.instance.client
          .from('emergency_health_release_sessions')
          .update({
            'status': 'cancelled',
            'panic_cancelled_at': AppConfig.currentUtc.toIso8601String(),
            'updated_at': AppConfig.currentUtc.toIso8601String(),
          })
          .eq('id', sessionId)
          .eq('patient_id', userId);

      if (mounted) {
        setState(() {
          _isEmergencyHealthPanicVisible = false;
        });
      }
    } catch (e) {
      debugPrint('[EmergencyHealth] Cancel session failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ยกเลิกไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showYieldWayDialog(Map<String, dynamic> data) {
    if (!mounted) return;

    // ✅ เงื่อนไขเพิ่มเติม: ถ้าเป็นคนแจ้งเหตุเอง (Reporter) ไม่ต้องเด้ง Dialog ให้ทางสำหรับงานของตัวเอง
    final currentUserId = AuthService.instance.userId?.toString();
    final reporterId = data['reporterId']?.toString() ?? data['victimId']?.toString();
    
    if (currentUserId != null && reporterId != null && currentUserId.trim() == reporterId.trim()) {
      debugPrint('[Yield Way] Suppressing alert dialog because user is the reporter of this incident.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => YieldWayMapDialog(
        alertData: data,
        onYield: () {
          // Dialog handles the interaction emit, we just need to maybe show a snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ขอบคุณที่ช่วยเปิดทางให้รถฉุกเฉิน 🙏'),
              backgroundColor: Colors.green,
            ),
          );
        },
        onDecline: () {},
      ),
    );
  }

  void _showEmergencyHealthSensorAlert(Map<String, dynamic> data) {
    final reasons = (data['reasons'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? const [];
    final message = reasons.isNotEmpty
        ? 'ตรวจพบความผิดปกติ: ${reasons.join(' • ')}'
        : 'ตรวจพบความผิดปกติของข้อมูลสุขภาพ';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.deepOrange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showEmergencyHealthDeadManReminder(Map<String, dynamic> data) {
    final reminderFor = data['reminderFor']?.toString();
    final intervalMinutes = data['intervalMinutes']?.toString();
    final message = reminderFor != null && intervalMinutes != null
        ? 'กรุณาเช็กอินภายใน $intervalMinutes นาที (เตือนครั้งถัดไป: ${DateTime.tryParse(reminderFor)?.toLocal().toString() ?? reminderFor})'
        : 'กรุณาเช็กอินตอนนี้เพื่อยืนยันว่าคุณปลอดภัย';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _showEmergencyHealthDeadManTriggered(Map<String, dynamic> data) {
    final nextCheckInAt = data['nextCheckInAt']?.toString();
    final message = nextCheckInAt != null
        ? 'Dead Man’s Switch ถูกกระตุ้นแล้ว • รอบถัดไป: ${DateTime.tryParse(nextCheckInAt)?.toLocal().toString() ?? nextCheckInAt}'
        : 'Dead Man’s Switch ถูกกระตุ้นแล้ว';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 7),
      ),
    );
  }

  // ── Phase 3a: Emergency Health Data Access for Responders ──

  void _subscribeToEmergencyHealthTokens() {
    final userId = AuthService.instance.userId;
    if (userId == null || _currentVideoId == null) return;

    _emergencyHealthTokenSub?.unsubscribe();
    _emergencyHealthTokenSub = Supabase.instance.client
        .channel('eh_tokens_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'emergency_health_access_tokens',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'responder_id',
            value: userId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord == null) return;
            final incidentId = newRecord['incident_id']?.toString();
            if (incidentId != null && incidentId == _currentVideoId) {
              _handleEmergencyHealthReleased({
                'incidentId': incidentId,
                'sessionId': newRecord['session_id']?.toString(),
              });
            }
          },
        )
        .subscribe();
  }

  void _handleEmergencyHealthReleased(Map<String, dynamic> payload) {
    if (!mounted) return;

    final incidentId = payload['incidentId']?.toString();
    if (incidentId == null || incidentId != _currentVideoId) return;

    setState(() {
      _isEmergencyHealthDataAvailable = true;
    });

    _fetchEmergencyHealthData();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ข้อมูลสุขภาพผู้ป่วยพร้อมให้เข้าถึงแล้ว'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _fetchEmergencyHealthData() async {
    final userId = AuthService.instance.userId;
    final videoId = _currentVideoId;
    if (userId == null || videoId == null) return;

    try {
      final ws = WebSocketService();
      final result = await ws.getIncidentHealthData(
        incidentId: videoId,
        responderId: userId,
      );

      if (!mounted || result == null) return;

      if (result['allowed'] == true) {
        setState(() {
          _emergencyHealthData = result;
          _isEmergencyHealthDataAvailable = true;
        });
      }
    } catch (e) {
      debugPrint('[EmergencyHealth] fetch data error: $e');
    }
  }

  Future<void> _showEmergencyHealthDataDialog() async {
    if (_emergencyHealthData == null && _isEmergencyHealthDataAvailable) {
      await _fetchEmergencyHealthData();
    }

    if (!mounted) return;

    final sessionStatus = _emergencyHealthSession?['status']?.toString();

    // Determine which state to show
    if (_emergencyHealthData != null && _emergencyHealthData!['allowed'] == true) {
      _showReleasedHealthDataDialog();
      return;
    }

    if (sessionStatus == 'counting') {
      _showLockedHealthDataDialog(isCounting: true);
      return;
    }

    if (sessionStatus == 'cancelled') {
      _showLockedHealthDataDialog(isCancelled: true);
      return;
    }

    // No session or no data available
    _showLockedHealthDataDialog();
  }

  void _showReleasedHealthDataDialog() {
    if (!mounted || _emergencyHealthData == null) return;

    final patient = _emergencyHealthData!['patient'] as Map<String, dynamic>? ?? {};
    final healthData = _emergencyHealthData!['healthData'] as Map<String, dynamic>? ?? {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.medical_services, color: Colors.green.shade700),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ข้อมูลสุขภาพผู้ป่วย',
                                style: TextStyle(
                                  fontFamily: 'SukhumvitSet',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                'ปลดล็อกแล้ว • เข้าถึงได้',
                                style: TextStyle(
                                  fontFamily: 'SukhumvitSet',
                                  color: Colors.green.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      children: [
                        // Patient info card
                        _buildPatientInfoCard(patient),
                        const SizedBox(height: 16),
                        // Health data fields
                        if (healthData['bloodType'] != null)
                          _buildHealthDataCard('กรุ๊ปเลือด', healthData['bloodType'], Icons.water_drop),
                        if (healthData['allergies'] != null)
                          _buildHealthDataCard('แพ้ยา/อาหาร', healthData['allergies'], Icons.warning_amber),
                        if (healthData['chronicConditions'] != null)
                          _buildHealthDataCard('โรคประจำตัว', healthData['chronicConditions'], Icons.healing),
                        if (healthData['surgicalHistory'] != null)
                          _buildHealthDataCard('ประวัติผ่าตัด', healthData['surgicalHistory'], Icons.local_hospital),
                        if ((healthData['prescriptions'] as List?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 16),
                          _buildSectionHeader('ยาล่าสุด', Icons.medication),
                          for (final p in healthData['prescriptions'] as List)
                            _buildListTile(p['medications'] ?? p['notes'] ?? ''),
                        ],
                        if ((healthData['consultationNotes'] as List?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 16),
                          _buildSectionHeader('บันทึกการรักษา', Icons.description),
                          for (final n in healthData['consultationNotes'] as List)
                            _buildListTile(n['chief_complaint'] ?? n['diagnosis'] ?? ''),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLockedHealthDataDialog({bool isCounting = false, bool isCancelled = false}) {
    if (!mounted) return;

    final session = _emergencyHealthSession;
    final triggeredAt = session?['triggered_at'] != null
        ? DateTime.tryParse(session!['triggered_at'].toString())
        : null;
    final delayMinutes = (session?['release_delay_minutes'] as num?)?.toInt() ?? 5;
    final remainingSec = triggeredAt != null
        ? (delayMinutes * 60) - DateTime.now().difference(triggeredAt).inSeconds
        : 0;
    final remainingMin = (remainingSec / 60).ceil().clamp(0, delayMinutes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.6,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        const SizedBox(height: 16),
                        // Lock icon with blur effect (Privacy Mask)
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Blurred placeholder content behind lock
                              Container(
                                width: 200,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                    child: Container(
                                      color: Colors.grey.shade200.withOpacity(0.5),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(width: 80, height: 12, color: Colors.grey.shade300),
                                          const SizedBox(height: 8),
                                          Container(width: 120, height: 12, color: Colors.grey.shade300),
                                          const SizedBox(height: 8),
                                          Container(width: 60, height: 12, color: Colors.grey.shade300),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Lock icon overlay
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isCancelled ? Colors.grey.shade700 : Colors.orange.shade700,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isCancelled ? Icons.lock : Icons.lock_clock,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          isCancelled
                              ? 'ข้อมูลสุขภาพถูกยกเลิก'
                              : (isCounting
                                  ? 'ข้อมูลสุขภาพกำลังถูกปลดล็อก'
                                  : 'ข้อมูลสุขภาพไม่พร้อมใช้งาน'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'SukhumvitSet',
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isCancelled ? Colors.grey.shade700 : Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isCancelled
                              ? 'ผู้ป่วยได้ยกเลิกการแชร์ข้อมูลสุขภาพสำหรับเหตุการณ์นี้'
                              : (isCounting
                                  ? 'ข้อมูลสุขภาพจะถูกปลดล็อกให้ผู้ช่วยเหลือที่ผ่านเงื่อนไขในอีก $remainingMin นาที'
                                  : 'ไม่มีข้อมูลสุขภาพที่เปิดใช้งานสำหรับเหตุการณ์นี้'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'SukhumvitSet',
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (isCounting && remainingMin > 0)
                          LinearProgressIndicator(
                            value: 1.0 - (remainingMin / delayMinutes),
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade700),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPatientInfoCard(Map<String, dynamic> patient) {
    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.person, color: Colors.blue.shade700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient['name'] ?? 'ไม่ระบุชื่อ',
                        style: const TextStyle(
                          fontFamily: 'SukhumvitSet',
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (patient['phone'] != null)
                        Text(
                          'เบอร์โทร: ${patient['phone']}',
                          style: TextStyle(
                            fontFamily: 'SukhumvitSet',
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (patient['emergencyContact'] != null || patient['emergencyPhone'] != null) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Icon(Icons.emergency, color: Colors.red.shade400, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${patient['emergencyContact'] ?? ''} ${patient['emergencyPhone'] ?? ''}',
                      style: const TextStyle(fontFamily: 'SukhumvitSet', fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthDataCard(String label, dynamic value, IconData icon) {
    final displayValue = value is List ? value.join(', ') : value.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: Colors.grey.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.teal.shade700, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'SukhumvitSet',
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayValue,
                      style: const TextStyle(
                        fontFamily: 'SukhumvitSet',
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.teal.shade700, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'SukhumvitSet',
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildListTile(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.teal.shade300,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'SukhumvitSet', fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthDataRow(String label, dynamic value) {
    final displayValue = value is List ? value.join(', ') : value.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontFamily: 'SukhumvitSet', fontWeight: FontWeight.bold)),
          Expanded(child: Text(displayValue, style: const TextStyle(fontFamily: 'SukhumvitSet'))),
        ],
      ),
    );
  }

  void _unsubscribeEmergencyHealthTokens() {
    _emergencyHealthTokenSub?.unsubscribe();
    _emergencyHealthTokenSub = null;
  }
}
