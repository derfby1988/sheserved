import 'dart:io';
import 'package:health/health.dart';
import 'health_data_source.dart';
import '../models/device_health_metric.dart';

class HealthConnectSource implements HealthDataSource {
  final Health _health = Health();

  // ขอสิทธิ์ทุก Data Type ที่ Health Connect รองรับ
  final List<HealthDataType> _allTypes = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.WEIGHT,
    HealthDataType.HEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.EXERCISE_TIME,
  ];

  @override
  String get sourceName => 'Health Connect';

  @override
  Future<bool> isAvailable() async => Platform.isAndroid;

  @override
  Future<bool> requestPermissions() async {
    try {
      Health().configure();
      return await _health.requestAuthorization(_allTypes);
    } catch (e) {
      print('Health Connect requestPermissions error: $e');
      return false;
    }
  }

  @override
  Future<bool> hasPermissions() async {
    try {
      return await _health.hasPermissions(_allTypes) ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> revokeAccess() async {
    await _health.revokePermissions();
  }

  // ---- Quick Summary Methods ----

  @override
  Future<int> fetchTodaySteps() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    try {
      return await _health.getTotalStepsInInterval(midnight, now) ?? 0;
    } catch (e) {
      print('fetchTodaySteps error: $e');
      return 0;
    }
  }

  @override
  Future<int?> fetchLatestHeartRate() async {
    final now = DateTime.now();
    final since = now.subtract(const Duration(hours: 24));
    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: since,
        endTime: now,
      );
      if (data.isEmpty) return null;
      data.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      return (data.first.value as NumericHealthValue).numericValue.toInt();
    } catch (e) {
      print('fetchLatestHeartRate error: $e');
      return null;
    }
  }

  @override
  Future<int?> fetchLastSleepDuration() async {
    final now = DateTime.now();
    final since = now.subtract(const Duration(hours: 24));
    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_SESSION],
        startTime: since,
        endTime: now,
      );
      if (data.isEmpty) return null;
      int total = 0;
      for (var d in data) {
        total += (d.value as NumericHealthValue).numericValue.toInt();
      }
      return total > 0 ? total : null;
    } catch (e) {
      print('fetchLastSleepDuration error: $e');
      return null;
    }
  }

  @override
  Future<double?> fetchTodayActiveCalories() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: midnight,
        endTime: now,
      );
      if (data.isEmpty) return null;
      double total = 0;
      for (var d in data) {
        total += (d.value as NumericHealthValue).numericValue.toDouble();
      }
      return total > 0 ? total : null;
    } catch (e) {
      print('fetchTodayActiveCalories error: $e');
      return null;
    }
  }

  @override
  Future<double?> fetchTodayDistance() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.DISTANCE_DELTA],
        startTime: midnight,
        endTime: now,
      );
      if (data.isEmpty) return null;
      double total = 0;
      for (var d in data) {
        total += (d.value as NumericHealthValue).numericValue.toDouble();
      }
      return total > 0 ? total : null;
    } catch (e) {
      print('fetchTodayDistance error: $e');
      return null;
    }
  }

  @override
  Future<double?> fetchLatestBloodOxygen() async {
    final now = DateTime.now();
    final since = now.subtract(const Duration(hours: 24));
    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.BLOOD_OXYGEN],
        startTime: since,
        endTime: now,
      );
      if (data.isEmpty) return null;
      data.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      return (data.first.value as NumericHealthValue).numericValue.toDouble();
    } catch (e) {
      print('fetchLatestBloodOxygen error: $e');
      return null;
    }
  }

  @override
  Future<double?> fetchLatestHRV() async {
    final now = DateTime.now();
    final since = now.subtract(const Duration(hours: 24));
    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
        startTime: since,
        endTime: now,
      );
      if (data.isEmpty) return null;
      data.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      return (data.first.value as NumericHealthValue).numericValue.toDouble();
    } catch (e) {
      print('fetchLatestHRV error: $e');
      return null;
    }
  }

  @override
  Future<int?> fetchTodayExerciseTime() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.EXERCISE_TIME],
        startTime: midnight,
        endTime: now,
      );
      if (data.isEmpty) return null;
      int total = 0;
      for (var d in data) {
        total += (d.value as NumericHealthValue).numericValue.toInt();
      }
      return total > 0 ? total : null;
    } catch (e) {
      print('fetchTodayExerciseTime error: $e');
      return null;
    }
  }

  // ---- Full Sync Method ----

  @override
  Future<List<DeviceHealthMetric>> fetchAllMetrics({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final List<DeviceHealthMetric> metrics = [];

    // --- 1. ก้าวเดิน (Steps) ---
    try {
      final steps = await _health.getTotalStepsInInterval(from, to);
      if (steps != null && steps > 0) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'steps',
          value: steps,
          unit: 'count',
          measuredAt: from,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync steps error: $e'); }

    // --- 2. อัตราการเต้นหัวใจ (Heart Rate) ---
    try {
      final hrData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: from,
        endTime: to,
      );
      for (var d in hrData) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'heart_rate',
          value: (d.value as NumericHealthValue).numericValue,
          unit: 'bpm',
          measuredAt: d.dateTo,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync heart_rate error: $e'); }

    // --- 3. ระยะทาง (Distance Delta) ---
    try {
      final distData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.DISTANCE_DELTA],
        startTime: from,
        endTime: to,
      );
      for (var d in distData) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'distance',
          value: (d.value as NumericHealthValue).numericValue,
          unit: 'meters',
          measuredAt: d.dateTo,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync distance error: $e'); }

    // --- 4. แคลอรี่ (Active Energy Burned) ---
    try {
      final calData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: from,
        endTime: to,
      );
      for (var d in calData) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'active_calories',
          value: (d.value as NumericHealthValue).numericValue,
          unit: 'kcal',
          measuredAt: d.dateTo,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync active_calories error: $e'); }

    // --- 5. การนอนหลับ (Sleep Session) ---
    try {
      final sleepData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_SESSION],
        startTime: from,
        endTime: to,
      );
      for (var d in sleepData) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'sleep_session',
          value: (d.value as NumericHealthValue).numericValue,
          unit: 'minutes',
          measuredAt: d.dateFrom,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync sleep error: $e'); }

    // --- 6. ออกซิเจนในเลือด (SpO2) ---
    try {
      final spo2Data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.BLOOD_OXYGEN],
        startTime: from,
        endTime: to,
      );
      for (var d in spo2Data) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'blood_oxygen',
          value: (d.value as NumericHealthValue).numericValue,
          unit: '%',
          measuredAt: d.dateTo,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync SpO2 error: $e'); }

    // --- 7. HRV ---
    try {
      final hrvData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
        startTime: from,
        endTime: to,
      );
      for (var d in hrvData) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'hrv_rmssd',
          value: (d.value as NumericHealthValue).numericValue,
          unit: 'ms',
          measuredAt: d.dateTo,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync HRV error: $e'); }

    // --- 8. ระยะเวลาออกกำลังกาย ---
    try {
      final exData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.EXERCISE_TIME],
        startTime: from,
        endTime: to,
      );
      for (var d in exData) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'exercise_time',
          value: (d.value as NumericHealthValue).numericValue,
          unit: 'minutes',
          measuredAt: d.dateTo,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync exercise_time error: $e'); }

    // --- 9. น้ำหนัก (Weight) ---
    try {
      final weightData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: from,
        endTime: to,
      );
      for (var d in weightData) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'weight',
          value: (d.value as NumericHealthValue).numericValue,
          unit: 'kg',
          measuredAt: d.dateTo,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync weight error: $e'); }

    // --- 10. มวลไขมัน (Body Fat) ---
    try {
      final bfData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.BODY_FAT_PERCENTAGE],
        startTime: from,
        endTime: to,
      );
      for (var d in bfData) {
        metrics.add(DeviceHealthMetric(
          userId: userId,
          metricType: 'body_fat_percentage',
          value: (d.value as NumericHealthValue).numericValue,
          unit: '%',
          measuredAt: d.dateTo,
          sourceName: sourceName,
        ));
      }
    } catch (e) { print('Sync body_fat error: $e'); }

    return metrics;
  }
}
