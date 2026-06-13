import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/customer.dart';
import '../../data/models/inventory_lot.dart';
import '../../data/models/product.dart';
import '../../data/models/supplier.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/custom_medication.dart';
import '../../data/models/stocktake_configuration.dart';
import '../../data/models/stocktake_session.dart';
import '../../data/models/stock_adjustment.dart';
import '../../data/models/inventory_transfer.dart';
import '../../data/models/inventory_alert.dart';
import '../../data/models/purchase_requisition.dart';
import '../../data/models/purchase_order.dart';
import '../../data/models/purchase_order_item.dart';
import '../../data/repositories/phase_one_repository.dart';

// ========================
// Repository Provider
// ========================

final phaseOneRepositoryProvider = Provider<PhaseOneRepository>((ref) {
  return PhaseOneRepository(Supabase.instance.client);
});

// ========================
// State
// ========================

class PhaseOneState {
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  final List<Product> products;
  final List<Customer> customers;
  final List<Supplier> suppliers;
  final List<InventoryLot> inventoryLots;
  final List<Map<String, dynamic>> coupons;
  final List<PurchaseOrder> purchaseOrders;
  final List<PurchaseRequisition> purchaseRequisitions;

  // Inventory System
  final List<InventoryItem> inventoryItems;
  final List<CustomMedication> customMedications;
  final List<StocktakeConfiguration> stocktakeConfigs;
  final List<StocktakeSession> stocktakeSessions;
  final List<StockAdjustment> stockAdjustments;
  final List<InventoryTransfer> inventoryTransfers;
  final List<InventoryAlert> inventoryAlerts;
  final List<Map<String, dynamic>> stockMovements;

  // Selected
  final Product? selectedProduct;
  final List<Map<String, dynamic>> selectedProductStockSummary;
  final List<InventoryLot> selectedProductLots;
  final List<PurchaseOrderItem> selectedPurchaseOrderItems;

  PhaseOneState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.products = const [],
    this.customers = const [],
    this.suppliers = const [],
    this.inventoryLots = const [],
    this.coupons = const [],
    this.purchaseOrders = const [],
    this.purchaseRequisitions = const [],
    this.inventoryItems = const [],
    this.customMedications = const [],
    this.stocktakeConfigs = const [],
    this.stocktakeSessions = const [],
    this.stockAdjustments = const [],
    this.inventoryTransfers = const [],
    this.inventoryAlerts = const [],
    this.stockMovements = const [],
    this.selectedProduct,
    this.selectedProductStockSummary = const [],
    this.selectedProductLots = const [],
    this.selectedPurchaseOrderItems = const [],
  });

  PhaseOneState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    List<Product>? products,
    List<Customer>? customers,
    List<Supplier>? suppliers,
    List<InventoryLot>? inventoryLots,
    List<Map<String, dynamic>>? coupons,
    List<PurchaseOrder>? purchaseOrders,
    List<PurchaseRequisition>? purchaseRequisitions,
    List<InventoryItem>? inventoryItems,
    List<CustomMedication>? customMedications,
    List<StocktakeConfiguration>? stocktakeConfigs,
    List<StocktakeSession>? stocktakeSessions,
    List<StockAdjustment>? stockAdjustments,
    List<InventoryTransfer>? inventoryTransfers,
    List<InventoryAlert>? inventoryAlerts,
    List<Map<String, dynamic>>? stockMovements,
    Product? selectedProduct,
    bool clearSelectedProduct = false,
    List<Map<String, dynamic>>? selectedProductStockSummary,
    List<InventoryLot>? selectedProductLots,
    List<PurchaseOrderItem>? selectedPurchaseOrderItems,
  }) {
    final shouldClearError = clearError ||
        ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return PhaseOneState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      products: products ?? this.products,
      customers: customers ?? this.customers,
      suppliers: suppliers ?? this.suppliers,
      inventoryLots: inventoryLots ?? this.inventoryLots,
      coupons: coupons ?? this.coupons,
      purchaseOrders: purchaseOrders ?? this.purchaseOrders,
      purchaseRequisitions: purchaseRequisitions ?? this.purchaseRequisitions,
      inventoryItems: inventoryItems ?? this.inventoryItems,
      customMedications: customMedications ?? this.customMedications,
      stocktakeConfigs: stocktakeConfigs ?? this.stocktakeConfigs,
      stocktakeSessions: stocktakeSessions ?? this.stocktakeSessions,
      stockAdjustments: stockAdjustments ?? this.stockAdjustments,
      inventoryTransfers: inventoryTransfers ?? this.inventoryTransfers,
      inventoryAlerts: inventoryAlerts ?? this.inventoryAlerts,
      stockMovements: stockMovements ?? this.stockMovements,
      selectedProduct: clearSelectedProduct ? null : (selectedProduct ?? this.selectedProduct),
      selectedProductStockSummary: selectedProductStockSummary ?? this.selectedProductStockSummary,
      selectedProductLots: selectedProductLots ?? this.selectedProductLots,
      selectedPurchaseOrderItems: selectedPurchaseOrderItems ?? this.selectedPurchaseOrderItems,
    );
  }

  List<Product> get lowStockProducts {
    return products.where((p) => p.isStockable && p.reorderPoint > 0).toList();
    // หมายเหตุ: logic จริงต้องเทียบกับ available stock
  }

  List<InventoryLot> get expiringLots {
    return inventoryLots.where((l) => l.isNearExpiry && l.status == 'active').toList();
  }

  List<InventoryLot> get expiredLots {
    return inventoryLots.where((l) => l.status == 'expired' || l.isExpired).toList();
  }
}

