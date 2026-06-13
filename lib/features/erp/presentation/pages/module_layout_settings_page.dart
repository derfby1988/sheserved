import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_module_layout.dart';
import '../providers/dashboard_theme_provider.dart';

class ModuleLayoutSettingsPage extends ConsumerStatefulWidget {
  const ModuleLayoutSettingsPage({super.key});

  @override
  ConsumerState<ModuleLayoutSettingsPage> createState() => _ModuleLayoutSettingsPageState();
}

class _ModuleLayoutSettingsPageState extends ConsumerState<ModuleLayoutSettingsPage> {
  late DashboardModuleLayoutConfig _layout;

  static const List<Color> _palette = [
    Color(0xFFBFE7FF),
    Color(0xFFCFEFBA),
    Color(0xFFF0E7B4),
    Color(0xFFA7D8F5),
    Color(0xFFBDEBDB),
    Color(0xFFE5F6C8),
    Color(0xFFD7D0FF),
    Color(0xFFF7C9A9),
    Color(0xFFFFD6E7),
    Color(0xFFD9E8FF),
  ];

  @override
  void initState() {
    super.initState();
    _layout = ref.read(dashboardThemeProvider.notifier).moduleLayout;
  }

  Future<void> _saveLayout(DashboardModuleLayoutConfig layout) async {
    setState(() => _layout = layout);
    await ref.read(dashboardThemeProvider.notifier).saveModuleLayout(layout);
  }

  Future<void> _moveModule(String moduleId, String targetGroupId) async {
    final next = _layout.moveModuleToGroup(moduleId, targetGroupId);
    await _saveLayout(next);
  }

  Future<void> _setGroupColor(String groupId, String colorHex) async {
    final next = _layout.updateGroupColor(groupId, colorHex);
    await _saveLayout(next);
  }

