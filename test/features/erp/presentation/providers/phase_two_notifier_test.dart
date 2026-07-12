import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/erp/data/models/delivery_order.dart';
import 'package:sheserved/features/erp/data/repositories/phase_two_repository.dart';
import 'package:sheserved/features/erp/presentation/providers/phase_two_provider.dart';
import 'package:sheserved/features/pharmacy/data/services/drug_risk_screening_service.dart';

/// Manual mock repository to verify P6 pass-through without Mockito/Supabase chain complexity
class _FakePhaseTwoRepository extends Fake implements PhaseTwoRepository {
  Map<String, dynamic>? lastData;
  Map<String, dynamic>? lastDrugRiskFlags;
  DeliveryOrder? nextReturn;

  @override
  Future<DeliveryOrder?> createDeliveryOrder(
    Map<String, dynamic> data, {
    Map<String, dynamic>? drugRiskFlags,
  }) async {
    lastData = data;
    lastDrugRiskFlags = drugRiskFlags;
    return nextReturn;
  }
}

void main() {
  group('PhaseTwoNotifier.createDeliveryOrder — P6 pass-through', () {
    test('passes drugRiskFlags to repository', () async {
      final repo = _FakePhaseTwoRepository();
      repo.nextReturn = DeliveryOrder(
        id: 'del-1',
        professionId: 'prof-1',
        orderId: 'order-1',
        recipientName: 'คนรับ',
        recipientPhone: '0812345678',
        deliveryAddress: '123 ถนนทดสอบ',
        createdAt: DateTime.parse('2026-07-09T10:00:00.000Z'),
        updatedAt: DateTime.parse('2026-07-09T10:00:00.000Z'),
      );
      final notifier = PhaseTwoNotifier(repo);

      final drugRiskFlags = DrugRiskScreeningService.buildDeliveryRiskFlags([
        DrugRiskScreeningResult(
          medicationName: 'Med',
          isBlocked: false,
          fdaRiskStatus: 'ND',
          overrideScope: 'organization',
        ),
      ]);

      final result = await notifier.createDeliveryOrder(
        {
          'profession_id': 'prof-1',
          'order_id': 'order-1',
          'recipient_name': 'คนรับ',
          'recipient_phone': '0812345678',
          'delivery_address': '123 ถนนทดสอบ',
        },
        drugRiskFlags: drugRiskFlags,
      );

      expect(result, isTrue);
      expect(repo.lastDrugRiskFlags?['drug_risk_flags']['has_override'], isTrue);
      expect(repo.lastDrugRiskFlags?['drug_risk_flags']['override_scope'], 'organization');
      expect(notifier.state.isSaving, isFalse);
      expect(notifier.state.errorMessage, isNull);
    });

    test('works without drugRiskFlags', () async {
      final repo = _FakePhaseTwoRepository();
      repo.nextReturn = DeliveryOrder(
        id: 'del-2',
        professionId: 'prof-1',
        orderId: 'order-1',
        recipientName: 'คนรับ',
        recipientPhone: '0812345678',
        deliveryAddress: '123 ถนนทดสอบ',
        createdAt: DateTime.parse('2026-07-09T10:00:00.000Z'),
        updatedAt: DateTime.parse('2026-07-09T10:00:00.000Z'),
      );
      final notifier = PhaseTwoNotifier(repo);

      final result = await notifier.createDeliveryOrder({
        'profession_id': 'prof-1',
        'order_id': 'order-1',
        'recipient_name': 'คนรับ',
        'recipient_phone': '0812345678',
        'delivery_address': '123 ถนนทดสอบ',
      });

      expect(result, isTrue);
      expect(repo.lastDrugRiskFlags, isNull);
      expect(notifier.state.errorMessage, isNull);
    });

    test('returns false when repository returns null', () async {
      final repo = _FakePhaseTwoRepository();
      repo.nextReturn = null;
      final notifier = PhaseTwoNotifier(repo);

      final result = await notifier.createDeliveryOrder({
        'profession_id': 'prof-1',
        'order_id': 'order-1',
        'recipient_name': 'คนรับ',
        'recipient_phone': '0812345678',
        'delivery_address': '123 ถนนทดสอบ',
      });

      expect(result, isFalse);
      expect(notifier.state.isSaving, isFalse);
    });
  });
}
