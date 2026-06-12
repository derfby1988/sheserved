import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer.dart';
import '../models/inventory_lot.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../models/custom_medication.dart';
import '../models/inventory_item.dart';
import '../models/stocktake_configuration.dart';
import '../models/stocktake_session.dart';
import '../models/stocktake_line.dart';
import '../models/stock_adjustment.dart';
import '../models/inventory_transfer.dart';
import '../models/inventory_transfer_line.dart';
import '../models/inventory_alert.dart';

/// Repository สำหรับ ERP Phase 1 — Data & Inflow
/// ครอบคลุม: Product Master, CRM, Procurement, Inventory
class PhaseOneRepository {
  final SupabaseClient _client;

  PhaseOneRepository(this._client);

  // ========================
  // PRODUCTS
  // ========================

  Future<List<Product>> getProducts(String professionId) async {
    try {
      final response = await _client
          .from('products')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('name');
      return (response as List)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getProducts error: $e');
      return [];
    }
  }

  Future<Product?> createProduct(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('products')
          .insert(data)
          .select()
          .single();
      return Product.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase1Repo] createProduct error: $e');
      return null;
    }
  }

  Future<bool> updateProduct(String productId, Map<String, dynamic> data) async {
    try {
      await _client.from('products').update(data).eq('id', productId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase1Repo] updateProduct error: $e');
      return false;
    }
  }

  Future<int?> getProductAvailableStock(String productId, String? branchId) async {
    try {
      final response = await _client.rpc(
        'get_product_available_stock',
        params: {
          'p_product_id': productId,
          'p_branch_id': branchId,
        },
      );
      return response as int?;
    } catch (e, st) {
      debugPrint('[Phase1Repo] getProductAvailableStock error: $e');
      return null;
    }
  }

  // ========================
  // CUSTOMERS
  // ========================

  Future<List<Customer>> getCustomers(String professionId) async {
    try {
      final response = await _client
          .from('customers')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('display_name');
      return (response as List)
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getCustomers error: $e');
      return [];
    }
  }

  Future<Customer?> createCustomer(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('customers')
          .insert(data)
          .select()
          .single();
      return Customer.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase1Repo] createCustomer error: $e');
      return null;
    }
  }

  Future<bool> updateCustomer(String customerId, Map<String, dynamic> data) async {
    try {
      await _client.from('customers').update(data).eq('id', customerId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase1Repo] updateCustomer error: $e');
      return false;
    }
  }

  // ========================
  // SUPPLIERS
  // ========================

  Future<List<Supplier>> getSuppliers(String professionId) async {
    try {
      final response = await _client
          .from('suppliers')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('supplier_name');
      return (response as List)
          .map((e) => Supplier.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getSuppliers error: $e');
      return [];
    }
  }

  Future<Supplier?> createSupplier(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('suppliers')
          .insert(data)
          .select()
          .single();
      return Supplier.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase1Repo] createSupplier error: $e');
      return null;
    }
  }

  // ========================
  // INVENTORY LOTS
  // ========================

  Future<List<InventoryLot>> getInventoryLots(String professionId) async {
    try {
      final response = await _client
          .from('inventory_lots')
          .select()
          .eq('profession_id', professionId)
          .order('expiry_date', ascending: true);
      return (response as List)
          .map((e) => InventoryLot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getInventoryLots error: $e');
      return [];
    }
  }

  Future<List<InventoryLot>> getInventoryLotsByProduct(String productId) async {
    try {
      final response = await _client
          .from('inventory_lots')
          .select()
          .eq('product_id', productId)
          .eq('status', 'active')
          .order('expiry_date', ascending: true);
      return (response as List)
          .map((e) => InventoryLot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getInventoryLotsByProduct error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProductStockSummary(
    String productId,
    String? branchId,
  ) async {
    try {
      final response = await _client.rpc(
        'get_product_stock_summary',
        params: {
          'p_product_id': productId,
          'p_branch_id': branchId,
        },
      );
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e, st) {
      debugPrint('[Phase1Repo] getProductStockSummary error: $e');
      return [];
    }
  }

  Future<bool> createInventoryLot(Map<String, dynamic> data) async {
    try {
      await _client.from('inventory_lots').insert(data);
      return true;
    } catch (e, st) {
      debugPrint('[Phase1Repo] createInventoryLot error: $e');
      return false;
    }
  }

  // ========================
  // STOCK MOVEMENTS
  // ========================

  Future<bool> recordStockMovement(Map<String, dynamic> data) async {
    try {
      await _client.from('stock_movements').insert(data);
      return true;
    } catch (e, st) {
      debugPrint('[Phase1Repo] recordStockMovement error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getStockMovements(String productId) async {
    try {
      final response = await _client
          .from('stock_movements')
          .select()
          .eq('product_id', productId)
          .order('created_at', ascending: false)
          .limit(50);
      return (response as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getStockMovements error: $e');
      return [];
    }
  }

  // ========================
  // COUPONS
  // ========================

  Future<List<Map<String, dynamic>>> getCoupons(String professionId) async {
    try {
      final response = await _client
          .from('coupons')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('end_date', ascending: true);
      return (response as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getCoupons error: $e');
      return [];
    }
  }

  Future<bool> createCoupon(Map<String, dynamic> data) async {
    try {
      await _client.from('coupons').insert(data);
      return true;
    } catch (e, st) {
      debugPrint('[Phase1Repo] createCoupon error: $e');
      return false;
    }
  }

  // ========================
  // PURCHASE ORDERS
  // ========================

  Future<List<Map<String, dynamic>>> getPurchaseOrders(String professionId) async {
    try {
      final response = await _client
          .from('purchase_orders')
          .select('*, supplier:suppliers(supplier_name)')
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getPurchaseOrders error: $e');
      return [];
    }
  }

  // ========================
  // INVENTORY RESERVATIONS
  // ========================

  Future<String?> createInventoryReservation({
    required String professionId,
    required String productId,
    String? branchId,
    required int quantity,
    required String reservationType,
    required String referenceId,
    required DateTime expiresAt,
    String? lotId,
  }) async {
    try {
      final response = await _client.rpc(
        'create_inventory_reservation',
        params: {
          'p_profession_id': professionId,
          'p_product_id': productId,
          'p_branch_id': branchId,
          'p_quantity': quantity,
          'p_reservation_type': reservationType,
          'p_reference_id': referenceId,
          'p_expires_at': expiresAt.toIso8601String(),
          'p_lot_id': lotId,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase1Repo] createInventoryReservation error: $e');
      return null;
    }
  }

  Future<bool> releaseStockReservation(String reservationId) async {
    try {
      await _client.rpc(
        'release_stock_reservation',
        params: {'p_reservation_id': reservationId},
      );
      return true;
    } catch (e, st) {
      debugPrint('[Phase1Repo] releaseStockReservation error: $e');
      return false;
    }
  }

  Future<bool> deductStock({
    required String reservationId,
    required String orderId,
  }) async {
    try {
      await _client.rpc(
        'deduct_stock',
        params: {
          'p_reservation_id': reservationId,
          'p_order_id': orderId,
        },
      );
      return true;
    } catch (e, st) {
      debugPrint('[Phase1Repo] deductStock error: $e');
      return false;
    }
  }

  Future<int> cleanupExpiredReservations() async {
    try {
      final response = await _client.rpc('cleanup_expired_reservations');
      return (response as num?)?.toInt() ?? 0;
    } catch (e, st) {
      debugPrint('[Phase1Repo] cleanupExpiredReservations error: $e');
      return 0;
    }
  }

  // ========================
  // INVENTORY ITEMS
  // ========================

  Future<List<InventoryItem>> getInventoryItems(String professionId) async {
    try {
      final response = await _client
          .from('inventory_items')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getInventoryItems error: $e');
      return [];
    }
  }

  Future<List<InventoryItem>> getLowStockItems(String professionId) async {
    try {
      final response = await _client
          .from('inventory_items')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('quantity', ascending: true);
      final items = (response as List)
          .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return items.where((i) => i.isLowStock).toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getLowStockItems error: $e');
      return [];
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
      final response = await _client.rpc(
        'deduct_inventory_fefo',
        params: {
          'p_profession_id': professionId,
          'p_inventory_item_id': inventoryItemId,
          'p_quantity': quantity,
          'p_reference_type': referenceType,
          'p_reference_id': referenceId,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase1Repo] deductInventoryFefo error: $e');
      return null;
    }
  }

  // ========================
  // CUSTOM MEDICATIONS
  // ========================

  Future<List<CustomMedication>> getCustomMedications(String professionId) async {
    try {
      final response = await _client
          .from('custom_medications')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('name');
      return (response as List)
          .map((e) => CustomMedication.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getCustomMedications error: $e');
      return [];
    }
  }

  // ========================
  // STOCKTAKE
  // ========================

  Future<List<StocktakeConfiguration>> getStocktakeConfigurations(String professionId) async {
    try {
      final response = await _client
          .from('stocktake_configurations')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('next_stocktake_date');
      return (response as List)
          .map((e) => StocktakeConfiguration.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getStocktakeConfigurations error: $e');
      return [];
    }
  }

  Future<List<StocktakeSession>> getStocktakeSessions(String professionId) async {
    try {
      final response = await _client
          .from('stocktake_sessions')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => StocktakeSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getStocktakeSessions error: $e');
      return [];
    }
  }

  Future<List<StocktakeLine>> getStocktakeLines(String sessionId) async {
    try {
      final response = await _client
          .from('stocktake_lines')
          .select()
          .eq('stocktake_session_id', sessionId);
      return (response as List)
          .map((e) => StocktakeLine.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getStocktakeLines error: $e');
      return [];
    }
  }

  Future<int?> completeStocktakeSession({
    required String sessionId,
    String? approvedBy,
  }) async {
    try {
      final response = await _client.rpc(
        'complete_stocktake_session',
        params: {
          'p_session_id': sessionId,
          'p_approved_by': approvedBy,
        },
      );
      return response != null ? (response as num).toInt() : null;
    } catch (e, st) {
      debugPrint('[Phase1Repo] completeStocktakeSession error: $e');
      return null;
    }
  }

  // ========================
  // STOCK ADJUSTMENTS
  // ========================

  Future<List<StockAdjustment>> getStockAdjustments(String professionId) async {
    try {
      final response = await _client
          .from('stock_adjustments')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => StockAdjustment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getStockAdjustments error: $e');
      return [];
    }
  }

  Future<String?> createStockAdjustment({
    required String professionId,
    required String inventoryItemId,
    required String adjustmentType,
    required int quantityAfter,
    String? reason,
    String? createdBy,
    String? referenceId,
  }) async {
    try {
      final response = await _client.rpc(
        'create_stock_adjustment',
        params: {
          'p_profession_id': professionId,
          'p_inventory_item_id': inventoryItemId,
          'p_adjustment_type': adjustmentType,
          'p_quantity_after': quantityAfter,
          'p_reason': reason,
          'p_created_by': createdBy,
          'p_reference_id': referenceId,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase1Repo] createStockAdjustment error: $e');
      return null;
    }
  }

  // ========================
  // INVENTORY TRANSFERS
  // ========================

  Future<List<InventoryTransfer>> getInventoryTransfers(String professionId) async {
    try {
      final response = await _client
          .from('inventory_transfers')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => InventoryTransfer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getInventoryTransfers error: $e');
      return [];
    }
  }

  Future<List<InventoryTransferLine>> getInventoryTransferLines(String transferId) async {
    try {
      final response = await _client
          .from('inventory_transfer_lines')
          .select()
          .eq('transfer_id', transferId);
      return (response as List)
          .map((e) => InventoryTransferLine.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getInventoryTransferLines error: $e');
      return [];
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
    try {
      final response = await _client.rpc(
        'create_inventory_transfer',
        params: {
          'p_profession_id': professionId,
          'p_from_branch_id': fromBranchId,
          'p_from_warehouse_id': fromWarehouseId,
          'p_to_branch_id': toBranchId,
          'p_to_warehouse_id': toWarehouseId,
          'p_items': items,
          'p_requested_by': requestedBy,
          'p_notes': notes,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase1Repo] createInventoryTransfer error: $e');
      return null;
    }
  }

  Future<bool> completeInventoryTransfer({
    required String transferId,
    String? approvedBy,
  }) async {
    try {
      final response = await _client.rpc(
        'complete_inventory_transfer',
        params: {
          'p_transfer_id': transferId,
          'p_approved_by': approvedBy,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase1Repo] completeInventoryTransfer error: $e');
      return false;
    }
  }

  // ========================
  // INVENTORY ALERTS
  // ========================

  Future<List<InventoryAlert>> getInventoryAlerts(String professionId, {bool unresolvedOnly = true}) async {
    try {
      var query = _client
          .from('inventory_alerts')
          .select()
          .eq('profession_id', professionId);
      if (unresolvedOnly) {
        query = query.eq('is_resolved', false);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List)
          .map((e) => InventoryAlert.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase1Repo] getInventoryAlerts error: $e');
      return [];
    }
  }

  Future<int> checkInventoryAlerts(String professionId) async {
    try {
      final response = await _client.rpc(
        'check_inventory_alerts',
        params: {'p_profession_id': professionId},
      );
      return (response as num?)?.toInt() ?? 0;
    } catch (e, st) {
      debugPrint('[Phase1Repo] checkInventoryAlerts error: $e');
      return 0;
    }
  }
}
