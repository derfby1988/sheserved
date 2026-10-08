import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/core/utils/file_ops.dart';

import '../../application/court_card_style_service.dart';
import '../../data/book_court_models.dart';
import '../../domain/court_card_3d_params.dart';
import '../../domain/court_card_style.dart';
import 'court_card.dart';

/// Admin tab "รูปแบบการ์ด": previews every Court Card style and stores the
/// chosen one in `app_settings`, so the Book Court feed renders that style on
/// every device.
class CourtCardStylePanel extends StatefulWidget {
  final CourtCardStyleService? service;

  const CourtCardStylePanel({super.key, this.service});

  @override
  State<CourtCardStylePanel> createState() => _CourtCardStylePanelState();
}

class _CourtCardStylePanelState extends State<CourtCardStylePanel> {
  CourtCardStyleService get _service =>
      widget.service ?? CourtCardStyleService.instance;

  bool _loading = true;
  CourtCardStyle? _saving;

  /// Local copy of 3D params for live slider preview.
  CourtCard3DParams _localParams = CourtCard3DParams.defaults;

  /// Whether we have unsaved 3D param changes.
  bool _paramsDirty = false;

  /// Whether we are persisting 3D params.
  bool _savingParams = false;

  /// Backdrop mode for previewing 3D glass transparency: 'studio' (dark) or 'light'.
  String _previewBackdrop = 'studio';

  static final VenueSummary _previewVenue = VenueSummary(
    id: 'preview-venue',
    name: 'สนามตัวอย่าง สุขุมวิท',
    district: 'คลองเตย',
    province: 'กรุงเทพฯ',
    timezone: 'Asia/Bangkok',
    courtCount: 6,
    averageRating: 4.3,
    reviewCount: 18,
    startingPriceAmount: 250,
    amenityIds: const {'parking', 'shower', 'lighting'},
  );

  static final List<VenueBooking> _previewBookings = [
    VenueBooking(
      id: 'preview-booking',
      courtId: 'preview-court',
      venueId: _previewVenue.id,
      sportId: 'preview-sport',
      startsAt: DateTime.now().add(const Duration(hours: 2, minutes: 15)),
      endsAt: DateTime.now().add(const Duration(hours: 3, minutes: 15)),
      status: VenueBookingStatus.confirmed,
      courtName: '3',
      unitLabel: 'คอร์ท',
      priceTotal: 250,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _service.load(force: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _localParams = _service.params3d.value;
      _paramsDirty = false;
    });
  }

  Future<void> _select(CourtCardStyle style) async {
    if (_saving != null) return;
    setState(() => _saving = style);
    final persisted = await _service.select(style);
    if (!mounted) return;
    setState(() => _saving = null);
    _toast(
      persisted
          ? 'ใช้รูปแบบ "${style.label}" กับการ์ดสนามของทุกเครื่องแล้ว'
          : 'เปลี่ยนบนเครื่องนี้แล้ว แต่บันทึกขึ้นเซิร์ฟเวอร์ไม่สำเร็จ',
    );
  }

  void _updateParam(CourtCard3DParams next) {
    setState(() {
      _localParams = next;
      _paramsDirty = true;
    });
  }

  Future<void> _saveParams() async {
    if (_savingParams) return;
    setState(() => _savingParams = true);
    final ok = await _service.update3DParams(_localParams);
    if (!mounted) return;
    setState(() {
      _savingParams = false;
      if (ok) _paramsDirty = false;
    });
    _toast(
      ok
          ? 'บันทึกค่า 3D ลงเซิร์ฟเวอร์แล้ว'
          : 'บันทึกค่า 3D ไม่สำเร็จ',
    );
  }

