import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer.dart';
import '../models/inventory_lot.dart';
import '../models/product.dart';
import '../models/supplier.dart';

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
}
