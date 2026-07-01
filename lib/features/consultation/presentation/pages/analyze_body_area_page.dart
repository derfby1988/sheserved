import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_request_model.dart';
import '../widgets/symptom_ruler_picker.dart';
import '../../../../services/service_locator.dart';
import '../../../admin/data/models/body_landmark_model.dart';
import '../../../admin/data/services/calibration_service.dart';

// ─── Data model for a body region selection ────────────────────────────────
class _BodyRegion {
  final String id;
  final String nameTh;
  final String nameEn;
  final double yRatio; // 0.0 = top, 1.0 = bottom (position on body silhouette)
  final double xRatio; // 0.0 = left, 1.0 = right (horizontal position on body)
  final IconData icon;
  final String iconName; // Material icon name string for DB storage (e.g. 'lens_outlined')
  final bool hasSides; // true = bilateral organ (left/right), false = midline (center only)
  final double modelTopRatio;    // 3D model top calibration in viewport
  final double modelBottomRatio; // 3D model bottom calibration in viewport

  /// v2.0: Optional per-region landmarks for multi-point calibration.
  final List<BodyLandmark>? landmarks;

  const _BodyRegion({
    required this.id,
    required this.nameTh,
    required this.nameEn,
    required this.yRatio,
    this.xRatio = 0.5, // Default to center
    required this.icon,
    required this.iconName,
    this.hasSides = false,
    this.modelTopRatio = 0.08,
    this.modelBottomRatio = 0.93,
    this.landmarks,
  });

  _BodyRegion copyWith({
    List<BodyLandmark>? landmarks,
  }) {
    return _BodyRegion(
      id: id,
      nameTh: nameTh,
      nameEn: nameEn,
      yRatio: yRatio,
      xRatio: xRatio,
      icon: icon,
      iconName: iconName,
      hasSides: hasSides,
      modelTopRatio: modelTopRatio,
      modelBottomRatio: modelBottomRatio,
      landmarks: landmarks ?? this.landmarks,
    );
  }
}

