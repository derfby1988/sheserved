import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/service_locator.dart';
import '../../data/models/supplier.dart';
import '../../data/models/purchase_requisition.dart';
import '../../data/models/purchase_order.dart';
import '../../data/models/purchase_order_item.dart';
import '../../data/models/goods_receipt.dart';
import '../../data/models/goods_receipt_item.dart';
import '../../data/models/back_order.dart';
import '../providers/phase_one_provider.dart';
import '../providers/phase_zero_provider.dart';
import '../providers/organization_settings_provider.dart';
import '../../data/models/dashboard_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/permission_denied_widget.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';

class ProcurementPage extends ConsumerStatefulWidget {
  final String professionId;

  const ProcurementPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<ProcurementPage> createState() => _ProcurementPageState();
}

class _ProcurementPageState extends ConsumerState<ProcurementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, bool> _expandedPos = {};
  final Map<String, bool> _expandedGRs = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    Future.microtask(() {
      ref.read(phaseZeroProvider.notifier).loadCurrentUserRoles();
      _loadAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadAll() {
    final notifier = ref.read(phaseOneProvider.notifier);
    notifier.loadSuppliers(widget.professionId);
    notifier.loadPurchaseRequisitions(widget.professionId);
    notifier.loadPurchaseOrders(widget.professionId);
    notifier.loadProducts(widget.professionId);
    notifier.loadGoodsReceipts(widget.professionId);
    notifier.loadBackOrders(widget.professionId);
    notifier.loadProcurementSettings(widget.professionId);
    ref.read(organizationSettingsProvider.notifier).loadOrganization(widget.professionId);
  }

  Future<void> _refresh() async {
    _loadAll();
    await Future.delayed(const Duration(milliseconds: 800));
  }

  int get _procurementAccessLevel {
    final zeroState = ref.watch(phaseZeroProvider);
    int maxLevel = 0;
    for (final roleMap in zeroState.userRolesAndPermissions) {
      final perms = roleMap['permissions'] as List<dynamic>?;
      if (perms == null) continue;
      for (final perm in perms) {
        if (perm is Map<String, dynamic> && perm['module_name'] == 'procurement') {
          final lvl = perm['access_level'] as int? ?? 0;
          if (lvl > maxLevel) maxLevel = lvl;
        }
      }
    }
    return maxLevel;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);
    final zeroState = ref.watch(phaseZeroProvider);

    if (zeroState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final accessLevel = _procurementAccessLevel;
    if (accessLevel == 0) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('จัดซื้อจัดจ้าง / Procurement'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: PermissionDeniedWidget(
          moduleName: 'procurement',
          moduleLabel: 'จัดซื้อจัดจ้าง',
          onRequestPermission: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('กรุณาติดต่อผู้ดูแลระบบเพื่อขอสิทธิ์')),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดซื้อจัดจ้าง / Procurement'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'ตั้งค่าระบบจัดซื้อ',
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/erp/procurement-settings',
                arguments: {'professionId': widget.professionId},
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'ผู้จัดจำหน่าย'),
            Tab(text: 'ใบขอซื้อ (PR)'),
            Tab(text: 'ใบสั่งซื้อ (PO)'),
            Tab(text: 'รับของ (GR)'),
            Tab(text: 'ค้างส่ง (Back Order)'),
          ],
        ),
      ),
      body: state.isLoading &&
              state.suppliers.isEmpty &&
              state.purchaseRequisitions.isEmpty &&
              state.purchaseOrders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _SuppliersTab(
                  suppliers: state.suppliers,
                  onRefresh: _refresh,
                  onCreate: _showCreateSupplierDialog,
                ),
                _RequisitionsTab(
                  requisitions: state.purchaseRequisitions,
                  onRefresh: _refresh,
                  onApprove: _approvePr,
                  onReject: _rejectPr,
                  onConvertToPo: (pr) => _showCreatePoDialog(sourcePr: pr),
                  onManageItems: _showPrItemsDialog,
                  accessLevel: accessLevel,
                ),
                _OrdersTab(
                  orders: state.purchaseOrders,
                  onRefresh: _refresh,
                  expandedPos: _expandedPos,
                  onToggleExpand: (poId) async {
                    setState(() {
                      _expandedPos[poId] = !(_expandedPos[poId] ?? false);
                    });
                    if (_expandedPos[poId] == true) {
                      await ref.read(phaseOneProvider.notifier).loadPurchaseOrderItems(poId);
                    }
                  },
                  selectedOrderItems: state.selectedPurchaseOrderItems,
                  onSendToSupplier: _sendPoToSupplier,
                  onReceiveGoods: _showCreateGrDialog,
                  accessLevel: accessLevel,
                ),
                _GoodsReceiptsTab(
                  goodsReceipts: state.goodsReceipts,
                  onRefresh: _refresh,
                  expandedGRs: _expandedGRs,
                  onToggleExpand: (grId) async {
                    setState(() {
                      _expandedGRs[grId] = !(_expandedGRs[grId] ?? false);
                    });
                    if (_expandedGRs[grId] == true) {
                      await ref.read(phaseOneProvider.notifier).loadGoodsReceiptItems(grId);
                    }
                  },
                  selectedGRItems: state.selectedGoodsReceiptItems,
                ),
                _BackOrdersTab(
                  backOrders: state.backOrders,
                  onRefresh: _refresh,
                ),
              ],
            ),
      floatingActionButton: accessLevel < 2
          ? null
          : AnimatedBuilder(
              animation: _tabController,
              builder: (context, child) {
                final index = _tabController.index;
                if (index == 0) {
                  return FloatingActionButton.extended(
                    onPressed: () => _showCreateSupplierDialog(),
                    icon: const Icon(Icons.add_business),
                    label: const Text('เพิ่มผู้จัดจำหน่าย'),
                  );
                }
                if (index == 1) {
                  return FloatingActionButton.extended(
                    onPressed: () => _showCreatePrDialog(),
                    icon: const Icon(Icons.note_add),
                    label: const Text('สร้างใบขอซื้อ (PR)'),
                  );
                }
                if (index == 2) {
                  return FloatingActionButton.extended(
                    onPressed: () => _showCreatePoDialog(),
                    icon: const Icon(Icons.shopping_cart),
                    label: const Text('สร้างใบสั่งซื้อ (PO)'),
                  );
                }
                if (index == 3) {
                  return FloatingActionButton.extended(
                    onPressed: () => _showCreateGrDialog(),
                    icon: const Icon(Icons.inventory_2),
                    label: const Text('รับของเข้า (GR)'),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
    );
  }

  // ========================
  // Goods Receipt Logic
  // ========================

  void _showCreateGrDialog({String? poId}) {
    final state = ref.read(phaseOneProvider);
    final receivablePOs = state.purchaseOrders
        .where((po) => po.status == 'sent' || po.status == 'partially_received')
        .toList();

    if (receivablePOs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีใบสั่งซื้อที่รอรับของ (ต้องส่งใบสั่งซื้อให้คู่ค้าก่อน)')),
      );
      return;
    }

    String? selectedPOId = poId ?? receivablePOs.first.id;
    final deliveryNoteController = TextEditingController();
    final notesController = TextEditingController();
    List<Map<String, dynamic>> grItems = [];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('รับของเข้า / Goods Receipt'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedPOId,
                        decoration: const InputDecoration(
                          labelText: 'เลือกใบสั่งซื้อ (PO)',
                          border: OutlineInputBorder(),
                        ),
                        items: receivablePOs.map((po) {
                          return DropdownMenuItem(
                            value: po.id,
                            child: Text('${po.poNumber} - ${po.supplierName ?? ''} (${po.statusLabel})'),
                          );
                        }).toList(),
                        onChanged: (val) async {
                          selectedPOId = val;
                          grItems = [];
                          if (val != null) {
                            await ref.read(phaseOneProvider.notifier).loadPurchaseOrderItems(val);
                            final poItems = ref.read(phaseOneProvider).selectedPurchaseOrderItems;
                            for (final item in poItems) {
                              final remaining = item.quantityOrdered - item.quantityReceived;
                              if (remaining > 0) {
                                grItems.add({
                                  'purchase_order_item_id': item.id,
                                  'product_name': item.productName ?? 'ไม่ระบุ',
                                  'quantity_ordered': item.quantityOrdered,
                                  'quantity_received': item.quantityReceived,
                                  'remaining': remaining,
                                  'quantity_accepted': remaining,
                                  'quantity_rejected': 0,
                                  'lot_number': '',
                                  'expiry_date': '',
                                  'unit_cost': item.unitPrice,
                                });
                              }
                            }
                          }
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: deliveryNoteController,
                        decoration: const InputDecoration(
                          labelText: 'เลขที่ใบส่งของของ Supplier (ถ้ามี)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (grItems.isNotEmpty) ...[
                        const Text('รายการรับของ:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...grItems.asMap().entries.map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${item['product_name']} (สั่ง: ${item['quantity_ordered']}, รับแล้ว: ${item['quantity_received']})',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: item['quantity_accepted'].toString(),
                                          decoration: const InputDecoration(
                                            labelText: 'จำนวนรับ',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (val) {
                                            grItems[i]['quantity_accepted'] = int.tryParse(val) ?? 0;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: item['quantity_rejected'].toString(),
                                          decoration: const InputDecoration(
                                            labelText: 'ตัดทิ้ง',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (val) {
                                            grItems[i]['quantity_rejected'] = int.tryParse(val) ?? 0;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: item['lot_number'] as String? ?? '',
                                          decoration: const InputDecoration(
                                            labelText: 'Lot/Batch',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (val) {
                                            grItems[i]['lot_number'] = val;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ThaiBuddhistDatePickerField(
                                          value: (item['expiry_date'] as String?) != null
                                              ? DateTime.tryParse(item['expiry_date'] as String)
                                              : null,
                                          label: 'วันหมดอายุ',
                                          hint: 'เลือกวันหมดอายุ',
                                          onDateSelected: (date) {
                                            grItems[i]['expiry_date'] = date.toIso8601String().split('T')[0];
                                            (context as Element).markNeedsBuild();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'หมายเหตุ',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('บันทึกรับของ'),
                  onPressed: () async {
                    if (selectedPOId == null || grItems.isEmpty) return;
                    final user = ServiceLocator.instance.currentUser;
                    if (user == null) return;

                    final itemsJson = grItems.map((item) {
                      return {
                        'purchase_order_item_id': item['purchase_order_item_id'],
                        'quantity_accepted': item['quantity_accepted'],
                        'quantity_rejected': item['quantity_rejected'],
                        'lot_number': item['lot_number'] ?? '',
                        'expiry_date': item['expiry_date'] ?? '',
                        'unit_cost': item['unit_cost'],
                      };
                    }).toList();

                    Navigator.of(dialogContext).pop();

                    final result = await ref.read(phaseOneProvider.notifier).createGoodsReceipt(
                      professionId: widget.professionId,
                      purchaseOrderId: selectedPOId!,
                      receivedBy: user.id,
                      supplierDeliveryNote: deliveryNoteController.text.isEmpty ? null : deliveryNoteController.text,
                      items: itemsJson,
                      notes: notesController.text.isEmpty ? null : notesController.text,
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result != null
                              ? 'รับของสำเร็จ: ${result['gr_number']}'
                              : 'รับของล้มเหลว'),
                        ),
                      );
                    }
                    if (result != null) _refresh();
                  },
                ),
              ],
            );
          },
        );
      },
    );

    // Pre-load PO items if poId was passed
    if (poId != null) {
      Future.microtask(() async {
        await ref.read(phaseOneProvider.notifier).loadPurchaseOrderItems(poId);
        final poItems = ref.read(phaseOneProvider).selectedPurchaseOrderItems;
        for (final item in poItems) {
          final remaining = item.quantityOrdered - item.quantityReceived;
          if (remaining > 0) {
            grItems.add({
              'purchase_order_item_id': item.id,
              'product_name': item.productName ?? 'ไม่ระบุ',
              'quantity_ordered': item.quantityOrdered,
              'quantity_received': item.quantityReceived,
              'remaining': remaining,
              'quantity_accepted': remaining,
              'quantity_rejected': 0,
              'lot_number': '',
              'expiry_date': '',
              'unit_cost': item.unitPrice,
            });
          }
        }
      });
    }
  }

  // ========================
  // PR & PO Logic Actions
  // ========================

  Future<void> _approvePr(String prId) async {
    final user = ServiceLocator.instance.currentUser;
    if (user == null) return;
    final success = await ref.read(phaseOneProvider.notifier).approvePurchaseRequisition(prId, user.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'อนุมัติใบขอซื้อสำเร็จ' : 'อนุมัติใบขอซื้อล้มเหลว')),
      );
    }
    if (success) _refresh();
  }

  Future<void> _rejectPr(String prId) async {
    final user = ServiceLocator.instance.currentUser;
    if (user == null) return;
    final success = await ref.read(phaseOneProvider.notifier).rejectPurchaseRequisition(prId, user.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'ปฏิเสธใบขอซื้อสำเร็จ' : 'ปฏิเสธใบขอซื้อล้มเหลว')),
      );
    }
    if (success) _refresh();
  }

  Future<void> _sendPoToSupplier(String poId) async {
    final success = await ref.read(phaseOneProvider.notifier).sendPurchaseOrderToSupplier(poId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'ส่งใบสั่งซื้อสำเร็จ' : 'ส่งใบสั่งซื้อล้มเหลว')),
      );
    }
    if (success) _refresh();
  }

  // ========================
  // Form Dialogs
  // ========================

  void _showPrItemsDialog(PurchaseRequisition pr) {
    ref.read(phaseOneProvider.notifier).loadPurchaseRequisitionItems(pr.id);

    final products = ref.read(phaseOneProvider).products;
    String? selectedProductId;
    final qtyController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final prState = ref.watch(phaseOneProvider);
          final items = prState.selectedPRItems;

          return AlertDialog(
            title: Text('รายการสินค้า: ${pr.prNumber}'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('ยังไม่มีรายการสินค้า'),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.3,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            dense: true,
                            title: Text(item.itemName),
                            subtitle: Text(
                              'จำนวน: ${item.quantityRequested}'
                              '${item.estimatedUnitPrice != null ? ' × ฿${item.estimatedUnitPrice!.toStringAsFixed(2)}' : ''}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () async {
                                final success = await ref
                                    .read(phaseOneProvider.notifier)
                                    .deletePurchaseRequisitionItem(item.id, pr.id);
                                if (success && context.mounted) {
                                  setStateDialog(() {});
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const Divider(),
                  DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(labelText: 'เลือกสินค้า'),
                    value: selectedProductId,
                    items: products
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            ))
                        .toList(),
                    onChanged: (v) => setStateDialog(() => selectedProductId = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyController,
                          decoration: const InputDecoration(
                            labelText: 'จำนวน',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: priceController,
                          decoration: const InputDecoration(
                            labelText: 'ราคา/หน่วย',
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ปิด'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedProductId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('กรุณาเลือกสินค้า')),
                    );
                    return;
                  }
                  final qty = int.tryParse(qtyController.text);
                  if (qty == null || qty <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('กรุณาระบุจำนวนที่ถูกต้อง')),
                    );
                    return;
                  }
                  final price = double.tryParse(priceController.text);
                  final productName = products
                      .firstWhere((p) => p.id == selectedProductId)
                      .name;

                  final success = await ref
                      .read(phaseOneProvider.notifier)
                      .addPurchaseRequisitionItem(
                        professionId: widget.professionId,
                        requisitionId: pr.id,
                        productId: selectedProductId!,
                        itemName: productName,
                        quantityRequested: qty,
                        estimatedUnitPrice: price,
                      );

                  if (success && context.mounted) {
                    qtyController.clear();
                    priceController.clear();
                    setStateDialog(() => selectedProductId = null);
                  }
                },
                child: const Text('เพิ่ม'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateSupplierDialog() {
    final nameController = TextEditingController();
    final contactController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มผู้จัดจำหน่าย'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อบริษัทผู้จัดจำหน่าย *')),
            TextField(controller: contactController, decoration: const InputDecoration(labelText: 'ชื่อผู้ติดต่อ')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'โทรศัพท์')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาระบุชื่อบริษัท')));
                return;
              }
              final success = await ref.read(phaseOneProvider.notifier).createSupplier({
                'profession_id': widget.professionId,
                'supplier_name': nameController.text.trim(),
                'contact_name': contactController.text.trim().isEmpty ? null : contactController.text.trim(),
                'phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
              });
              if (success && context.mounted) {
                Navigator.pop(context);
                _loadAll();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('เพิ่มผู้จัดจำหน่ายสำเร็จ')),
                );
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _showCreatePrDialog() {
    final orgState = ref.read(organizationSettingsProvider);
    final branches = orgState.settings?.branches ?? [];
    String? selectedBranchId;
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('สร้างใบขอซื้อ (PR)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (branches.isNotEmpty)
                DropdownButtonFormField<String?>(
                  decoration: const InputDecoration(labelText: 'สาขา'),
                  initialValue: selectedBranchId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('สำนักงานใหญ่ (HQ)')),
                    ...branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.displayName))),
                  ],
                  onChanged: (v) => setStateDialog(() => selectedBranchId = v),
                ),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'ยอดเงินประมาณการ (฿)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'หมายเหตุ / เหตุผลการซื้อ'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาระบุยอดเงินที่ถูกต้อง')));
                  return;
                }
                final user = ServiceLocator.instance.currentUser;
                if (user == null) return;
                
                final success = await ref.read(phaseOneProvider.notifier).createPurchaseRequisition(
                  professionId: widget.professionId,
                  requesterId: user.id,
                  branchId: selectedBranchId,
                  totalAmount: amount,
                  notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                );
                if (success && context.mounted) {
                  Navigator.pop(context);
                  _loadAll();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างใบขอซื้อสำเร็จ')));
                }
              },
              child: const Text('ส่งขออนุมัติ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatePoDialog({PurchaseRequisition? sourcePr}) {
    final state = ref.read(phaseOneProvider);
    final orgState = ref.read(organizationSettingsProvider);
    final branches = orgState.settings?.branches ?? [];
    final suppliers = state.suppliers;
    final products = state.products;

    String? selectedSupplierId;
    String? selectedBranchId = sourcePr?.branchId;
    final notesController = TextEditingController(text: sourcePr != null ? 'สร้างจากใบขอซื้อ ${sourcePr.prNumber}' : '');
    final deliveryDateController = TextEditingController();
    DateTime? selectedDeliveryDate;

    // PO Items list state
    final selectedItems = <Map<String, dynamic>>[];
    
    // Add product state inside dialog
    String? currentProductId;
    final qtyController = TextEditingController();
    final priceController = TextEditingController();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, anim1, anim2) => StatefulBuilder(
        builder: (context, setStateDialog) {
          double totalAmount = 0.0;
          for (final item in selectedItems) {
            totalAmount += (item['quantity_ordered'] as int) * (item['unit_price'] as double);
          }
          double taxAmount = totalAmount * 0.07;
          double grandTotal = totalAmount + taxAmount;

          return Scaffold(
            appBar: AppBar(
              title: Text(sourcePr != null ? 'สร้างใบสั่งซื้อจาก PR (${sourcePr.prNumber})' : 'สร้างใบสั่งซื้อ (PO)'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                TextButton(
                  onPressed: selectedSupplierId == null || selectedItems.isEmpty
                      ? null
                      : () async {
                          final success = await ref.read(phaseOneProvider.notifier).createPurchaseOrder(
                                professionId: widget.professionId,
                                supplierId: selectedSupplierId!,
                                branchId: selectedBranchId,
                                prId: sourcePr?.id,
                                totalAmount: totalAmount,
                                taxAmount: taxAmount,
                                grandTotal: grandTotal,
                                notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                expectedDeliveryDate: selectedDeliveryDate,
                                items: selectedItems,
                              );
                          if (success && context.mounted) {
                            Navigator.pop(context);
                            _loadAll();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างใบสั่งซื้อ (แบบร่าง) สำเร็จ')));
                          }
                        },
                  child: const Text('บันทึก', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('ข้อมูลทั่วไป', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                GlassCard(
                  section: GlassSection.card,
                  borderRadius: 12,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'ผู้จัดจำหน่าย *'),
                        items: suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.supplierName))).toList(),
                        onChanged: (v) => setStateDialog(() => selectedSupplierId = v),
                      ),
                      const SizedBox(height: 10),
                      if (branches.isNotEmpty)
                        DropdownButtonFormField<String?>(
                          decoration: const InputDecoration(labelText: 'ส่งสาขา'),
                          initialValue: selectedBranchId,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('สำนักงานใหญ่ (HQ)')),
                            ...branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.displayName))),
                          ],
                          onChanged: (v) => setStateDialog(() => selectedBranchId = v),
                        ),
                      const SizedBox(height: 10),
                      ThaiBuddhistDatePickerField(
                        value: selectedDeliveryDate,
                        label: 'กำหนดส่งมอบสินค้า',
                        hint: 'เลือกวันที่ส่งมอบ',
                        onDateSelected: (date) {
                          selectedDeliveryDate = date;
                          deliveryDateController.text = date.toIso8601String().split('T')[0];
                          (context as Element).markNeedsBuild();
                        },
                      ),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'หมายเหตุ'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('เลือกสินค้าลงใบสั่งซื้อ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                GlassCard(
                  section: GlassSection.card,
                  borderRadius: 12,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'สินค้า'),
                        initialValue: currentProductId,
                        items: products.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.name} (฿${p.costPrice.toStringAsFixed(2)})'))).toList(),
                        onChanged: (v) {
                          setStateDialog(() {
                            currentProductId = v;
                            if (v != null) {
                              final p = products.firstWhere((p) => p.id == v);
                              priceController.text = p.costPrice.toString();
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: qtyController,
                              decoration: const InputDecoration(labelText: 'จำนวนสั่งซื้อ'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: priceController,
                              decoration: const InputDecoration(labelText: 'ราคาต่อหน่วย (฿)'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: currentProductId == null ? null : () {
                            final qty = int.tryParse(qtyController.text);
                            final price = double.tryParse(priceController.text);
                            if (qty == null || qty <= 0 || price == null || price < 0) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกข้อมูลจำนวนและราคาที่ถูกต้อง')));
                              return;
                            }
                            final p = products.firstWhere((p) => p.id == currentProductId);
                            setStateDialog(() {
                              selectedItems.add({
                                'product_id': currentProductId!,
                                'quantity_ordered': qty,
                                'unit_price': price,
                                'total_price': qty * price,
                                'product_name': p.name,
                              });
                              qtyController.clear();
                              priceController.clear();
                              currentProductId = null;
                            });
                          },
                          child: const Text('เพิ่มรายการสินค้า'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (selectedItems.isNotEmpty) ...[
                  const Text('รายการสินค้าสั่งซื้อ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ...selectedItems.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        section: GlassSection.card,
                        borderRadius: 12,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: ListTile(
                          dense: true,
                          title: Text(item['product_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('จำนวน: ${item['quantity_ordered']} | ราคาหน่วยละ: ฿${(item['unit_price'] as double).toStringAsFixed(2)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('฿${(item['total_price'] as double).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => setStateDialog(() => selectedItems.removeAt(idx)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  GlassCard(
                    section: GlassSection.card,
                    borderRadius: 12,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('ยอดรวมสินค้า:'),
                            Text('฿${totalAmount.toStringAsFixed(2)}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('ภาษีมูลค่าเพิ่ม (7%):'),
                            Text('฿${taxAmount.toStringAsFixed(2)}'),
                          ],
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('ยอดเงินสุทธิ (Grand Total):', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('฿${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ========================
// 1. Suppliers Tab
// ========================

class _SuppliersTab extends StatelessWidget {
  final List<Supplier> suppliers;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;

  const _SuppliersTab({
    required this.suppliers,
    required this.onRefresh,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    if (suppliers.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ไม่มีข้อมูลผู้จัดจำหน่าย'),
              ),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: suppliers.length,
        itemBuilder: (context, index) {
          final supplier = suppliers[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              section: GlassSection.card,
              borderRadius: 16,
              padding: const EdgeInsets.all(14),
              child: ListTile(
                title: Text(supplier.supplierName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (supplier.contactName != null) Text('ผู้ติดต่อ: ${supplier.contactName}'),
                    if (supplier.phone != null) Text('โทร: ${supplier.phone}'),
                    Text('เครดิต: ${supplier.paymentTerms} | ระยะเวลานำส่ง: ${supplier.leadTimeDays} วัน'),
                  ],
                ),
                trailing: supplier.isActive
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.cancel, color: Colors.grey),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ========================
// 2. PR Tab
// ========================

class _RequisitionsTab extends StatelessWidget {
  final List<PurchaseRequisition> requisitions;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onApprove;
  final Future<void> Function(String) onReject;
  final Function(PurchaseRequisition) onConvertToPo;
  final Function(PurchaseRequisition) onManageItems;
  final int accessLevel;

  const _RequisitionsTab({
    required this.requisitions,
    required this.onRefresh,
    required this.onApprove,
    required this.onReject,
    required this.onConvertToPo,
    required this.onManageItems,
    required this.accessLevel,
  });

  @override
  Widget build(BuildContext context) {
    if (requisitions.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ไม่มีข้อมูลใบขอซื้อ (PR)'),
              ),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: requisitions.length,
        itemBuilder: (context, index) {
          final pr = requisitions[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              section: GlassSection.card,
              borderRadius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('เลขที่: ${pr.prNumber}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ยอดเงิน: ฿${pr.totalAmount.toStringAsFixed(2)}'),
                        Text('ผู้ขอซื้อ: ${pr.requesterName ?? 'ไม่ระบุ'}'),
                        if (pr.branchName != null) Text('สาขา: ${pr.branchName}'),
                        if (pr.notes != null) Text('หมายเหตุ: ${pr.notes}'),
                        if (pr.approvedByName != null)
                          Text('${pr.isApproved ? 'อนุมัติโดย' : 'จัดการโดย'}: ${pr.approvedByName}'),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(pr.statusLabel, style: const TextStyle(fontSize: 11)),
                      backgroundColor: pr.statusColor.withValues(alpha: 0.15),
                      side: BorderSide(color: pr.statusColor.withValues(alpha: 0.5)),
                    ),
                  ),
                  if (pr.isPendingApproval && accessLevel >= 3) ...[
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => onReject(pr.id),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('ปฏิเสธ'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => onApprove(pr.id),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          child: const Text('อนุมัติ'),
                        ),
                      ],
                    ),
                  ],
                  if (pr.isApproved && accessLevel >= 2) ...[
                    const Divider(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => onConvertToPo(pr),
                        child: const Text('แปลงเป็นใบสั่งซื้อ (Convert to PO)'),
                      ),
                    ),
                  ],
                  if (pr.status != 'converted' && accessLevel >= 2) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => onManageItems(pr),
                        icon: const Icon(Icons.list_alt),
                        label: const Text('จัดการรายการสินค้า'),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ========================
// 3. PO Tab
// ========================

class _OrdersTab extends StatelessWidget {
  final List<PurchaseOrder> orders;
  final Future<void> Function() onRefresh;
  final Map<String, bool> expandedPos;
  final Function(String) onToggleExpand;
  final List<PurchaseOrderItem> selectedOrderItems;
  final Future<void> Function(String) onSendToSupplier;
  final void Function({String? poId}) onReceiveGoods;
  final int accessLevel;

  const _OrdersTab({
    required this.orders,
    required this.onRefresh,
    required this.expandedPos,
    required this.onToggleExpand,
    required this.selectedOrderItems,
    required this.onSendToSupplier,
    required this.onReceiveGoods,
    required this.accessLevel,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ไม่มีข้อมูลใบสั่งซื้อ (PO)'),
              ),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final po = orders[index];
          final isExpanded = expandedPos[po.id] ?? false;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              section: GlassSection.card,
              borderRadius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => onToggleExpand(po.id),
                    title: Text('เลขที่: ${po.poNumber}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ผู้จัดจำหน่าย: ${po.supplierName ?? 'ไม่ระบุ'}'),
                        Text('ยอดเงินสุทธิ: ฿${po.grandTotal.toStringAsFixed(2)} (ภาษี ฿${po.taxAmount.toStringAsFixed(2)})'),
                        if (po.prNumber != null) Text('อ้างอิง PR: ${po.prNumber}'),
                        if (po.branchName != null) Text('สาขา: ${po.branchName}'),
                        if (po.notes != null) Text('หมายเหตุ: ${po.notes}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(po.statusLabel, style: const TextStyle(fontSize: 11)),
                          backgroundColor: po.statusColor.withValues(alpha: 0.15),
                          side: BorderSide(color: po.statusColor.withValues(alpha: 0.5)),
                        ),
                        Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                      ],
                    ),
                  ),
                  if (isExpanded) ...[
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('รายการสินค้า:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    if (selectedOrderItems.isEmpty || selectedOrderItems.first.poId != po.id)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: selectedOrderItems.length,
                        itemBuilder: (context, i) {
                          final item = selectedOrderItems[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text('${item.productName ?? 'ไม่ระบุ'} x${item.quantityOrdered} ${item.productUnitOfMeasure ?? ''}',
                                      style: const TextStyle(fontSize: 12)),
                                ),
                                Text('฿${item.totalPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                  if (po.isDraft && accessLevel >= 2) ...[
                    const Divider(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send),
                        onPressed: () => onSendToSupplier(po.id),
                        label: const Text('ส่งใบสั่งซื้อให้คู่ค้า (Send to Supplier)'),
                      ),
                    ),
                  ],
                  if ((po.isSent || po.isPartiallyReceived) && accessLevel >= 2) ...[
                    const Divider(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.inventory_2),
                        onPressed: () => onReceiveGoods(poId: po.id),
                        label: const Text('รับของเข้า (Goods Receipt)'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ========================
// 4. Goods Receipts Tab
// ========================

class _GoodsReceiptsTab extends StatelessWidget {
  final List<GoodsReceipt> goodsReceipts;
  final Future<void> Function() onRefresh;
  final Map<String, bool> expandedGRs;
  final Function(String) onToggleExpand;
  final List<GoodsReceiptItem> selectedGRItems;

  const _GoodsReceiptsTab({
    required this.goodsReceipts,
    required this.onRefresh,
    required this.expandedGRs,
    required this.onToggleExpand,
    required this.selectedGRItems,
  });

  @override
  Widget build(BuildContext context) {
    if (goodsReceipts.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ยังไม่มีใบรับของ\nกดปุ่ม + เพื่อสร้างใบรับของใหม่',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: goodsReceipts.length,
        itemBuilder: (context, index) {
          final gr = goodsReceipts[index];
          final isExpanded = expandedGRs[gr.id] ?? false;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => onToggleExpand(gr.id),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(gr.grNumber,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text('PO: ${gr.poNumber ?? '-'} | ${gr.receivedByName ?? '-'}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              Text('วันที่รับ: ${gr.receiptDate.toLocal().toString().split('.')[0]}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Chip(
                          label: Text(gr.statusLabel, style: const TextStyle(fontSize: 11)),
                          backgroundColor: gr.statusColor.withValues(alpha: 0.15),
                          side: BorderSide(color: gr.statusColor.withValues(alpha: 0.5)),
                        ),
                        Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                      ],
                    ),
                  ),
                  if (isExpanded) ...[
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('รายการรับของ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    if (selectedGRItems.isEmpty || selectedGRItems.first.goodsReceiptId != gr.id)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: selectedGRItems.length,
                        itemBuilder: (context, i) {
                          final item = selectedGRItems[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.productName ?? 'ไม่ระบุ',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                      Text('รับ: ${item.quantityAccepted} | ตัดทิ้ง: ${item.quantityRejected}',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      if (item.lotNumber != null && item.lotNumber!.isNotEmpty)
                                        Text('Lot: ${item.lotNumber}${item.expiryDate != null ? ' | หมดอายุ: ${ThaiDateUtils.formatShortDateBE(item.expiryDate!)}' : ''}',
                                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                if (item.unitCost != null)
                                  Text('฿${item.unitCost!.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ========================
// 5. Back Orders Tab
// ========================

class _BackOrdersTab extends StatelessWidget {
  final List<BackOrder> backOrders;
  final Future<void> Function() onRefresh;

  const _BackOrdersTab({
    required this.backOrders,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (backOrders.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ไม่มีรายการค้างส่ง\nรายการจะปรากฏเมื่อรับของบางส่วน',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            ),
          ],
        ),
      );
    }

    final openCount = backOrders.where((bo) => bo.isOpen || bo.isPartiallyFulfilled).length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Column(
        children: [
          if (openCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.withValues(alpha: 0.1),
              child: Text('มีรายการค้างส่ง $openCount รายการ',
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: backOrders.length,
              itemBuilder: (context, index) {
                final bo = backOrders[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('PO: ${bo.poNumber ?? '-'}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(bo.productName ?? 'ไม่ระบุ',
                                      style: const TextStyle(fontSize: 12)),
                                  Text('Supplier: ${bo.supplierName ?? '-'}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Chip(
                              label: Text(bo.statusLabel, style: const TextStyle(fontSize: 11)),
                              backgroundColor: bo.statusColor.withValues(alpha: 0.15),
                              side: BorderSide(color: bo.statusColor.withValues(alpha: 0.5)),
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('ค้างส่ง: ${bo.quantityBackOrdered}',
                                style: const TextStyle(fontSize: 12)),
                            Text('รับแล้ว: ${bo.quantityFulfilled}',
                                style: const TextStyle(fontSize: 12)),
                            Text('คงเหลือ: ${bo.remainingQuantity}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                          ],
                        ),
                        if (bo.expectedDeliveryDate != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('กำหนดส่งครั้งหน้า: ${ThaiDateUtils.formatShortDateBE(bo.expectedDeliveryDate!)}',
                                style: const TextStyle(fontSize: 11, color: Colors.blue)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
