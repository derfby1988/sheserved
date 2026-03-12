import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../../../config/app_config.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/service_locator.dart';

/// หน้าสำหรับจิตอาสา (Rescue Page) - Phase 3 Production-Ready
class RescuePage extends StatefulWidget {
  const RescuePage({super.key});

  @override
  State<RescuePage> createState() => _RescuePageState();
}

class _RescuePageState extends State<RescuePage> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  StreamSubscription? _emergencySub;
  List<Map<String, dynamic>> _activeEmergencies = [];
  bool _isAssisting = false;
  bool _isLoading = true;
  bool _isVolunteerActive = true;
  
  String? _activeResponseId;
  String _currentAssistingStatus = 'accepted';
  Map<String, dynamic>? _selectedEmergency;
  
  String _distanceString = '';
  String _durationString = '';
  LatLng? _volunteerLoc;
  LatLng? _emergencyLoc;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _setupWebSocket();
    await _checkActiveRescues();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _checkActiveRescues() async {
    final user = ServiceLocator.instance.currentUser;
    if (user == null) return;

    try {
      final active = await ServiceLocator.instance.videoRepository.getActiveRescues(user.id);
      if (active.isNotEmpty && mounted) {
        final job = active.first;
        final videoData = job['videos'];
        final videoId = videoData['id'] as String;
        
        setState(() {
          _isAssisting = true;
          _activeResponseId = job['id'];
          _currentAssistingStatus = job['status'];
          _selectedEmergency = {
             'videoId': videoId,
             'type': videoData['type'],
             'senderId': videoData['user_id'],
             'text': 'กำลังให้ความช่วยเหลือ',
          };
        });
        
        // Fetch real GPS location from DB
        final loc = await ServiceLocator.instance.videoRepository.getEmergencyLocation(videoId);
        if (loc != null) {
          _emergencyLoc = LatLng(loc['latitude']!, loc['longitude']!);
        } else {
          _emergencyLoc = const LatLng(13.7300, 100.5600); // Fallback
        }
        
        try {
          Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          _volunteerLoc = LatLng(pos.latitude, pos.longitude);
          await _drawRouteToEmergency(_volunteerLoc!, _emergencyLoc!);
        } catch (e) {
          debugPrint('Error restoring location: $e');
        }
      }
    } catch (e) {
      debugPrint('Error checking active rescues: $e');
    }
  }

  void _setupWebSocket() {
    _emergencySub = WebSocketService().emergencyNotificationStream.listen((data) {
      if (mounted) {
        setState(() {
          _activeEmergencies.insert(0, data);
        });
        if (!_isAssisting) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['text'] ?? 'มีผู้ขอความช่วยเหลือฉุกเฉินใหม่!'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'ดูรายละเอียด',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _emergencySub?.cancel();
    super.dispose();
  }

  // ============== RESCUE ACTIONS ==============

  void _acceptRescue(Map<String, dynamic> alert) async {
    final user = ServiceLocator.instance.currentUser;
    if (user == null) return;
    
    setState(() {
      _isAssisting = true;
      _selectedEmergency = alert;
      _currentAssistingStatus = 'accepted';
      _activeEmergencies.remove(alert); 
    });
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('รับงานเรียบร้อย ระบบกำลังคำนวณเส้นทาง...'), backgroundColor: Colors.green),
    );
    
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _volunteerLoc = LatLng(pos.latitude, pos.longitude);

      // Save to DB with volunteer start location
      _activeResponseId = await ServiceLocator.instance.videoRepository.acceptRescue(
         videoId: alert['videoId'], 
         volunteerId: user.id,
         startLat: pos.latitude,
         startLng: pos.longitude,
      );
      
      // Notify victim via WebSocket
      WebSocketService().sendRescueStatusUpdate(
         videoId: alert['videoId'], 
         volunteerId: user.id, 
         status: 'accepted',
         victimId: alert['senderId'],
         responseId: _activeResponseId,
      );
      
      double parseDouble(dynamic value) {
        if (value == null) return 0.0;
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0.0;
        return 0.0;
      }
      // Use real GPS from WebSocket payload, fallback to DB query
      final lat = alert['latitude'];
      final lng = alert['longitude'];
      if (lat != null && lng != null) {
        _emergencyLoc = LatLng(parseDouble(lat), parseDouble(lng));
      } else if (alert['videoId'] != null) {
        final loc = await ServiceLocator.instance.videoRepository.getEmergencyLocation(alert['videoId']);
        if (loc != null) {
          _emergencyLoc = LatLng(loc['latitude'] ?? 0.0, loc['longitude'] ?? 0.0);
        }
      }
      _emergencyLoc ??= const LatLng(13.7300, 100.5600); // Last resort fallback
      
      await _drawRouteToEmergency(_volunteerLoc!, _emergencyLoc!);
    } catch (e) {
      debugPrint('Error accept rescue: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().contains('รับงานนี้ไปแล้ว') ? 'คุณรับงานนี้ไปแล้ว' : 'เกิดข้อผิดพลาดในการรับงาน'), backgroundColor: Colors.red),
      );
      setState(() => _isAssisting = false);
    }
  }
  
  void _updateStatus(String newStatus) async {
    if (_activeResponseId == null || _selectedEmergency == null) return;
    final user = ServiceLocator.instance.currentUser;
    
    try {
      String? notes;
      
      // Show post-action report dialog for 'resolved'
      if (newStatus == 'resolved' && mounted) {
        notes = await _showPostActionDialog();
      }
      
      // Show confirmation for 'cancelled'
      if (newStatus == 'cancelled' && mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ยืนยันการยกเลิก'),
            content: const Text('คุณแน่ใจหรือไม่ว่าต้องการยกเลิกภารกิจนี้?\nผู้ประสบเหตุจะรอคอยความช่วยเหลือ'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ไม่')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ยืนยัน', style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (confirm != true) return;
      }

      await ServiceLocator.instance.videoRepository.updateRescueStatus(
          responseId: _activeResponseId!,
          status: newStatus,
          notes: notes,
      );
      
      if (user != null) {
        WebSocketService().sendRescueStatusUpdate(
           videoId: _selectedEmergency!['videoId'], 
           volunteerId: user.id, 
           status: newStatus,
           victimId: _selectedEmergency!['senderId'],
           responseId: _activeResponseId,
        );
      }
      
      setState(() {
        if (newStatus == 'resolved' || newStatus == 'cancelled') {
          _isAssisting = false;
          _selectedEmergency = null;
          _activeResponseId = null;
          _markers.clear();
          _polylines.clear();
        } else {
          _currentAssistingStatus = newStatus;
        }
      });
      
      if (!mounted) return;
      if (newStatus == 'resolved') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ภารกิจเสร็จสิ้น ขอบคุณสำหรับความช่วยเหลือ!'), backgroundColor: Colors.green),
        );
      } else if (newStatus == 'cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ยกเลิกภารกิจแล้ว'), backgroundColor: Colors.grey),
        );
      }
    } catch (e) {
      debugPrint('Failed to update status: $e');
    }
  }

  Future<String?> _showPostActionDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('สรุปรายงานหลังจบงาน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('บันทึกข้อมูลเพิ่มเติมเกี่ยวกับเหตุการณ์ (ไม่บังคับ)'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'เช่น สภาพเหตุการณ์, จำนวนผู้บาดเจ็บ...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('ข้าม')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('บันทึกและจบงาน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  void _openNavigation() async {
    if (_emergencyLoc == null) return;
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${_emergencyLoc!.latitude},${_emergencyLoc!.longitude}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดแอพนำทางได้')),
      );
    }
  }

  void _toggleDutyStatus() async {
    final user = ServiceLocator.instance.currentUser;
    if (user == null) return;
    
    final newStatus = !_isVolunteerActive;
    try {
      await ServiceLocator.instance.videoRepository.setVolunteerActiveStatus(
        userId: user.id,
        isActive: newStatus,
      );
      setState(() => _isVolunteerActive = newStatus);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus ? 'เปิดรับงานแล้ว' : 'ปิดรับงานชั่วคราว'),
          backgroundColor: newStatus ? Colors.green : Colors.grey,
        ),
      );
    } catch (e) {
      debugPrint('Error toggling duty status: $e');
    }
  }

  // ============== MAP DRAWING ==============

  Future<void> _drawRouteToEmergency(LatLng startLoc, LatLng endLoc) async {
    setState(() {
      _markers.clear();
      _polylines.clear();
      _distanceString = 'กำลังคำนวณ...';
      _durationString = 'กำลังคำนวณ...';
    });

    String url = 'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${startLoc.latitude},${startLoc.longitude}'
        '&destination=${endLoc.latitude},${endLoc.longitude}'
        '&key=${AppConfig.googleMapsApiKey}';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];
          
          setState(() {
            _distanceString = leg['distance']['text'];
            _durationString = leg['duration']['text'];
          });

          List<PointLatLng> result = PolylinePoints.decodePolyline(route['overview_polyline']['points']);
          
          List<LatLng> polylineCoordinates = [];
          for (var point in result) {
            polylineCoordinates.add(LatLng(point.latitude, point.longitude));
          }

          setState(() {
            _polylines.add(Polyline(
              polylineId: const PolylineId('route_to_emergency'),
              color: Colors.blue,
              width: 6,
              points: polylineCoordinates,
            ));
            
            _markers.add(Marker(
              markerId: const MarkerId('incident'),
              position: endLoc,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: const InfoWindow(title: 'จุดเกิดเหตุ'),
            ));
            _markers.add(Marker(
              markerId: const MarkerId('volunteer_me'),
              position: startLoc,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
              infoWindow: InfoWindow(title: 'ตำแหน่งของคุณ', snippet: 'เวลา: $_durationString'),
            ));
          });

          if (_mapController != null) {
            LatLngBounds bounds = _createBounds(startLoc, endLoc);
            _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching directions: $e');
    }
  }

  LatLngBounds _createBounds(LatLng a, LatLng b) {
    final south = a.latitude < b.latitude ? a.latitude : b.latitude;
    final north = a.latitude > b.latitude ? a.latitude : b.latitude;
    final west = a.longitude < b.longitude ? a.longitude : b.longitude;
    final east = a.longitude > b.longitude ? a.longitude : b.longitude;
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  // ============== BUILD UI ==============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ศูนย์กู้ภัยจิตอาสา'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        actions: [
          // On/Off Duty Toggle
          Row(
            children: [
              Text(_isVolunteerActive ? 'เปิดรับ' : 'ปิดรับ', style: const TextStyle(fontSize: 12)),
              Switch(
                value: _isVolunteerActive,
                onChanged: (_) => _toggleDutyStatus(),
                activeColor: Colors.greenAccent,
                inactiveTrackColor: Colors.grey,
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('กำลังตรวจสอบสถานะ...', style: TextStyle(color: Colors.grey)),
            ],
          ))
        : Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(13.736717, 100.523186),
                  zoom: 12,
                ),
                onMapCreated: (controller) => _mapController = controller,
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                padding: EdgeInsets.only(bottom: _isAssisting || _activeEmergencies.isNotEmpty ? 240 : 0),
              ),
              
              if (_isAssisting)
                _buildAssistingPanel()
              else if (_activeEmergencies.isNotEmpty)
                _buildEmergencyCarousel()
              else if (!_isVolunteerActive)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    color: Colors.orange.shade100,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(child: Text('คุณปิดรับงานอยู่ เปิด Switch ด้านบนเพื่อเริ่มรับงาน', style: TextStyle(color: Colors.orange))),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
    );
  }
  
  Widget _buildAssistingPanel() {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _currentAssistingStatus == 'arrived' ? Icons.check_circle : Icons.emergency,
                    color: _currentAssistingStatus == 'arrived' ? Colors.green : Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentAssistingStatus == 'arrived' ? 'อยู่ที่จุดเกิดเหตุ' : 'กำลังเดินทางไปให้ความช่วยเหลือ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _currentAssistingStatus == 'arrived' ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ระยะทาง: $_distanceString', style: const TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('ระยะเวลา: $_durationString', style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _openNavigation,
                    icon: const Icon(Icons.navigation, color: Colors.white, size: 20),
                    label: const Text('นำทาง', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_currentAssistingStatus == 'accepted')
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.location_on, color: Colors.white, size: 18),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade600),
                        onPressed: () => _updateStatus('arrived'),
                        label: const Text('ถึงที่เกิดเหตุแล้ว', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  if (_currentAssistingStatus == 'arrived')
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check, color: Colors.white, size: 18),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600),
                        onPressed: () => _updateStatus('resolved'),
                        label: const Text('เสร็จสิ้นภารกิจ', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 18),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _updateStatus('cancelled'),
                      label: const Text('ยกเลิกงาน'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildEmergencyCarousel() {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      height: 180,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.85),
        itemCount: _activeEmergencies.length,
        itemBuilder: (context, index) {
          final alert = _activeEmergencies[index];
          final categoryName = alert['categoryName'] ?? 'เหตุฉุกเฉิน';
          final hasGps = alert['latitude'] != null && alert['longitude'] != null;
          
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                        child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(categoryName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            if (hasGps) Text('📍 พิกัด: ${double.tryParse(alert['latitude']?.toString() ?? '0')?.toStringAsFixed(4)}, ${double.tryParse(alert['longitude']?.toString() ?? '0')?.toStringAsFixed(4)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(alert['text'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700)),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.volunteer_activism, color: Colors.white, size: 18),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _acceptRescue(alert),
                      label: const Text('ยอมรับการช่วยเหลือ (รับงาน)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
