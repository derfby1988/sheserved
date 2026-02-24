import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_request_model.dart';
import '../widgets/symptom_ruler_picker.dart';
import '../../../../services/service_locator.dart';

// ─── Data model for a body region selection ────────────────────────────────
class _BodyRegion {
  final String id;
  final String nameTh;
  final String nameEn;
  final double yRatio; // 0.0 = top, 1.0 = bottom (position on body silhouette)
  final double xRatio; // 0.0 = left, 1.0 = right (horizontal position on body)
  final IconData icon;

  const _BodyRegion({
    required this.id,
    required this.nameTh,
    required this.nameEn,
    required this.yRatio,
    this.xRatio = 0.5, // Default to center
    required this.icon,
  });
}

List<_BodyRegion> _bodyRegions = [
  _BodyRegion(id: 'top_head',   nameTh: 'ศีรษะด้านบน',  nameEn: 'Top of Head',   yRatio: 0.04, xRatio: 0.50, icon: Icons.face),
  _BodyRegion(id: 'forehead',   nameTh: 'หน้าผาก',      nameEn: 'Forehead',      yRatio: 0.07, xRatio: 0.50, icon: Icons.face_retouching_natural),
  _BodyRegion(id: 'eyes',       nameTh: 'ดวงตา',        nameEn: 'Eyes',          yRatio: 0.09, xRatio: 0.50, icon: Icons.remove_red_eye_outlined),
  _BodyRegion(id: 'nose_ears',  nameTh: 'จมูก/หู',      nameEn: 'Nose/Ears',     yRatio: 0.11, xRatio: 0.50, icon: Icons.hearing_outlined),
  _BodyRegion(id: 'mouth_jaw',  nameTh: 'ปาก/กราม',     nameEn: 'Mouth/Jaw',     yRatio: 0.13, xRatio: 0.50, icon: Icons.record_voice_over_outlined),
  _BodyRegion(id: 'neck',       nameTh: 'ลำคอ',         nameEn: 'Neck',          yRatio: 0.17, xRatio: 0.50, icon: Icons.compress),
  _BodyRegion(id: 'shoulder',   nameTh: 'หัวไหล่',      nameEn: 'Shoulder',      yRatio: 0.22, xRatio: 0.38, icon: Icons.accessibility_new),
  _BodyRegion(id: 'collarbone', nameTh: 'ไหปลาร้า',     nameEn: 'Collarbone',    yRatio: 0.25, xRatio: 0.42, icon: Icons.horizontal_rule),
  _BodyRegion(id: 'upper_chest',nameTh: 'หน้าอกส่วนบน', nameEn: 'Upper Chest',   yRatio: 0.29, xRatio: 0.50, icon: Icons.monitor_heart_outlined),
  _BodyRegion(id: 'upper_arm',  nameTh: 'ต้นแขน',       nameEn: 'Upper Arm',     yRatio: 0.33, xRatio: 0.28, icon: Icons.fitness_center),
  _BodyRegion(id: 'lower_chest',nameTh: 'หน้าอกส่วนล่าง',nameEn: 'Lower Chest',   yRatio: 0.36, xRatio: 0.50, icon: Icons.favorite_border),
  _BodyRegion(id: 'upper_abd',  nameTh: 'ท้องส่วนบน',   nameEn: 'Upper Abdomen', yRatio: 0.40, xRatio: 0.50, icon: Icons.restaurant_menu),
  _BodyRegion(id: 'elbow',      nameTh: 'ข้อศอก',       nameEn: 'Elbow',         yRatio: 0.44, xRatio: 0.22, icon: Icons.adjust),
  _BodyRegion(id: 'middle_abd', nameTh: 'รอบสะดือ',     nameEn: 'Navel Area',    yRatio: 0.47, xRatio: 0.50, icon: Icons.radio_button_checked),
  _BodyRegion(id: 'lower_arm',  nameTh: 'แขนท่อนล่าง',  nameEn: 'Forearm',       yRatio: 0.50, xRatio: 0.20, icon: Icons.pan_tool_alt_outlined),
  _BodyRegion(id: 'lower_abd',  nameTh: 'ท้องส่วนล่าง',  nameEn: 'Lower Abdomen', yRatio: 0.53, xRatio: 0.50, icon: Icons.water_drop_outlined),
  _BodyRegion(id: 'wrist',      nameTh: 'ข้อมือ',       nameEn: 'Wrist',         yRatio: 0.56, xRatio: 0.18, icon: Icons.watch_outlined),
  _BodyRegion(id: 'pelvis',     nameTh: 'เชิงกราน/ก้น', nameEn: 'Pelvis/Glutes', yRatio: 0.59, xRatio: 0.50, icon: Icons.trip_origin),
  _BodyRegion(id: 'hand',       nameTh: 'มือ/นิ้วมือ',  nameEn: 'Hand/Fingers',  yRatio: 0.62, xRatio: 0.15, icon: Icons.back_hand_outlined),
  _BodyRegion(id: 'upper_thigh',nameTh: 'ต้นขาส่วนบน',  nameEn: 'Upper Thigh',   yRatio: 0.66, xRatio: 0.40, icon: Icons.directions_walk),
  _BodyRegion(id: 'mid_thigh',  nameTh: 'ต้นขาส่วนกลาง',nameEn: 'Mid Thigh',     yRatio: 0.71, xRatio: 0.38, icon: Icons.directions_run),
  _BodyRegion(id: 'knee',       nameTh: 'หัวเข่า',      nameEn: 'Knee',          yRatio: 0.77, xRatio: 0.42, icon: Icons.lens_outlined),
  _BodyRegion(id: 'upper_shin', nameTh: 'หน้าแข้ง/น่อง',nameEn: 'Shin/Calf',     yRatio: 0.83, xRatio: 0.42, icon: Icons.linear_scale),
  _BodyRegion(id: 'lower_shin', nameTh: 'ข้อเท้าด้านบน',nameEn: 'Lower Shin',    yRatio: 0.88, xRatio: 0.42, icon: Icons.align_vertical_bottom),
  _BodyRegion(id: 'ankle',      nameTh: 'ข้อเท้า',      nameEn: 'Ankle',         yRatio: 0.93, xRatio: 0.42, icon: Icons.radio_button_unchecked),
  _BodyRegion(id: 'foot',       nameTh: 'หลังเท้า',     nameEn: 'Foot',          yRatio: 0.96, xRatio: 0.42, icon: Icons.run_circle_outlined),
  _BodyRegion(id: 'toes',       nameTh: 'นิ้วเท้า',     nameEn: 'Toes',          yRatio: 0.99, xRatio: 0.42, icon: Icons.linear_scale_outlined),
];

