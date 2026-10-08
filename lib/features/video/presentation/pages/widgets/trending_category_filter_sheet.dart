import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

/// Phase 20: Bottom sheet เลือกประเภทเหตุหลายหมวด (OR) สำหรับกล่องยอดนิยม
///
/// - รายการหมวดเรียงตาม [categories] ที่ส่งมา (display_order จากหน้าแล้ว)
/// - draft อยู่ใน sheet — commit เข้า page state เฉพาะเมื่อ apply สำเร็จ
/// - apply เป็น async: ล้มเหลว → แสดง error + ปุ่มลองใหม่ โดยไม่แตะค่าเดิม
/// - footer มี 2 ปุ่ม: "ล้างค่าทั้งหมด" (สีส้ม — ล้าง draft แล้ว commit ทันที)
///   และ "แสดงผล" (commit draft ปัจจุบัน); ไม่มีปุ่มยกเลิก — ปิด sheet ได้ทาง
///   ปุ่มปิดมุมขวาบนหรือแตะฉากหลัง ซึ่งไม่ commit draft
/// - [suspensionSignal] = true (เข้าสู่ mission/reporter lock) → ปิด route
///   นี้เองโดยไม่ commit draft — ห้าม pop หน้าจอแม่
class TrendingCategoryFilterSheet extends StatefulWidget {
  final List<DonationCategory> categories;
  final Set<String> initialSelectedIds;
  final Future<bool> Function(Set<String> selected)? onApply;
  final ValueListenable<bool> suspensionSignal;

  /// Phase 22 — ปุ่ม "แผนที่เกิดเหตุ" บรรทัดเดียวกับชื่อหมวด (ต่อจากชื่อ
  /// ก่อน toggle): ใช้ `categoryId` ของหมวดนั้นเพียงหมวดเดียว ไม่อ่าน/
  /// commit `_draft` และไม่เปลี่ยนตัวกรองยอดนิยม
  /// (null = ปิด feature gate → ไม่แสดงปุ่ม)
  final void Function(DonationCategory category)? onOpenIncidentMap;

  /// Phase 22 — แจ้ง draft ปัจจุบันของ sheet ให้หน้าเก็บไว้ (ครั้งแรกตอนเปิด
  /// และทุกครั้งที่ผู้ใช้สลับ toggle) เพื่อให้กดย้อนกลับจากโหมดแผนที่แล้วเปิด
  /// sheet กลับมาที่สถานะเดิมได้ (§22.13)
  final ValueChanged<Set<String>>? onDraftChanged;

  const TrendingCategoryFilterSheet({
    super.key,
    required this.categories,
    required this.initialSelectedIds,
    required this.suspensionSignal,
    this.onApply,
    this.onOpenIncidentMap,
    this.onDraftChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required List<DonationCategory> categories,
    required Set<String> initialSelectedIds,
    required ValueListenable<bool> suspensionSignal,
    Future<bool> Function(Set<String> selected)? onApply,
    void Function(DonationCategory category)? onOpenIncidentMap,
    ValueChanged<Set<String>>? onDraftChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => TrendingCategoryFilterSheet(
        categories: categories,
        initialSelectedIds: initialSelectedIds,
        suspensionSignal: suspensionSignal,
        onApply: onApply,
        onOpenIncidentMap: onOpenIncidentMap,
        onDraftChanged: onDraftChanged,
      ),
    );
  }

  @override
  State<TrendingCategoryFilterSheet> createState() =>
      _TrendingCategoryFilterSheetState();
}

