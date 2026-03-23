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
            if (data['type'] == 'like') _likeCount++; 
            if (data['type'] == 'gift') _donationTotal += (data['value'] ?? 0); 
            // หมายเหตุ: ไม่นับ view ที่นี่ เพราะ viewerCountStream จัดการค่า unique viewers อยู่แล้ว
          });
        }
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
  }

  void _subscribeToVideoEvents(String videoId) {
    final ws = WebSocketService();
    ws.joinVideoRoom(videoId);
    
    // Supabase subscription (one-time or per video)
    _supabaseInteractionSub?.unsubscribe();
    _supabaseInteractionSub = ServiceLocator.instance.videoRepository.subscribeToInteractions(videoId, (payload) {
       if (mounted && _currentVideoId == videoId) { 
         setState(() { 
           if (payload['type'] == 'like') _likeCount++; 
           if (payload['type'] == 'gift') _donationTotal += (payload['value'] ?? 0); 
           // หมายเหตุ: ไม่นับ view ที่นี่ เพราะ viewerCountStream จัดการค่า unique viewers อยู่แล้ว
         }); 
       }
    });
  }
}
