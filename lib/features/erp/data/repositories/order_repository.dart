import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';

/// Repository สำหรับ existing orders / order_items tables (POS Core)
class OrderRepository {
  final SupabaseClient _client;

  OrderRepository(this._client);

  // ========================
  // ORDERS
  // ========================

  Future<Order?> createOrder(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('orders')
          .insert(data)
          .select()
          .single();
      return Order.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[OrderRepo] createOrder error: $e');
      return null;
    }
  }

  Future<Order?> getOrder(String orderId) async {
    try {
      final response = await _client
          .from('orders')
          .select()
          .eq('id', orderId)
          .single();
      return Order.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[OrderRepo] getOrder error: $e');
      return null;
    }
  }

  Future<List<Order>> getOrdersByProfession(String professionId) async {
    try {
      final response = await _client
          .from('orders')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[OrderRepo] getOrdersByProfession error: $e');
      return [];
    }
  }

  Future<bool> updateOrderStatus(String orderId, String status) async {
    try {
      await _client
          .from('orders')
          .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', orderId);
      return true;
    } catch (e, st) {
      debugPrint('[OrderRepo] updateOrderStatus error: $e');
      return false;
    }
  }

  // ========================
  // ORDER ITEMS
  // ========================

  Future<OrderItem?> createOrderItem(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('order_items')
          .insert(data)
          .select()
          .single();
      return OrderItem.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[OrderRepo] createOrderItem error: $e');
      return null;
    }
  }

  Future<List<OrderItem>> getOrderItems(String orderId) async {
    try {
      final response = await _client
          .from('order_items')
          .select()
          .eq('order_id', orderId);
      return (response as List)
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[OrderRepo] getOrderItems error: $e');
      return [];
    }
  }

  // ========================
  // SHOPPING CART (existing JSONB)
  // ========================

  Future<Map<String, dynamic>?> getShoppingCart(String userId) async {
    try {
      final response = await _client
          .from('shopping_carts')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (response == null) return null;
      return response as Map<String, dynamic>;
    } catch (e, st) {
      debugPrint('[OrderRepo] getShoppingCart error: $e');
      return null;
    }
  }

  Future<bool> upsertShoppingCart(String userId, List<Map<String, dynamic>> items) async {
    try {
      await _client.from('shopping_carts').upsert({
        'user_id': userId,
        'items': items,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e, st) {
      debugPrint('[OrderRepo] upsertShoppingCart error: $e');
      return false;
    }
  }

  // ========================
  // CREATE ORDER FROM CART
  // ========================

  Future<Order?> createOrderFromCart({
    required String professionId,
    required String userId,
    required List<Map<String, dynamic>> cartItems,
    String posMode = 'mode_b_counter',
    String? customerId,
    String? servedBy,
  }) async {
    try {
      // Calculate totals
      double subtotal = 0;
      for (final item in cartItems) {
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        final qty = (item['quantity'] as int?) ?? 1;
        subtotal += price * qty;
      }
      final vat = subtotal * 0.07;
      final grandTotal = subtotal + vat;

      // Create order
      final orderData = {
        'user_id': userId,
        'profession_id': professionId,
        'customer_id': customerId,
        'pos_mode': posMode,
        'status': 'pending',
        'subtotal': subtotal,
        'vat_total': vat,
        'grand_total': grandTotal,
        'served_by': servedBy,
      };

      final order = await createOrder(orderData);
      if (order == null) return null;

      // Create order items
      for (final item in cartItems) {
        await createOrderItem({
          'order_id': order.id,
          'item_type': 'product',
          'item_id': item['id'],
          'name': item['name'],
          'quantity': item['quantity'] ?? 1,
          'unit_price': item['price'],
          'line_total': (item['price'] as double) * (item['quantity'] as int? ?? 1),
        });
      }

      return order;
    } catch (e, st) {
      debugPrint('[OrderRepo] createOrderFromCart error: $e');
      return null;
    }
  }
}