class _TrendingCategoryFilterSheetState
    extends State<TrendingCategoryFilterSheet> {
  late final Set<String> _draft = {...widget.initialSelectedIds};
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.suspensionSignal.addListener(_onSuspensionChanged);
    // เปิดมาระหว่างที่ suspension เริ่มไปแล้ว → ปิดทันที
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSuspensionChanged();
      // แจ้ง draft เริ่มต้น — หน้าเก็บไว้ใช้เปิด sheet กลับมาที่เดิม (§22.13)
      widget.onDraftChanged?.call(Set.of(_draft));
    });
  }

  @override
  void dispose() {
    widget.suspensionSignal.removeListener(_onSuspensionChanged);
    super.dispose();
  }

  void _onSuspensionChanged() {
    if (!mounted || widget.suspensionSignal.value != true) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Navigator.of(context).maybePop();
    }
  }

  /// สีส้มเดียวกับป้าย "ยอดนิยม"/ปุ่มตัวกรองประเภทเหตุในแถวบนสุด
  static const Color _clearAllColor = Color(0xFFFF6B35);

  /// ล้างตัวกรองทั้งหมดแล้ว commit ทันที — ไม่ปิด sheet เองตรงนี้
  /// (`_apply` จะ pop เมื่อ commit สำเร็จ; ล้มเหลวจะคง sheet + error/retry)
  Future<void> _clearAllAndApply() async {
    if (_applying) return;
    setState(() => _draft.clear());
    widget.onDraftChanged?.call(Set.of(_draft));
    await _apply();
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    bool ok;
    try {
      ok = await widget.onApply?.call(Set.of(_draft)) ?? true;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _applying = false;
      _error = 'โหลดรายการไม่สำเร็จ — กรุณาลองอีกครั้ง';
    });
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicSheetShell(
      title: 'คัดกรอง และแผนที่',
      icon: Icons.filter_list_rounded,
      heightFactor: 0.6,
      onClose: _applying ? null : () => Navigator.of(context).pop(),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              // ✅ ย้ายปุ่มล้างค่าทั้งหมดจาก header มาแทนตำแหน่งเดิมของ
              // "ยกเลิก" — กดแล้วล้าง draft + commit ทันที (กลับไปแสดงทุก
              // ประเภท) แล้ว sheet ปิดเองเมื่อ apply สำเร็จ
              Expanded(
                child: NeumorphicPillButton(
                  text: 'ล้างค่าทั้งหมด',
                  color: _clearAllColor,
                  onPressed: _applying ? null : _clearAllAndApply,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NeumorphicVerifyButton(
                  text: 'แสดงผล',
                  isLoading: _applying,
                  isEnabled: !_applying,
                  height: 48,
                  onPressed: _apply,
                ),
              ),
            ],
          ),
        ],
      ),
      children: [
        Text(
          _draft.isEmpty
              ? 'เลือกเพื่อประเมินสถานการณ์ (เฉพาะเหตุ)'
              : 'เลือก ${_draft.length} ประเภท',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: NeumorphicTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        for (final category in widget.categories) ...[
          NeumorphicSwitchTile(
            title: category.name,
            value: _draft.contains(category.id),
            onChanged: _applying
                ? null
                : (selected) {
                    setState(() {
                      if (selected) {
                        _draft.add(category.id);
                      } else {
                        _draft.remove(category.id);
                      }
                    });
                    widget.onDraftChanged?.call(Set.of(_draft));
                  },
            // ✅ Phase 22: ปุ่ม "แผนที่เกิดเหตุ" บรรทัดเดียวกับชื่อหมวด
            // (ต่อจากชื่อ ก่อน toggle) — ใช้หมวดนั้นเพียงหมวดเดียว
            // ไม่แตะ draft/ตัวกรอง (§22.1/§22.11)
            titleAccessory: widget.onOpenIncidentMap == null
                ? null
                : NeumorphicPillButton(
                    text: 'แผนที่เกิดเหตุ',
                    icon: Icons.map_outlined,
                    height: 32,
                    // §22.15: ลดตัวอักษร/ไอคอนและความกว้างขั้นต่ำลง เพื่อไม่ให้
                    // แคปซูลกินพื้นที่จนชื่อหมวดเหลือ 2–3 ตัวอักษร (เดิม
                    // fontSize 12/minWidth 132/padding 10 → แคปซูล ~152dp)
                    fontSize: 11,
                    iconSize: 13,
                    depth: 3,
                    blur: 6,
                    minWidth: 100,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    // ✅ §22.1: กดแล้ว sheet ปิดตัวเองก่อน (ไม่ commit draft)
                    // แล้ว callback จึงเข้าสู่โหมดแผนที่ — page ไม่ต้อง pop ซ้ำ
                    onPressed: _applying
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            widget.onOpenIncidentMap!(category);
                          },
                  ),
          ),
        ],
      ],
    );
  }
}
