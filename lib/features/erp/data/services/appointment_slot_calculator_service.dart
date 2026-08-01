import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service คำนวณ Slot เวลาว่างของนัดหมาย (Group E - Phase 16)
class AppointmentSlotCalculatorService {
  final SupabaseClient _client;

  AppointmentSlotCalculatorService(this._client);

  /// คำนวณ Slot เวลาว่างในวันที่กำหนดสำหรับ Practitioner
  Future<List<DateTime>> calculateAvailableSlots({
    required String professionId,
    required String practitionerId,
    required DateTime targetDate,
    int slotDurationMinutes = 30,
  }) async {
    try {
      final dayOfWeek = targetDate.weekday % 7; // 0 = Sunday, 1 = Monday, ...

      // 1. ดึงเวลาทำงานปกติจาก service_schedules
      final schedulesRes = await _client
          .from('service_schedules')
          .select()
          .eq('profession_id', professionId)
          .eq('practitioner_id', practitionerId)
          .eq('day_of_week', dayOfWeek)
          .eq('is_active', true);

      if (schedulesRes.isEmpty) return [];

      // 2. ดึงเวลา Blockout (วันหยุด/ติดภารกิจ) ในวันที่กำหนด
      final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 0, 0, 0);
      final endOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59);

      final blockoutsRes = await _client
          .from('schedule_blockouts')
          .select()
          .eq('profession_id', professionId)
          .eq('practitioner_id', practitionerId)
          .gte('start_time', startOfDay.toIso8601String())
          .lte('end_time', endOfDay.toIso8601String());

      // 3. ดึงรายการนัดหมายที่มีอยู่แล้วในตาราง clinic_appointments
      final existingAppointmentsRes = await _client
          .from('clinic_appointments')
          .select()
          .eq('profession_id', professionId)
          .eq('staff_id', practitionerId)
          .gte('scheduled_at', startOfDay.toIso8601String())
          .lte('scheduled_at', endOfDay.toIso8601String())
          .neq('status', 'cancelled');

      final List<DateTime> availableSlots = [];

      for (var schedule in schedulesRes) {
        final startTimeParts = (schedule['start_time'] as String).split(':');
        final endTimeParts = (schedule['end_time'] as String).split(':');

        final schedStart = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          int.parse(startTimeParts[0]),
          int.parse(startTimeParts[1]),
        );

        final schedEnd = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          int.parse(endTimeParts[0]),
          int.parse(endTimeParts[1]),
        );

        var currentSlot = schedStart;
        while (currentSlot.add(Duration(minutes: slotDurationMinutes)).isBefore(schedEnd) ||
            currentSlot.add(Duration(minutes: slotDurationMinutes)).isAtSameMomentAs(schedEnd)) {
          final slotEnd = currentSlot.add(Duration(minutes: slotDurationMinutes));

          // Check blockouts
          bool isBlocked = blockoutsRes.any((b) {
            final bStart = DateTime.parse(b['start_time'] as String);
            final bEnd = DateTime.parse(b['end_time'] as String);
            return currentSlot.isBefore(bEnd) && slotEnd.isAfter(bStart);
          });

          // Check existing appointments
          bool isBooked = existingAppointmentsRes.any((a) {
            final apptStart = DateTime.parse(a['scheduled_at'] as String);
            final duration = a['duration_minutes'] as int? ?? slotDurationMinutes;
            final apptEnd = apptStart.add(Duration(minutes: duration));
            return currentSlot.isBefore(apptEnd) && slotEnd.isAfter(apptStart);
          });

          if (!isBlocked && !isBooked) {
            availableSlots.add(currentSlot);
          }

          currentSlot = currentSlot.add(Duration(minutes: slotDurationMinutes));
        }
      }

      return availableSlots;
    } catch (e) {
      debugPrint('[SlotCalculator] error: $e');
      return [];
    }
  }
}
