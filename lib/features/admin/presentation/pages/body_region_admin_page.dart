import 'dart:io';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/models/body_region_model.dart';
import '../../data/repositories/body_region_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../shared/widgets/widgets.dart';

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
    BodyRegionModel(id: 'eyes',       nameTh: 'ดวงตา',        nameEn: 'Eyes',          yRatio: 0.09, xRatio: 0.50, iconName: 'remove_red_eye_outlined', gender: 'both', hasSides: false, displayOrder: 3),
    BodyRegionModel(id: 'nose_ears',  nameTh: 'จมูก/หู',      nameEn: 'Nose/Ears',     yRatio: 0.11, xRatio: 0.50, iconName: 'hearing_outlined', gender: 'both', hasSides: false, displayOrder: 4),
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
                          painter: _HumanSilhouettePainter(color: Colors.grey.shade300, gender: 'both'),
                          child: Container(),
                        ),
                      ),
                    ),
                    // All Points
                    ..._regions.map((region) {
                      return Positioned(
                        left: constraints.maxWidth * region.xRatio - 4,
                        top: constraints.maxHeight * region.yRatio - 4,
                        child: Tooltip(
                          message: region.nameTh,
                          child: GestureDetector(
                            onTap: () => _showEditor(region),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _getRegionColor(region),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 2,
                                  )
                                ],
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

  File? _image2dFile;
  File? _model3dFile;
  bool _isSaving = false;

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
        displayOrder: int.tryParse(_displayOrderCtrl.text.trim()) ?? 0,
        image2dUrl: widget.region?.image2dUrl,
        model3dUrl: widget.region?.model3dUrl,
      );

      if (isEditing) {
        await widget.repository.updateRegion(
          widget.region!.id, 
          model,
          image2dFile: _image2dFile,
          model3dFile: _model3dFile,
        );
      } else {
        await widget.repository.createRegion(
          model,
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
      body: Form(
        key: _formKey,
        child: Row(
          children: [
            // Left Side: Settings Form
            Expanded(
              flex: 4,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
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
                  _buildSectionHeader('สีประจำอวัยวะ'),
                  const SizedBox(height: 16),
                  _buildColorPicker(),
                  
                  const SizedBox(height: 32),
                  _buildSectionHeader('ตำแหน่งและการแสดงผล'),
                  const SizedBox(height: 16),
                  
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
                        ListTile(
                          leading: const Icon(Icons.image_outlined),
                          title: const Text('ภาพนิ่ง 2D (PNG โปร่งใส)'),
                          subtitle: Text(_image2dFile != null ? 'เลือกไฟล์แล้ว' : (widget.region?.image2dUrl != null ? 'มีไฟล์เดิม' : 'ยังไม่มีไฟล์')),
                          trailing: ElevatedButton(onPressed: _pick2dImage, child: const Text('เลือกไฟล์')),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.view_in_ar_outlined),
                          title: const Text('โมเดล 3D (.glb)'),
                          subtitle: Text(_model3dFile != null ? 'เลือกไฟล์แล้ว' : (widget.region?.model3dUrl != null ? 'มีไฟล์เดิม' : 'ยังไม่มีไฟล์')),
                          trailing: ElevatedButton(onPressed: _pick3dModel, child: const Text('เลือกไฟล์')),
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
                ],
              ),
            ),
            
            // Right Side: Visual Picker and Preview
            Expanded(
              flex: 3,
              child: Container(
                color: Colors.grey.shade100,
                child: Column(
                  children: [
                    // Position Picker
                    Expanded(
                      flex: 6,
                      child: _buildPositionPicker(),
                    ),
                    const Divider(height: 1, thickness: 2),
                    // Asset Preview (2D or 3D)
                    Expanded(
                      flex: 4,
                      child: _buildAssetPreview(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildPositionPicker() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('แตะบนร่างกายเพื่อกำหนดจุดตำแหน่ง (X, Y)', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (details) {
                  setState(() {
                    _xRatio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                    _yRatio = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
                  });
                },
                child: Stack(
                  children: [
                    // Body Silhouette
                    Center(
                      child: AspectRatio(
                        aspectRatio: 0.5,
                        child: CustomPaint(
                          painter: _HumanSilhouettePainter(
                            color: Colors.grey.shade200,
                            gender: _gender,
                          ),
                          child: Container(),
                        ),
                      ),
                    ),
                    // Pointer Dot
                    Positioned(
                      left: constraints.maxWidth * _xRatio - 10,
                      top: constraints.maxHeight * _yRatio - 10,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _colorHex != null 
                              ? Color(int.parse('FF${_colorHex!.replaceAll('#', '')}', radix: 16))
                              : AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6)],
                        ),
                        child: const Icon(Icons.touch_app, size: 12, color: Colors.white),
                      ),
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
              : const Center(child: Text('ไม่มีตัวอย่างไฟล์')),
        ),
      ],
    );
  }
}

class _HumanSilhouettePainter extends CustomPainter {
  final Color color;
  final String gender;

  _HumanSilhouettePainter({required this.color, required this.gender});

  bool get _isMale => gender == 'male' || gender == 'm' || gender == 'both';

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final cx = size.width / 2;
    final h = size.height;

    // === HEAD ===
    final headRadius = size.width * 0.095;
    final headRect = Rect.fromCenter(
      center: Offset(cx, h * 0.07),
      width: headRadius * 2,
      height: headRadius * 2.2,
    );
    canvas.drawOval(headRect, fillPaint);
    canvas.drawOval(headRect, strokePaint);

    // === NECK ===
    final neckPath = Path()
      ..moveTo(cx - size.width * 0.03, h * 0.14)
      ..lineTo(cx + size.width * 0.03, h * 0.14)
      ..lineTo(cx + size.width * 0.05, h * 0.19)
      ..lineTo(cx - size.width * 0.05, h * 0.19)
      ..close();
    canvas.drawPath(neckPath, fillPaint);
    canvas.drawPath(neckPath, strokePaint);

    // === TORSO ===
    final shoulderW = _isMale ? 0.22 : 0.18; // Male has broader shoulders
    final waistW = _isMale ? 0.14 : 0.12;
    final hipW = _isMale ? 0.15 : 0.17; // Female has broader hips

    final torsoPath = Path()
      ..moveTo(cx - size.width * shoulderW, h * 0.20)
      ..quadraticBezierTo(cx, h * 0.18, cx + size.width * shoulderW, h * 0.20)
      ..lineTo(cx + size.width * waistW, h * 0.47)
      ..lineTo(cx + size.width * hipW, h * 0.55)
      ..lineTo(cx - size.width * hipW, h * 0.55)
      ..lineTo(cx - size.width * waistW, h * 0.47)
      ..close();
    canvas.drawPath(torsoPath, fillPaint);
    canvas.drawPath(torsoPath, strokePaint);

    // === ARMS ===
    _drawArm(canvas, fillPaint, strokePaint, size, cx, h, startX: cx - size.width * shoulderW, isLeft: true);
    _drawArm(canvas, fillPaint, strokePaint, size, cx, h, startX: cx + size.width * shoulderW, isLeft: false);

    // === LEGS ===
    _drawLeg(canvas, fillPaint, strokePaint, size, cx, h, hipW: hipW, isLeft: true);
    _drawLeg(canvas, fillPaint, strokePaint, size, cx, h, hipW: hipW, isLeft: false);
    
    // === ANATOMICAL GUIDES (Internal lines for better orientation) ===
    final guidePaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
      
    // Chest/Breast line
    canvas.drawLine(Offset(cx - size.width * shoulderW * 0.8, h * 0.3), Offset(cx + size.width * shoulderW * 0.8, h * 0.3), guidePaint);
    // Waist line
    canvas.drawLine(Offset(cx - size.width * waistW, h * 0.47), Offset(cx + size.width * waistW, h * 0.47), guidePaint);
    // Knee lines
    canvas.drawLine(Offset(cx - size.width * 0.1, h * 0.77), Offset(cx - size.width * 0.02, h * 0.77), guidePaint);
    canvas.drawLine(Offset(cx + size.width * 0.02, h * 0.77), Offset(cx + size.width * 0.1, h * 0.77), guidePaint);
  }

  void _drawArm(Canvas canvas, Paint fill, Paint stroke, Size size, double cx, double h, {required double startX, required bool isLeft}) {
    final direction = isLeft ? -1 : 1;
    final path = Path()
      ..moveTo(startX, h * 0.22)
      ..lineTo(startX + direction * size.width * 0.04, h * 0.22)
      ..lineTo(startX + direction * size.width * 0.08, h * 0.44) // Elbow area
      ..lineTo(startX + direction * size.width * 0.06, h * 0.60) // Hand area
      ..lineTo(startX + direction * size.width * 0.01, h * 0.60)
      ..lineTo(startX + direction * size.width * 0.03, h * 0.44)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  void _drawLeg(Canvas canvas, Paint fill, Paint stroke, Size size, double cx, double h, {required double hipW, required bool isLeft}) {
    final direction = isLeft ? -1 : 1;
    final path = Path()
      ..moveTo(cx + direction * size.width * hipW * 0.9, h * 0.55)
      ..lineTo(cx + direction * size.width * 0.03, h * 0.55)
      ..lineTo(cx + direction * size.width * 0.04, h * 0.77) // Knee
      ..lineTo(cx + direction * size.width * 0.06, h * 0.96) // Ankle
      ..lineTo(cx + direction * size.width * 0.12, h * 0.96)
      ..lineTo(cx + direction * size.width * 0.10, h * 0.77)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
