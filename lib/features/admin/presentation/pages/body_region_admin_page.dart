import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/body_region_model.dart';
import '../../data/models/body_landmark_model.dart';
import '../../data/services/calibration_service.dart';
import '../../data/repositories/body_region_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../shared/widgets/widgets.dart';

/// Map Material icon name string → IconData
IconData? _iconNameToIconData(String? name) {
  switch (name) {
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
    default: return null;
  }
}

Widget _buildFilePickerRow({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 108,
          height: 40,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text(
              'เลือกไฟล์',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    ),
  );
}

class BodyRegionAdminPage extends StatefulWidget {
  const BodyRegionAdminPage({super.key});

  @override
  State<BodyRegionAdminPage> createState() => _BodyRegionAdminPageState();
}

class _BodyRegionAdminPageState extends State<BodyRegionAdminPage> {
  final BodyRegionRepository _repository = BodyRegionRepository(Supabase.instance.client);
  List<BodyRegionModel> _regions = [];
  bool _isLoading = true;
  bool _showMap = true; // Toggle between List and Map view
  String? _tableError;

  static const List<BodyRegionModel> _defaultRegions = [
    BodyRegionModel(id: 'top_head',   nameTh: 'ศีรษะด้านบน',  nameEn: 'Top of Head',   yRatio: 0.04, xRatio: 0.50, iconName: 'face', gender: 'both', hasSides: false, displayOrder: 1),
    BodyRegionModel(id: 'forehead',   nameTh: 'หน้าผาก',      nameEn: 'Forehead',      yRatio: 0.07, xRatio: 0.50, iconName: 'face_retouching_natural', gender: 'both', hasSides: false, displayOrder: 2),
    BodyRegionModel(id: 'eyes',       nameTh: 'ดวงตา',        nameEn: 'Eyes',          yRatio: 0.09, xRatio: 0.50, iconName: 'remove_red_eye_outlined', gender: 'both', hasSides: true, displayOrder: 3),
    BodyRegionModel(id: 'nose_ears',  nameTh: 'จมูก/หู',      nameEn: 'Nose/Ears',     yRatio: 0.11, xRatio: 0.50, iconName: 'hearing_outlined', gender: 'both', hasSides: true, displayOrder: 4),
    BodyRegionModel(id: 'mouth_jaw',  nameTh: 'ปาก/กราม',     nameEn: 'Mouth/Jaw',     yRatio: 0.13, xRatio: 0.50, iconName: 'record_voice_over_outlined', gender: 'both', hasSides: false, displayOrder: 5),
    BodyRegionModel(id: 'neck',       nameTh: 'ลำคอ',         nameEn: 'Neck',          yRatio: 0.17, xRatio: 0.50, iconName: 'compress', gender: 'both', hasSides: false, displayOrder: 6),
    BodyRegionModel(id: 'shoulder',   nameTh: 'หัวไหล่',      nameEn: 'Shoulder',      yRatio: 0.22, xRatio: 0.38, iconName: 'accessibility_new', gender: 'both', hasSides: true, displayOrder: 7),
    BodyRegionModel(id: 'collarbone', nameTh: 'ไหปลาร้า',     nameEn: 'Collarbone',    yRatio: 0.25, xRatio: 0.42, iconName: 'horizontal_rule', gender: 'both', hasSides: true, displayOrder: 8),
    BodyRegionModel(id: 'upper_chest',nameTh: 'หน้าอกส่วนบน', nameEn: 'Upper Chest',   yRatio: 0.29, xRatio: 0.50, iconName: 'monitor_heart_outlined', gender: 'both', hasSides: false, displayOrder: 9),
    BodyRegionModel(id: 'upper_arm',  nameTh: 'ต้นแขน',       nameEn: 'Upper Arm',     yRatio: 0.33, xRatio: 0.28, iconName: 'fitness_center', gender: 'both', hasSides: true, displayOrder: 10),
    BodyRegionModel(id: 'lower_chest',nameTh: 'หน้าอกส่วนล่าง',nameEn: 'Lower Chest',   yRatio: 0.36, xRatio: 0.50, iconName: 'favorite_border', gender: 'both', hasSides: false, displayOrder: 11),
    BodyRegionModel(id: 'upper_abd',  nameTh: 'ท้องส่วนบน',   nameEn: 'Upper Abdomen', yRatio: 0.40, xRatio: 0.50, iconName: 'restaurant_menu', gender: 'both', hasSides: false, displayOrder: 12),
    BodyRegionModel(id: 'elbow',      nameTh: 'ข้อศอก',       nameEn: 'Elbow',         yRatio: 0.44, xRatio: 0.22, iconName: 'adjust', gender: 'both', hasSides: true, displayOrder: 13),
    BodyRegionModel(id: 'middle_abd', nameTh: 'รอบสะดือ',     nameEn: 'Navel Area',    yRatio: 0.47, xRatio: 0.50, iconName: 'radio_button_checked', gender: 'both', hasSides: false, displayOrder: 14),
    BodyRegionModel(id: 'lower_arm',  nameTh: 'แขนท่อนล่าง',  nameEn: 'Forearm',       yRatio: 0.50, xRatio: 0.20, iconName: 'pan_tool_alt_outlined', gender: 'both', hasSides: true, displayOrder: 15),
    BodyRegionModel(id: 'lower_abd',  nameTh: 'ท้องส่วนล่าง',  nameEn: 'Lower Abdomen', yRatio: 0.53, xRatio: 0.50, iconName: 'water_drop_outlined', gender: 'both', hasSides: false, displayOrder: 16),
    BodyRegionModel(id: 'wrist',      nameTh: 'ข้อมือ',       nameEn: 'Wrist',         yRatio: 0.56, xRatio: 0.18, iconName: 'watch_outlined', gender: 'both', hasSides: true, displayOrder: 17),
    BodyRegionModel(id: 'pelvis',     nameTh: 'เชิงกราน/ก้น', nameEn: 'Pelvis/Glutes', yRatio: 0.59, xRatio: 0.50, iconName: 'trip_origin', gender: 'both', hasSides: false, displayOrder: 18),
    BodyRegionModel(id: 'hand',       nameTh: 'มือ/นิ้วมือ',  nameEn: 'Hand/Fingers',  yRatio: 0.62, xRatio: 0.15, iconName: 'back_hand_outlined', gender: 'both', hasSides: true, displayOrder: 19),
    BodyRegionModel(id: 'upper_thigh',nameTh: 'ต้นขาส่วนบน',  nameEn: 'Upper Thigh',   yRatio: 0.66, xRatio: 0.40, iconName: 'directions_walk', gender: 'both', hasSides: true, displayOrder: 20),
    BodyRegionModel(id: 'mid_thigh',  nameTh: 'ต้นขาส่วนกลาง',nameEn: 'Mid Thigh',     yRatio: 0.71, xRatio: 0.38, iconName: 'directions_run', gender: 'both', hasSides: true, displayOrder: 21),
    BodyRegionModel(id: 'knee',       nameTh: 'หัวเข่า',      nameEn: 'Knee',          yRatio: 0.77, xRatio: 0.42, iconName: 'lens_outlined', gender: 'both', hasSides: true, displayOrder: 22),
    BodyRegionModel(id: 'upper_shin', nameTh: 'หน้าแข้ง/น่อง',nameEn: 'Shin/Calf',     yRatio: 0.83, xRatio: 0.42, iconName: 'linear_scale', gender: 'both', hasSides: true, displayOrder: 23),
    BodyRegionModel(id: 'lower_shin', nameTh: 'ข้อเท้าด้านบน',nameEn: 'Lower Shin',    yRatio: 0.88, xRatio: 0.42, iconName: 'align_vertical_bottom', gender: 'both', hasSides: true, displayOrder: 24),
    BodyRegionModel(id: 'ankle',      nameTh: 'ข้อเท้า',      nameEn: 'Ankle',         yRatio: 0.93, xRatio: 0.42, iconName: 'radio_button_unchecked', gender: 'both', hasSides: true, displayOrder: 25),
    BodyRegionModel(id: 'foot',       nameTh: 'หลังเท้า',     nameEn: 'Foot',          yRatio: 0.96, xRatio: 0.42, iconName: 'run_circle_outlined', gender: 'both', hasSides: true, displayOrder: 26),
    BodyRegionModel(id: 'toes',       nameTh: 'นิ้วเท้า',     nameEn: 'Toes',          yRatio: 0.99, xRatio: 0.42, iconName: 'linear_scale_outlined', gender: 'both', hasSides: true, displayOrder: 27),
  ];

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    setState(() {
      _isLoading = true;
      _tableError = null;
    });
    try {
      final regions = await _repository.getAllRegions();
      if (mounted) {
        setState(() {
          _regions = regions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading regions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (e.toString().contains('PGRST205')) {
            _tableError = 'ไม่พบตาราง body_regions ในกลุ่มข้อมูลสาธารณะ (Schema Cache)\nกรุณาลองกดปุ่มรีเฟรชด้านบน หรือตรวจสอบ SQL ใน Supabase Editor';
          } else {
            _tableError = 'เกิดข้อผิดพลาด: $e';
          }
        });
      }
    }
  }

  Future<void> _seedData() async {
    setState(() => _isLoading = true);
    try {
      await _repository.seedInitialRegions(_defaultRegions);
      await _loadRegions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('นำเข้าข้อมูลเริ่มต้นสำเร็จ')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error seeding: $e')));
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditor([BodyRegionModel? region]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _BodyRegionEditorPage(
          repository: _repository,
          region: region,
          onSave: () {
            _loadRegions();
          },
        ),
      ),
    );
  }

  void _deleteRegion(BodyRegionModel region) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('คุณต้องการลบ "${region.nameTh}" ใช่หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('ลบ', style: TextStyle(color: Colors.red))
          ),
        ],
      )
    );

    if (confirm == true) {
      try {
        await _repository.deleteRegion(region.id);
        _loadRegions();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  Color _getRegionColor(BodyRegionModel region) {
    if (region.colorHex != null && region.colorHex!.isNotEmpty) {
      try {
        final hex = region.colorHex!.replaceAll('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      } catch (e) {
        debugPrint('Error parsing colorHex: $e');
      }
    }
    
    // Fallback to generated color based on ID
    final int hash = region.id.split('').fold(0, (prev, element) => prev + element.codeUnitAt(0));
    final List<Color> palette = [
      Colors.red.shade400,
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.teal.shade400,
      Colors.pink.shade400,
      Colors.indigo.shade400,
      Colors.cyan.shade400,
      Colors.amber.shade400,
      Colors.deepOrange.shade400,
      Colors.brown.shade400,
      Colors.blueGrey.shade400,
      Colors.lime.shade700,
    ];
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 16),
        child: Container(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TlzAppTopBar.onPrimary(
                searchHintText: 'ค้นหาอวัยวะ...',
                notificationCategory: 'admin',
              ),
            ),
          ),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _tableError != null 
          ? _buildTableErrorView()
          : _showMap ? _buildMapView() : _buildListView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('เพิ่มอวัยวะ', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildTableErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.table_rows_outlined, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'ตรวจพบปัญหาการเชื่อมต่อตาราง',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _tableError ?? 'Unknown table error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadRegions,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่อีกครั้ง'),
            ),
            const SizedBox(height: 12),
            const Text(
              'หากคุณยังไม่ได้รัน SQL ใน Supabase\nกรุณาใช้โค้ดที่ผมเตรียมไว้ให้ในแชทครับ',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    if (_regions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.accessibility_new, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('ยังไม่มีข้อมูลอวัยวะ', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _seedData, child: const Text('นำเข้าข้อมูลเริ่มต้น')),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _regions.length,
      itemBuilder: (context, index) {
        final region = _regions[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getRegionColor(region).withOpacity(0.1),
              child: Icon(Icons.accessibility, color: _getRegionColor(region)),
            ),
            title: Text('${region.nameTh} (${region.nameEn})'),
            subtitle: Text('X: ${region.xRatio.toStringAsFixed(2)}, Y: ${region.yRatio.toStringAsFixed(2)} | เพศ: ${region.gender}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showEditor(region),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteRegion(region),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapView() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('จุดตำแหน่งอวัยวะทั้งหมดที่มีในระบบ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Silhouette
                    Center(
                      child: AspectRatio(
                        aspectRatio: 0.5,
                        child: CustomPaint(
                          painter: _HumanSilhouettePainter(
                            color: Colors.grey.shade300,
                            gender: 'both',
                            selectedSide: 0,
                          ),
                          child: Container(),
                        ),
                      ),
                    ),
                    // All Points — show Material icon or custom image
                    ..._regions.map((region) {
                      final left = constraints.maxWidth * region.xRatio - 14;
                      final top = constraints.maxHeight * region.yRatio - 14;
                      final iconData = _iconNameToIconData(region.iconName);
                      return Positioned(
                        left: left,
                        top: top,
                        child: Tooltip(
                          message: region.nameTh,
                          child: GestureDetector(
                            onTap: () => _showEditor(region),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getRegionColor(region),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  )
                                ],
                              ),
                              child: region.iconImageUrl != null && region.iconImageUrl!.isNotEmpty
                                ? ClipOval(
                                    child: Image.network(
                                      region.iconImageUrl!,
                                      width: 24,
                                      height: 24,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        iconData ?? Icons.circle,
                                        size: 16,
                                        color: _getRegionColor(region),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Icon(
                                      iconData ?? Icons.circle,
                                      size: 16,
                                      color: _getRegionColor(region),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                );
              },
            ),
          ),
        ),
        if (_regions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: ElevatedButton(onPressed: _seedData, child: const Text('นำเข้าข้อมูลเริ่มต้น')),
          ),
      ],
    );
  }

}

class _BodyRegionEditorPage extends StatefulWidget {
  final BodyRegionRepository repository;
  final BodyRegionModel? region;
  final VoidCallback onSave;

  const _BodyRegionEditorPage({
    required this.repository,
    this.region,
    required this.onSave,
  });

  @override
  State<_BodyRegionEditorPage> createState() => _BodyRegionEditorPageState();
}

class _BodyRegionEditorPageState extends State<_BodyRegionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _idCtrl;
  late TextEditingController _nameThCtrl;
  late TextEditingController _nameEnCtrl;
  late TextEditingController _iconNameCtrl;
  late TextEditingController _displayOrderCtrl;

  double _xRatio = 0.5;
  double _yRatio = 0.5;
  bool _hasSides = false;
  String _gender = 'both';
  String? _colorHex;

  // 3D model viewport calibration (how much the 3D model is inset within the viewport)
  double _modelTopRatio = 0.08;
  double _modelBottomRatio = 0.93;

  // ── v2.0 Multi-Point Calibration ───────────────────────────────────────
  /// Whether this region uses its own landmark override (true) or global defaults (false).
  bool _useLandmarkOverride = false;

  /// Per-region landmarks (only used when [_useLandmarkOverride] is true).
  List<BodyLandmark> _landmarks = [];

  /// Calibration target gender for this region.
  String _calibrationGender = 'both';

  /// Calibration target platform for this region.
  String _calibrationPlatform = 'universal';

  File? _iconImageFile;
  File? _image2dFile;
  File? _model3dFile;
  bool _isSaving = false;

  // Toggle between 2D picker view and 3D reference body view in the position picker
  bool _show3dReference = false;

  bool get isEditing => widget.region != null;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController(text: widget.region?.id ?? '');
    _nameThCtrl = TextEditingController(text: widget.region?.nameTh ?? '');
    _nameEnCtrl = TextEditingController(text: widget.region?.nameEn ?? '');
    _iconNameCtrl = TextEditingController(text: widget.region?.iconName ?? '');
    _displayOrderCtrl = TextEditingController(text: widget.region?.displayOrder.toString() ?? '0');
    
    _xRatio = widget.region?.xRatio ?? 0.5;
    _yRatio = widget.region?.yRatio ?? 0.5;
    _hasSides = widget.region?.hasSides ?? false;
    _gender = widget.region?.gender ?? 'both';
    _colorHex = widget.region?.colorHex;
    _modelTopRatio = widget.region?.modelTopRatio ?? 0.08;
    _modelBottomRatio = widget.region?.modelBottomRatio ?? 0.93;

    // v2.0 init
    _useLandmarkOverride = widget.region?.landmarks != null && widget.region!.landmarks!.isNotEmpty;
    _landmarks = widget.region?.landmarks != null
        ? List<BodyLandmark>.from(widget.region!.landmarks!)
        : CalibrationService.autoDetectLandmarks();
    _calibrationGender = widget.region?.calibrationGender ?? 'both';
    _calibrationPlatform = widget.region?.calibrationPlatform ?? 'universal';
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameThCtrl.dispose();
    _nameEnCtrl.dispose();
    _iconNameCtrl.dispose();
    _displayOrderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick2dImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image2dFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _pick3dModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['glb', 'obj', 'gltf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _model3dFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> _pickIconImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _iconImageFile = File(pickedFile.path));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final model = BodyRegionModel(
        id: _idCtrl.text.trim(),
        nameTh: _nameThCtrl.text.trim(),
        nameEn: _nameEnCtrl.text.trim(),
        yRatio: _yRatio,
        xRatio: _xRatio,
        iconName: _iconNameCtrl.text.trim(),
        hasSides: _hasSides,
        gender: _gender,
        colorHex: _colorHex,
        modelTopRatio: _modelTopRatio,
        modelBottomRatio: _modelBottomRatio,
        displayOrder: int.tryParse(_displayOrderCtrl.text.trim()) ?? 0,
        iconImageUrl: widget.region?.iconImageUrl,
        image2dUrl: widget.region?.image2dUrl,
        model3dUrl: widget.region?.model3dUrl,
        landmarks: _useLandmarkOverride ? _landmarks : null,
        calibrationGender: _calibrationGender,
        calibrationPlatform: _calibrationPlatform,
      );

      if (isEditing) {
        await widget.repository.updateRegion(
          widget.region!.id,
          model,
          iconImageFile: _iconImageFile,
          image2dFile: _image2dFile,
          model3dFile: _model3dFile,
        );
      } else {
        await widget.repository.createRegion(
          model,
          iconImageFile: _iconImageFile,
          image2dFile: _image2dFile,
          model3dFile: _model3dFile,
        );
      }

      widget.onSave();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'แก้ไขอวัยวะ' : 'เพิ่มอวัยวะ'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 900;

          return Form(
            key: _formKey,
            child: isCompact
                ? SingleChildScrollView(
                    child: _buildSettingsForm(isCompact: isCompact),
                  )
                : Row(
                    children: [
                      Expanded(flex: 4, child: _buildSettingsForm(isCompact: isCompact)),
                      Expanded(flex: 3, child: _buildVisualPanel(isCompact: isCompact)),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsForm({required bool isCompact}) {
    final children = <Widget>[
                  _buildSectionHeader('ข้อมูลพื้นฐาน'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _idCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ID (ภาษาอังกฤษ, ตัวพิมพ์เล็ก, เช่น "shoulder")',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !isEditing,
                    validator: (v) => v!.isEmpty ? 'โปรดระบุ ID' : null,
                  ),
                  const SizedBox(height: 16),
                  if (isCompact)
                    Column(
                      children: [
                        TextFormField(
                          controller: _nameThCtrl,
                          decoration: const InputDecoration(labelText: 'ชื่อภาษาไทย', border: OutlineInputBorder()),
                          validator: (v) => v!.isEmpty ? 'โปรดระบุชื่อภาษาไทย' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameEnCtrl,
                          decoration: const InputDecoration(labelText: 'ชื่อภาษาอังกฤษ', border: OutlineInputBorder()),
                          validator: (v) => v!.isEmpty ? 'โปรดระบุชื่อภาษาอังกฤษ' : null,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nameThCtrl,
                            decoration: const InputDecoration(labelText: 'ชื่อภาษาไทย', border: OutlineInputBorder()),
                            validator: (v) => v!.isEmpty ? 'โปรดระบุชื่อภาษาไทย' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _nameEnCtrl,
                            decoration: const InputDecoration(labelText: 'ชื่อภาษาอังกฤษ', border: OutlineInputBorder()),
                            validator: (v) => v!.isEmpty ? 'โปรดระบุชื่อภาษาอังกฤษ' : null,
                          ),
                        ),
                      ],
                    ),
                  
                  const SizedBox(height: 32),
                  _buildSectionHeader('เลือกตำแหน่งและตัวอย่างแบบจำลอง'),
                  const SizedBox(height: 16),
                  if (isCompact) _buildVisualPanel(isCompact: isCompact),
                  const SizedBox(height: 32),
                  _buildSectionHeader('สีประจำอวัยวะ'),
                  const SizedBox(height: 16),
                  _buildColorPicker(),
                  
                  const SizedBox(height: 32),
                  _buildSectionHeader('ไอคอนสำหรับแผนที่ร่างกาย'),
                  const SizedBox(height: 16),
                  if (isCompact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _iconNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อ Material Icon (เช่น face, hearing_outlined)',
                            border: OutlineInputBorder(),
                            helperText: 'ใช้ fallback ถ้าไม่มีรูปไอคอน',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _colorHex != null
                                ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                                : AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: _iconImageFile != null
                              ? ClipOval(
                                  child: Image.file(
                                    _iconImageFile!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : widget.region?.iconImageUrl != null
                                  ? ClipOval(
                                      child: Image.network(
                                        widget.region!.iconImageUrl!,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          _iconNameToIconData(_iconNameCtrl.text) ?? Icons.image_not_supported,
                                          size: 24,
                                          color: _colorHex != null
                                              ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                                              : AppColors.primary,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      _iconNameToIconData(_iconNameCtrl.text) ?? Icons.image_not_supported,
                                      size: 24,
                                      color: _colorHex != null
                                          ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                                          : AppColors.primary,
                                    ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _iconNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'ชื่อ Material Icon (เช่น face, hearing_outlined)',
                              border: OutlineInputBorder(),
                              helperText: 'ใช้ fallback ถ้าไม่มีรูปไอคอน',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Icon preview
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _colorHex != null
                                ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                                : AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: _iconImageFile != null
                              ? ClipOval(
                                  child: Image.file(
                                    _iconImageFile!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : widget.region?.iconImageUrl != null
                                  ? ClipOval(
                                      child: Image.network(
                                        widget.region!.iconImageUrl!,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          _iconNameToIconData(_iconNameCtrl.text) ?? Icons.image_not_supported,
                                          size: 24,
                                          color: _colorHex != null
                                              ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                                              : AppColors.primary,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      _iconNameToIconData(_iconNameCtrl.text) ?? Icons.image_not_supported,
                                      size: 24,
                                      color: _colorHex != null
                                          ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                                          : AppColors.primary,
                                    ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Card(
                    child: _buildFilePickerRow(
                      icon: Icons.broken_image_outlined,
                      title: 'รูปไอคอน (PNG สี่เหลี่ยม หรือวงกลม)',
                      subtitle: _iconImageFile != null
                          ? 'เลือกไฟล์แล้ว'
                          : (widget.region?.iconImageUrl != null ? 'มีไฟล์เดิม' : 'ยังไม่มีไฟล์'),
                      onPressed: _pickIconImage,
                    ),
                  ),

                  const SizedBox(height: 32),
                  _buildSectionHeader('ตำแหน่งและการแสดงผล'),
                  const SizedBox(height: 16),
                  
                  if (isCompact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('แกน X: ${_xRatio.toStringAsFixed(3)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Slider(
                              value: _xRatio,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (val) => setState(() => _xRatio = val),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('แกน Y: ${_yRatio.toStringAsFixed(3)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Slider(
                              value: _yRatio,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (val) => setState(() => _yRatio = val),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('แกน X: ${_xRatio.toStringAsFixed(3)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Slider(
                                value: _xRatio,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (val) => setState(() => _xRatio = val),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('แกน Y: ${_yRatio.toStringAsFixed(3)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Slider(
                                value: _yRatio,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (val) => setState(() => _yRatio = val),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                  // ── v2.0 Multi-Point Calibration ─────────────────────────────────
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(Icons.model_training_outlined, color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSectionHeader('Calibration โมเดล 3D (Multi-Point v2.0)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ปรับขอบเขตแนวตั้งของโมเดล 3D ด้วย landmarks หลายจุด — แม่นยำกว่า top/bottom 2 จุด',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),

                  // Per-region override toggle
                  SwitchListTile(
                    title: const Text('ใช้ Landmarks เฉพาะอวัยวะนี้', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('ปิด = ใช้ Global Defaults (gender + platform) | เปิด = กำหนดเอง'),
                    value: _useLandmarkOverride,
                    onChanged: (val) {
                      setState(() {
                        _useLandmarkOverride = val;
                        if (val && _landmarks.isEmpty) {
                          _landmarks = CalibrationService.autoDetectLandmarks();
                        }
                      });
                    },
                  ),

                  if (_useLandmarkOverride) ...[
                    const SizedBox(height: 8),
                    if (isCompact)
                      Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _calibrationGender,
                            decoration: const InputDecoration(labelText: 'Calibration Gender', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'both', child: Text('ทั้งสองเพศ')),
                              DropdownMenuItem(value: 'female', child: Text('เฉพาะผู้หญิง')),
                              DropdownMenuItem(value: 'male', child: Text('เฉพาะผู้ชาย')),
                            ],
                            onChanged: (val) => setState(() => _calibrationGender = val!),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _calibrationPlatform,
                            decoration: const InputDecoration(labelText: 'Calibration Platform', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'universal', child: Text('ทุกแพลตฟอร์ม')),
                              DropdownMenuItem(value: 'mobile', child: Text('มือถือ')),
                              DropdownMenuItem(value: 'web', child: Text('เว็บ')),
                              DropdownMenuItem(value: 'tablet', child: Text('แท็บเล็ต')),
                            ],
                            onChanged: (val) => setState(() => _calibrationPlatform = val!),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _calibrationGender,
                              decoration: const InputDecoration(labelText: 'Calibration Gender', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'both', child: Text('ทั้งสองเพศ')),
                                DropdownMenuItem(value: 'female', child: Text('เฉพาะผู้หญิง')),
                                DropdownMenuItem(value: 'male', child: Text('เฉพาะผู้ชาย')),
                              ],
                              onChanged: (val) => setState(() => _calibrationGender = val!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _calibrationPlatform,
                              decoration: const InputDecoration(labelText: 'Calibration Platform', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'universal', child: Text('ทุกแพลตฟอร์ม')),
                                DropdownMenuItem(value: 'mobile', child: Text('มือถือ')),
                                DropdownMenuItem(value: 'web', child: Text('เว็บ')),
                                DropdownMenuItem(value: 'tablet', child: Text('แท็บเล็ต')),
                              ],
                              onChanged: (val) => setState(() => _calibrationPlatform = val!),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _landmarks = CalibrationService.autoDetectLandmarks();
                            });
                          },
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Auto-Detect จาก 3D'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              final nextId = _landmarks.isEmpty ? 0 : _landmarks.map((l) => l.id).reduce((a, b) => a > b ? a : b) + 1;
                              _landmarks = [..._landmarks, BodyLandmark(
                                id: nextId,
                                name: 'จุดใหม่',
                                y2d: 0.5,
                                y3d: 0.5,
                                x2d: 0.5,
                                x3d: 0.5,
                              )];
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('เพิ่ม Landmark'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Landmark list editor
                    ..._landmarks.map((lm) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      decoration: const InputDecoration(labelText: 'ชื่อ', isDense: true),
                                      controller: TextEditingController(text: lm.name),
                                      onChanged: (val) {
                                        final idx = _landmarks.indexWhere((l) => l.id == lm.id);
                                        if (idx >= 0) {
                                          setState(() => _landmarks[idx] = _landmarks[idx].copyWith(name: val));
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setState(() => _landmarks = _landmarks.where((l) => l.id != lm.id).toList());
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(child: Text('y2d: ${lm.y2d.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11))),
                                  Expanded(child: Text('y3d: ${lm.y3d.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11))),
                                  Expanded(child: Text('x2d: ${lm.x2d.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11))),
                                  Expanded(child: Text('x3d: ${lm.x3d.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11))),
                                  if (lm.autoDetected)
                                    const Chip(label: Text('Auto', style: TextStyle(fontSize: 10)), padding: EdgeInsets.zero),
                                ],
                              ),
                              Slider(
                                value: lm.y2d,
                                min: 0.0,
                                max: 1.0,
                                label: 'y2d',
                                onChanged: (val) {
                                  final idx = _landmarks.indexWhere((l) => l.id == lm.id);
                                  if (idx >= 0) {
                                    setState(() => _landmarks[idx] = _landmarks[idx].copyWith(y2d: val));
                                  }
                                },
                              ),
                              Slider(
                                value: lm.y3d,
                                min: 0.0,
                                max: 1.0,
                                label: 'y3d',
                                onChanged: (val) {
                                  final idx = _landmarks.indexWhere((l) => l.id == lm.id);
                                  if (idx >= 0) {
                                    setState(() => _landmarks[idx] = _landmarks[idx].copyWith(y3d: val));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ] else ...[
                    // Fallback: show old top/bottom sliders when not using landmark override
                    const Text('ใช้ Global Defaults — ปรับที่ Global Calibration Manager', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Top: ${_modelTopRatio.toStringAsFixed(3)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Slider(
                                value: _modelTopRatio,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (val) {
                                  if (val < _modelBottomRatio - 0.05) {
                                    setState(() => _modelTopRatio = val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Bottom: ${_modelBottomRatio.toStringAsFixed(3)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Slider(
                                value: _modelBottomRatio,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (val) {
                                  if (val > _modelTopRatio + 0.05) {
                                    setState(() => _modelBottomRatio = val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],

                  const Divider(height: 32),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: const InputDecoration(labelText: 'เพศ (Gender)', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'both', child: Text('ทั้งสองเพศ')),
                            DropdownMenuItem(value: 'female', child: Text('เฉพาะผู้หญิง')),
                            DropdownMenuItem(value: 'male', child: Text('เฉพาะผู้ชาย')),
                          ],
                          onChanged: (val) => setState(() => _gender = val!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('มีข้างซ้าย/ขวา'),
                          value: _hasSides,
                          onChanged: (val) => setState(() => _hasSides = val),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                  _buildSectionHeader('ไฟล์สื่อสนับสนุน'),
                  const SizedBox(height: 16),
                  
                  Card(
                    child: Column(
                      children: [
                        _buildFilePickerRow(
                          icon: Icons.image_outlined,
                          title: 'ภาพนิ่ง 2D (PNG โปร่งใส)',
                          subtitle: _image2dFile != null
                              ? 'เลือกไฟล์แล้ว'
                              : (widget.region?.image2dUrl != null ? 'มีไฟล์เดิม' : 'ยังไม่มีไฟล์'),
                          onPressed: _pick2dImage,
                        ),
                        const Divider(height: 1),
                        _buildFilePickerRow(
                          icon: Icons.view_in_ar_outlined,
                          title: 'โมเดล 3D (.glb)',
                          subtitle: _model3dFile != null
                              ? 'เลือกไฟล์แล้ว'
                              : (widget.region?.model3dUrl != null ? 'มีไฟล์เดิม' : 'ยังไม่มีไฟล์'),
                          onPressed: _pick3dModel,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : const Text('บันทึกข้อมูลอวัยวะ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
    ];

    return isCompact
        ? Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(24),
            children: children,
          );
  }

  Widget _buildVisualPanel({required bool isCompact}) {
    return Container(
      color: Colors.grey.shade100,
      child: isCompact
          ? Column(
              children: [
                SizedBox(
                  height: 440,
                  child: _buildPositionPicker(isCompact: isCompact),
                ),
                const Divider(height: 1, thickness: 2),
                SizedBox(
                  height: 300,
                  child: _buildAssetPreview(),
                ),
              ],
            )
          : Column(
              children: [
                // Position Picker
                Expanded(
                  flex: 6,
                  child: _buildPositionPicker(isCompact: isCompact),
                ),
                const Divider(height: 1, thickness: 2),
                // Asset Preview (2D or 3D)
                Expanded(
                  flex: 4,
                  child: _buildAssetPreview(),
                ),
              ],
            ),
    );
  }

  Widget _buildColorPicker() {
    final palette = [
      '#EF5350', '#42A5F5', '#66BB6A', '#FFA726', '#AB47BC', 
      '#26A69A', '#EC407A', '#5C6BC0', '#26C6DA', '#FFCA28',
      '#FF7043', '#8D6E63', '#78909C', '#C0CA33'
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('เลือกสีเพื่อแยกแยะชนิดอวัยวะ (ถ้าไม่เลือกจะใช้สีเริ่มต้น)', 
            style: TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Auto Color Option
            GestureDetector(
              onTap: () => setState(() => _colorHex = null),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _colorHex == null ? AppColors.primary : Colors.grey.shade300,
                    width: _colorHex == null ? 3 : 1,
                  ),
                ),
                child: const Icon(Icons.auto_awesome, size: 20, color: Colors.grey),
              ),
            ),
            ...palette.map((hex) => GestureDetector(
              onTap: () => setState(() => _colorHex = hex),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16)),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _colorHex == hex ? Colors.black : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: [
                    if (_colorHex == hex) 
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)
                  ],
                ),
              ),
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
        const Divider(color: AppColors.primary, thickness: 1),
      ],
    );
  }

  Widget _buildPositionPicker({required bool isCompact}) {
    final silhouetteAspectRatio = isCompact ? 0.95 : 0.5;

    return Column(
      children: [
        // Header with toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'แตะบนร่างกายเพื่อกำหนดจุดตำแหน่ง (X, Y)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              // 2D / 3D Reference toggle
              GestureDetector(
                onTap: () => setState(() => _show3dReference = !_show3dReference),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: _show3dReference ? AppColors.primaryGradient : null,
                    color: _show3dReference ? null : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _show3dReference
                          ? Colors.transparent
                          : AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _show3dReference ? Icons.threed_rotation : Icons.view_in_ar_outlined,
                        size: 14,
                        color: _show3dReference ? Colors.white : AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _show3dReference ? '3D' : '2D',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _show3dReference ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (details) {
                  setState(() {
                    if (_show3dReference) {
                      _xRatio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                      _yRatio = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
                    } else {
                      // Calculate silhouette rectangle
                      final silW = math.min(constraints.maxWidth, constraints.maxHeight * 0.5);
                      final silH = silW / 0.5;
                      final silLeft = (constraints.maxWidth - silW) / 2;
                      final silTop = (constraints.maxHeight - silH) / 2;

                      // Convert tap to silhouette-relative coordinates
                      final localDx = details.localPosition.dx - silLeft;
                      final localDy = details.localPosition.dy - silTop;
                      if (localDx >= 0 && localDx <= silW && localDy >= 0 && localDy <= silH) {
                        _xRatio = (localDx / silW).clamp(0.0, 1.0);
                        _yRatio = (localDy / silH).clamp(0.0, 1.0);
                      }
                    }
                  });
                },
                child: Stack(
                  children: [
                    // ── 3D Reference Body (read-only, behind everything) ──
                    if (_show3dReference)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _buildReferenceModelViewer(),
                        ),
                      ),

                    // ── 2D Silhouette (picker mode) ──
                    if (!_show3dReference)
                      Center(
                        child: AspectRatio(
                          aspectRatio: silhouetteAspectRatio,
                          child: LayoutBuilder(
                            builder: (context, silConstraints) {
                              final silW = silConstraints.maxWidth;
                              final silH = silConstraints.maxHeight;
                              return Stack(
                                children: [
                                  CustomPaint(
                                    painter: _HumanSilhouettePainter(
                                      color: Colors.grey.shade200,
                                      gender: _gender,
                                      selectedSide: _hasSides
                                          ? (_xRatio < 0.5 ? -1 : 1)
                                          : 0,
                                      landmarks: _landmarks,
                                    ),
                                    child: Container(),
                                  ),
                                  // Calibration zone overlay
                                  Positioned(
                                    top: silH * _modelTopRatio,
                                    left: 0,
                                    right: 0,
                                    height: silH * (_modelBottomRatio - _modelTopRatio),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: AppColors.primary.withValues(alpha: 0.4),
                                            width: 2,
                                          ),
                                          bottom: BorderSide(
                                            color: AppColors.primary.withValues(alpha: 0.4),
                                            width: 2,
                                          ),
                                        ),
                                        color: AppColors.primary.withValues(alpha: 0.06),
                                      ),
                                    ),
                                  ),
                                  // Pointer dot
                                  Positioned(
                                    left: silW * _xRatio - 14,
                                    top: silH * _yRatio - 14,
                                    child: _buildPointerDot(),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),

                    // ── Pointer Dot (3D mode only) ──
                    if (_show3dReference)
                      Positioned(
                        left: constraints.maxWidth * _xRatio - 14,
                        top: constraints.maxHeight *
                                (_modelTopRatio +
                                    _yRatio *
                                        (_modelBottomRatio - _modelTopRatio)) -
                            14,
                        child: _buildPointerDot(),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPointerDot() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: _colorHex != null
              ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
              : AppColors.primary,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, spreadRadius: 1),
        ],
      ),
      child: _iconImageFile != null
          ? ClipOval(
              child: Image.file(
                _iconImageFile!,
                width: 24,
                height: 24,
                fit: BoxFit.cover,
              ),
            )
          : widget.region?.iconImageUrl != null
              ? ClipOval(
                  child: Image.network(
                    widget.region!.iconImageUrl!,
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      _iconNameToIconData(_iconNameCtrl.text) ?? Icons.touch_app,
                      size: 16,
                      color: _colorHex != null
                          ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                          : AppColors.primary,
                    ),
                  ),
                )
              : Icon(
                  _iconNameToIconData(_iconNameCtrl.text) ?? Icons.touch_app,
                  size: 16,
                  color: _colorHex != null
                      ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                      : AppColors.primary,
                ),
    );
  }

  /// Read-only full-body 3D model for admin reference.
  /// Placeholder: actual .glb assets are not yet bundled.
  Widget _buildReferenceModelViewer() {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              '3D Reference Model\n(${_gender})',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'เพิ่มไฟล์ .glb ที่ assets/models/',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: const Text('ตัวอย่างการแสดงผล (Preview)', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: _model3dFile != null || widget.region?.model3dUrl != null
            ? ModelViewer(
                src: _model3dFile != null 
                    ? 'file://${_model3dFile!.path}' 
                    : widget.region!.model3dUrl!,
                alt: "A 3D model",
                ar: false,
                autoRotate: true,
                cameraControls: true,
              )
            : _image2dFile != null || widget.region?.image2dUrl != null
              ? Center(
                  child: _image2dFile != null 
                    ? Image.file(_image2dFile!, fit: BoxFit.contain)
                    : Image.network(widget.region!.image2dUrl!, fit: BoxFit.contain),
                )
              : _buildReferenceModelViewer(),
        ),
      ],
    );
  }
}

class _HumanSilhouettePainter extends CustomPainter {
  final Color color;
  final String gender;
  /// -1 = left, 0 = none/center, 1 = right — highlights the selected half
  final int selectedSide;
  /// v2.0: Optional landmarks to draw as guide lines and dots on the silhouette.
  final List<BodyLandmark>? landmarks;

  _HumanSilhouettePainter({
    required this.color,
    required this.gender,
    this.selectedSide = 0,
    this.landmarks,
  });

  bool get _isMale => gender == 'male' || gender == 'm' || gender == 'both';

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final h = size.height;

    // --- Gradient fill for 3D volume illusion ---
    final baseFill = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.3),
        radius: 0.9,
        colors: [
          color.withValues(alpha: 0.9),
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0.35),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // === HEAD ===
    final headRadius = size.width * 0.095;
    final headRect = Rect.fromCenter(
      center: Offset(cx, h * 0.07),
      width: headRadius * 2,
      height: headRadius * 2.2,
    );
    // Shadow behind head
    canvas.drawOval(
      headRect.translate(0, 3),
      shadowPaint,
    );
    canvas.drawOval(headRect, baseFill);
    canvas.drawOval(headRect, strokePaint);

    // === NECK ===
    final neckPath = Path()
      ..moveTo(cx - size.width * 0.03, h * 0.14)
      ..lineTo(cx + size.width * 0.03, h * 0.14)
      ..lineTo(cx + size.width * 0.05, h * 0.19)
      ..lineTo(cx - size.width * 0.05, h * 0.19)
      ..close();
    canvas.drawPath(neckPath, baseFill);
    canvas.drawPath(neckPath, strokePaint);

    // === TORSO ===
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
    canvas.drawPath(torsoPath, baseFill);
    canvas.drawPath(torsoPath, strokePaint);

    // === ARMS ===
    _drawArm(
      canvas, baseFill, strokePaint, size, cx, h,
      startX: cx - size.width * shoulderW, isLeft: true,
    );
    _drawArm(
      canvas, baseFill, strokePaint, size, cx, h,
      startX: cx + size.width * shoulderW, isLeft: false,
    );

    // === LEGS ===
    _drawLeg(
      canvas, baseFill, strokePaint, size, cx, h,
      hipW: hipW, isLeft: true,
    );
    _drawLeg(
      canvas, baseFill, strokePaint, size, cx, h,
      hipW: hipW, isLeft: false,
    );

    // === LANDMARK GUIDES (v2.0) ===
    if (landmarks != null && landmarks!.isNotEmpty) {
      final guidePaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;

      final dotPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;

      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );

      for (final lm in landmarks!) {
        final ly = h * lm.y2d;
        final lx = size.width * lm.x2d;

        // Horizontal guide line across the silhouette
        canvas.drawLine(
          Offset(size.width * 0.05, ly),
          Offset(size.width * 0.95, ly),
          guidePaint,
        );

        // Dot at (x2d, y2d)
        canvas.drawCircle(Offset(lx, ly), 3.5, dotPaint);

        // Label
        textPainter.text = TextSpan(
          text: lm.name,
          style: TextStyle(
            color: Colors.red.withValues(alpha: 0.8),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(lx + 6, ly - textPainter.height - 2));
      }
    }

    // === ANATOMICAL GUIDES (Internal lines) ===
    final guidePaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Chest/Breast line
    canvas.drawLine(
      Offset(cx - size.width * shoulderW * 0.8, h * 0.3),
      Offset(cx + size.width * shoulderW * 0.8, h * 0.3),
      guidePaint,
    );
    // Waist line
    canvas.drawLine(
      Offset(cx - size.width * waistW, h * 0.47),
      Offset(cx + size.width * waistW, h * 0.47),
      guidePaint,
    );
    // Knee lines
    canvas.drawLine(
      Offset(cx - size.width * 0.1, h * 0.77),
      Offset(cx - size.width * 0.02, h * 0.77),
      guidePaint,
    );
    canvas.drawLine(
      Offset(cx + size.width * 0.02, h * 0.77),
      Offset(cx + size.width * 0.1, h * 0.77),
      guidePaint,
    );

    // === CENTER VERTICAL LINE (anatomical midline) ===
    final centerLinePaint = Paint()
      ..color = Colors.grey.shade500.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, h * 0.13),
      Offset(cx, h * 0.58),
      centerLinePaint,
    );

    // === SIDE HIGHLIGHT ===
    if (selectedSide != 0) {
      final highlightPaint = Paint()
        ..color = (selectedSide < 0 ? Colors.blue : Colors.purple)
            .withValues(alpha: 0.18)
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver;

      final halfClip = Path()
        ..addRect(
          selectedSide < 0
              ? Rect.fromLTWH(0, 0, cx, size.height)
              : Rect.fromLTWH(cx, 0, size.width - cx, size.height),
        );

      canvas.save();
      canvas.clipPath(halfClip);

      // Re-draw body parts with highlight overlay
      canvas.drawOval(headRect, highlightPaint);
      canvas.drawPath(neckPath, highlightPaint);
      canvas.drawPath(torsoPath, highlightPaint);
      _drawArm(
        canvas, highlightPaint, strokePaint, size, cx, h,
        startX: cx - size.width * shoulderW, isLeft: true,
      );
      _drawArm(
        canvas, highlightPaint, strokePaint, size, cx, h,
        startX: cx + size.width * shoulderW, isLeft: false,
      );
      _drawLeg(
        canvas, highlightPaint, strokePaint, size, cx, h,
        hipW: hipW, isLeft: true,
      );
      _drawLeg(
        canvas, highlightPaint, strokePaint, size, cx, h,
        hipW: hipW, isLeft: false,
      );
      canvas.restore();
    }
  }

  void _drawArm(
    Canvas canvas, Paint fill, Paint stroke, Size size, double cx, double h, {
    required double startX,
    required bool isLeft,
  }) {
    final direction = isLeft ? -1 : 1;
    final path = Path()
      ..moveTo(startX, h * 0.22)
      ..lineTo(startX + direction * size.width * 0.04, h * 0.22)
      ..lineTo(startX + direction * size.width * 0.08, h * 0.44)
      ..lineTo(startX + direction * size.width * 0.06, h * 0.60)
      ..lineTo(startX + direction * size.width * 0.01, h * 0.60)
      ..lineTo(startX + direction * size.width * 0.03, h * 0.44)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  void _drawLeg(
    Canvas canvas, Paint fill, Paint stroke, Size size, double cx, double h, {
    required double hipW,
    required bool isLeft,
  }) {
    final direction = isLeft ? -1 : 1;
    final path = Path()
      ..moveTo(cx + direction * size.width * hipW * 0.9, h * 0.55)
      ..lineTo(cx + direction * size.width * 0.03, h * 0.55)
      ..lineTo(cx + direction * size.width * 0.04, h * 0.77)
      ..lineTo(cx + direction * size.width * 0.06, h * 0.96)
      ..lineTo(cx + direction * size.width * 0.12, h * 0.96)
      ..lineTo(cx + direction * size.width * 0.10, h * 0.77)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _HumanSilhouettePainter oldDelegate) {
    return oldDelegate.selectedSide != selectedSide ||
        oldDelegate.color != color ||
        oldDelegate.gender != gender ||
        oldDelegate.landmarks != landmarks;
  }
}
