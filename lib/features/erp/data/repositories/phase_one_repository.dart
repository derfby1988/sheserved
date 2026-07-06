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
import '../models/purchase_requisition.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../models/purchase_requisition_item.dart';
import '../models/goods_receipt.dart';
import '../models/goods_receipt_item.dart';
import '../models/back_order.dart';
import '../models/procurement_settings.dart';

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
    } catch (e) {
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
      return Product.fromJson(response);
    } catch (e) {
      debugPrint('[Phase1Repo] createProduct error: $e');
      return null;
    }
  }

  Future<bool> updateProduct(String productId, Map<String, dynamic> data) async {
    try {
      await _client.from('products').update(data).eq('id', productId);
      return true;
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
      return Customer.fromJson(response);
    } catch (e) {
      debugPrint('[Phase1Repo] createCustomer error: $e');
      return null;
    }
  }

  Future<bool> updateCustomer(String customerId, Map<String, dynamic> data) async {
    try {
      await _client.from('customers').update(data).eq('id', customerId);
      return true;
    } catch (e) {
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
    } catch (e) {
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
      return Supplier.fromJson(response);
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      debugPrint('[Phase1Repo] getProductStockSummary error: $e');
      return [];
    }
  }

  Future<bool> createInventoryLot(Map<String, dynamic> data) async {
    try {
      await _client.from('inventory_lots').insert(data);
      return true;
    } catch (e) {
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
    } catch (e) {
      debugPrint('[Phase1Repo] recordStockMovement error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getStockMovements({
    String? productId,
    String? customMedicationId,
    String? professionId,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('stock_movements')
          .select();

      if (productId != null) {
        query = query.eq('product_id', productId);
      }
      if (customMedicationId != null) {
        query = query.eq('custom_medication_id', customMedicationId);
      }
      if (professionId != null) {
        query = query.eq('profession_id', professionId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getStockMovements error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStockMovementsByProfession(
    String professionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _client.rpc(
        'get_stock_movements_by_profession',
        params: {
          'p_profession_id': professionId,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      return (response as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getStockMovementsByProfession error: $e');
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
    } catch (e) {
      debugPrint('[Phase1Repo] getCoupons error: $e');
      return [];
    }
  }

  Future<bool> createCoupon(Map<String, dynamic> data) async {
    try {
      await _client.from('coupons').insert(data);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] createCoupon error: $e');
      return false;
    }
  }

  // ========================
  // PURCHASE REQUISITIONS
  // ========================

  Future<List<PurchaseRequisition>> getPurchaseRequisitions(String professionId) async {
    try {
      final response = await _client
          .from('purchase_requisitions')
          .select('*, requester:users(display_name), approver:users(display_name), branch:organization_branches(name)')
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => PurchaseRequisition.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getPurchaseRequisitions error: $e');
      return [];
    }
  }

  Future<bool> createPurchaseRequisition(Map<String, dynamic> data) async {
    try {
      await _client.from('purchase_requisitions').insert(data);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] createPurchaseRequisition error: $e');
      return false;
    }
  }

  Future<bool> updatePurchaseRequisitionStatus(
    String prId,
    String status, {
    String? approvedBy,
  }) async {
    try {
      final data = {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
        if (approvedBy != null) 'approved_by': approvedBy,
        if (approvedBy != null) 'approved_at': DateTime.now().toIso8601String(),
      };
      await _client.from('purchase_requisitions').update(data).eq('id', prId);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] updatePurchaseRequisitionStatus error: $e');
      return false;
    }
  }

  // ========================
  // PURCHASE ORDERS
  // ========================

  Future<List<PurchaseOrder>> getPurchaseOrders(String professionId) async {
    try {
      final response = await _client
          .from('purchase_orders')
          .select('*, supplier:suppliers(supplier_name), branch:organization_branches(name), purchase_requisitions(pr_number)')
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => PurchaseOrder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getPurchaseOrders error: $e');
      return [];
    }
  }

  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(String poId) async {
    try {
      final response = await _client
          .from('purchase_order_items')
          .select('*, product:products(name, unit_of_measure)')
          .eq('po_id', poId)
          .order('created_at', ascending: true);
      return (response as List)
          .map((e) => PurchaseOrderItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getPurchaseOrderItems error: $e');
      return [];
    }
  }

  Future<bool> createPurchaseOrder({
    required Map<String, dynamic> poData,
    required List<Map<String, dynamic>> itemsData,
  }) async {
    try {
      // 1. Insert purchase order
      final poResponse = await _client
          .from('purchase_orders')
          .insert(poData)
          .select()
          .single();
      
      final String poId = poResponse['id'] as String;

      // 2. Prepare items data with the new poId
      final itemsToInsert = itemsData.map((item) {
        return {
          ...item,
          'po_id': poId,
        };
      }).toList();

      // 3. Insert items
      await _client.from('purchase_order_items').insert(itemsToInsert);

      // 4. If this PO was created from a PR, update the PR status to 'converted'
      final String? prId = poData['pr_id'] as String?;
      if (prId != null) {
        await updatePurchaseRequisitionStatus(prId, 'converted');
      }

      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] createPurchaseOrder error: $e');
      return false;
    }
  }

  Future<bool> updatePurchaseOrderStatus(String poId, String status) async {
    try {
      await _client
          .from('purchase_orders')
          .update({
            'status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', poId);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] updatePurchaseOrderStatus error: $e');
      return false;
    }
  }

  Future<bool> sendPurchaseOrderRpc(String poId, String? sentBy) async {
    try {
      await _client.rpc(
        'send_purchase_order',
        params: {
          'p_po_id': poId,
          'p_sent_by': sentBy,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] sendPurchaseOrderRpc error: $e');
      return false;
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      debugPrint('[Phase1Repo] deductStock error: $e');
      return false;
    }
  }

  Future<int> cleanupExpiredReservations() async {
    try {
      final response = await _client.rpc('cleanup_expired_reservations');
      return (response as num?)?.toInt() ?? 0;
    } catch (e) {
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
    } catch (e) {
      debugPrint('[Phase1Repo] getInventoryItems error: $e');
      return [];
    }
  }

  Future<InventoryItem?> findInventoryItem({
    required String professionId,
    String? productId,
    String? customMedicationId,
    String? branchId,
  }) async {
    try {
      var query = _client
          .from('inventory_items')
          .select()
          .eq('profession_id', professionId);

      if (productId != null) {
        query = query.eq('product_id', productId);
      }
      if (customMedicationId != null) {
        query = query.eq('custom_medication_id', customMedicationId);
      }
      if (branchId != null) {
        query = query.eq('branch_id', branchId);
      }

      final response = await query.maybeSingle();
      if (response == null) return null;
      return InventoryItem.fromJson(response);
    } catch (e) {
      debugPrint('[Phase1Repo] findInventoryItem error: $e');
      return null;
    }
  }

  Future<bool> createInventoryItem(Map<String, dynamic> data) async {
    try {
      await _client.from('inventory_items').insert(data);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] createInventoryItem error: $e');
      return false;
    }
  }

  Future<bool> updateInventoryItem(String id, Map<String, dynamic> data) async {
    try {
      await _client.from('inventory_items').update(data).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] updateInventoryItem error: $e');
      return false;
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      debugPrint('[Phase1Repo] getStocktakeConfigurations error: $e');
      return [];
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
    try {
      final response = await _client.rpc(
        'create_stocktake_configuration',
        params: {
          'p_profession_id': professionId,
          'p_branch_id': branchId,
          'p_name': name,
          'p_frequency_type': frequencyType,
          'p_custom_interval_days': customIntervalDays,
          'p_next_stocktake_date': nextStocktakeDate?.toIso8601String().split('T')[0],
        },
      );
      return response as String?;
    } catch (e) {
      debugPrint('[Phase1Repo] createStocktakeConfiguration error: $e');
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
    try {
      await _client.rpc(
        'update_stocktake_configuration',
        params: {
          'p_config_id': configId,
          'p_name': name,
          'p_frequency_type': frequencyType,
          'p_custom_interval_days': customIntervalDays,
          'p_next_stocktake_date': nextStocktakeDate?.toIso8601String().split('T')[0],
          'p_is_active': isActive,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] updateStocktakeConfiguration error: $e');
      return false;
    }
  }

  Future<bool> deleteStocktakeConfiguration(String configId) async {
    try {
      await _client.rpc(
        'delete_stocktake_configuration',
        params: {'p_config_id': configId},
      );
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] deleteStocktakeConfiguration error: $e');
      return false;
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      debugPrint('[Phase1Repo] checkInventoryAlerts error: $e');
      return 0;
    }
  }

  // ========================
  // PROCUREMENT STEP 2 — Goods Receipt, Back Orders, PR Items, Settings
  // ========================

  // --- Goods Receipts ---

  Future<List<GoodsReceipt>> getGoodsReceipts(String professionId) async {
    try {
      final response = await _client
          .from('goods_receipts')
          .select('*, purchase_order:purchase_orders(po_number), branch:organization_branches(name), receiver:users(display_name)')
          .eq('profession_id', professionId)
          .order('receipt_date', ascending: false);
      return (response as List)
          .map((e) => GoodsReceipt.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getGoodsReceipts error: $e');
      return [];
    }
  }

  Future<List<GoodsReceipt>> getGoodsReceiptsByPO(String poId) async {
    try {
      final response = await _client
          .from('goods_receipts')
          .select('*, purchase_order:purchase_orders(po_number), branch:organization_branches(name), receiver:users(display_name)')
          .eq('purchase_order_id', poId)
          .order('receipt_date', ascending: false);
      return (response as List)
          .map((e) => GoodsReceipt.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getGoodsReceiptsByPO error: $e');
      return [];
    }
  }

  Future<List<GoodsReceiptItem>> getGoodsReceiptItems(String grId) async {
    try {
      final response = await _client
          .from('goods_receipt_items')
          .select('*, purchase_order_item:purchase_order_items(quantity_ordered, quantity_received, product:products(name))')
          .eq('goods_receipt_id', grId)
          .order('created_at', ascending: true);
      return (response as List)
          .map((e) => GoodsReceiptItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getGoodsReceiptItems error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> createGoodsReceiptRpc({
    required String professionId,
    String? branchId,
    required String purchaseOrderId,
    required String receivedBy,
    String? supplierDeliveryNote,
    required List<Map<String, dynamic>> items,
    String? notes,
    String? idempotencyKey,
  }) async {
    try {
      final response = await _client.rpc(
        'create_goods_receipt',
        params: {
          'p_profession_id': professionId,
          'p_branch_id': branchId,
          'p_purchase_order_id': purchaseOrderId,
          'p_received_by': receivedBy,
          'p_supplier_delivery_note': supplierDeliveryNote,
          'p_items': items,
          'p_notes': notes,
          'p_idempotency_key': idempotencyKey,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[Phase1Repo] createGoodsReceiptRpc error: $e');
      return null;
    }
  }

  // --- Back Orders ---

  Future<List<BackOrder>> getBackOrders(String professionId, {String? status}) async {
    try {
      var query = _client
          .from('back_orders')
          .select('*, purchase_order:purchase_orders(po_number), supplier:suppliers(supplier_name), purchase_order_item:purchase_order_items(product:products(name))')
          .eq('profession_id', professionId);
      if (status != null) {
        query = query.eq('status', status);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List)
          .map((e) => BackOrder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getBackOrders error: $e');
      return [];
    }
  }

  // --- Purchase Requisition Items ---

  Future<List<PurchaseRequisitionItem>> getPurchaseRequisitionItems(String requisitionId) async {
    try {
      final response = await _client
          .from('purchase_requisition_items')
          .select('*, product:products(name, sku)')
          .eq('requisition_id', requisitionId)
          .order('created_at', ascending: true);
      return (response as List)
          .map((e) => PurchaseRequisitionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase1Repo] getPurchaseRequisitionItems error: $e');
      return [];
    }
  }

  Future<bool> createPurchaseRequisitionItems(List<Map<String, dynamic>> items) async {
    try {
      await _client.from('purchase_requisition_items').insert(items);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] createPurchaseRequisitionItems error: $e');
      return false;
    }
  }

  Future<bool> addPurchaseRequisitionItem(Map<String, dynamic> item) async {
    try {
      await _client.from('purchase_requisition_items').insert(item);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] addPurchaseRequisitionItem error: $e');
      return false;
    }
  }

  Future<bool> deletePurchaseRequisitionItem(String itemId) async {
    try {
      await _client.from('purchase_requisition_items').delete().eq('id', itemId);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] deletePurchaseRequisitionItem error: $e');
      return false;
    }
  }

  // --- Procurement Settings ---

  Future<ProcurementSettings?> getProcurementSettings(String professionId) async {
    try {
      final response = await _client
          .from('procurement_settings')
          .select()
          .eq('profession_id', professionId)
          .maybeSingle();
      if (response == null) return null;
      return ProcurementSettings.fromJson(response);
    } catch (e) {
      debugPrint('[Phase1Repo] getProcurementSettings error: $e');
      return null;
    }
  }

  Future<bool> updateProcurementSettings(String professionId, Map<String, dynamic> data) async {
    try {
      await _client
          .from('procurement_settings')
          .update(data)
          .eq('profession_id', professionId);
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] updateProcurementSettings error: $e');
      return false;
    }
  }

  // --- PR Approval/Rejection RPCs ---

  Future<bool> approvePurchaseRequisitionRpc(String prId, String approvedBy) async {
    try {
      await _client.rpc(
        'approve_purchase_requisition',
        params: {
          'p_requisition_id': prId,
          'p_approved_by': approvedBy,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] approvePurchaseRequisitionRpc error: $e');
      return false;
    }
  }

  Future<bool> rejectPurchaseRequisitionRpc(String prId, String rejectedBy, {String? reason}) async {
    try {
      await _client.rpc(
        'reject_purchase_requisition',
        params: {
          'p_requisition_id': prId,
          'p_rejected_by': rejectedBy,
          'p_reason': reason,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] rejectPurchaseRequisitionRpc error: $e');
      return false;
    }
  }

  // --- Convert PR to PO RPC ---

  Future<Map<String, dynamic>?> convertPrToPoRpc({
    required String requisitionId,
    required String supplierId,
    required String createdBy,
    String? branchId,
    String? notes,
  }) async {
    try {
      final response = await _client.rpc(
        'convert_pr_to_po',
        params: {
          'p_requisition_id': requisitionId,
          'p_supplier_id': supplierId,
          'p_created_by': createdBy,
          'p_branch_id': branchId,
          'p_notes': notes,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[Phase1Repo] convertPrToPoRpc error: $e');
      return null;
    }
  }

  // --- Reorder Suggestions (Step 3) ---

  Future<List<Map<String, dynamic>>> getReorderSuggestions(
    String professionId, {
    String? branchId,
    String? status,
  }) async {
    try {
      var query = _client
          .from('reorder_suggestions')
          .select('''
            *,
            products(name, sku, unit_of_measure),
            suppliers(supplier_name)
          ''')
          .eq('profession_id', professionId);
      if (status != null) {
        query = query.eq('status', status);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Phase1Repo] getReorderSuggestions error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> checkReorderPoints(
    String professionId, {
    String? branchId,
  }) async {
    try {
      final response = await _client.rpc(
        'check_reorder_points',
        params: {
          'p_profession_id': professionId,
          'p_branch_id': branchId,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[Phase1Repo] checkReorderPoints error: $e');
      return null;
    }
  }

  Future<bool> confirmReorderSuggestion(String suggestionId, String confirmedBy) async {
    try {
      await _client.rpc(
        'confirm_reorder_suggestion',
        params: {
          'p_id': suggestionId,
          'p_confirmed_by': confirmedBy,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] confirmReorderSuggestion error: $e');
      return false;
    }
  }

  Future<bool> rejectReorderSuggestion(String suggestionId, String rejectedBy, {String? reason}) async {
    try {
      await _client.rpc(
        'reject_reorder_suggestion',
        params: {
          'p_id': suggestionId,
          'p_rejected_by': rejectedBy,
          'p_reason': reason,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[Phase1Repo] rejectReorderSuggestion error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> convertReorderToPr(String suggestionId, String createdBy) async {
    try {
      final response = await _client.rpc(
        'convert_reorder_to_pr',
        params: {
          'p_id': suggestionId,
          'p_created_by': createdBy,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[Phase1Repo] convertReorderToPr error: $e');
      return null;
    }
  }

  // --- Supplier Price History (Step 3) ---

  Future<List<Map<String, dynamic>>> getSupplierPriceHistory(
    String professionId, {
    String? supplierId,
    String? productId,
    int limit = 20,
  }) async {
    try {
      final response = await _client.rpc(
        'get_supplier_price_history',
        params: {
          'p_profession_id': professionId,
          'p_supplier_id': supplierId,
          'p_product_id': productId,
          'p_limit': limit,
        },
      );
      if (response == null) return [];
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Phase1Repo] getSupplierPriceHistory error: $e');
      return [];
    }
  }

  Future<double?> getLatestSupplierPrice(
    String professionId,
    String supplierId,
    String productId,
  ) async {
    try {
      final response = await _client.rpc(
        'get_latest_supplier_price',
        params: {
          'p_profession_id': professionId,
          'p_supplier_id': supplierId,
          'p_product_id': productId,
        },
      );
      return (response as num?)?.toDouble();
    } catch (e) {
      debugPrint('[Phase1Repo] getLatestSupplierPrice error: $e');
      return null;
    }
  }
}
