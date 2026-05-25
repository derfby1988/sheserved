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
    if (_emergencyHealthData == null) {
      await _fetchEmergencyHealthData();
    }

    if (!mounted || _emergencyHealthData == null) return;

    final patient = _emergencyHealthData!['patient'] as Map<String, dynamic>? ?? {};
    final healthData = _emergencyHealthData!['healthData'] as Map<String, dynamic>? ?? {};
    final session = _emergencyHealthData!['session'] as Map<String, dynamic>? ?? {};
    final releasedFields = (session['releasedFields'] as List?)?.cast<String>() ?? [];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'ข้อมูลสุขภาพผู้ป่วย',
            style: TextStyle(fontFamily: 'SukhumvitSet', fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Patient info
                if (patient['name'] != null)
                  Text('ชื่อ: ${patient['name']}', style: const TextStyle(fontFamily: 'SukhumvitSet')),
                if (patient['phone'] != null)
                  Text('เบอร์โทร: ${patient['phone']}', style: const TextStyle(fontFamily: 'SukhumvitSet')),
                if (patient['emergencyContact'] != null)
                  Text('ติดต่อฉุกเฉิน: ${patient['emergencyContact']}', style: const TextStyle(fontFamily: 'SukhumvitSet')),
                if (patient['emergencyPhone'] != null)
                  Text('เบอร์ฉุกเฉิน: ${patient['emergencyPhone']}', style: const TextStyle(fontFamily: 'SukhumvitSet')),
                const Divider(height: 24),
                // Health data fields
                if (healthData['bloodType'] != null)
                  _buildHealthDataRow('กรุ๊ปเลือด', healthData['bloodType']),
                if (healthData['allergies'] != null)
                  _buildHealthDataRow('แพ้ยา/อาหาร', healthData['allergies']),
                if (healthData['chronicConditions'] != null)
                  _buildHealthDataRow('โรคประจำตัว', healthData['chronicConditions']),
                if (healthData['surgicalHistory'] != null)
                  _buildHealthDataRow('ประวัติผ่าตัด', healthData['surgicalHistory']),
                if ((healthData['prescriptions'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  const Text('ยาล่าสุด:', style: TextStyle(fontFamily: 'SukhumvitSet', fontWeight: FontWeight.bold)),
                  for (final p in healthData['prescriptions'] as List)
                    Text('- ${p['medications'] ?? p['notes'] ?? ''}', style: const TextStyle(fontFamily: 'SukhumvitSet')),
                ],
                if ((healthData['consultationNotes'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  const Text('บันทึกการรักษา:', style: TextStyle(fontFamily: 'SukhumvitSet', fontWeight: FontWeight.bold)),
                  for (final n in healthData['consultationNotes'] as List)
                    Text('- ${n['chief_complaint'] ?? n['diagnosis'] ?? ''}', style: const TextStyle(fontFamily: 'SukhumvitSet')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ปิด', style: TextStyle(fontFamily: 'SukhumvitSet')),
            ),
          ],
        );
      },
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