const List<String> _medicalSymptoms = [
  'ระบุอาการ', 'ปกติ', 'เจ็บ', 'ปวด', 'คัน', 'บวม', 'แสบ', 'ระคาย', 'กระตุก', 
  'ชา', 'เกร็ง', 'ตึง', 'เสียด', 'ร้าว', 'อักเสบ', 'เป็นแผล'
];

// ─── Side Enum ────────────────────────────────────────────────────────────
enum _BodySide { left, center, right }

extension _BodySideExt on _BodySide {
  String get labelTh {
    switch (this) {
      case _BodySide.left:   return 'ซ้าย';
      case _BodySide.center: return 'กลาง';
      case _BodySide.right:  return 'ขวา';
    }
  }
  String get labelEn {
    switch (this) {
      case _BodySide.left:   return 'Left';
      case _BodySide.center: return 'Center';
      case _BodySide.right:  return 'Right';
    }
  }
}

// ─── Selected point data model ─────────────────────────────────────────────
class _SelectedPoint {
  final _BodyRegion region;
  final _BodySide side;
  final String symptom; // NEW

  const _SelectedPoint({
    required this.region, 
    required this.side,
    required this.symptom,
  });

  String get displayLabel {
    final area = side == _BodySide.center ? region.nameTh : '${region.nameTh}(${side.labelTh})';
    return '$area: $symptom';
  }

  String get key => '${region.id}_${side.labelEn.toLowerCase()}';
}

// ─── Page ─────────────────────────────────────────────────────────────────
class AnalyzeBodyAreaPage extends StatefulWidget {
  final ConsultationRequestModel request;

  const AnalyzeBodyAreaPage({super.key, required this.request});

  @override
  State<AnalyzeBodyAreaPage> createState() => _AnalyzeBodyAreaPageState();
}

