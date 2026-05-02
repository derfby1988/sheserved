import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/core/constants/app_text_styles.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/services/websocket_service.dart';

/// Dialog แสดงแผนที่เส้นทางฉุกเฉิน + ปุ่ม "ช่วยเปิดทาง" / "ไม่สะดวก"
/// เปิดขึ้นทันทีเมื่อได้รับ yield-way-alert จาก Server
class YieldWayMapDialog extends StatefulWidget {
  final Map<String, dynamic> alertData;
  /// callback เมื่อผู้ใช้กด "ช่วยเปิดทาง" — ให้ caller ส่ง yield-way interaction
  final VoidCallback onYield;
  /// callback เมื่อผู้ใช้กด "ไม่สะดวก" — ให้ caller ปิดหน้า Emergency + dismiss notification
  final VoidCallback onDecline;

  const YieldWayMapDialog({
    super.key,
    required this.alertData,
    required this.onYield,
    required this.onDecline,
  });

  @override
  State<YieldWayMapDialog> createState() => _YieldWayMapDialogState();
}

class _YieldWayMapDialogState extends State<YieldWayMapDialog>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  bool _isYielding = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _decodeRoute();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _decodeRoute() {
    final encoded = widget.alertData['encodedPolyline'] as String?;
    final incidentLat = (widget.alertData['incidentLat'] as num?)?.toDouble();
    final incidentLng = (widget.alertData['incidentLng'] as num?)?.toDouble();
    final userLat = (widget.alertData['userLat'] as num?)?.toDouble();
    final userLng = (widget.alertData['userLng'] as num?)?.toDouble();

    if (encoded == null || incidentLat == null || incidentLng == null) return;

    // Decode polyline
    final points = PolylinePoints.decodePolyline(encoded);
    final coords = points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    setState(() {
      _polylines.add(Polyline(
        polylineId: const PolylineId('emergency_route'),
        color: const Color(0xFFFF3B30),
        width: 5,
        points: coords,
        patterns: [PatternItem.dash(20), PatternItem.gap(8)],
      ));

      // Marker จุดเกิดเหตุ
      _markers.add(Marker(
        markerId: const MarkerId('incident'),
        position: LatLng(incidentLat, incidentLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: '🚨 จุดเกิดเหตุ'),
      ));

      // Marker ตำแหน่งผู้ใช้ (ถ้ามี)
      if (userLat != null && userLng != null) {
        _markers.add(Marker(
          markerId: const MarkerId('user_pos'),
          position: LatLng(userLat, userLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: '📍 คุณอยู่ที่นี่'),
        ));
      }
    });
  }

  void _handleYield() async {
    if (_isYielding) return;
    setState(() => _isYielding = true);

    final videoId = widget.alertData['videoId'] as String?;
    final userId = AuthService.instance.currentUser?.id;
    if (videoId != null && userId != null) {
      // ส่ง yield-way interaction
      WebSocketService().sendVideoInteraction(videoId, userId, 'yield-way');
    }

    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) Navigator.of(context).pop();
    widget.onYield();
  }

  void _handleDecline() {
    Navigator.of(context).pop();
    widget.onDecline();
  }

  @override
  Widget build(BuildContext context) {
    final categoryName = widget.alertData['categoryName'] ?? 'เหตุฉุกเฉิน';
    final distMeters = widget.alertData['distanceMeters'] as int?;
    final distText = distMeters != null
        ? distMeters >= 1000
            ? '${(distMeters / 1000).toStringAsFixed(1)} กม.'
            : '$distMeters ม.'
        : '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── Header ────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF3B30), Color(0xFFFF6B35)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: const Icon(Icons.emergency, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'รถฉุกเฉินกำลังวิ่งมา!',
                            style: AppTextStyles.heading3.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$categoryName${distText.isNotEmpty ? ' · ห่าง $distText' : ''}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '⚠️ คุณอยู่บนเส้นทางของรถฉุกเฉิน กรุณาหลบให้ทาง',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Map ────────────────────────────────────────────────
              SizedBox(
                height: 220,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _markers.isNotEmpty
                        ? _markers.first.position
                        : const LatLng(13.736717, 100.523186),
                    zoom: 14,
                  ),
                  onMapCreated: (ctrl) {
                    _mapController = ctrl;
                    // Fit ทั้ง markers ใน view
                    if (_markers.length >= 2) {
                      final lats = _markers.map((m) => m.position.latitude).toList();
                      final lngs = _markers.map((m) => m.position.longitude).toList();
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngBounds(
                          LatLngBounds(
                            southwest: LatLng(lats.reduce((a, b) => a < b ? a : b),
                                lngs.reduce((a, b) => a < b ? a : b)),
                            northeast: LatLng(lats.reduce((a, b) => a > b ? a : b),
                                lngs.reduce((a, b) => a > b ? a : b)),
                          ),
                          60,
                        ),
                      );
                    }
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),

              // ─── Instruction ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF007AFF), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'เส้นสีแดงคือเส้นทางที่รถฉุกเฉินกำลังใช้ หากคุณสามารถหลบทางได้ กรุณากดปุ่มด้านล่าง',
                        style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Action Buttons ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Row(
                  children: [
                    // ปุ่มปฏิเสธ
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _handleDecline,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('ไม่สะดวก'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                          side: BorderSide(color: Colors.grey[300]!),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ปุ่มให้ทาง
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isYielding ? null : _handleYield,
                        icon: _isYielding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.airport_shuttle, color: Colors.white, size: 20),
                        label: Text(
                          _isYielding ? 'กำลังบันทึก...' : '🙏 ช่วยเปิดทาง',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B30),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
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
}
