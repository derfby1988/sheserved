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
  final List<Map<String, dynamic>> purchaseOrders;

  // Inventory System
  final List<InventoryItem> inventoryItems;
  final List<CustomMedication> customMedications;
  final List<StocktakeConfiguration> stocktakeConfigs;
  final List<StocktakeSession> stocktakeSessions;
  final List<StockAdjustment> stockAdjustments;
  final List<InventoryTransfer> inventoryTransfers;
  final List<InventoryAlert> inventoryAlerts;

  // Selected
  final Product? selectedProduct;
  final List<Map<String, dynamic>> selectedProductStockSummary;
  final List<InventoryLot> selectedProductLots;

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
    this.inventoryItems = const [],
    this.customMedications = const [],
    this.stocktakeConfigs = const [],
    this.stocktakeSessions = const [],
    this.stockAdjustments = const [],
    this.inventoryTransfers = const [],
    this.inventoryAlerts = const [],
    this.selectedProduct,
    this.selectedProductStockSummary = const [],
    this.selectedProductLots = const [],
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
    List<Map<String, dynamic>>? purchaseOrders,
    List<InventoryItem>? inventoryItems,
    List<CustomMedication>? customMedications,
    List<StocktakeConfiguration>? stocktakeConfigs,
    List<StocktakeSession>? stocktakeSessions,
    List<StockAdjustment>? stockAdjustments,
    List<InventoryTransfer>? inventoryTransfers,
    List<InventoryAlert>? inventoryAlerts,
    Product? selectedProduct,
    bool clearSelectedProduct = false,
    List<Map<String, dynamic>>? selectedProductStockSummary,
    List<InventoryLot>? selectedProductLots,
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
      inventoryItems: inventoryItems ?? this.inventoryItems,
      customMedications: customMedications ?? this.customMedications,
      stocktakeConfigs: stocktakeConfigs ?? this.stocktakeConfigs,
      stocktakeSessions: stocktakeSessions ?? this.stocktakeSessions,
      stockAdjustments: stockAdjustments ?? this.stockAdjustments,
      inventoryTransfers: inventoryTransfers ?? this.inventoryTransfers,
      inventoryAlerts: inventoryAlerts ?? this.inventoryAlerts,
      selectedProduct: clearSelectedProduct ? null : (selectedProduct ?? this.selectedProduct),
      selectedProductStockSummary: selectedProductStockSummary ?? this.selectedProductStockSummary,
      selectedProductLots: selectedProductLots ?? this.selectedProductLots,
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
    } catch (e, st) {
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
    } catch (e, st) {
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
    } catch (e, st) {
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
    } catch (e, st) {
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
    } catch (e, st) {
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
    } catch (e, st) {
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
    } catch (e, st) {
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
    } catch (e, st) {
      debugPrint('[Phase1] loadInventoryLots ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดข้อมูลคลังสินค้าล้มเหลว: $e');
    }
  }

  Future<bool> recordStockReceipt({
    required String professionId,
    required String productId,
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
      // 1. Create inventory lot
      final lotData = {
        'profession_id': professionId,
        'product_id': productId,
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

      // 2. Record stock movement
      final movementData = {
        'profession_id': professionId,
        'product_id': productId,
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
    } catch (e, st) {
      debugPrint('[Phase1] recordStockReceipt ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึกรับเข้าล้มเหลว: $e');
      return false;
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
    } catch (e, st) {
      debugPrint('[Phase1] loadCoupons ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดคูปองล้มเหลว: $e');
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
    } catch (e, st) {
      debugPrint('[Phase1] loadPurchaseOrders ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดใบสั่งซื้อล้มเหลว: $e');
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
    } catch (e, st) {
      debugPrint('[Phase1] loadInventoryItems ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดสต็อกล้มเหลว: $e');
    }
  }

  Future<void> loadLowStockItems(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repository.getLowStockItems(professionId);
      state = state.copyWith(isLoading: false, inventoryItems: items);
    } catch (e, st) {
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
    } catch (e, st) {
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
    } catch (e, st) {
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
    } catch (e, st) {
      debugPrint('[Phase1] loadStocktakeConfigurations ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดตั้งค่าตรวจนับล้มเหลว: $e');
    }
  }

  Future<void> loadStocktakeSessions(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final sessions = await _repository.getStocktakeSessions(professionId);
      state = state.copyWith(isLoading: false, stocktakeSessions: sessions);
    } catch (e, st) {
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
    } catch (e, st) {
      debugPrint('[Phase1] completeStocktakeSession ERROR: $e');
      return null;
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
    } catch (e, st) {
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
    } catch (e, st) {
      debugPrint('[Phase1] loadInventoryTransfers ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดการโอนย้ายล้มเหลว: $e');
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
    } catch (e, st) {
      debugPrint('[Phase1] loadInventoryAlerts ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดแจ้งเตือนสต็อกล้มเหลว: $e');
    }
  }

  Future<int> checkInventoryAlerts(String professionId) async {
    try {
      return await _repository.checkInventoryAlerts(professionId);
    } catch (e, st) {
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