class _AnalyzeBodyAreaPageState extends State<AnalyzeBodyAreaPage>
    with TickerProviderStateMixin {
  // Currently hovered/selected region on the vertical axis
  _BodyRegion? _hoveredRegion;
  // Selected side: left / center / right
  _BodySide? _selectedSide;
  // All confirmed selected points
  final List<_SelectedPoint> _selectedPoints = [];

  // Currently selected symptom from ruler
  String _currentSymptom = _medicalSymptoms[0]; // 'ระบุอาการ'

  // Draggable popup state — tracks popup position as 0.0..1.0 ratio of silhouette height
  double _popupDragRatio = 0.5;
  // Cached silhouette height for drag calculations
  double _silhouetteH = 0;

  // Ripple center position (x, y ratios)
  double _rippleCenterX = 0.5;
  double _rippleCenterY = 0.5;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _rippleController;
  late Animation<double> _pulseAnim;
  late Animation<double> _rippleAnim;

  String get _gender {
    return widget.request.bodyArea['gender']?.toString().toLowerCase() ?? 'unknown';
  }

  IconData _getIconData(String? iconName) {
    if (iconName == null) return Icons.circle;
    // Map existing icons for backward compatibility
    switch (iconName) {
      case 'face': return Icons.face;
      case 'face_retouching_natural': return Icons.face_retouching_natural;
      case 'remove_red_eye_outlined': return Icons.remove_red_eye_outlined;
      case 'hearing_outlined': return Icons.hearing_outlined;
      case 'record_voice_over_outlined': return Icons.record_voice_over_outlined;
      case 'compress': return Icons.compress;
      case 'accessibility_new': return Icons.accessibility_new;
      case 'horizontal_rule': return Icons.horizontal_rule;
      case 'monitor_heart_outlined': return Icons.monitor_heart_outlined;
      case 'fitness_center': return Icons.fitness_center;
      case 'favorite_border': return Icons.favorite_border;
      case 'restaurant_menu': return Icons.restaurant_menu;
      case 'adjust': return Icons.adjust;
      case 'radio_button_checked': return Icons.radio_button_checked;
      case 'pan_tool_alt_outlined': return Icons.pan_tool_alt_outlined;
      case 'water_drop_outlined': return Icons.water_drop_outlined;
      case 'watch_outlined': return Icons.watch_outlined;
      case 'trip_origin': return Icons.trip_origin;
      case 'back_hand_outlined': return Icons.back_hand_outlined;
      case 'directions_walk': return Icons.directions_walk;
      case 'directions_run': return Icons.directions_run;
      case 'lens_outlined': return Icons.lens_outlined;
      case 'linear_scale': return Icons.linear_scale;
      case 'align_vertical_bottom': return Icons.align_vertical_bottom;
      case 'radio_button_unchecked': return Icons.radio_button_unchecked;
      case 'run_circle_outlined': return Icons.run_circle_outlined;
      case 'linear_scale_outlined': return Icons.linear_scale_outlined;
      default: return Icons.accessibility;
    }
  }

  // Symptom frequency stats for heatmap effect
  Map<String, int> _symptomStats = {};
  int _maxSymptomCount = 0;

  // Scanning state
  bool _isScanning = true;
  double _scanProgress = 0.0;
  late AnimationController _scanController;

  // Popup opening state for UI feedback
  bool _isOpeningPopup = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _scanController.addListener(() {
      setState(() {
        _scanProgress = _scanController.value;
      });
    });

    _pulseAnim = Tween<double>(begin: 0.8, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _rippleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.linear),
    );

    _loadSymptomStats();
  }

  Future<void> _loadSymptomStats() async {
    // Start scan animation
    _scanController.forward();
    
    try {
      final stats = await ServiceLocator.instance.consultationRepository.getSymptomStatistics();
      final dbRegions = await ServiceLocator.instance.bodyRegionRepository.getAllRegions();
      
      // Wait for at least some animation progress for better UX
      if (_scanController.value < 0.6) {
        await Future.delayed(const Duration(milliseconds: 800));
      }

      if (mounted) {
        setState(() {
          _symptomStats = stats;
          if (stats.isNotEmpty) {
            _maxSymptomCount = stats.values.reduce((a, b) => a > b ? a : b);
          }
          if (dbRegions.isNotEmpty) {
            _bodyRegions = dbRegions.where((r) {
              if (r.gender == 'both') return true;
              return r.gender == _gender;
            }).map((r) => _BodyRegion(
              id: r.id,
              nameTh: r.nameTh,
              nameEn: r.nameEn,
              yRatio: r.yRatio,
              xRatio: r.xRatio,
              icon: _getIconData(r.iconName),
            )).toList();
          }
        });
        
        // Complete the scan
        await _scanController.forward(from: _scanController.value);
        if (mounted) {
          setState(() => _isScanning = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading symptom stats: $e');
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  void _onRegionTapped(_BodyRegion region) async {
    // Provide immediate haptic feedback
    HapticFeedback.mediumImpact();
    
    // Phase 1: Show loading indicator immediately
    setState(() {
      _isOpeningPopup = true;
      // Update ripple position immediately for visual response
      _rippleCenterX = region.xRatio;
      _rippleCenterY = region.yRatio;
    });

    // Phase 2: Wait for one frame so the loading indicator can be painted
    await Future.delayed(const Duration(milliseconds: 50));

    if (!mounted) return;

    // Phase 3: Set the expensive state (popup build)
    setState(() {
      _hoveredRegion = region;
      _popupDragRatio = region.yRatio;
      _selectedSide = null;
      _currentSymptom = _medicalSymptoms[0];
    });

    // Phase 4: Reset opening state after the expensive build frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isOpeningPopup = false);
    });

    _rippleController.reset();
    _rippleController.repeat();
  }

  /// Called when the popup is dragged — updates popup position & hovered region
  void _onPopupDrag(DragUpdateDetails details) {
    if (_silhouetteH <= 0) return;
    setState(() {
      _popupDragRatio = (_popupDragRatio + details.delta.dy / _silhouetteH)
          .clamp(0.0, 1.0);
      // Find nearest region to the new drag ratio
      _BodyRegion? closest;
      double minDist = double.infinity;
      for (final r in _bodyRegions) {
        final dist = (r.yRatio - _popupDragRatio).abs();
        if (dist < minDist) {
          minDist = dist;
          closest = r;
        }
      }
      if (closest != null && closest != _hoveredRegion) {
        _hoveredRegion = closest;
        // RESET selection states when organ changes via drag
        _selectedSide = null;
        _currentSymptom = _medicalSymptoms[0];
        
        // Update ripple center to follow drag
        _rippleCenterY = closest.yRatio;
        _rippleCenterX = closest.xRatio + _xOffsetForSide(_selectedSide);
      }
    });
  }

  /// Returns an x-axis offset based on the selected side
  double _xOffsetForSide(_BodySide? side) {
    switch (side) {
      case _BodySide.left:   return -0.12;
      case _BodySide.right:  return  0.12;
      case _BodySide.center: return  0.0;
      case null:             return  0.0;
    }
  }

  void _confirmSelection() {
    if (_hoveredRegion == null || _selectedSide == null || _currentSymptom == _medicalSymptoms[0]) return;
    
    final point = _SelectedPoint(
      region: _hoveredRegion!, 
      side: _selectedSide!,
      symptom: _currentSymptom,
    );
    // Avoid duplicates by key
    if (!_selectedPoints.any((p) => p.key == point.key)) {
      setState(() => _selectedPoints.add(point));
    }
    // Light haptic-like feedback via snackbar
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ เพิ่มบริเวณ: ${point.displayLabel}'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _removePoint(_SelectedPoint point) {
    setState(() => _selectedPoints.removeWhere((p) => p.key == point.key));
  }

  void _proceed() {
    if (_selectedPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('กรุณาระบุบริเวณที่พบอาการอย่างน้อย 1 จุด'),
          backgroundColor: Colors.redAccent.shade200,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    // Map to normalized models
    final symptoms = _selectedPoints
        .map((p) => SymptomPoint(
              regionId: p.region.id,
              side: p.side.labelEn.toLowerCase(),
              symptom: p.symptom,
              displayLabel: p.displayLabel,
            ))
        .toList();

    final updatedRequest = widget.request.copyWith(
      bodyArea: {
        'gender': _gender,
      },
      symptoms: symptoms,
    );

    if (updatedRequest.useAI) {
      Navigator.pushNamed(context, '/vega-ai-chat', arguments: updatedRequest);
    } else {
      Navigator.pushNamed(context, '/chart-board', arguments: updatedRequest);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F9E8),
      body: Stack(
        children: [
          // Gradient background
          _buildBackground(),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Row(
                    children: [
                      // ── Left side selector ──────────────────────────────
                      _buildSidePanel(_BodySide.left),

                      // ── Center: Body silhouette ──────────────────────────
                      Expanded(child: _buildBodySilhouette()),

                      // ── Right side selector ─────────────────────────────
                      _buildSidePanel(_BodySide.right),
                    ],
                  ),
                ),

                // ── Selected tags + Proceed ──────────────────────────────
                _buildBottomPanel(),
              ],
            ),
          ),

          // ── Scanning Overlay ───────────────────────────────────────────
          if (_isScanning) _buildScanningOverlay(),
        ],
      ),
    );
  }

  // ─── Background ──────────────────────────────────────────────────────────
  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE8F5DA),
            Color(0xFFF5FAF0),
            Color(0xFFFFFFFF),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.primary, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ระบุบริเวณที่พบอาการ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A4D10),
                  ),
                ),
                Text(
                  'แตะที่ตำแหน่ง แล้วเลือกด้านซ้าย/ขวา',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          // Cart icon
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined,
                color: AppColors.cartIcon, size: 24),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  // ─── Side panel (Left / Right) ────────────────────────────────────────────
  Widget _buildSidePanel(_BodySide side) {
    final isSelected = _selectedSide == side;
    final bool isLeft = side == _BodySide.left;

    return GestureDetector(
      onTap: () => setState(() => _selectedSide = side),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 52,
        margin: EdgeInsets.only(
          left: isLeft ? 8 : 0,
          right: isLeft ? 0 : 8,
          top: 16,
          bottom: 16,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.5)
                : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isLeft ? Icons.arrow_back : Icons.arrow_forward,
              color: isSelected ? AppColors.primary : Colors.grey.shade400,
              size: 18,
            ),
            const SizedBox(height: 6),
            RotatedBox(
              quarterTurns: isLeft ? 3 : 1,
              child: Text(
                isLeft ? 'ซ้าย' : 'ขวา',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppColors.primary : Colors.grey.shade500,
                  letterSpacing: 2,
                ),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.6),
                        blurRadius: 4 * _pulseAnim.value,
                        spreadRadius: 1 * _pulseAnim.value,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Body silhouette with tap regions ────────────────────────────────────
  Widget _buildBodySilhouette() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;
        // Cache height for drag calculations
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_silhouetteH != h) _silhouetteH = h;
        });

        return GestureDetector(
          onTapDown: (details) {
            // Find closest region by y position
            final tapY = details.localPosition.dy;
            final ratio = tapY / h;
            _BodyRegion? closest;
            double minDist = double.infinity;
            for (final r in _bodyRegions) {
              final dist = (r.yRatio - ratio).abs();
              if (dist < minDist) {
                minDist = dist;
                closest = r;
              }
            }
            if (closest != null) _onRegionTapped(closest);
          },
          child: Stack(
            clipBehavior: Clip.none, // Allow popup to overflow side panels
            children: [
              // Background glass card
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),

              // Water ripple effect from selected organ center
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: AnimatedBuilder(
                    animation: _rippleAnim,
                    builder: (_, __) {
                      return CustomPaint(
                        painter: _RipplePainter(
                          progress: _rippleAnim.value,
                          centerX: _rippleCenterX,
                          centerY: _rippleCenterY,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Human silhouette
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _HumanSilhouettePainter(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      gender: _gender,
                    ),
                  ),
                ),
              ),

              // === Permanent Organ Labels (identify organ names) ===
              ..._bodyRegions.map((region) {
                final topY = h * region.yRatio;
                final isHovered = _hoveredRegion?.id == region.id;
                
                return Positioned(
                  top: topY - 20,
                  left: 12,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: Builder(
                      builder: (context) {
                        final count = _symptomStats[region.id] ?? 0;
                        // Intensity calculations:
                        // Opacity from 0.4 (rare) to 1.0 (very frequent)
                        double intensity = 0.45;
                        if (_maxSymptomCount > 0) {
                          intensity = 0.45 + (count / _maxSymptomCount) * 0.55;
                        }
                        
                        // Font weight based on frequency
                        FontWeight weight = FontWeight.w400;
                        if (count > 0) {
                          if (count >= _maxSymptomCount * 0.7) {
                            weight = FontWeight.w800;
                          } else if (count >= _maxSymptomCount * 0.3) {
                            weight = FontWeight.w600;
                          } else {
                            weight = FontWeight.w500;
                          }
                        }

                        return Text(
                          region.nameTh,
                          style: TextStyle(
                            fontSize: isHovered ? 12 : 10,
                            fontWeight: isHovered ? FontWeight.bold : weight,
                            color: isHovered 
                              ? AppColors.primary 
                              : Colors.grey.shade800.withValues(alpha: intensity),
                            letterSpacing: 0.5,
                          ),
                        );
                      }
                    ),
                  ),
                );
              }),

              // Horizontal region tap lines + labels
              ...List.generate(_bodyRegions.length, (i) {
                final region = _bodyRegions[i];
                final topY = h * region.yRatio;
                final isHovered = _hoveredRegion?.id == region.id;
                final isConfirmed = _selectedPoints.any((p) => p.region.id == region.id);

                return Positioned(
                  top: topY - 12,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _onRegionTapped(region),
                    behavior: HitTestBehavior.translucent,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 24,
                      child: Row(
                        children: [
                          // Left endpoint dot
                          _buildSideEndpoint(
                              isHovered, isConfirmed, _BodySide.left),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: isHovered ? 2.0 : 0.8,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isHovered
                                      ? [
                                          AppColors.primary.withValues(alpha: 0.8),
                                          AppColors.primaryLight.withValues(alpha: 0.9),
                                          AppColors.primary.withValues(alpha: 0.8),
                                        ]
                                      : isConfirmed
                                          ? [
                                              AppColors.primary.withValues(alpha: 0.4),
                                              AppColors.primary.withValues(alpha: 0.4),
                                            ]
                                          : [
                                              Colors.grey.withValues(alpha: 0.2),
                                              Colors.grey.withValues(alpha: 0.1),
                                            ],
                                ),
                              ),
                            ),
                          ),
                          // Right endpoint dot
                          _buildSideEndpoint(
                              isHovered, isConfirmed, _BodySide.right),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              // Hovered region: draggable label + confirm button
              if (_hoveredRegion != null)
                _buildHoveredLabel(h),

              // Feedback if popup is still 'opening' (busy UI thread)
              if (_isOpeningPopup)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),

              // Confirmed points: small dot indicators on body
              ..._selectedPoints.map((point) {
                final topY = h * point.region.yRatio;
                double leftX;
                switch (point.side) {
                  case _BodySide.left:
                    leftX = w * 0.22;
                    break;
                  case _BodySide.center:
                    leftX = w * 0.5 - 6;
                    break;
                  case _BodySide.right:
                    leftX = w * 0.72;
                    break;
                }
                return Positioned(
                  left: leftX,
                  top: topY - 8,
                  child: _PulsingDot(
                    color: AppColors.primary,
                    pulseAnim: _pulseAnim,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSideEndpoint(bool isHovered, bool isConfirmed, _BodySide side) {
    final bool pointOnSide =
        _selectedPoints.any((p) => p.side == side);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isHovered ? 10 : (isConfirmed || pointOnSide) ? 7 : 4,
      height: isHovered ? 10 : (isConfirmed || pointOnSide) ? 7 : 4,
      decoration: BoxDecoration(
        color: isHovered
            ? AppColors.primary
            : (isConfirmed || pointOnSide)
                ? AppColors.primary.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.3),
        shape: BoxShape.circle,
        boxShadow: isHovered
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  blurRadius: 6,
                )
              ]
            : [],
      ),
    );
  }

  Widget _buildHoveredLabel(double h) {
    final region = _hoveredRegion!;
    // Use _popupDragRatio (updated by drag) instead of region.yRatio directly
    final labelTop = (h * _popupDragRatio - 28).clamp(12.0, h - 70.0);

    return Positioned(
      top: labelTop,
      right: 8,
      child: GestureDetector(
        onVerticalDragUpdate: _onPopupDrag,
        onVerticalDragEnd: (_) {},
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Icon (Moved to far left as requested) ──────
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white, // Solid opaque white for icon
                      shape: BoxShape.circle,
                    ),
                    child: Icon(region.icon, color: AppColors.primary, size: 18),
                  ),

                  const SizedBox(width: 10),

                  // 2. Side Selector ─────────────────────────────
                  _buildInlineSideSelector(),

                  const SizedBox(width: 8),

                  // 3. Symptom Ruler ─────────────────────────────
                  SymptomRulerPicker(
                    key: ValueKey('ruler_${region.id}'), // Force reset when region changes
                    symptoms: _medicalSymptoms,
                    initialSymptom: _currentSymptom,
                    onChanged: (val) {
                      setState(() => _currentSymptom = val);
                    },
                  ),

                  const SizedBox(width: 8),

                  // 4. Gold 'เพิ่ม' pill button
                  GestureDetector(
                    onTap: (_selectedSide != null && _currentSymptom != _medicalSymptoms[0]) 
                        ? _confirmSelection 
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: (_selectedSide != null && _currentSymptom != _medicalSymptoms[0])
                          ? const LinearGradient(
                              colors: [Color(0xFFFFB300), Color(0xFFFFD54F)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : const LinearGradient(
                              colors: [Color(0xFFE0E0E0), Color(0xFFF5F5F5)], // Solid grey gradient
                            ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: (_selectedSide != null && _currentSymptom != _medicalSymptoms[0])
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFFB300).withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                      ),
                      child: const Text(
                        'เพิ่ม',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineSideSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_BodySide.left, _BodySide.center, _BodySide.right].map((s) {
        final isSelected = _selectedSide == s;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedSide = s;
              // Update ripple X to reflect the selected side
              if (_hoveredRegion != null) {
                _rippleCenterX = _hoveredRegion!.xRatio + _xOffsetForSide(s);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary
                  : const Color(0xFFEEEEEE), // Solid light grey
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              s.labelTh,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Bottom panel: tags + center button ───────────────────────────────────
  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Title row
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                'บริเวณที่เลือก (${_selectedPoints.length} จุด)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF1A4D10),
                ),
              ),
              const Spacer(),
              if (_selectedPoints.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _selectedPoints.clear()),
                  child: Text(
                    'ล้างทั้งหมด',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Tags
          if (_selectedPoints.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Text(
                'แตะบนร่างกายเพื่อระบุจุดที่มีอาการ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _selectedPoints.map((point) {
                Color tagColor = _sideColor(point.side);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Chip(
                    backgroundColor: tagColor.withValues(alpha: 0.12),
                    side: BorderSide(
                        color: tagColor.withValues(alpha: 0.4), width: 1),
                    avatar: Icon(point.region.icon,
                        color: tagColor, size: 18),
                    label: Text(
                      point.displayLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tagColor,
                      ),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 12),
                    deleteIconColor: tagColor.withValues(alpha: 0.7),
                    onDeleted: () => _removePoint(point),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: 14),

          // Proceed button
          Center(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.5,
              child: GestureDetector(
                onTap: _proceed,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _selectedPoints.isNotEmpty
                        ? const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          )
                        : LinearGradient(
                            colors: [
                              Colors.grey.shade300,
                              Colors.grey.shade200,
                            ],
                          ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: _selectedPoints.isNotEmpty
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _selectedPoints.isEmpty
                            ? 'เลือกบริเวณที่พบอาการ'
                            : 'ถัดไป (${_selectedPoints.length} จุด)',
                        style: TextStyle(
                          color: _selectedPoints.isNotEmpty
                              ? Colors.white
                              : Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (_selectedPoints.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _sideColor(_BodySide side) {
    switch (side) {
      case _BodySide.left:
        return const Color(0xFF0288D1); // blue
      case _BodySide.right:
        return const Color(0xFF8E24AA); // purple
      case _BodySide.center:
        return AppColors.primary; // green
    }
  }

  // ─── Scanning Overlay Component ──────────────────────────────────────────
  Widget _buildScanningOverlay() {
    return Positioned.fill(
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: Colors.white.withValues(alpha: 0.8),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Scanner Eye
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: _scanProgress,
                          strokeWidth: 6,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          color: AppColors.primary,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(_scanProgress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const Text(
                            'SCANNING',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'กำลังวิเคราะห์ข้อมูลอวัยวะ...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A4D10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'กำลังดึงสถิติจากฐานข้อมูลสุขภาพส่วนกลาง',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Pulsing dot widget ────────────────────────────────────────────────────
class _PulsingDot extends StatelessWidget {
  final Color color;
  final Animation<double> pulseAnim;

  const _PulsingDot({required this.color, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 16 * pulseAnim.value * 0.5,
            height: 16 * pulseAnim.value * 0.5,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Water Ripple painter ─────────────────────────────────────────────────────
/// Draws concentric circular ripples radiating from a given center point,
/// simulating a water drop effect.
class _RipplePainter extends CustomPainter {
  final double progress; // 0.0 → 1.0 (repeats)
  final double centerX;  // 0.0 → 1.0 ratio
  final double centerY;  // 0.0 → 1.0 ratio

  static const int _rippleCount = 3;

  _RipplePainter({
    required this.progress,
    required this.centerX,
    required this.centerY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * centerX, size.height * centerY);
    final maxRadius = size.longestSide * 0.6;

    for (int i = 0; i < _rippleCount; i++) {
      // Stagger each ripple by offset
      final rippleProgress = (progress + i / _rippleCount) % 1.0;
      final radius = maxRadius * rippleProgress;
      // Fade out as ripple expands
      final opacity = (1.0 - rippleProgress).clamp(0.0, 1.0) * 0.18;

      if (opacity <= 0.0) continue;

      final paint = Paint()
        ..color = const Color(0xFF71BE0A).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - rippleProgress * 0.5);

      canvas.drawCircle(center, radius, paint);
    }

    // Small center dot
    final dotPaint = Paint()
      ..color = const Color(0xFF71BE0A).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) =>
      old.progress != progress ||
      old.centerX != centerX ||
      old.centerY != centerY;
}

// ─── Human Silhouette Painter ──────────────────────────────────────────────
class _HumanSilhouettePainter extends CustomPainter {
  final Color color;
  final String gender;

  _HumanSilhouettePainter({required this.color, required this.gender});

  bool get _isMale =>
      gender == 'male' || gender == 'ชาย' || gender == 'm';

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final h = size.height;

    // === HEAD ===
    final headRadius = size.width * 0.095;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.07),
        width: headRadius * 2,
        height: headRadius * 2.2,
      ),
      paint,
    );

    // === NECK ===
    final neckPath = Path()
      ..moveTo(cx - size.width * 0.03, h * 0.14)
      ..lineTo(cx + size.width * 0.03, h * 0.14)
      ..lineTo(cx + size.width * 0.05, h * 0.19)
      ..lineTo(cx - size.width * 0.05, h * 0.19)
      ..close();
    canvas.drawPath(neckPath, paint);

    // === TORSO (wider for male) ===
    final shoulderW = _isMale ? 0.22 : 0.18;
    final waistW = _isMale ? 0.14 : 0.12;
    final hipW = _isMale ? 0.15 : 0.17;

    final torsoPath = Path()
      ..moveTo(cx - size.width * shoulderW, h * 0.20)
      ..quadraticBezierTo(
          cx, h * 0.18, cx + size.width * shoulderW, h * 0.20)
      ..lineTo(cx + size.width * waistW, h * 0.47)
      ..lineTo(cx + size.width * hipW, h * 0.55)
      ..lineTo(cx - size.width * hipW, h * 0.55)
      ..lineTo(cx - size.width * waistW, h * 0.47)
      ..close();
    canvas.drawPath(torsoPath, paint);

    // === ARMS ===
    final armW = _isMale ? 0.06 : 0.05;
    // Left arm
    _drawArm(canvas, paint, size, cx, h,
        startX: cx - size.width * shoulderW,
        isLeft: true,
        armW: armW);
    // Right arm
    _drawArm(canvas, paint, size, cx, h,
        startX: cx + size.width * shoulderW,
        isLeft: false,
        armW: armW);

    // === LEGS ===
    final Paint strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Left leg
    final leftLegPath = Path()
      ..moveTo(cx - size.width * hipW, h * 0.55)
      ..lineTo(cx - size.width * 0.03, h * 0.57)
      ..lineTo(cx - size.width * 0.04, h * 0.78) // knee
      ..quadraticBezierTo(
          cx - size.width * 0.05, h * 0.79,
          cx - size.width * 0.06, h * 0.78)
      ..lineTo(cx - size.width * 0.15, h * 0.57)
      ..close();
    canvas.drawPath(leftLegPath, strokePaint);

    // Right leg
    final rightLegPath = Path()
      ..moveTo(cx + size.width * hipW, h * 0.55)
      ..lineTo(cx + size.width * 0.03, h * 0.57)
      ..lineTo(cx + size.width * 0.04, h * 0.78) // knee
      ..quadraticBezierTo(
          cx + size.width * 0.05, h * 0.79,
          cx + size.width * 0.06, h * 0.78)
      ..lineTo(cx + size.width * 0.15, h * 0.57)
      ..close();
    canvas.drawPath(rightLegPath, strokePaint);

    // Left shin + foot
    final leftShinPath = Path()
      ..moveTo(cx - size.width * 0.06, h * 0.78)
      ..lineTo(cx - size.width * 0.04, h * 0.78)
      ..lineTo(cx - size.width * 0.05, h * 0.96)
      ..lineTo(cx - size.width * 0.07, h * 0.96)
      ..close();
    canvas.drawPath(leftShinPath, strokePaint);

    // Right shin + foot
    final rightShinPath = Path()
      ..moveTo(cx + size.width * 0.04, h * 0.78)
      ..lineTo(cx + size.width * 0.06, h * 0.78)
      ..lineTo(cx + size.width * 0.07, h * 0.96)
      ..lineTo(cx + size.width * 0.05, h * 0.96)
      ..close();
    canvas.drawPath(rightShinPath, strokePaint);

    // Feet
    for (final foot in [-1, 1]) {
      final fCx = cx + foot * size.width * 0.06;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(fCx, h * 0.97),
          width: size.width * 0.075,
          height: size.height * 0.02,
        ),
        paint,
      );
    }
  }

  void _drawArm(Canvas canvas, Paint paint, Size size, double cx, double h,
      {required double startX, required bool isLeft, required double armW}) {
    final direction = isLeft ? -1 : 1;
    final elbowX = startX + direction * size.width * 0.06;
    final handX = startX + direction * size.width * 0.04;

    final path = Path()
      ..moveTo(startX, h * 0.22)
      ..lineTo(startX + direction * armW * size.width, h * 0.22)
      ..lineTo(elbowX + direction * armW * size.width, h * 0.47)
      ..lineTo(handX + direction * armW * size.width, h * 0.58)
      ..lineTo(handX, h * 0.58)
      ..lineTo(elbowX, h * 0.47)
      ..lineTo(startX, h * 0.22)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HumanSilhouettePainter old) =>
      old.color != color || old.gender != gender;
}
