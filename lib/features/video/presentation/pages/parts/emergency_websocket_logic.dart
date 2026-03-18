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
    _connectionSub = ws.connectionStream.listen((connected) { if (mounted) setState(() => _isConnected = connected); });

    if (_currentVideoId != null) {
      ws.joinVideoRoom(_currentVideoId!);
      _interactionSub = ws.videoInteractionStream.listen((data) {
        if (data['videoId'] == _currentVideoId) {
          if (mounted) {
            setState(() { if (data['type'] == 'like') _likeCount++; if (data['type'] == 'gift') _donationTotal += (data['value'] ?? 0); if (data['type'] == 'view') _viewerCount++; });
          }
        }
      });
      _supabaseInteractionSub = ServiceLocator.instance.videoRepository.subscribeToInteractions(_currentVideoId!, (payload) {
         if (mounted) { setState(() { if (payload['type'] == 'like') _likeCount++; if (payload['type'] == 'gift') _donationTotal += (payload['value'] ?? 0); if (payload['type'] == 'view') _viewerCount++; }); }
      });
    }

    _emergencySub = ws.emergencyNotificationStream.listen((data) {
      final currentUserId = AuthService.instance.userId?.toString();
      final reporterId = data['userId']?.toString() ?? data['senderId']?.toString();
      final bool isSelfReport = (reporterId != null && currentUserId != null) && (reporterId.trim() == currentUserId.trim());
      if (mounted && data['videoId'] != _currentVideoId && !isSelfReport) {
        setState(() { _highlightVideoId = data['videoId']; });
        _loadTrendingVideos();
      } else { _loadTrendingVideos(); }
    });

    _progressSub = ws.videoProgressStream.listen((data) {
      if (data['videoId'] == _currentVideoId && data['location'] != null) {
        final loc = data['location'];
        final point = LatLng(loc['lat'], loc['lng']);
        if (mounted) setState(() { _routePoints.add(point); });
      }
    });

    _rescueIncomingSub = ws.rescueIncomingStream.listen((data) {
      if (mounted) {
         final status = data['status'];
         String msg = '';
         if (status == 'accepted') { msg = 'กู้ภัยกำลังเดินทางมาหาคุณ...'; _loadResponders(); }
         else if (status == 'arrived') msg = 'กู้ภัยเดินทางมาถึงที่เกิดเหตุแล้ว!';
         else if (status == 'resolved') msg = 'ภารกิจของกู้ภัยเสร็จสิ้น!';
         if (msg.isNotEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.airport_shuttle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)))]), backgroundColor: status == 'resolved' ? Colors.green : Colors.orange.shade800, duration: const Duration(seconds: 5), behavior: SnackBarBehavior.floating)); }
      }
    });

    _locationSub = ws.locationStream.listen((data) {
      if (!mounted) return;
      final String? userId = data['userId'];
      if (userId == null) return;
      setState(() {
        bool found = false;
        for (int i = 0; i < _responders.length; i++) {
          if (_responders[i]['volunteer_id'] == userId || _responders[i]['id'] == userId) {
            _responders[i]['currentLat'] = data['latitude'];
            _responders[i]['currentLng'] = data['longitude'];
            if (data['speed'] != null) _responders[i]['currentSpeed'] = data['speed'];
            if (_routePoints.isNotEmpty) {
              final incidentPoint = _routePoints.last;
              final distanceMeters = Geolocator.distanceBetween(data['latitude'], data['longitude'], incidentPoint.latitude, incidentPoint.longitude);
              _responders[i]['distanceKm'] = distanceMeters / 1000.0;
              double speedMps = data['speed'] ?? 11.1; 
              if (speedMps < 2.0) speedMps = 11.1;
              _responders[i]['estimatedMinutes'] = (distanceMeters / speedMps / 60).round();
            }
            found = true;
          }
        }
        if (found) _adjustMapBounds();
      });
    });

    if (_currentVideoId != null) {
      _videoStatusSub = ws.videoStatusStream.listen((data) {
        if (data['videoId'] == _currentVideoId && data['status'] == 'ready') {
           final url = data['url'];
           if (url != null) _initializePlayer(url);
        }
      });
    }
  }
}