// ========================
// Notifier
// ========================

class PhaseOneNotifier extends StateNotifier<PhaseOneState> {
  final PhaseOneRepository _repository;

  PhaseOneNotifier(this._repository) : super(PhaseOneState());

  // ========================
  // PRODUCTS
  // ========================

  Future<void> loadProducts(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final products = await _repository.getProducts(professionId);
      state = state.copyWith(isLoading: false, products: products);
    } catch (e) {
      debugPrint('[Phase1] loadProducts ERROR: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลดสินค้าล้มเหลว: $e',
      );
    }
  }

  Future<bool> createProduct(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final product = await _repository.createProduct(data);
      if (product != null) {
        state = state.copyWith(isSaving: false);
        return true;
      }
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างสินค้าไม่สำเร็จ');
      return false;
    } catch (e) {
      debugPrint('[Phase1] createProduct ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างสินค้าล้มเหลว: $e');
      return false;
    }
  }

  Future<void> selectProduct(Product product, String? branchId) async {
    state = state.copyWith(isLoading: true, clearError: true, selectedProduct: product);
    try {
      final summary = await _repository.getProductStockSummary(product.id, branchId);
      final lots = await _repository.getInventoryLotsByProduct(product.id);
      state = state.copyWith(
        isLoading: false,
        selectedProductStockSummary: summary,
        selectedProductLots: lots,
      );
    } catch (e) {
      debugPrint('[Phase1] selectProduct ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดข้อมูลสต็อกล้มเหลว: $e');
    }
  }

  void clearSelectedProduct() {
    state = state.copyWith(clearSelectedProduct: true, selectedProductStockSummary: [], selectedProductLots: []);
  }

  // ========================
  // CUSTOMERS
  // ========================

  Future<void> loadCustomers(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final customers = await _repository.getCustomers(professionId);
      state = state.copyWith(isLoading: false, customers: customers);
    } catch (e) {
      debugPrint('[Phase1] loadCustomers ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดลูกค้าล้มเหลว: $e');
    }
  }

  Future<bool> createCustomer(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final customer = await _repository.createCustomer(data);
      state = state.copyWith(isSaving: false);
      return customer != null;
    } catch (e) {
      debugPrint('[Phase1] createCustomer ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างลูกค้าล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // SUPPLIERS
  // ========================

  Future<void> loadSuppliers(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final suppliers = await _repository.getSuppliers(professionId);
      state = state.copyWith(isLoading: false, suppliers: suppliers);
    } catch (e) {
      debugPrint('[Phase1] loadSuppliers ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดผู้จำหน่ายล้มเหลว: $e');
    }
  }

  Future<bool> createSupplier(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final supplier = await _repository.createSupplier(data);
      state = state.copyWith(isSaving: false);
      return supplier != null;
    } catch (e) {
      debugPrint('[Phase1] createSupplier ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างผู้จำหน่ายล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // INVENTORY
  // ========================

  Future<void> loadInventoryLots(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final lots = await _repository.getInventoryLots(professionId);
      state = state.copyWith(isLoading: false, inventoryLots: lots);
    } catch (e) {
      debugPrint('[Phase1] loadInventoryLots ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดข้อมูลคลังสินค้าล้มเหลว: $e');
    }
  }

  Future<bool> recordStockReceipt({
    required String professionId,
    String? productId,
    String? customMedicationId,
    required String? branchId,
    required String? warehouseLocationId,
    required String lotNumber,
    required int quantity,
    required double unitCost,
    String? poId,
    DateTime? expiryDate,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      // Validate: must have exactly one of productId or customMedicationId
      if ((productId == null && customMedicationId == null) ||
          (productId != null && customMedicationId != null)) {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'ต้องเลือกสินค้าหรือยาคัสตอมอย่างใดอย่างหนึ่ง',
        );
        return false;
      }

      // 1. Find or create/update inventory item
      final existingItem = await _repository.findInventoryItem(
        professionId: professionId,
        productId: productId,
        customMedicationId: customMedicationId,
        branchId: branchId,
      );

      if (existingItem == null) {
        final itemData = {
          'profession_id': professionId,
          if (productId != null) 'product_id': productId,
          if (customMedicationId != null) 'custom_medication_id': customMedicationId,
          'branch_id': branchId,
          'warehouse_location_id': warehouseLocationId,
          'quantity': quantity,
          'cost_price': unitCost,
        };
        final itemSuccess = await _repository.createInventoryItem(itemData);
        if (!itemSuccess) {
          state = state.copyWith(isSaving: false, errorMessage: 'สร้างรายการสต็อกไม่สำเร็จ');
          return false;
        }
      } else {
        final newQty = existingItem.quantity + quantity;
        final itemSuccess = await _repository.updateInventoryItem(existingItem.id, {
          'quantity': newQty,
          'cost_price': unitCost,
        });
        if (!itemSuccess) {
          state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตสต็อกไม่สำเร็จ');
          return false;
        }
      }

      // 2. Create inventory lot
      final lotData = {
        'profession_id': professionId,
        if (productId != null) 'product_id': productId,
        if (customMedicationId != null) 'custom_medication_id': customMedicationId,
        'branch_id': branchId,
        'warehouse_location_id': warehouseLocationId,
        'lot_number': lotNumber,
        'quantity_received': quantity,
        'quantity_remaining': quantity,
        'unit_cost': unitCost,
        'po_id': poId,
        'expiry_date': expiryDate?.toIso8601String(),
        'status': 'active',
      };
      final lotSuccess = await _repository.createInventoryLot(lotData);
      if (!lotSuccess) {
        state = state.copyWith(isSaving: false, errorMessage: 'สร้าง Lot ไม่สำเร็จ');
        return false;
      }

      // 3. Record stock movement
      final movementData = {
        'profession_id': professionId,
        if (productId != null) 'product_id': productId,
        if (customMedicationId != null) 'custom_medication_id': customMedicationId,
        'branch_id': branchId,
        'warehouse_location_id': warehouseLocationId,
        'movement_type': 'receipt',
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': quantity * unitCost,
        'reference_type': poId != null ? 'po' : 'manual',
        'reference_id': poId,
      };
      final moveSuccess = await _repository.recordStockMovement(movementData);
      state = state.copyWith(isSaving: false);
      return moveSuccess;
    } catch (e) {
      debugPrint('[Phase1] recordStockReceipt ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึกรับเข้าล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // STOCK MOVEMENTS
  // ========================

  Future<void> loadStockMovements(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final movements = await _repository.getStockMovementsByProfession(professionId);
      state = state.copyWith(isLoading: false, stockMovements: movements);
    } catch (e) {
      debugPrint('[Phase1] loadStockMovements ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดประวัติสต็อกล้มเหลว: $e');
    }
  }

  // ========================
  // COUPONS
  // ========================

  Future<void> loadCoupons(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final coupons = await _repository.getCoupons(professionId);
      state = state.copyWith(isLoading: false, coupons: coupons);
    } catch (e) {
      debugPrint('[Phase1] loadCoupons ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดคูปองล้มเหลว: $e');
    }
  }

  // ========================
  // PURCHASE REQUISITIONS
  // ========================

  Future<void> loadPurchaseRequisitions(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final prs = await _repository.getPurchaseRequisitions(professionId);
      state = state.copyWith(isLoading: false, purchaseRequisitions: prs);
    } catch (e) {
      debugPrint('[Phase1] loadPurchaseRequisitions ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดใบขอซื้อล้มเหลว: $e');
    }
  }

  Future<bool> createPurchaseRequisition({
    required String professionId,
    required String requesterId,
    String? branchId,
    required double totalAmount,
    String? notes,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final prNumber = 'PR-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().millisecond.toString().padLeft(3, '0')}';
      final success = await _repository.createPurchaseRequisition({
        'profession_id': professionId,
        'requester_id': requesterId,
        'branch_id': branchId,
        'pr_number': prNumber,
        'status': 'pending_approval',
        'total_amount': totalAmount,
        'notes': notes,
      });
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      debugPrint('[Phase1] createPurchaseRequisition ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างใบขอซื้อล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> approvePurchaseRequisition(String prId, String approvedBy) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updatePurchaseRequisitionStatus(
        prId,
        'approved',
        approvedBy: approvedBy,
      );
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      debugPrint('[Phase1] approvePurchaseRequisition ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อนุมัติใบขอซื้อล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> rejectPurchaseRequisition(String prId, String rejectedBy) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updatePurchaseRequisitionStatus(
        prId,
        'rejected',
        approvedBy: rejectedBy,
      );
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      debugPrint('[Phase1] rejectPurchaseRequisition ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ปฏิเสธใบขอซื้อล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // PURCHASE ORDERS
  // ========================

  Future<void> loadPurchaseOrders(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final pos = await _repository.getPurchaseOrders(professionId);
      state = state.copyWith(isLoading: false, purchaseOrders: pos);
    } catch (e) {
      debugPrint('[Phase1] loadPurchaseOrders ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดใบสั่งซื้อล้มเหลว: $e');
    }
  }

  Future<void> loadPurchaseOrderItems(String poId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repository.getPurchaseOrderItems(poId);
      state = state.copyWith(isLoading: false, selectedPurchaseOrderItems: items);
    } catch (e) {
      debugPrint('[Phase1] loadPurchaseOrderItems ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดรายการสั่งซื้อล้มเหลว: $e');
    }
  }

  Future<bool> createPurchaseOrder({
    required String professionId,
    required String supplierId,
    String? branchId,
    String? prId,
    required double totalAmount,
    required double taxAmount,
    required double grandTotal,
    String? notes,
    DateTime? expectedDeliveryDate,
    required List<Map<String, dynamic>> items,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final poNumber = 'PO-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().millisecond.toString().padLeft(3, '0')}';
      final poData = {
        'profession_id': professionId,
        'supplier_id': supplierId,
        'branch_id': branchId,
        'pr_id': prId,
        'po_number': poNumber,
        'status': 'draft',
        'total_amount': totalAmount,
        'tax_amount': taxAmount,
        'grand_total': grandTotal,
        'notes': notes,
        if (expectedDeliveryDate != null)
          'expected_delivery_date': expectedDeliveryDate.toIso8601String().split('T')[0],
      };

      final success = await _repository.createPurchaseOrder(
        poData: poData,
        itemsData: items,
      );
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      debugPrint('[Phase1] createPurchaseOrder ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างใบสั่งซื้อล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> sendPurchaseOrderToSupplier(String poId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updatePurchaseOrderStatus(poId, 'sent');
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      debugPrint('[Phase1] sendPurchaseOrderToSupplier ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ส่งใบสั่งซื้อล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // INVENTORY ITEMS
  // ========================

  Future<void> loadInventoryItems(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repository.getInventoryItems(professionId);
      state = state.copyWith(isLoading: false, inventoryItems: items);
    } catch (e) {
      debugPrint('[Phase1] loadInventoryItems ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดสต็อกล้มเหลว: $e');
    }
  }

  Future<void> loadLowStockItems(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repository.getLowStockItems(professionId);
      state = state.copyWith(isLoading: false, inventoryItems: items);
    } catch (e) {
      debugPrint('[Phase1] loadLowStockItems ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดสินค้าใกล้หมดล้มเหลว: $e');
    }
  }

  Future<Map<String, dynamic>?> deductInventoryFefo({
    required String professionId,
    required String inventoryItemId,
    required int quantity,
    String referenceType = 'sale',
    String? referenceId,
  }) async {
    try {
      return await _repository.deductInventoryFefo(
        professionId: professionId,
        inventoryItemId: inventoryItemId,
        quantity: quantity,
        referenceType: referenceType,
        referenceId: referenceId,
      );
    } catch (e) {
      debugPrint('[Phase1] deductInventoryFefo ERROR: $e');
      return null;
    }
  }

  // ========================
  // CUSTOM MEDICATIONS
  // ========================

  Future<void> loadCustomMedications(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final meds = await _repository.getCustomMedications(professionId);
      state = state.copyWith(isLoading: false, customMedications: meds);
    } catch (e) {
      debugPrint('[Phase1] loadCustomMedications ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดยาเฉพาะล้มเหลว: $e');
    }
  }

  // ========================
  // STOCKTAKE
  // ========================

  Future<void> loadStocktakeConfigurations(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final configs = await _repository.getStocktakeConfigurations(professionId);
      state = state.copyWith(isLoading: false, stocktakeConfigs: configs);
    } catch (e) {
      debugPrint('[Phase1] loadStocktakeConfigurations ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดตั้งค่าตรวจนับล้มเหลว: $e');
    }
  }

  Future<void> loadStocktakeSessions(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final sessions = await _repository.getStocktakeSessions(professionId);
      state = state.copyWith(isLoading: false, stocktakeSessions: sessions);
    } catch (e) {
      debugPrint('[Phase1] loadStocktakeSessions ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดรอบตรวจนับล้มเหลว: $e');
    }
  }

  Future<int?> completeStocktakeSession({
    required String sessionId,
    String? approvedBy,
  }) async {
    try {
      final count = await _repository.completeStocktakeSession(
        sessionId: sessionId,
        approvedBy: approvedBy,
      );
      return count;
    } catch (e) {
      debugPrint('[Phase1] completeStocktakeSession ERROR: $e');
      return null;
    }
  }

  Future<String?> createStocktakeConfiguration({
    required String professionId,
    String? branchId,
    String name = 'Stocktake',
    String frequencyType = 'MONTHLY',
    int? customIntervalDays,
    DateTime? nextStocktakeDate,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final id = await _repository.createStocktakeConfiguration(
        professionId: professionId,
        branchId: branchId,
        name: name,
        frequencyType: frequencyType,
        customIntervalDays: customIntervalDays,
        nextStocktakeDate: nextStocktakeDate,
      );
      state = state.copyWith(isSaving: false);
      return id;
    } catch (e) {
      debugPrint('[Phase1] createStocktakeConfiguration ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างตั้งค่าตรวจนับล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> updateStocktakeConfiguration({
    required String configId,
    String? name,
    String? frequencyType,
    int? customIntervalDays,
    DateTime? nextStocktakeDate,
    bool? isActive,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updateStocktakeConfiguration(
        configId: configId,
        name: name,
        frequencyType: frequencyType,
        customIntervalDays: customIntervalDays,
        nextStocktakeDate: nextStocktakeDate,
        isActive: isActive,
      );
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      debugPrint('[Phase1] updateStocktakeConfiguration ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตตั้งค่าตรวจนับล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> deleteStocktakeConfiguration(String configId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.deleteStocktakeConfiguration(configId);
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      debugPrint('[Phase1] deleteStocktakeConfiguration ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ลบตั้งค่าตรวจนับล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // STOCK ADJUSTMENTS
  // ========================

  Future<void> loadStockAdjustments(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final adjustments = await _repository.getStockAdjustments(professionId);
      state = state.copyWith(isLoading: false, stockAdjustments: adjustments);
    } catch (e) {
      debugPrint('[Phase1] loadStockAdjustments ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดการปรับสต็อกล้มเหลว: $e');
    }
  }

  // ========================
  // INVENTORY TRANSFERS
  // ========================

  Future<void> loadInventoryTransfers(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final transfers = await _repository.getInventoryTransfers(professionId);
      state = state.copyWith(isLoading: false, inventoryTransfers: transfers);
    } catch (e) {
      debugPrint('[Phase1] loadInventoryTransfers ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดการโอนย้ายล้มเหลว: $e');
    }
  }

  Future<String?> createInventoryTransfer({
    required String professionId,
    String? fromBranchId,
    String? fromWarehouseId,
    String? toBranchId,
    String? toWarehouseId,
    required List<Map<String, dynamic>> items,
    String? requestedBy,
    String? notes,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final id = await _repository.createInventoryTransfer(
        professionId: professionId,
        fromBranchId: fromBranchId,
        fromWarehouseId: fromWarehouseId,
        toBranchId: toBranchId,
        toWarehouseId: toWarehouseId,
        items: items,
        requestedBy: requestedBy,
        notes: notes,
      );
      state = state.copyWith(isSaving: false);
      return id;
    } catch (e) {
      debugPrint('[Phase1] createInventoryTransfer ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างรายการโอนย้ายล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> completeInventoryTransfer({
    required String transferId,
    String? approvedBy,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.completeInventoryTransfer(
        transferId: transferId,
        approvedBy: approvedBy,
      );
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      debugPrint('[Phase1] completeInventoryTransfer ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ยืนยันโอนย้ายล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // STOCK ADJUSTMENTS
  // ========================

  Future<String?> createStockAdjustment({
    required String professionId,
    required String inventoryItemId,
    required String adjustmentType,
    required int quantityAfter,
    String? reason,
    String? createdBy,
    String? referenceId,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final id = await _repository.createStockAdjustment(
        professionId: professionId,
        inventoryItemId: inventoryItemId,
        adjustmentType: adjustmentType,
        quantityAfter: quantityAfter,
        reason: reason,
        createdBy: createdBy,
        referenceId: referenceId,
      );
      state = state.copyWith(isSaving: false);
      return id;
    } catch (e) {
      debugPrint('[Phase1] createStockAdjustment ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างรายการปรับสต็อกล้มเหลว: $e');
      return null;
    }
  }

  // ========================
  // INVENTORY ALERTS
  // ========================

  Future<void> loadInventoryAlerts(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final alerts = await _repository.getInventoryAlerts(professionId);
      state = state.copyWith(isLoading: false, inventoryAlerts: alerts);
    } catch (e) {
      debugPrint('[Phase1] loadInventoryAlerts ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดแจ้งเตือนสต็อกล้มเหลว: $e');
    }
  }

  Future<int> checkInventoryAlerts(String professionId) async {
    try {
      return await _repository.checkInventoryAlerts(professionId);
    } catch (e) {
      debugPrint('[Phase1] checkInventoryAlerts ERROR: $e');
      return 0;
    }
  }
}

// ========================
// Provider
// ========================

final phaseOneProvider =
    StateNotifierProvider<PhaseOneNotifier, PhaseOneState>((ref) {
  final repo = ref.watch(phaseOneRepositoryProvider);
  return PhaseOneNotifier(repo);
});