  Future<void> _renameGroup(BuildContext context, DashboardModuleGroupConfig group) async {
    final controller = TextEditingController(text: group.title);
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('เปลี่ยนชื่อกลุ่ม'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'ชื่อกลุ่ม',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('บันทึก')),
        ],
      ),
    );

    if (shouldSave != true) {
      controller.dispose();
      return;
    }

    final title = controller.text.trim();
    controller.dispose();
    if (title.isEmpty) return;

    final ok = await ref.read(dashboardThemeProvider.notifier).renameModuleGroup(group.id, title);
    if (!context.mounted) return;
    if (ok) {
      setState(() => _layout = ref.read(dashboardThemeProvider.notifier).moduleLayout);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'เปลี่ยนชื่อกลุ่มเรียบร้อยแล้ว' : 'เปลี่ยนชื่อกลุ่มไม่สำเร็จ')),
    );
  }

  Future<void> _resetGroupTitle(BuildContext context, DashboardModuleGroupConfig group) async {
    final defaultGroup = DashboardModuleLayoutConfig.defaultGroupConfigById(group.id);
    if (defaultGroup == null) return;

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('รีเซตชื่อกลุ่ม?'),
        content: Text('จะคืนชื่อกลุ่มกลับเป็น "${defaultGroup.title}"'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('รีเซตชื่อ')),
        ],
      ),
    );

    if (shouldReset != true) return;

    final ok = await ref.read(dashboardThemeProvider.notifier).resetModuleGroupTitle(group.id);
    if (!context.mounted) return;
    if (ok) {
      setState(() => _layout = ref.read(dashboardThemeProvider.notifier).moduleLayout);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'รีเซตชื่อกลุ่มเรียบร้อยแล้ว' : 'รีเซตชื่อกลุ่มไม่สำเร็จ')),
    );
  }

  Future<void> _resetGroup(BuildContext context, DashboardModuleGroupConfig group) async {
    final defaultGroup = DashboardModuleLayoutConfig.defaultGroupConfigById(group.id);
    if (defaultGroup == null) return;

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('รีเซตกลุ่มนี้?'),
        content: const Text('ระบบจะคืนชื่อและสีของกลุ่มนี้กลับเป็นค่าเริ่มต้น แต่จะคงการ์ดที่อยู่ในกลุ่มนี้ไว้'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('รีเซตกลุ่ม')),
        ],
      ),
    );

    if (shouldReset != true) return;

    final ok = await ref.read(dashboardThemeProvider.notifier).resetModuleGroup(group.id);
    if (!context.mounted) return;
    if (ok) {
      setState(() => _layout = ref.read(dashboardThemeProvider.notifier).moduleLayout);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'รีเซตกลุ่มเรียบร้อยแล้ว' : 'รีเซตกลุ่มไม่สำเร็จ')),
    );
  }

  Future<void> _resetColors(BuildContext context) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('รีเซตสีของกลุ่ม?'),
        content: const Text('ระบบจะคืนค่าสีของแต่ละกลุ่มกลับไปเป็นค่าเริ่มต้น แต่จะไม่เปลี่ยนการจัดกลุ่มหรือการเรียงลำดับการ์ด'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('รีเซตสี')),
        ],
      ),
    );

    if (shouldReset != true) return;

    final ok = await ref.read(dashboardThemeProvider.notifier).resetModuleColors();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'รีเซตสีของกลุ่มเรียบร้อยแล้ว' : 'รีเซตสีของกลุ่มไม่สำเร็จ')),
    );
  }

  Future<void> _resetLayout(BuildContext context) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('รีเซต layout กลับค่าเริ่มต้น?'),
        content: const Text('ระบบจะคืนค่ากลุ่ม สี และลำดับการ์ดทั้งหมดกลับเป็นค่าเริ่มต้น'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('รีเซต layout')),
        ],
      ),
    );

    if (shouldReset != true) return;

    final ok = await ref.read(dashboardThemeProvider.notifier).resetModuleLayout();
    if (!context.mounted) return;
    if (ok) {
      setState(() => _layout = ref.read(dashboardThemeProvider.notifier).moduleLayout);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'รีเซต layout เรียบร้อยแล้ว' : 'รีเซต layout ไม่สำเร็จ')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardThemeProvider);
    final isDark = state.theme?.isDarkMode ?? false;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF617181);
    final background = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEFF8F5);

    final assigned = <String>{};
    for (final group in _layout.groups) {
      assigned.addAll(group.moduleIds);
    }
    final ungrouped = dashboardModuleDefinitions.where((module) => !assigned.contains(module.id)).toList();

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text('จัดการกลุ่มการ์ด Dashboard', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'ลากการ์ดไปยังกลุ่มที่ต้องการ และแตะสีเพื่อเปลี่ยนโทนประจำกลุ่ม',
              style: TextStyle(fontSize: 13, color: textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: state.isSaving ? null : () => _resetColors(context),
                  icon: const Icon(Icons.color_lens_outlined),
                  label: const Text('รีเซตสี'),
                ),
                OutlinedButton.icon(
                  onPressed: state.isSaving ? null : () => _resetLayout(context),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('รีเซต layout'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.isSaving)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ..._layout.groups.map((group) => _buildGroupCard(group, context)),
            if (ungrouped.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildUngroupedCard(ungrouped, context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(DashboardModuleGroupConfig group, BuildContext context) {
    final color = group.color;
    final modules = group.moduleIds.map((id) => dashboardModuleById(id)).whereType<DashboardModuleDefinition>().toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) => _moveModule(details.data, group.id),
        builder: (context, candidate, rejected) {
          final highlighted = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: color.withValues(alpha: highlighted ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: highlighted ? 0.75 : 0.42), width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          group.title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${modules.length} รายการ',
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: color),
                        onSelected: (value) {
                          switch (value) {
                            case 'rename':
                              _renameGroup(context, group);
                              break;
                            case 'reset_name':
                              _resetGroupTitle(context, group);
                              break;
                            case 'reset_group':
                              _resetGroup(context, group);
                              break;
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem<String>(value: 'rename', child: Text('เปลี่ยนชื่อกลุ่ม')),
                          PopupMenuItem<String>(value: 'reset_name', child: Text('รีเซตชื่อกลุ่ม')),
                          PopupMenuItem<String>(value: 'reset_group', child: Text('รีเซตกลุ่มนี้')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _palette.map((paletteColor) {
                      final hex = _hexFromColor(paletteColor);
                      final isSelected = _sameColor(group.color, paletteColor);
                      return GestureDetector(
                        onTap: () => _setGroupColor(group.id, hex),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: paletteColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? const Color(0xFF1D2733) : Colors.white.withValues(alpha: 0.5),
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  if (modules.isEmpty)
                    Text('ลากการ์ดมาวางที่นี่เพื่อเพิ่มไปยังกลุ่มนี้', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: modules.map((module) => _buildDraggableModuleChip(module, color)).toList(),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUngroupedCard(List<DashboardModuleDefinition> modules, BuildContext context) {
    return DragTarget<String>(
      onAcceptWithDetails: (details) => _moveModule(details.data, _layout.groups.first.id),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: highlighted ? 0.65 : 0.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ไม่มีกลุ่ม', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('โมดูลเหล่านี้ยังไม่ได้ถูกกำหนดกลุ่ม', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: modules.map((module) => _buildDraggableModuleChip(module, Colors.grey.shade400)).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDraggableModuleChip(DashboardModuleDefinition module, Color color) {
    return LongPressDraggable<String>(
      data: module.id,
      feedback: Material(
        color: Colors.transparent,
        child: _ModuleChip(
          module: module,
          color: color,
          elevated: true,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _ModuleChip(module: module, color: color),
      ),
      child: _ModuleChip(module: module, color: color),
    );
  }

  static bool _sameColor(Color a, Color b) => a.toARGB32() == b.toARGB32();

  static String _hexFromColor(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

class _ModuleChip extends StatelessWidget {
  final DashboardModuleDefinition module;
  final Color color;
  final bool elevated;

  const _ModuleChip({required this.module, required this.color, this.elevated = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(module.icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  module.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  module.thaiLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