List<_BodyRegion> _bodyRegions = [
  _BodyRegion(
    id: 'top_head',
    nameTh: 'ศีรษะด้านบน',
    nameEn: 'Top of Head',
    yRatio: 0.04,
    xRatio: 0.50,
    icon: Icons.face,
    iconName: 'face',
  ),
  _BodyRegion(
    id: 'forehead',
    nameTh: 'หน้าผาก',
    nameEn: 'Forehead',
    yRatio: 0.07,
    xRatio: 0.50,
    icon: Icons.face_retouching_natural,
    iconName: 'face_retouching_natural',
  ),
  _BodyRegion(
    id: 'eyes',
    nameTh: 'ดวงตา',
    nameEn: 'Eyes',
    yRatio: 0.09,
    xRatio: 0.50,
    icon: Icons.remove_red_eye_outlined,
    iconName: 'remove_red_eye_outlined',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'nose_ears',
    nameTh: 'จมูก/หู',
    nameEn: 'Nose/Ears',
    yRatio: 0.11,
    xRatio: 0.50,
    icon: Icons.hearing_outlined,
    iconName: 'hearing_outlined',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'mouth_jaw',
    nameTh: 'ปาก/กราม',
    nameEn: 'Mouth/Jaw',
    yRatio: 0.13,
    xRatio: 0.50,
    icon: Icons.record_voice_over_outlined,
    iconName: 'record_voice_over_outlined',
  ),
  _BodyRegion(
    id: 'neck',
    nameTh: 'ลำคอ',
    nameEn: 'Neck',
    yRatio: 0.17,
    xRatio: 0.50,
    icon: Icons.compress,
    iconName: 'compress',
  ),
  _BodyRegion(
    id: 'shoulder',
    nameTh: 'หัวไหล่',
    nameEn: 'Shoulder',
    yRatio: 0.22,
    xRatio: 0.38,
    icon: Icons.accessibility_new,
    iconName: 'accessibility_new',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'collarbone',
    nameTh: 'ไหปลาร้า',
    nameEn: 'Collarbone',
    yRatio: 0.25,
    xRatio: 0.42,
    icon: Icons.horizontal_rule,
    iconName: 'horizontal_rule',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'upper_chest',
    nameTh: 'หน้าอกส่วนบน',
    nameEn: 'Upper Chest',
    yRatio: 0.29,
    xRatio: 0.50,
    icon: Icons.monitor_heart_outlined,
    iconName: 'monitor_heart_outlined',
  ),
  _BodyRegion(
    id: 'upper_arm',
    nameTh: 'ต้นแขน',
    nameEn: 'Upper Arm',
    yRatio: 0.33,
    xRatio: 0.28,
    icon: Icons.fitness_center,
    iconName: 'fitness_center',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'lower_chest',
    nameTh: 'หน้าอกส่วนล่าง',
    nameEn: 'Lower Chest',
    yRatio: 0.36,
    xRatio: 0.50,
    icon: Icons.favorite_border,
    iconName: 'favorite_border',
  ),
  _BodyRegion(
    id: 'upper_abd',
    nameTh: 'ท้องส่วนบน',
    nameEn: 'Upper Abdomen',
    yRatio: 0.40,
    xRatio: 0.50,
    icon: Icons.restaurant_menu,
    iconName: 'restaurant_menu',
  ),
  _BodyRegion(
    id: 'elbow',
    nameTh: 'ข้อศอก',
    nameEn: 'Elbow',
    yRatio: 0.44,
    xRatio: 0.22,
    icon: Icons.adjust,
    iconName: 'adjust',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'middle_abd',
    nameTh: 'รอบสะดือ',
    nameEn: 'Navel Area',
    yRatio: 0.47,
    xRatio: 0.50,
    icon: Icons.radio_button_checked,
    iconName: 'radio_button_checked',
  ),
  _BodyRegion(
    id: 'lower_arm',
    nameTh: 'แขนท่อนล่าง',
    nameEn: 'Forearm',
    yRatio: 0.50,
    xRatio: 0.20,
    icon: Icons.pan_tool_alt_outlined,
    iconName: 'pan_tool_alt_outlined',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'lower_abd',
    nameTh: 'ท้องส่วนล่าง',
    nameEn: 'Lower Abdomen',
    yRatio: 0.53,
    xRatio: 0.50,
    icon: Icons.water_drop_outlined,
    iconName: 'water_drop_outlined',
  ),
  _BodyRegion(
    id: 'wrist',
    nameTh: 'ข้อมือ',
    nameEn: 'Wrist',
    yRatio: 0.56,
    xRatio: 0.18,
    icon: Icons.watch_outlined,
    iconName: 'watch_outlined',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'pelvis',
    nameTh: 'เชิงกราน/ก้น',
    nameEn: 'Pelvis/Glutes',
    yRatio: 0.59,
    xRatio: 0.50,
    icon: Icons.trip_origin,
    iconName: 'trip_origin',
  ),
  _BodyRegion(
    id: 'hand',
    nameTh: 'มือ/นิ้วมือ',
    nameEn: 'Hand/Fingers',
    yRatio: 0.62,
    xRatio: 0.15,
    icon: Icons.back_hand_outlined,
    iconName: 'back_hand_outlined',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'upper_thigh',
    nameTh: 'ต้นขาส่วนบน',
    nameEn: 'Upper Thigh',
    yRatio: 0.66,
    xRatio: 0.40,
    icon: Icons.directions_walk,
    iconName: 'directions_walk',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'mid_thigh',
    nameTh: 'ต้นขาส่วนกลาง',
    nameEn: 'Mid Thigh',
    yRatio: 0.71,
    xRatio: 0.38,
    icon: Icons.directions_run,
    iconName: 'directions_run',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'knee',
    nameTh: 'หัวเข่า',
    nameEn: 'Knee',
    yRatio: 0.77,
    xRatio: 0.42,
    icon: Icons.lens_outlined,
    iconName: 'lens_outlined',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'upper_shin',
    nameTh: 'หน้าแข้ง/น่อง',
    nameEn: 'Shin/Calf',
    yRatio: 0.83,
    xRatio: 0.42,
    icon: Icons.linear_scale,
    iconName: 'linear_scale',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'lower_shin',
    nameTh: 'ข้อเท้าด้านบน',
    nameEn: 'Lower Shin',
    yRatio: 0.88,
    xRatio: 0.42,
    icon: Icons.align_vertical_bottom,
    iconName: 'align_vertical_bottom',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'ankle',
    nameTh: 'ข้อเท้า',
    nameEn: 'Ankle',
    yRatio: 0.93,
    xRatio: 0.42,
    icon: Icons.radio_button_unchecked,
    iconName: 'radio_button_unchecked',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'foot',
    nameTh: 'หลังเท้า',
    nameEn: 'Foot',
    yRatio: 0.96,
    xRatio: 0.42,
    icon: Icons.run_circle_outlined,
    iconName: 'run_circle_outlined',
    hasSides: true,
  ),
  _BodyRegion(
    id: 'toes',
    nameTh: 'นิ้วเท้า',
    nameEn: 'Toes',
    yRatio: 0.99,
    xRatio: 0.42,
    icon: Icons.linear_scale_outlined,
    iconName: 'linear_scale_outlined',
    hasSides: true,
  ),
];

const List<String> _medicalSymptoms = [
  'ระบุอาการ',
  'ปกติ',
  'เจ็บ',
  'ปวด',
  'คัน',
  'บวม',
  'แสบ',
  'ระคาย',
  'กระตุก',
  'ชา',
  'เกร็ง',
  'ตึง',
  'เสียด',
  'ร้าว',
  'อักเสบ',
  'เป็นแผล',
];

// ─── Side Enum ────────────────────────────────────────────────────────────
enum _BodySide { left, center, right }

extension _BodySideExt on _BodySide {
  String get labelTh {
    switch (this) {
      case _BodySide.left:
        return 'ซ้าย';
      case _BodySide.center:
        return 'กลาง';
      case _BodySide.right:
        return 'ขวา';
    }
  }