  void _resetParams() {
    _updateParam(CourtCard3DParams.defaults);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static const List<(String, String, IconData, Color)> _presets = [
    ('preset:tennis', 'เทนนิส', Icons.sports_tennis_rounded, Color(0xFFD91E28)),
    ('preset:badminton', 'แบดมินตัน', Icons.sports_baseball_rounded, Color(0xFF00897B)),
    ('preset:football', 'ฟุตบอล', Icons.sports_soccer_rounded, Color(0xFF1E88E5)),
    ('preset:basketball', 'บาสเกตบอล', Icons.sports_basketball_rounded, Color(0xFFFB8C00)),
    ('preset:trophy', 'ถ้วยรางวัล', Icons.emoji_events_rounded, Color(0xFFF59E0B)),
    ('preset:stadium', 'สนามกีฬา', Icons.stadium_rounded, Color(0xFF8B5CF6)),
  ];

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      Uint8List bytes;
      try {
        bytes = await compressImageToBytes(
          picked,
          quality: 75,
          maxDimension: 256,
        );
      } catch (_) {
        bytes = await picked.readAsBytes();
      }
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _updateParam(_localParams.copyWith(
        show3dIcon: false,
        customImageUrl: b64,
      ));
      _toast('เลือกรูปภาพแล้ว (อย่าลืมกด "บันทึกค่า 3D")');
    } catch (e) {
      _toast('ไม่สามารถเลือกรูปภาพได้: $e');
    }
  }

  Future<void> _promptImageUrl() async {
    final controller = TextEditingController(
      text: _localParams.customImageUrl?.startsWith('http') == true
          ? _localParams.customImageUrl
          : '',
    );
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ระบุ URL รูปภาพ', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com/logo.png',
            labelText: 'URL รูปภาพ (HTTPS)',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      _updateParam(_localParams.copyWith(
        show3dIcon: false,
        customImageUrl: url,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CourtCardStyle>(
      valueListenable: _service.style,
      builder: (context, selected, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _header(selected),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 12),
          // 3D parameter sliders (shown whenever a 3D style is active)
          if (selected.isThreeDimensional) ...[
            _build3DParamsSection(),
            const SizedBox(height: 14),
          ],
          for (final style in CourtCardStyle.values) ...[
            _styleTile(style, selected),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _header(CourtCardStyle selected) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'รูปแบบการ์ดสนาม (Book Court)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'รูปแบบที่เลือกมีผลกับการ์ดสนามในหน้า Book Court ของทุกคน '
            'และบันทึกไว้ในตาราง app_settings',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            'ใช้อยู่ตอนนี้: ${selected.label}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  // ===================== 3D Parameter Sliders =====================

  Widget _build3DParamsSection() {
    final p = _localParams;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryDark.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'ปรับค่า 3D (สันขอบ & ความโปร่งใส)',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              // Reset button
              TextButton.icon(
                onPressed: _resetParams,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('รีเซ็ต', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ปรับเลื่อนเพื่อดูผลแบบ Real-time บนการ์ดตัวอย่างด้านล่าง',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),

          // Backdrop preview toggle (Studio vs App Feed)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'ฉากหลังตัวอย่าง:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              ChoiceChip(
                label: const Text('สตูดิโอ (Dark Studio)', style: TextStyle(fontSize: 11.5)),
                selected: _previewBackdrop == 'studio',
                onSelected: (s) {
                  if (s) setState(() => _previewBackdrop = 'studio');
                },
                visualDensity: VisualDensity.compact,
              ),
              ChoiceChip(
                label: const Text('หน้าแอปจริง (Light)', style: TextStyle(fontSize: 11.5)),
                selected: _previewBackdrop == 'light',
                onSelected: (s) {
                  if (s) setState(() => _previewBackdrop = 'light');
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Divider(height: 16),

          // 1. องศาการ์ด (rotateY)
          _paramSlider(
            icon: Icons.rotate_right_rounded,
            label: 'องศาการ์ด',
            value: p.rotateY,
            min: -0.35,
            max: 0.35,
            displayValue: '${(p.rotateY * 180 / math.pi).toStringAsFixed(1)}°',
            onChanged: (v) => _updateParam(p.copyWith(rotateY: v)),
          ),

          // 2. ความเอียง (rotateX)
          _paramSlider(
            icon: Icons.open_in_full_rounded,
            label: 'ความเอียง',
            value: p.rotateX,
            min: -0.25,
            max: 0.25,
            displayValue: '${(p.rotateX * 180 / math.pi).toStringAsFixed(1)}°',
            onChanged: (v) => _updateParam(p.copyWith(rotateX: v)),
          ),

          // 3. ความหนาสันขอบ (thickness)
          _paramSlider(
            icon: Icons.layers_rounded,
            label: 'ความหนาสัน',
            value: p.thickness,
            min: 2.0,
            max: 26.0,
            displayValue: '${p.thickness.toStringAsFixed(1)} px',
            onChanged: (v) => _updateParam(p.copyWith(thickness: v)),
          ),

          // 4. ความโปร่งใส (opacity)
          _paramSlider(
            icon: Icons.opacity_rounded,
            label: 'ความโปร่งใส',
            value: p.opacity,
            min: 0.10,
            max: 0.90,
            displayValue: '${(p.opacity * 100).toStringAsFixed(0)}%',
            onChanged: (v) => _updateParam(p.copyWith(opacity: v)),
          ),

          // 5. มุมแสง (lightAngle)
          _paramSlider(
            icon: Icons.wb_sunny_rounded,
            label: 'มุมแสง',
            value: p.lightAngle,
            min: -math.pi,
            max: math.pi,
            displayValue: '${(p.lightAngle * 180 / math.pi).toStringAsFixed(0)}°',
            onChanged: (v) => _updateParam(p.copyWith(lightAngle: v)),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // ==================== จัดการเงาและการสะท้อน (Shadow Controls) ====================
          Row(
            children: [
              Icon(Icons.wb_shade_rounded, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Text(
                'การจัดการเงาและแสงสะท้อน',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 6. รัศมีกว้างเงาแนวนอน (shadowWidthFactor)
          _paramSlider(
            icon: Icons.swap_horiz_rounded,
            label: 'ความกว้างเงา',
            value: p.shadowWidthFactor,
            min: 0.50,
            max: 1.80,
            displayValue: '${(p.shadowWidthFactor * 100).toStringAsFixed(0)}%',
            onChanged: (v) => _updateParam(p.copyWith(shadowWidthFactor: v)),
          ),

          // 7. ความยาวเงาแนวตั้ง (shadowHeightFactor)
          _paramSlider(
            icon: Icons.swap_vert_rounded,
            label: 'ความยาวเงา',
            value: p.shadowHeightFactor,
            min: 0.40,
            max: 2.20,
            displayValue: '${(p.shadowHeightFactor * 100).toStringAsFixed(0)}%',
            onChanged: (v) => _updateParam(p.copyWith(shadowHeightFactor: v)),
          ),

          // 8. ความเข้มเงา (shadowOpacity)
          _paramSlider(
            icon: Icons.tonality_rounded,
            label: 'ความเข้มเงา',
            value: p.shadowOpacity,
            min: 0.0,
            max: 1.80,
            displayValue: '${(p.shadowOpacity * 100).toStringAsFixed(0)}%',
            onChanged: (v) => _updateParam(p.copyWith(shadowOpacity: v)),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ==================== Toggle ไอคอน 3 มิติ / รูปภาพ ====================
          Container(
            decoration: BoxDecoration(
              color: p.show3dIcon
                  ? AppColors.primaryDark.withValues(alpha: 0.05)
                  : Colors.amber.shade50.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: p.show3dIcon
                    ? AppColors.primaryDark.withValues(alpha: 0.25)
                    : Colors.amber.shade300,
              ),
            ),
            child: SwitchListTile(
              key: const ValueKey('court-card-3d-icon-toggle'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              secondary: Icon(
                p.show3dIcon ? Icons.view_in_ar_rounded : Icons.image_rounded,
                color: p.show3dIcon ? AppColors.primaryDark : Colors.amber.shade800,
              ),
              title: const Text(
                'ใช้ไอคอน 3 มิติ (3D Voxel Icon)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                p.show3dIcon
                    ? 'เปิด: แสดงก้อนลูกบาศก์ 3 มิติตามระดับคอร์ท'
                    : 'ปิด: ใช้รูปภาพที่เลือกแทนลูกบาศก์ 3 มิติ',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
              value: p.show3dIcon,
              activeThumbColor: AppColors.primaryDark,
              onChanged: (enabled) {
                _updateParam(p.copyWith(
                  show3dIcon: enabled,
                  customImageUrl: !enabled &&
                          (p.customImageUrl == null || p.customImageUrl!.isEmpty)
                      ? 'preset:tennis'
                      : null,
                ));
              },
            ),
          ),

          // ==================== เลือกรูปแทน (เมื่อปิดไอคอน 3 มิติ) ====================
          if (!p.show3dIcon) ...[
            const SizedBox(height: 10),
            _buildCustomImageSelector(p),
          ],

          const SizedBox(height: 10),

          // Save button
          if (_paramsDirty)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('court-card-save-3d-params-button'),
                onPressed: _savingParams ? null : _saveParams,
                icon: _savingParams
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('บันทึกค่า 3D'),
              ),
            ),
        ],
      ),
    );
  }

  // ===================== Custom Image Selector =====================

  Widget _buildCustomImageSelector(CourtCard3DParams p) {
    final currentImage = p.customImageUrl;
    final hasImage = currentImage != null && currentImage.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.collections_rounded, size: 16, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'เลือกรูปภาพแทนไอคอน 3 มิติ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E2330),
                  ),
                ),
              ),
              if (hasImage)
                TextButton.icon(
                  onPressed: () {
                    _updateParam(p.copyWith(clearCustomImage: true));
                  },
                  icon: const Icon(Icons.close_rounded, size: 14, color: Colors.red),
                  label: const Text(
                    'ลบรูป',
                    style: TextStyle(fontSize: 11.5, color: Colors.red),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Current image preview & upload action buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Preview box
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primaryDark.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: hasImage
                      ? _buildImageThumbnail(currentImage)
                      : Center(
                          child: Icon(
                            Icons.hide_image_outlined,
                            size: 26,
                            color: Colors.grey.shade400,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              // Action buttons (Gallery, Camera, URL)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_rounded, size: 15),
                            label: const Text('เลือกจากคลัง', style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_rounded, size: 15),
                            label: const Text('ถ่ายภาพ', style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _promptImageUrl,
                      icon: const Icon(Icons.link_rounded, size: 14),
                      label: const Text('ใส่ URL รูปภาพ', style: TextStyle(fontSize: 11.5)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Text(
            'หรือเลือกไอคอนกีฬาสำเร็จรูป:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 6),

          // Preset Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in _presets)
                _presetChip(
                  key: preset.$1,
                  label: preset.$2,
                  icon: preset.$3,
                  color: preset.$4,
                  isSelected: currentImage == preset.$1,
                  onTap: () {
                    _updateParam(p.copyWith(
                      show3dIcon: false,
                      customImageUrl: preset.$1,
                    ));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageThumbnail(String imageUrl) {
    if (imageUrl.startsWith('preset:')) {
      final key = imageUrl.substring('preset:'.length);
      final (iconData, label, color) = switch (key) {
        'tennis' => (Icons.sports_tennis_rounded, 'เทนนิส', const Color(0xFFD91E28)),
        'badminton' => (Icons.sports_baseball_rounded, 'แบดมินตัน', const Color(0xFF00897B)),
        'football' => (Icons.sports_soccer_rounded, 'ฟุตบอล', const Color(0xFF1E88E5)),
        'basketball' => (Icons.sports_basketball_rounded, 'บาสเกตบอล', const Color(0xFFFB8C00)),
        'trophy' => (Icons.emoji_events_rounded, 'รางวัล', const Color(0xFFF59E0B)),
        'stadium' => (Icons.stadium_rounded, 'สนาม', const Color(0xFF8B5CF6)),
        _ => (Icons.sports_rounded, 'กีฬา', const Color(0xFFD91E28)),
      };
      return Container(
        color: color.withValues(alpha: 0.1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconData, size: 28, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      );
    } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded, color: Colors.grey),
      );
    } else if (imageUrl.startsWith('data:image')) {
      try {
        final comma = imageUrl.indexOf(',');
        final bytes = comma != -1
            ? base64Decode(imageUrl.substring(comma + 1))
            : base64Decode(imageUrl);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
        );
      } catch (_) {
        return const Icon(Icons.broken_image_rounded, color: Colors.grey);
      }
    } else {
      try {
        return Image.file(
          File(imageUrl),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.image_outlined, color: Colors.grey),
        );
      } catch (_) {
        return const Icon(Icons.image_outlined, color: Colors.grey);
      }
    }
  }

  Widget _presetChip({
    required String key,
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: ValueKey('preset-chip-$key'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? color : Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paramSlider({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: AppColors.primaryDark.withValues(alpha: 0.7),
                inactiveTrackColor: Colors.grey.shade300,
                thumbColor: AppColors.primaryDark,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              displayValue,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== Style Tiles =====================

  Widget _styleTile(CourtCardStyle style, CourtCardStyle selected) {
    final isSelected = style == selected;
    final isSaving = _saving == style;
    return Container(
      key: ValueKey('court-card-style-${style.wireValue}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.primaryDark : Colors.grey.shade300,
          width: isSelected ? 1.8 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  style.label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isSelected)
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppColors.primaryDark,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'ใช้อยู่',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            style.description,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          // Previews are non-interactive: tapping the button selects.
          IgnorePointer(
            child: style.isThreeDimensional
                ? _buildStudioStage(style)
                : CourtCard(
                    venue: _previewVenue,
                    distanceKm: 3.4,
                    upcomingBookings: _previewBookings,
                    styleOverride: style,
                  ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: ValueKey('court-card-style-select-${style.wireValue}'),
              onPressed: isSaving ? null : () => _select(style),
              icon: isSaving
                  ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(isSelected ? 'เลือกซ้ำ' : 'ใช้รูปแบบนี้'),
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps 3D card previews in a realistic studio stage backdrop so transparency,
  /// frosted blur, red ambient glow, and right thickness edges pop vividly!
  Widget _buildStudioStage(CourtCardStyle style) {
    final isDarkStudio = _previewBackdrop == 'studio';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isDarkStudio
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF282B33),
                  Color(0xFF353944),
                  Color(0xFF454B58),
                  Color(0xFF20232A),
                ],
                stops: [0.0, 0.35, 0.75, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF3F5F9),
                  Color(0xFFE8ECF2),
                ],
              ),
        border: Border.all(
          color: isDarkStudio ? const Color(0xFF555B6A) : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: CourtCard(
          venue: _previewVenue,
          distanceKm: 3.4,
          upcomingBookings: _previewBookings,
          styleOverride: style,
          params3dOverride: _localParams,
        ),
      ),
    );
  }
}
