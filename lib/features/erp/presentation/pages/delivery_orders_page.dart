import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/delivery_order.dart';
import '../providers/phase_two_provider.dart';
import '../widgets/glass_card.dart';

class DeliveryOrdersPage extends ConsumerStatefulWidget {
  final String professionId;

  const DeliveryOrdersPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<DeliveryOrdersPage> createState() => _DeliveryOrdersPageState();
}

class _DeliveryOrdersPageState extends ConsumerState<DeliveryOrdersPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseTwoProvider.notifier).loadDeliveryOrders(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseTwoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('การจัดส่ง / Delivery'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.deliveryOrders.isEmpty
                  ? const Center(
                      child: Text(
                        'ยังไม่มีรายการจัดส่ง',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.deliveryOrders.length,
                      itemBuilder: (context, index) {
                        final order = state.deliveryOrders[index];
                        return _DeliveryOrderCard(order: order);
                      },
                    ),
    );
  }
}

class _DeliveryOrderCard extends StatelessWidget {
  final DeliveryOrder order;

  const _DeliveryOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    switch (order.deliveryStatus) {
      case 'delivered':
        statusColor = Colors.green;
        break;
      case 'in_transit':
        statusColor = Colors.blue;
        break;
      case 'failed':
      case 'cancelled':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.orange;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order: ${order.orderId.substring(0, 8)}...',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    order.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('ผู้รับ: ${order.recipientName}'),
            Text('โทร: ${order.recipientPhone}'),
            Text('ที่อยู่: ${order.deliveryAddress}', maxLines: 2, overflow: TextOverflow.ellipsis),
            if (order.trackingNumber != null) ...[
              const SizedBox(height: 4),
              Text('Tracking: ${order.trackingNumber}', style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