  String get labelEn {
    switch (this) {
      case _BodySide.left:
        return 'Left';
      case _BodySide.center:
        return 'Center';
      case _BodySide.right:
        return 'Right';
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
    final area = side == _BodySide.center
        ? region.nameTh
        : '${region.nameTh}(${side.labelTh})';
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

  // ─── 3D model state ──────────────────────────────────────────────────────
  // When true, the 3D model is freely rotatable/zoomable and the tap overlays
  // are disabled so the user can inspect the body. When false (select mode),
  // the model is locked front-facing and the overlays handle region taps.
  bool _is3dRotateMode = false;

  // ─── v2.0 Calibration state ─────────────────────────────────────────────
  late CalibrationService _calibrationService;
  List<BodyLandmark> _calibrationLandmarks = [];

  /// True only when a real 3D model asset is loaded. Landmark-based
  /// calibration maps 2D silhouette coordinates onto the 3D model viewport,
  /// so it must only be applied when the 3D model is actually shown.
  /// Without a model, the flat 2D silhouette is the reference and the raw
  /// yRatio/xRatio must be used so labels align with the drawn body.
  bool get _use3dCalibration => _is3dModelAssetChecked && _has3dModelAsset;

  /// Resolves a region's abstract yRatio (0..1 on the body silhouette)
  /// into the on-screen vertical ratio.
  ///
  /// v2.0: When a 3D model is present, uses per-region landmarks (or global
  /// calibration defaults) to map onto the 3D viewport. When no model is
  /// present, returns the raw yRatio so labels line up with the 2D silhouette.
  double _modelYRatio(_BodyRegion region) {
    if (!_use3dCalibration) return region.yRatio;
    final landmarks = region.landmarks ?? _calibrationLandmarks;
    return CalibrationService.modelYRatioCompat(
      landmarks,
      region.yRatio,
      modelTopRatio: region.modelTopRatio,
      modelBottomRatio: region.modelBottomRatio,
    );
  }

  /// v2.0: Resolves xRatio using landmark calibration when a 3D model is
  /// present; otherwise returns the raw xRatio for the 2D silhouette.
  double _modelXRatio(_BodyRegion region) {
    if (!_use3dCalibration) return region.xRatio;
    final landmarks = region.landmarks ?? _calibrationLandmarks;
    if (landmarks.isNotEmpty) {
      return CalibrationService.modelXRatio(landmarks, region.xRatio);
    }
    return region.xRatio;
  }

  /// Asset path of the 3D anatomy model for the current gender.
  /// 'both' and unknown genders resolve to the male model so the 2D/3D
  /// representations stay consistent.
  String get _model3dSrc {
    final g = _gender;
    final isMale = g == 'male' || g == 'ชาย' || g == 'm' || g == 'both';
    return isMale
        ? 'assets/models/male_anatomy.glb'
        : 'assets/models/female_anatomy.glb';
  }

  // Animations
  late AnimationController _pulseController;
  late AnimationController _rippleController;
  late Animation<double> _pulseAnim;
  late Animation<double> _rippleAnim;

  String get _gender {
    return widget.request.bodyArea['gender']?.toString().toLowerCase() ??
        'unknown';
  }

  IconData _getIconData(String? iconName) {
    if (iconName == null) return Icons.circle;
    // Map existing icons for backward compatibility
    switch (iconName) {
      case 'face':
        return Icons.face;
      case 'face_retouching_natural':
        return Icons.face_retouching_natural;
      case 'remove_red_eye_outlined':
        return Icons.remove_red_eye_outlined;
      case 'hearing_outlined':
        return Icons.hearing_outlined;
      case 'record_voice_over_outlined':
        return Icons.record_voice_over_outlined;
      case 'compress':
        return Icons.compress;
      case 'accessibility_new':
        return Icons.accessibility_new;
      case 'horizontal_rule':
        return Icons.horizontal_rule;
      case 'monitor_heart_outlined':
        return Icons.monitor_heart_outlined;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'favorite_border':
        return Icons.favorite_border;
      case 'restaurant_menu':
        return Icons.restaurant_menu;
      case 'adjust':
        return Icons.adjust;
      case 'radio_button_checked':
        return Icons.radio_button_checked;
      case 'pan_tool_alt_outlined':
        return Icons.pan_tool_alt_outlined;
      case 'water_drop_outlined':
        return Icons.water_drop_outlined;
      case 'watch_outlined':
        return Icons.watch_outlined;
      case 'trip_origin':
        return Icons.trip_origin;
      case 'back_hand_outlined':
        return Icons.back_hand_outlined;
      case 'directions_walk':
        return Icons.directions_walk;
      case 'directions_run':
        return Icons.directions_run;
      case 'lens_outlined':
        return Icons.lens_outlined;
      case 'linear_scale':
        return Icons.linear_scale;
      case 'align_vertical_bottom':
        return Icons.align_vertical_bottom;
      case 'radio_button_unchecked':
        return Icons.radio_button_unchecked;
      case 'run_circle_outlined':
        return Icons.run_circle_outlined;
      case 'linear_scale_outlined':
        return Icons.linear_scale_outlined;
      default:
        return Icons.accessibility;
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

  bool _has3dModelAsset = false;
  bool _is3dModelAssetChecked = false;

  // ─── Left region panel auto-scroll ───────────────────────────────────────
  final ScrollController _panelScrollController = ScrollController();
  // Key on the panel ListView, used as the viewport reference for measurements.
  final GlobalKey _panelListKey = GlobalKey();
  // GlobalKeys per region row, used to measure position for keep-visible scroll.
  final Map<String, GlobalKey> _regionKeys = {};

  @override
  void initState() {
    super.initState();
    _calibrationService = CalibrationService(Supabase.instance.client);
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

    _check3dModelAvailability();

    _pulseAnim = Tween<double>(begin: 0.8, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _rippleAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _rippleController, curve: Curves.linear));

    _loadSymptomStats();
  }

  Future<void> _check3dModelAvailability() async {
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final g = _gender;
      final isMale = g == 'male' || g == 'ชาย' || g == 'm';
      final assetPath = isMale
          ? 'assets/models/male_anatomy.glb'
          : 'assets/models/female_anatomy.glb';
      final hasAsset = manifest.contains(assetPath);

      if (!mounted) return;
      setState(() {
        _has3dModelAsset = hasAsset;
        _is3dModelAssetChecked = true;
        if (!hasAsset) {
          _is3dRotateMode = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _has3dModelAsset = false;
        _is3dModelAssetChecked = true;
        _is3dRotateMode = false;
      });
    }
  }

  Future<void> _loadSymptomStats() async {
    // Start scan animation
    _scanController.forward();

    try {
      final stats = await ServiceLocator.instance.consultationRepository
          .getSymptomStatistics();
      final dbRegions = await ServiceLocator.instance.bodyRegionRepository
          .getAllRegions();

      // v2.0: Load global calibration defaults for the current gender/platform.
      // Falls back to hardcoded fallback landmarks if DB is unavailable.
      final calibrationGender = _gender == 'unknown' ? 'both' : _gender;
      final landmarks = await _calibrationService.getDefaultLandmarks(
        gender: calibrationGender,
        platform: 'mobile',
      );

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
          _calibrationLandmarks = landmarks;
          if (dbRegions.isNotEmpty) {
            _bodyRegions = dbRegions
                .where((r) {
                  if (r.gender == 'both') return true;
                  return r.gender == _gender;
                })
                .map<_BodyRegion>(
                  (r) => _BodyRegion(
                    id: r.id,
                    nameTh: r.nameTh,
                    nameEn: r.nameEn,
                    yRatio: r.yRatio,
                    xRatio: r.xRatio,
                    icon: _getIconData(r.iconName),
                    iconName: r.iconName ?? '',
                    hasSides: r.hasSides,
                    modelTopRatio: r.modelTopRatio,
                    modelBottomRatio: r.modelBottomRatio,
                    landmarks: r.landmarks ?? landmarks,
                  ),
                )
                .toList()
              ..sort((a, b) => a.yRatio.compareTo(b.yRatio));
          } else {
            // No DB regions: apply global defaults to the hardcoded list.
            _bodyRegions = _bodyRegions
                .map((r) => r.copyWith(landmarks: landmarks))
                .toList();
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
    _panelScrollController.dispose();
    super.dispose();
  }

  /// Scrolls the left region panel so [region]'s row sits at roughly the same
  /// vertical fraction as its position on the body model (via _modelYRatio).
  /// This makes the list "follow" the tapped point on the silhouette. The
  /// target is clamped to the scroll extent, so near the top/bottom the row
  /// simply stays as close as possible while remaining visible. Runs after the
  /// current frame so the target row is laid out and measurable.
  void _ensureRegionVisibleInPanel(_BodyRegion region) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_panelScrollController.hasClients) return;
      final key = _regionKeys[region.id];
      final itemCtx = key?.currentContext;
      final viewport = _panelScrollController.position;
      if (itemCtx == null) return;

      final itemBox = itemCtx.findRenderObject() as RenderBox?;
      final listCtx = _panelListKey.currentContext;
      final listBox = listCtx?.findRenderObject() as RenderBox?;
      if (itemBox == null || listBox == null) return;

      final itemTop = itemBox
          .localToGlobal(Offset.zero, ancestor: listBox)
          .dy;
      final viewHeight = listBox.size.height;
      final itemHeight = itemBox.size.height;

      // Desired position of the row (its center) within the viewport, matching
      // where the region's line is drawn on the model (0..1 of the height).
      final modelRatio = _modelYRatio(region).clamp(0.0, 1.0);
      final desiredTop = viewHeight * modelRatio - itemHeight / 2;

      // Convert the desired viewport position into an absolute scroll offset.
      final target = _panelScrollController.offset + (itemTop - desiredTop);

      _panelScrollController.animateTo(
        target.clamp(viewport.minScrollExtent, viewport.maxScrollExtent),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Determines the side to auto-select for a region given the horizontal
  /// tap position (0.0 = far left, 1.0 = far right). Midline organs always
  /// resolve to [_BodySide.center]; bilateral organs resolve to left/right
  /// based on the tapped half. Returns null when the side cannot be inferred.
  _BodySide? _autoSideForRegion(_BodyRegion region, double? tapXRatio) {
    if (!region.hasSides) return _BodySide.center;
    if (tapXRatio == null) return null;
    return tapXRatio < 0.5 ? _BodySide.left : _BodySide.right;
  }

  void _onRegionTapped(_BodyRegion region, {double? tapXRatio}) async {
    final autoSide = _autoSideForRegion(region, tapXRatio);

    // If it's the same region, keep current selection but allow the user to
    // re-tap the other half to switch sides (for bilateral organs).
    if (_hoveredRegion?.id == region.id) {
      setState(() {
        if (region.hasSides && autoSide != null) {
          _selectedSide = autoSide;
        } else if (!region.hasSides) {
          _selectedSide = _BodySide.center;
        }
        _rippleCenterX = _modelXRatio(region) + _xOffsetForSide(_selectedSide);
        _rippleCenterY = region.yRatio;
      });
      return;
    }

    // Provide immediate haptic feedback
    HapticFeedback.mediumImpact();

    // Phase 1: Show loading indicator immediately
    setState(() {
      _isOpeningPopup = true;
      // Update ripple position immediately for visual response
      _rippleCenterX = _modelXRatio(region) + _xOffsetForSide(autoSide);
      _rippleCenterY = region.yRatio;
    });

    // Phase 2: Wait for one frame so the loading indicator can be painted
    await Future.delayed(const Duration(milliseconds: 50));

    if (!mounted) return;

    // Phase 3: Set the expensive state (popup build)
    setState(() {
      _hoveredRegion = region;
      _popupDragRatio = region.yRatio;
      // Auto-select the side based on where the user tapped (still editable).
      _selectedSide = autoSide;
      _currentSymptom = _medicalSymptoms[0];
    });

    // Keep the selected region visible in the left panel list.
    _ensureRegionVisibleInPanel(region);

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
      // Convert the screen-space drag delta into logical yRatio space.
      // With a 3D model, the silhouette is framed within top/bottom so the
      // delta must be scaled by that span. Without a model the flat silhouette
      // fills the height, so the mapping is identity (span = 1.0).
      final region = _hoveredRegion;
      final top = region?.modelTopRatio ?? 0.08;
      final bottom = region?.modelBottomRatio ?? 0.93;
      final span = _use3dCalibration
          ? (bottom - top).clamp(0.01, 1.0)
          : 1.0;
      _popupDragRatio =
          (_popupDragRatio + details.delta.dy / (_silhouetteH * span)).clamp(
            0.0,
            1.0,
          );
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
        // RESET selection states when organ changes via drag.
        // Midline organs auto-resolve to center; bilateral organs wait for the
        // user to pick a side.
        _selectedSide = closest.hasSides ? null : _BodySide.center;
        _currentSymptom = _medicalSymptoms[0];

        // Update ripple center to follow drag
        _rippleCenterY = closest.yRatio;
        _rippleCenterX = _modelXRatio(closest) + _xOffsetForSide(_selectedSide);

        // Keep the newly hovered region visible in the left panel list.
        _ensureRegionVisibleInPanel(closest);
      }
    });
  }

  /// Returns an x-axis offset based on the selected side
  double _xOffsetForSide(_BodySide? side) {
    switch (side) {
      case _BodySide.left:
        return -0.12;
      case _BodySide.right:
        return 0.12;
      case _BodySide.center:
        return 0.0;
      case null:
        return 0.0;
    }
  }

  void _confirmSelection() {
    if (_hoveredRegion == null ||
        _selectedSide == null ||
        _currentSymptom == _medicalSymptoms[0])
      return;

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    // Map to normalized models
    final symptoms = _selectedPoints
        .map(
          (p) => SymptomPoint(
            regionId: p.region.id,
            side: p.side.labelEn.toLowerCase(),
            symptom: p.symptom,
            displayLabel: p.displayLabel,
            iconName: p.region.iconName,
          ),
        )
        .toList();

    final updatedRequest = widget.request.copyWith(
      bodyArea: {'gender': _gender},
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Left: Scrollable region list (no overlap) ─────────
                      SizedBox(width: 130, child: _buildRegionSidePanel()),
                      // ── Right: Body silhouette ────────────────────────────
                      Expanded(child: _buildBodySilhouette()),
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
          colors: [Color(0xFFE8F5DA), Color(0xFFF5FAF0), Color(0xFFFFFFFF)],
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
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.primary,
                size: 18,
              ),
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // Cart icon
          IconButton(
            icon: const Icon(
              Icons.shopping_cart_outlined,
              color: AppColors.cartIcon,
              size: 24,
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  // ─── Left side panel: scrollable list of body regions (no overlap) ───────
  Widget _buildRegionSidePanel() {
    return Container(
      margin: const EdgeInsets.only(left: 8, top: 12, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ListView.builder(
          key: _panelListKey,
          controller: _panelScrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _bodyRegions.length,
          itemBuilder: (context, index) {
            final region = _bodyRegions[index];
            final isHovered = _hoveredRegion?.id == region.id;
            final isConfirmed = _selectedPoints.any((p) => p.region.id == region.id);
            final count = _symptomStats[region.id] ?? 0;
            final rowKey = _regionKeys.putIfAbsent(region.id, () => GlobalKey());

            return GestureDetector(
              key: rowKey,
              onTap: () {
                // Tap on the panel acts like tapping the center of the region.
                _onRegionTapped(region, tapXRatio: 0.5);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isHovered
                      ? AppColors.primary.withOpacity(0.12)
                      : isConfirmed
                          ? AppColors.primary.withOpacity(0.08)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isHovered
                        ? AppColors.primary.withOpacity(0.4)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      region.icon,
                      size: 16,
                      color: isHovered
                          ? AppColors.primary
                          : isConfirmed
                              ? AppColors.primary
                              : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        region.nameTh,
                        style: TextStyle(
                          fontSize: isHovered ? 12 : 11,
                          fontWeight: isHovered || count > 0
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isHovered
                              ? AppColors.primary
                              : Colors.grey.shade800,
                        ),
                      ),
                    ),
                    if (isConfirmed)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
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

        return Stack(
          clipBehavior: Clip.none, // Allow popup to overflow side panels
          children: [
            // ─── Background GestureDetector (Catch taps only when child doesn't) ───
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  if (_is3dRotateMode) return;
                  // Compare the tap's on-screen vertical ratio directly against
                  // each region's on-screen ratio (via _modelYRatio). This works
                  // for both the flat 2D silhouette (raw yRatio) and the 3D model
                  // (landmark-mapped), so detection always matches the drawn lines.
                  final tapYRatio = (details.localPosition.dy / h).clamp(
                    0.0,
                    1.0,
                  );
                  final tapXRatio = (details.localPosition.dx / w).clamp(
                    0.0,
                    1.0,
                  );
                  _BodyRegion? closest;
                  double minDist = double.infinity;
                  for (final r in _bodyRegions) {
                    final dist = (_modelYRatio(r) - tapYRatio).abs();
                    if (dist < minDist) {
                      minDist = dist;
                      closest = r;
                    }
                  }
                  if (closest != null) {
                    _onRegionTapped(closest, tapXRatio: tapXRatio);
                  }
                },
              ),
            ),
            // Background glass card
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.06),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Water ripple effect from selected organ center
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: AnimatedBuilder(
                  animation: _rippleAnim,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _RipplePainter(
                        progress: _rippleAnim.value,
                        centerX: _rippleCenterX,
                        centerY: _hoveredRegion != null
                          ? _modelYRatio(_hoveredRegion!)
                          : _rippleCenterY,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Faint silhouette behind the 3D model — acts as a graceful
            // fallback while the model loads or if it fails on a platform.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  // Landmark guides are an admin calibration aid only. Their
                  // y2d values are tuned for the 3D model, not this simplified
                  // 2D silhouette, so they must not be drawn on the
                  // patient-facing page (they would mislead the user).
                  painter: _HumanSilhouettePainter(
                    color: AppColors.primary.withOpacity(0.08),
                    gender: _gender,
                  ),
                ),
              ),
            ),

            // === 3D anatomy model / placeholder ===
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                child: _build3dModelViewport(),
              ),
            ),

            // Horizontal region tap lines + labels
            if (!_is3dRotateMode)
              ...List.generate(_bodyRegions.length, (i) {
                final region = _bodyRegions[i];
                final topY = h * _modelYRatio(region);
                final isHovered = _hoveredRegion?.id == region.id;
                final isConfirmed = _selectedPoints.any(
                  (p) => p.region.id == region.id,
                );

                return Positioned(
                  top: topY - 12,
                  left: 0,
                  right: 0,
                child: GestureDetector(
                  onTapDown: (details) {
                    final tapXRatio = (details.localPosition.dx / w).clamp(
                      0.0,
                      1.0,
                    );
                    _onRegionTapped(region, tapXRatio: tapXRatio);
                  },
                  behavior: HitTestBehavior.translucent,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 24,
                    child: Row(
                      children: [
                        // Left endpoint dot
                        _buildSideEndpoint(
                          isHovered,
                          isConfirmed,
                          _BodySide.left,
                        ),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: isHovered ? 2.0 : 0.8,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isHovered
                                    ? [
                                        AppColors.primary.withOpacity(0.8),
                                        AppColors.primaryLight.withOpacity(0.9),
                                        AppColors.primary.withOpacity(0.8),
                                      ]
                                    : isConfirmed
                                    ? [
                                        AppColors.primary.withOpacity(0.4),
                                        AppColors.primary.withOpacity(0.4),
                                      ]
                                    : [
                                        Colors.grey.withOpacity(0.2),
                                        Colors.grey.withOpacity(0.1),
                                      ],
                              ),
                            ),
                          ),
                        ),
                        // Right endpoint dot
                        _buildSideEndpoint(
                          isHovered,
                          isConfirmed,
                          _BodySide.right,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            // Hovered region: draggable label + confirm button
            if (_hoveredRegion != null && !_is3dRotateMode)
              _buildHoveredLabel(h),

            // Feedback if popup is still 'opening' (busy UI thread)
            if (_isOpeningPopup)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),

            // Confirmed points: small dot indicators on body
            if (!_is3dRotateMode)
              ..._selectedPoints.map((point) {
                final topY = h * _modelYRatio(point.region);
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

            // 3D rotate / inspect toggle button
            Positioned(
              top: 20,
              right: 16,
              child: _build3dToggleButton(),
            ),

            // Hint shown while inspecting in 3D rotate mode
            if (_is3dRotateMode)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ลากเพื่อหมุน • บีบเพื่อซูม',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ─── 3D rotate / inspect toggle ──────────────────────────────────────────
  Widget _build3dToggleButton() {
    final canUse3d = _is3dModelAssetChecked && _has3dModelAsset;
    final active = canUse3d && _is3dRotateMode;
    return GestureDetector(
      onTap: canUse3d
          ? () {
              HapticFeedback.selectionClick();
              setState(() => _is3dRotateMode = !_is3dRotateMode);
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? AppColors.primaryGradient : null,
          color: active
              ? null
              : canUse3d
                  ? Colors.white.withOpacity(0.85)
                  : Colors.white.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? Colors.transparent
                : canUse3d
                    ? AppColors.primary.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.2),
          ),
          boxShadow: [
            if (canUse3d)
              BoxShadow(
                color: AppColors.primary.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              !canUse3d
                  ? Icons.image_not_supported_outlined
                  : active
                      ? Icons.touch_app_outlined
                      : Icons.threed_rotation,
              size: 16,
              color: !canUse3d
                  ? Colors.grey.shade500
                  : active
                      ? Colors.white
                      : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              !canUse3d
                  ? 'ไม่มีโมเดล 3D'
                  : active
                      ? 'โหมดเลือก'
                      : 'หมุนดู 3D',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: !canUse3d
                    ? Colors.grey.shade500
                    : active
                        ? Colors.white
                        : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build3dModelViewport() {
    if (_is3dModelAssetChecked && _has3dModelAsset) {
      return IgnorePointer(
        ignoring: !_is3dRotateMode,
        child: ModelViewer(
          key: ValueKey('model_${_model3dSrc}_$_is3dRotateMode'),
          src: _model3dSrc,
          alt: 'แบบจำลองร่างกาย 3 มิติ',
          ar: false,
          autoRotate: false,
          cameraControls: _is3dRotateMode,
          disableZoom: !_is3dRotateMode,
          disablePan: !_is3dRotateMode,
          disableTap: true,
          backgroundColor: Colors.transparent,
          shadowIntensity: 0.8,
          exposure: 1.05,
          cameraOrbit: '0deg 90deg auto',
          minCameraOrbit: 'auto auto auto',
          maxCameraOrbit: 'auto auto auto',
          interactionPrompt: InteractionPrompt.none,
        ),
      );
    }

    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.04),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.view_in_ar_outlined,
                  size: 16,
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _is3dModelAssetChecked
                        ? 'ไม่มีโมเดล 3D'
                        : 'กำลังตรวจสอบโมเดล...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A4D10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideEndpoint(bool isHovered, bool isConfirmed, _BodySide side) {
    final bool pointOnSide = _selectedPoints.any((p) => p.side == side);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isHovered
          ? 10
          : (isConfirmed || pointOnSide)
          ? 7
          : 4,
      height: isHovered
          ? 10
          : (isConfirmed || pointOnSide)
          ? 7
          : 4,
      decoration: BoxDecoration(
        color: isHovered
            ? AppColors.primary
            : (isConfirmed || pointOnSide)
            ? AppColors.primary.withOpacity(0.5)
            : Colors.grey.withOpacity(0.3),
        shape: BoxShape.circle,
        boxShadow: isHovered
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.5),
                  blurRadius: 6,
                ),
              ]
            : [],
      ),
    );
  }

  Widget _buildHoveredLabel(double h) {
    final region = _hoveredRegion!;
    // Use _popupDragRatio (updated by drag) instead of region.yRatio directly,
    // mapped through the model framing transform so it aligns with the body.
    final labelTop = (h * _modelYRatio(region) - 28).clamp(
      12.0,
      h - 70.0,
    );

    return Positioned(
      top: labelTop,
      right: 12, // More padding from edge
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: _onPopupDrag,
        onTap:
            () {}, // Absorb taps to prevent them from reaching the background silhouette
        onVerticalDragEnd: (_) {},
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 5,
              ), // Reduced vertical padding
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.12),
                    blurRadius: 25,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag indicator handle - More subtle
                  Container(
                    width: 30,
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 5),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Icon (Circular accent)
                      Container(
                        padding: const EdgeInsets.all(6), // Reduced padding
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          region.icon,
                          color: Colors.white,
                          size: 18,
                        ), // Smaller icon
                      ),

                      const SizedBox(width: 12),

                      // 2. Side Selector
                      _buildInlineSideSelector(),

                      const SizedBox(width: 8),

                      // 3. Symptom Ruler
                      SymptomRulerPicker(
                        key: ValueKey('ruler_${region.id}'),
                        symptoms: _medicalSymptoms,
                        initialSymptom: _currentSymptom,
                        onChanged: (val) {
                          setState(() => _currentSymptom = val);
                        },
                      ),

                      const SizedBox(width: 8),

                      // 4. Premium 'เพิ่ม' Action
                      GestureDetector(
                        onTap:
                            (_selectedSide != null &&
                                _currentSymptom != _medicalSymptoms[0])
                            ? _confirmSelection
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 7,
                          ), // Reduced vertical padding
                          decoration: BoxDecoration(
                            gradient:
                                (_selectedSide != null &&
                                    _currentSymptom != _medicalSymptoms[0])
                                ? AppColors.goldGradient
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFFE0E0E0),
                                      Color(0xFFF0F0F0),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow:
                                (_selectedSide != null &&
                                    _currentSymptom != _medicalSymptoms[0])
                                ? [
                                    BoxShadow(
                                      color: AppColors.accent.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'เพิ่ม',
                            style: TextStyle(
                              color:
                                  (_selectedSide != null &&
                                      _currentSymptom != _medicalSymptoms[0])
                                  ? Colors.white
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
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
    final region = _hoveredRegion;
    // Midline organs (no left/right) show a static "กึ่งกลาง" indicator instead
    // of a toggle, so the user is not asked to choose an irrelevant side.
    if (region != null && !region.hasSides) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.vertical_align_center,
              size: 12,
              color: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              _BodySide.center.labelTh,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      );
    }

    // Bilateral organs: offer only ซ้าย / ขวา (the auto-detected one is
    // pre-highlighted but the user can switch).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_BodySide.left, _BodySide.right].map((s) {
        final isSelected = _selectedSide == s;
        final sideColor = _sideColor(s);
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedSide = s;
              // Update ripple X to reflect the selected side
              if (_hoveredRegion != null) {
                _rippleCenterX = _modelXRatio(_hoveredRegion!) + _xOffsetForSide(s);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: isSelected ? sideColor : const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? sideColor : Colors.grey.withOpacity(0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  s == _BodySide.left
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                  size: 12,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
                Text(
                  s.labelTh,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Bottom panel: tags + center button ───────────────────────────────────
  Widget _buildBottomPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(28),
        topRight: Radius.circular(28),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
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
              const Icon(
                Icons.location_on_outlined,
                color: AppColors.primary,
                size: 18,
              ),
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
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Text(
                'แตะบนร่างกายเพื่อระบุจุดที่มีอาการ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
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
                    backgroundColor: tagColor.withOpacity(0.12),
                    side: BorderSide(
                      color: tagColor.withOpacity(0.4),
                      width: 1,
                    ),
                    avatar: Icon(point.region.icon, color: tagColor, size: 18),
                    label: Text(
                      point.displayLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tagColor,
                      ),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 12),
                    deleteIconColor: tagColor.withOpacity(0.7),
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
                              color: AppColors.primary.withOpacity(0.35),
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
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
          ),
        ),
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
            color: Colors.white.withOpacity(0.8),
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
                            color: AppColors.primary.withOpacity(0.2),
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
                          backgroundColor: AppColors.primary.withOpacity(0.1),
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
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 16 * pulseAnim.value * 0.5,
            height: 16 * pulseAnim.value * 0.5,
            decoration: BoxDecoration(
              color: color.withOpacity(0.25),
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
                  color: color.withOpacity(0.5),
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
  final double centerX; // 0.0 → 1.0 ratio
  final double centerY; // 0.0 → 1.0 ratio

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
      ..color = const Color(0xFF71BE0A).withOpacity(0.25)
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

  _HumanSilhouettePainter({
    required this.color,
    required this.gender,
  });

  bool get _isMale => gender == 'male' || gender == 'ชาย' || gender == 'm' || gender == 'both';

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.05),
          color.withOpacity(0.2),
          color.withOpacity(0.05),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final cx = size.width / 2;
    final h = size.height;

    void drawShape(Path path) {
      canvas.drawPath(path, paint);
      canvas.drawPath(path, strokePaint);
    }

    // === HEAD ===
    final headRadius = size.width * 0.095;
    final headPath = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(cx, h * 0.07),
          width: headRadius * 2,
          height: headRadius * 2.2,
        ),
      );
    drawShape(headPath);

    // === NECK ===
    final neckPath = Path()
      ..moveTo(cx - size.width * 0.03, h * 0.14)
      ..lineTo(cx + size.width * 0.03, h * 0.14)
      ..lineTo(cx + size.width * 0.05, h * 0.19)
      ..lineTo(cx - size.width * 0.05, h * 0.19)
      ..close();
    drawShape(neckPath);

    // === TORSO (wider for male) ===
    final shoulderW = _isMale ? 0.22 : 0.18;
    final waistW = _isMale ? 0.14 : 0.12;
    final hipW = _isMale ? 0.15 : 0.17;

    final torsoPath = Path()
      ..moveTo(cx - size.width * shoulderW, h * 0.20)
      ..quadraticBezierTo(cx, h * 0.18, cx + size.width * shoulderW, h * 0.20)
      ..lineTo(cx + size.width * waistW, h * 0.47)
      ..lineTo(cx + size.width * hipW, h * 0.55)
      ..lineTo(cx - size.width * hipW, h * 0.55)
      ..lineTo(cx - size.width * waistW, h * 0.47)
      ..close();
    drawShape(torsoPath);

    // === ARMS ===
    final armW = _isMale ? 0.06 : 0.05;
    // Left arm
    _drawArm(
      canvas,
      paint,
      strokePaint,
      size,
      cx,
      h,
      startX: cx - size.width * shoulderW,
      isLeft: true,
      armW: armW,
    );
    // Right arm
    _drawArm(
      canvas,
      paint,
      strokePaint,
      size,
      cx,
      h,
      startX: cx + size.width * shoulderW,
      isLeft: false,
      armW: armW,
    );

    // === LEGS ===
    // Left leg
    final leftLegPath = Path()
      ..moveTo(cx - size.width * hipW, h * 0.55)
      ..lineTo(cx - size.width * 0.03, h * 0.57)
      ..lineTo(cx - size.width * 0.04, h * 0.78) // knee
      ..quadraticBezierTo(
        cx - size.width * 0.05,
        h * 0.79,
        cx - size.width * 0.06,
        h * 0.78,
      )
      ..lineTo(cx - size.width * 0.15, h * 0.57)
      ..close();
    drawShape(leftLegPath);

    // Right leg
    final rightLegPath = Path()
      ..moveTo(cx + size.width * hipW, h * 0.55)
      ..lineTo(cx + size.width * 0.03, h * 0.57)
      ..lineTo(cx + size.width * 0.04, h * 0.78) // knee
      ..quadraticBezierTo(
        cx + size.width * 0.05,
        h * 0.79,
        cx + size.width * 0.06,
        h * 0.78,
      )
      ..lineTo(cx + size.width * 0.15, h * 0.57)
      ..close();
    drawShape(rightLegPath);

    // Left shin + foot
    final leftShinPath = Path()
      ..moveTo(cx - size.width * 0.06, h * 0.78)
      ..lineTo(cx - size.width * 0.04, h * 0.78)
      ..lineTo(cx - size.width * 0.05, h * 0.96)
      ..lineTo(cx - size.width * 0.07, h * 0.96)
      ..close();
    drawShape(leftShinPath);

    // Right shin + foot
    final rightShinPath = Path()
      ..moveTo(cx + size.width * 0.04, h * 0.78)
      ..lineTo(cx + size.width * 0.06, h * 0.78)
      ..lineTo(cx + size.width * 0.07, h * 0.96)
      ..lineTo(cx + size.width * 0.05, h * 0.96)
      ..close();
    drawShape(rightShinPath);

    // Feet
    for (final foot in [-1, 1]) {
      final fCx = cx + foot * size.width * 0.06;
      final footPath = Path()
        ..addOval(
          Rect.fromCenter(
            center: Offset(fCx, h * 0.97),
            width: size.width * 0.075,
            height: size.height * 0.02,
          ),
        );
      drawShape(footPath);
    }
  }

  void _drawArm(
    Canvas canvas,
    Paint paint,
    Paint strokePaint,
    Size size,
    double cx,
    double h, {
    required double startX,
    required bool isLeft,
    required double armW,
  }) {
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
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _HumanSilhouettePainter old) =>
      old.color != color || old.gender != gender;
}
