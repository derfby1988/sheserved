import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/consultation/data/models/consultation_request_model.dart';
import 'package:sheserved/features/consultation/presentation/logic/consultation_guard.dart';

ConsultationRequestModel _request(
  String id,
  String status,
  DateTime createdAt,
) => ConsultationRequestModel(
  id: id,
  userId: 'patient-1',
  packageName: 'Consultation',
  price: 495,
  status: status,
  createdAt: createdAt,
  updatedAt: createdAt,
);

void main() {
  group('ConsultationGuard', () {
    test('prefers the in-progress case over a newer pending duplicate', () {
      final pending = _request(
        'pending-new',
        'pending',
        DateTime.utc(2026, 9, 24),
      );
      final active = _request(
        'in-progress-old',
        'in_progress',
        DateTime.utc(2026, 9, 20),
      );

      expect(
        ConsultationGuard.selectActiveConsultation([pending, active]),
        same(active),
      );
    });

    test('uses the newest pending case if none is in progress', () {
      final newest = _request(
        'pending-new',
        'pending',
        DateTime.utc(2026, 9, 24),
      );
      final older = _request(
        'pending-old',
        'pending',
        DateTime.utc(2026, 9, 20),
      );

      expect(
        ConsultationGuard.selectActiveConsultation([newest, older]),
        same(newest),
      );
    });

    test('history puts the in-progress room before newer pending requests', () {
      final completed = _request(
        'completed-new',
        'completed',
        DateTime.utc(2026, 9, 25),
      );
      final pending = _request(
        'pending-new',
        'pending',
        DateTime.utc(2026, 9, 24),
      );
      final active = _request(
        'in-progress-old',
        'in_progress',
        DateTime.utc(2026, 9, 20),
      );

      final sorted = ConsultationGuard.prioritizePatientHistory([
        completed,
        pending,
        active,
      ]);

      expect(sorted.map((request) => request.id), [
        'in-progress-old',
        'pending-new',
        'completed-new',
      ]);
    });
  });
}
