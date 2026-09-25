import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

/// Owner editor for the venue profile fields that public discovery,
/// radius search and timezone handling depend on. Fields marked * are
/// required before the venue can be submitted for admin review
/// (`sports_venue_setup_missing` enforces the same list server-side).
/// Photos are optional and intentionally not part of this gate.
class VenueProfileEditorSheet {
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    String? name,
    String? description,
    String? province,
    String? district,
    String? address,
    double? lat,
    double? lng,
    String? timezone,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _VenueProfileEditorSheetBody(
        name: name,
        description: description,
        province: province,
        district: district,
        address: address,
        lat: lat,
        lng: lng,
        timezone: timezone,
      ),
    );
  }
}

class _VenueProfileEditorSheetBody extends StatefulWidget {
  final String? name;
  final String? description;
  final String? province;
  final String? district;
  final String? address;
  final double? lat;
  final double? lng;
  final String? timezone;

  const _VenueProfileEditorSheetBody({
    this.name,
    this.description,
    this.province,
    this.district,
    this.address,
    this.lat,
    this.lng,
    this.timezone,
  });

  @override
  State<_VenueProfileEditorSheetBody> createState() =>
      _VenueProfileEditorSheetBodyState();
}

class _VenueProfileEditorSheetBodyState
    extends State<_VenueProfileEditorSheetBody> {
  static const _timezones = [
    'Asia/Bangkok',
    'Asia/Singapore',
    'Asia/Yangon',
    'Asia/Vientiane',
    'Asia/Phnom_Penh',
    'Asia/Kuala_Lumpur',
    'UTC',
  ];

  late final _name = TextEditingController(text: widget.name ?? '');
  late final _description = TextEditingController(
    text: widget.description ?? '',
  );
  late final _province = TextEditingController(text: widget.province ?? '');
  late final _district = TextEditingController(text: widget.district ?? '');
  late final _address = TextEditingController(text: widget.address ?? '');
  late final _lat = TextEditingController(text: widget.lat?.toString() ?? '');
  late final _lng = TextEditingController(text: widget.lng?.toString() ?? '');
  late String? _timezone = _timezones.contains(widget.timezone)
      ? widget.timezone
      : 'Asia/Bangkok';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _province.dispose();
    _district.dispose();
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  /// Null = valid empty; -1 = malformed / out of range.
  double? _coord(TextEditingController c, {required bool isLat}) {
    final raw = c.text.trim();
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null) return -1;
    if (isLat && (parsed < -90 || parsed > 90)) return -1;
    if (!isLat && (parsed < -180 || parsed > 180)) return -1;
    return parsed;
  }

  double? get _latValue => _coord(_lat, isLat: true);
  double? get _lngValue => _coord(_lng, isLat: false);

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _province.text.trim().isNotEmpty &&
      _district.text.trim().isNotEmpty &&
      _address.text.trim().isNotEmpty &&
      _latValue != null &&
      _latValue != -1 &&
      _lngValue != null &&
      _lngValue != -1 &&
      _timezone != null;

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      'province': _province.text.trim(),
      'district': _district.text.trim(),
      'address': _address.text.trim(),
      'lat': _latValue,
      'lng': _lngValue,
      'timezone': _timezone,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ข้อมูลสนาม',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'ข้อมูลที่มีเครื่องหมาย * จำเป็นต่อการค้นหาและการส่งตรวจสอบ — รูปภาพสนามไม่บังคับ',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                maxLength: 120,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: 'ชื่อสนาม/สถานที่ *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: 'รายละเอียด (ไม่บังคับ)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _province,
                      decoration: const InputDecoration(
                        labelText: 'จังหวัด *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _district,
                      decoration: const InputDecoration(
                        labelText: 'อำเภอ/เขต *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                maxLength: 500,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: 'ที่อยู่ *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'ละติจูด *',
                        hintText: 'เช่น 13.7563',
                        errorText: _latValue == -1 ? '-90 ถึง 90' : null,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'ลองจิจูด *',
                        hintText: 'เช่น 100.5018',
                        errorText: _lngValue == -1 ? '-180 ถึง 180' : null,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _timezone,
                decoration: const InputDecoration(
                  labelText: 'เขตเวลา *',
                  helperText: 'เวลาเปิด–ปิดและเวลาจองใช้เขตเวลานี้',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final tz in _timezones)
                    DropdownMenuItem(value: tz, child: Text(tz)),
                ],
                onChanged: (v) => setState(() => _timezone = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                  ),
                  onPressed: _valid ? _submit : null,
                  child: const Text('บันทึก'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
