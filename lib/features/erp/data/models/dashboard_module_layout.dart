import 'package:flutter/material.dart';

/// Catalog กลางของโมดูล ERP Dashboard
class DashboardModuleDefinition {
  final String id;
  final String label;
  final String thaiLabel;
  final String routeName;
  final IconData icon;
  final int span;
  final double heightFactor;
  final DashboardModuleTileVariant variant;
  final String defaultGroupId;

  const DashboardModuleDefinition({
    required this.id,
    required this.label,
    required this.thaiLabel,
    required this.routeName,
    required this.icon,
    required this.span,
    required this.heightFactor,
    required this.variant,
    required this.defaultGroupId,
  });
}

enum DashboardModuleTileVariant { square, capsule, tall }

class DashboardModuleGroupConfig {
  final String id;
  final String title;
  final String colorHex;
  final String titleColorHex;
  final List<String> moduleIds;

  const DashboardModuleGroupConfig({
    required this.id,
    required this.title,
    required this.colorHex,
    this.titleColorHex = '',
    required this.moduleIds,
  });

  static const String noColorHex = '';

  Color? get tintColor {
    final clean = colorHex.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'none') return null;
    final normalized = clean.replaceFirst('#', '');
    if (normalized.length == 6) return Color(int.parse('FF$normalized', radix: 16));
    if (normalized.length == 8) return Color(int.parse(normalized, radix: 16));
    return null;
  }

  bool get hasTintColor => tintColor != null;

  Color get color {
    return tintColor ?? const Color(0xFF94A3B8);
  }

  Color? get titleTintColor {
    final clean = titleColorHex.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'none') return null;
    final normalized = clean.replaceFirst('#', '');
    if (normalized.length == 6) return Color(int.parse('FF$normalized', radix: 16));
    if (normalized.length == 8) return Color(int.parse(normalized, radix: 16));
    return null;
  }

  Color? get titleColor {
    final clean = titleColorHex.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'none') return null;
    return titleTintColor ?? color;
  }

  DashboardModuleGroupConfig copyWith({
    String? id,
    String? title,
    String? colorHex,
    String? titleColorHex,
    List<String>? moduleIds,
  }) {
    return DashboardModuleGroupConfig(
      id: id ?? this.id,
      title: title ?? this.title,
      colorHex: colorHex ?? this.colorHex,
      titleColorHex: titleColorHex ?? this.titleColorHex,
      moduleIds: moduleIds ?? this.moduleIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'color_hex': colorHex,
        'title_color_hex': titleColorHex,
        'module_ids': moduleIds,
      };

  factory DashboardModuleGroupConfig.fromJson(Map<String, dynamic> json) {
    return DashboardModuleGroupConfig(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      colorHex: json['color_hex'] as String? ?? noColorHex,
      titleColorHex: json['title_color_hex'] as String? ?? '',
      moduleIds: (json['module_ids'] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }
}

class DashboardModuleLayoutConfig {
  final List<DashboardModuleGroupConfig> groups;

  const DashboardModuleLayoutConfig({required this.groups});

  static DashboardModuleGroupConfig? defaultGroupConfigById(String groupId) {
    for (final group in defaultLayout().groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  static DashboardModuleLayoutConfig defaultLayout() {
    return DashboardModuleLayoutConfig(groups: [
      DashboardModuleGroupConfig(
        id: 'sales',
        title: 'ขายและบริการ',
        colorHex: '#BFE7FF',
        titleColorHex: '',
        moduleIds: [
          'counter_pos',
          'clinic_pos',
          'cart_checkout',
          'delivery',
          'refunds',
          'loyalty_rules',
          'reports',
        ],
      ),
      DashboardModuleGroupConfig(
        id: 'inventory',
        title: 'คลังสินค้า',
        colorHex: '#CFEFBA',
        titleColorHex: '',
        moduleIds: [
          'inventory_management',
          'inventory_dashboard',
          'stock_transfer',
          'stock_adjustment',
          'stock_movements',
          'stocktake_config',
          'goods_receipt',
        ],
      ),
      DashboardModuleGroupConfig(
        id: 'procurement',
        title: 'จัดซื้อ',
        colorHex: '#F7C9A9',
        titleColorHex: '',
        moduleIds: [
          'procurement_management',
          'vendor_contracts',
          'payment_channels',
        ],
      ),
      DashboardModuleGroupConfig(
        id: 'finance',
        title: 'การเงิน',
        colorHex: '#D7D0FF',
        titleColorHex: '',
        moduleIds: [
          'gl_entries',
          'chart_of_accounts',
          'accounts_receivable',
          'accounts_payable',
          'analytics',
        ],
      ),
      DashboardModuleGroupConfig(
        id: 'people',
        title: 'บุคคล',
        colorHex: '#A7D8F5',
        titleColorHex: '',
        moduleIds: [
          'employees',
          'shifts',
          'payroll',
          'hr_settings',
        ],
      ),
      DashboardModuleGroupConfig(
        id: 'crm',
        title: 'ลูกค้าสัมพันธ์',
        colorHex: '#F0E7B4',
        titleColorHex: '',
        moduleIds: [
          'customers',
        ],
      ),
      DashboardModuleGroupConfig(
        id: 'clinical',
        title: 'คลินิก',
        colorHex: '#BDEBDB',
        titleColorHex: '',
        moduleIds: [
          'emr_records',
          'opd_visits',
          'prescriptions',
          'lab_results',
          'patient_cohorts',
        ],
      ),
      DashboardModuleGroupConfig(
        id: 'admin',
        title: 'ตั้งค่า',
        colorHex: '#E5F6C8',
        titleColorHex: '',
        moduleIds: [
          'organization_settings',
          'role_management',
        ],
      ),
    ]);
  }

  factory DashboardModuleLayoutConfig.fromJson(dynamic json) {
    try {
      final rawGroups = json is Map<String, dynamic> ? json['groups'] as List? : null;
      if (rawGroups == null || rawGroups.isEmpty) {
        return defaultLayout();
      }
      return DashboardModuleLayoutConfig(
        groups: rawGroups
            .map((e) => DashboardModuleGroupConfig.fromJson(e as Map<String, dynamic>))
            .where((g) => g.id.isNotEmpty)
            .toList(),
      );
    } catch (_) {
      return defaultLayout();
    }
  }

  Map<String, dynamic> toJson() => {
        'groups': groups.map((group) => group.toJson()).toList(),
      };

  DashboardModuleLayoutConfig copyWith({List<DashboardModuleGroupConfig>? groups}) {
    return DashboardModuleLayoutConfig(groups: groups ?? this.groups);
  }

  DashboardModuleLayoutConfig reorderGroups(int oldIndex, int newIndex) {
    final next = [...groups];
    if (oldIndex < 0 || oldIndex >= next.length) return this;
    if (newIndex < 0 || newIndex > next.length) return this;
    final item = next.removeAt(oldIndex);
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(targetIndex, item);
    return copyWith(groups: next);
  }

  DashboardModuleLayoutConfig moveModuleToGroup(String moduleId, String targetGroupId) {
    final next = groups
        .map((group) => group.copyWith(moduleIds: [...group.moduleIds]))
        .toList();

    DashboardModuleGroupConfig? targetGroup;
    for (final group in next) {
      if (group.moduleIds.contains(moduleId)) {
        group.moduleIds.remove(moduleId);
      }
      if (group.id == targetGroupId) {
        targetGroup = group;
      }
    }

    if (targetGroup == null) return this;
    if (!targetGroup.moduleIds.contains(moduleId)) {
      targetGroup.moduleIds.add(moduleId);
    }
    return copyWith(groups: next);
  }

  DashboardModuleLayoutConfig updateGroupColor(String groupId, String colorHex) {
    final next = groups
        .map((group) => group.id == groupId ? group.copyWith(colorHex: colorHex) : group)
        .toList();
    return copyWith(groups: next);
  }

  DashboardModuleLayoutConfig renameGroup(String groupId, String title) {
    final cleaned = title.trim();
    if (cleaned.isEmpty) return this;
    final next = groups
        .map((group) => group.id == groupId ? group.copyWith(title: cleaned) : group)
        .toList();
    return copyWith(groups: next);
  }

  DashboardModuleLayoutConfig resetGroupTitle(String groupId) {
    final defaultGroup = defaultGroupConfigById(groupId);
    if (defaultGroup == null) return this;

    final next = groups
        .map((group) => group.id == groupId ? group.copyWith(title: defaultGroup.title) : group)
        .toList();
    return copyWith(groups: next);
  }

  DashboardModuleLayoutConfig resetGroupAppearance(String groupId) {
    final defaultGroup = defaultGroupConfigById(groupId);
    if (defaultGroup == null) return this;

    final next = groups
        .map((group) {
          if (group.id != groupId) return group;
          return group.copyWith(
            title: defaultGroup.title,
            colorHex: defaultGroup.colorHex,
            titleColorHex: defaultGroup.titleColorHex,
          );
        })
        .toList();
    return copyWith(groups: next);
  }

  DashboardModuleLayoutConfig updateGroupTitleColor(String groupId, String colorHex) {
    final next = groups
        .map((group) => group.id == groupId ? group.copyWith(titleColorHex: colorHex) : group)
        .toList();
    return copyWith(groups: next);
  }

  DashboardModuleGroupConfig? groupById(String groupId) {
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  DashboardModuleGroupConfig? groupForModule(String moduleId) {
    for (final group in groups) {
      if (group.moduleIds.contains(moduleId)) return group;
    }
    return null;
  }

  String groupColorHexForModule(String moduleId) {
    return groupForModule(moduleId)?.colorHex ?? '#BFE7FF';
  }

  /// ตรวจสอบว่า module ทุกตัวถูก assign เข้า group ตาม defaultGroupId
  /// ถ้า module ไหนหาย หรืออยู่ในกลุ่มผิด ให้ย้ายกลับไป default group
  DashboardModuleLayoutConfig normalize() {
    final defaultGroups = defaultLayout().groups;
    final defaultGroupByModuleId = <String, String>{};
    for (final def in dashboardModuleDefinitions) {
      defaultGroupByModuleId[def.id] = def.defaultGroupId;
    }

    // สร้าง group ใหม่จาก defaultLayout แล้วใส่ module ที่ควรอยู่
    final nextGroups = defaultGroups.map((defaultGroup) {
      final existingGroup = groupById(defaultGroup.id);
      final existingModules = existingGroup?.moduleIds.toSet() ?? <String>{};
      final normalizedModules = defaultGroup.moduleIds.toList();

      // ย้าย module ที่ default อยู่กลุ่มนี้ แต่ถูกบันทึกไว้ที่อื่น กลับมาที่นี่
      for (final moduleId in defaultGroup.moduleIds) {
        if (defaultGroupByModuleId[moduleId] == defaultGroup.id) {
          if (!normalizedModules.contains(moduleId)) {
            normalizedModules.add(moduleId);
          }
        }
      }

      // เก็บ module ที่ user จัดวางไว้ในกลุ่มนี้ (แต่ไม่ใช่ default) ไว้ก่อน
      for (final moduleId in existingModules) {
        if (!normalizedModules.contains(moduleId) &&
            groupForModule(moduleId)?.id == defaultGroup.id) {
          normalizedModules.add(moduleId);
        }
      }

      return defaultGroup.copyWith(moduleIds: normalizedModules);
    }).toList();

    return DashboardModuleLayoutConfig(groups: nextGroups);
  }
}

const List<DashboardModuleDefinition> dashboardModuleDefinitions = [
  DashboardModuleDefinition(
    id: 'counter_pos',
    label: 'Counter POS',
    thaiLabel: 'ขายหน้าร้าน',
    routeName: '/erp/pos/counter',
    icon: Icons.point_of_sale,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'sales',
  ),
  DashboardModuleDefinition(
    id: 'clinic_pos',
    label: 'Clinic POS',
    thaiLabel: 'ขายบริการคลินิก',
    routeName: '/erp/pos/clinic',
    icon: Icons.local_hospital,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'sales',
  ),
  DashboardModuleDefinition(
    id: 'inventory_management',
    label: 'Inventory Management',
    thaiLabel: 'คลังสินค้า',
    routeName: '/erp/inventory',
    icon: Icons.inventory_2,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'inventory',
  ),
  DashboardModuleDefinition(
    id: 'inventory_dashboard',
    label: 'Inventory Dashboard',
    thaiLabel: 'ภาพรวมคลัง',
    routeName: '/erp/inventory/dashboard',
    icon: Icons.dashboard,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'inventory',
  ),
  DashboardModuleDefinition(
    id: 'stock_transfer',
    label: 'Stock Transfer',
    thaiLabel: 'โอนย้ายสินค้า',
    routeName: '/erp/inventory/transfer',
    icon: Icons.swap_horiz,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'inventory',
  ),
  DashboardModuleDefinition(
    id: 'stock_adjustment',
    label: 'Stock Adjustment',
    thaiLabel: 'ปรับสต็อก',
    routeName: '/erp/inventory/adjustment',
    icon: Icons.tune,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'inventory',
  ),
  DashboardModuleDefinition(
    id: 'stock_movements',
    label: 'Stock Movements',
    thaiLabel: 'ประวัติสต็อก',
    routeName: '/erp/inventory/movements',
    icon: Icons.history,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'inventory',
  ),
  DashboardModuleDefinition(
    id: 'stocktake_config',
    label: 'Stocktake Config',
    thaiLabel: 'ตั้งค่าตรวจนับ',
    routeName: '/erp/inventory/stocktake-config',
    icon: Icons.fact_check,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'inventory',
  ),
  DashboardModuleDefinition(
    id: 'goods_receipt',
    label: 'Goods Receipt',
    thaiLabel: 'รับของเข้า',
    routeName: '/erp/inventory/receipt',
    icon: Icons.arrow_downward,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'inventory',
  ),
  DashboardModuleDefinition(
    id: 'procurement_management',
    label: 'Procurement Management',
    thaiLabel: 'จัดซื้อจัดจ้าง',
    routeName: '/erp/suppliers',
    icon: Icons.shopping_bag,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'procurement',
  ),
  DashboardModuleDefinition(
    id: 'vendor_contracts',
    label: 'Vendor Contracts',
    thaiLabel: 'สัญญาผู้ให้บริการ',
    routeName: '/erp/vendor-contracts',
    icon: Icons.description,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'procurement',
  ),
  DashboardModuleDefinition(
    id: 'payment_channels',
    label: 'Payment Channels',
    thaiLabel: 'ช่องทางชำระเงิน',
    routeName: '/erp/payment-channels',
    icon: Icons.payments,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'procurement',
  ),
  DashboardModuleDefinition(
    id: 'delivery',
    label: 'Delivery',
    thaiLabel: 'การจัดส่ง',
    routeName: '/erp/delivery',
    icon: Icons.local_shipping,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'sales',
  ),
  DashboardModuleDefinition(
    id: 'gl_entries',
    label: 'GL Entries',
    thaiLabel: 'บัญชีแยกประเภท',
    routeName: '/erp/gl-entries',
    icon: Icons.account_balance,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'finance',
  ),
  DashboardModuleDefinition(
    id: 'chart_of_accounts',
    label: 'Chart of Accounts',
    thaiLabel: 'ผังบัญชี',
    routeName: '/erp/chart-of-accounts',
    icon: Icons.account_tree,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'finance',
  ),
  DashboardModuleDefinition(
    id: 'accounts_receivable',
    label: 'AR',
    thaiLabel: 'ลูกหนี้การค้า',
    routeName: '/erp/accounts-receivable',
    icon: Icons.request_quote,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'finance',
  ),
  DashboardModuleDefinition(
    id: 'accounts_payable',
    label: 'AP',
    thaiLabel: 'เจ้าหนี้การค้า',
    routeName: '/erp/accounts-payable',
    icon: Icons.payment,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'finance',
  ),
  DashboardModuleDefinition(
    id: 'analytics',
    label: 'Analytics',
    thaiLabel: 'วิเคราะห์ข้อมูล',
    routeName: '/erp/analytics',
    icon: Icons.analytics,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'finance',
  ),
  DashboardModuleDefinition(
    id: 'employees',
    label: 'HR Management',
    thaiLabel: 'บุคคล',
    routeName: '/erp/employees',
    icon: Icons.people_alt,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'people',
  ),
  DashboardModuleDefinition(
    id: 'shifts',
    label: 'Shifts',
    thaiLabel: 'ตารางเวร',
    routeName: '/erp/shifts',
    icon: Icons.calendar_month,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'people',
  ),
  DashboardModuleDefinition(
    id: 'payroll',
    label: 'Payroll',
    thaiLabel: 'เงินเดือน',
    routeName: '/erp/payroll',
    icon: Icons.payments,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'people',
  ),
  DashboardModuleDefinition(
    id: 'hr_settings',
    label: 'HR Settings',
    thaiLabel: 'ตั้งค่า HR',
    routeName: '/erp/hr-settings',
    icon: Icons.settings_suggest,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'people',
  ),
  DashboardModuleDefinition(
    id: 'customers',
    label: 'CRM Management',
    thaiLabel: 'ลูกค้าสัมพันธ์',
    routeName: '/erp/customers',
    icon: Icons.contact_support,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'crm',
  ),
  DashboardModuleDefinition(
    id: 'emr_records',
    label: 'EMR Records',
    thaiLabel: 'ประวัติผู้ป่วย',
    routeName: '/clinical/emr',
    icon: Icons.folder_shared,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'clinical',
  ),
  DashboardModuleDefinition(
    id: 'opd_visits',
    label: 'OPD Visits',
    thaiLabel: 'ตรวจผู้ป่วยนอก',
    routeName: '/clinical/opd',
    icon: Icons.medical_services,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'clinical',
  ),
  DashboardModuleDefinition(
    id: 'prescriptions',
    label: 'Prescriptions',
    thaiLabel: 'ใบสั่งยา',
    routeName: '/clinical/prescriptions',
    icon: Icons.medication,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'clinical',
  ),
  DashboardModuleDefinition(
    id: 'lab_results',
    label: 'Lab Results',
    thaiLabel: 'ผลแล็บ',
    routeName: '/clinical/lab',
    icon: Icons.biotech,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'clinical',
  ),
  DashboardModuleDefinition(
    id: 'patient_cohorts',
    label: 'Patient Cohorts',
    thaiLabel: 'กลุ่มผู้ป่วย',
    routeName: '/clinical/cohorts',
    icon: Icons.groups,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'clinical',
  ),
  DashboardModuleDefinition(
    id: 'refunds',
    label: 'Refunds',
    thaiLabel: 'คืนเงิน',
    routeName: '/erp/refunds',
    icon: Icons.undo,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'sales',
  ),
  DashboardModuleDefinition(
    id: 'loyalty_rules',
    label: 'Loyalty Rules',
    thaiLabel: 'แต้มสะสม',
    routeName: '/erp/loyalty',
    icon: Icons.stars,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'sales',
  ),
  DashboardModuleDefinition(
    id: 'reports',
    label: 'Reports',
    thaiLabel: 'รายงาน',
    routeName: '/erp/reports',
    icon: Icons.assessment,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'sales',
  ),
  DashboardModuleDefinition(
    id: 'organization_settings',
    label: 'Organization Settings',
    thaiLabel: 'ตั้งค่าองค์กร',
    routeName: '/erp/settings',
    icon: Icons.business,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'admin',
  ),
  DashboardModuleDefinition(
    id: 'role_management',
    label: 'Role Management',
    thaiLabel: 'จัดการสิทธิ์ผู้ใช้',
    routeName: '/erp/settings/employee-roles',
    icon: Icons.admin_panel_settings,
    span: 1,
    heightFactor: 0.96,
    variant: DashboardModuleTileVariant.square,
    defaultGroupId: 'admin',
  ),
];

DashboardModuleDefinition? dashboardModuleById(String id) {
  for (final module in dashboardModuleDefinitions) {
    if (module.id == id) return module;
  }
  return null;
}
