import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/sources/health_data_source.dart';
import '../../data/sources/apple_health_source.dart';
import '../../data/sources/health_connect_source.dart';
import '../../data/repositories/health_repository.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../auth/data/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// สถานะของการเชื่อมต่ออุปกรณ์
enum HealthConnectionState { initial, checking, connected, disconnected, error }

// Key สำหรับเก็บเวลา Sync ล่าสุดใน SharedPreferences
const _kLastSyncKey = 'health_last_sync_at';
// ทุก 1 ชั่วโมง ค่อย Sync ใหม่
const _kSyncIntervalHours = 1;

class HealthState {
  final HealthConnectionState connectionState;
  final String? errorMessage;
  final HealthDataSource? activeSource;

  // ---- Metrics (แสดงใน UI) ----
  final int todaySteps;
  final int? latestHeartRate; // bpm
  final int? lastSleepDuration; // นาที
  final double? todayActiveCalories; // kcal
  final double? todayDistance; // เมตร
  final double? latestBloodOxygen; // %
  final double? latestHRV; // ms
  final int? todayExerciseTime; // นาที
  final int healthScore;

  // ---- Sync State ----
  final bool isSyncing;
  final DateTime? lastSyncedAt;

  HealthState({
    this.connectionState = HealthConnectionState.initial,
    this.errorMessage,
    this.activeSource,
    this.todaySteps = 0,
    this.latestHeartRate,
    this.lastSleepDuration,
    this.todayActiveCalories,
    this.todayDistance,
    this.latestBloodOxygen,
    this.latestHRV,
    this.todayExerciseTime,
    this.healthScore = 0,
    this.isSyncing = false,
    this.lastSyncedAt,
  });

  HealthState copyWith({
    HealthConnectionState? connectionState,
    String? errorMessage,
    bool clearError = false,
    HealthDataSource? activeSource,
    int? todaySteps,
    int? latestHeartRate,
    int? lastSleepDuration,
    double? todayActiveCalories,
    double? todayDistance,
    double? latestBloodOxygen,
    double? latestHRV,
    int? todayExerciseTime,
    int? healthScore,
    bool? isSyncing,
    DateTime? lastSyncedAt,
  }) {
    final shouldClearError =
        clearError ||
        (connectionState != null &&
            connectionState != HealthConnectionState.error);

    return HealthState(
      connectionState: connectionState ?? this.connectionState,
      errorMessage: shouldClearError
          ? null
          : (errorMessage ?? this.errorMessage),
      activeSource: activeSource ?? this.activeSource,
      todaySteps: todaySteps ?? this.todaySteps,
      latestHeartRate: latestHeartRate ?? this.latestHeartRate,
      lastSleepDuration: lastSleepDuration ?? this.lastSleepDuration,
      todayActiveCalories: todayActiveCalories ?? this.todayActiveCalories,
      todayDistance: todayDistance ?? this.todayDistance,
      latestBloodOxygen: latestBloodOxygen ?? this.latestBloodOxygen,
      latestHRV: latestHRV ?? this.latestHRV,
      todayExerciseTime: todayExerciseTime ?? this.todayExerciseTime,
      healthScore: healthScore ?? this.healthScore,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class HealthNotifier extends StateNotifier<HealthState> {
  HealthNotifier() : super(HealthState()) {
    _initSource();
    loadMetricsFromDatabase();
  }

  HealthRepository get _repo => ServiceLocator.get<HealthRepository>();

  Future<void> loadMetricsFromDatabase() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;

    try {
      final todayRes = await _repo.getLatestDailyMetrics(userId);

      // โหลด BMI จาก profile ของผู้ใช้
      final userRepo = ServiceLocator.get<UserRepository>();
      final profile = await userRepo.getConsumerProfile(userId);
      double bmi = 21.4; // default
      if (profile != null && profile.healthInfo != null) {
        final rawBmi = profile.healthInfo!['bmi'];
        if (rawBmi is num) {
          bmi = rawBmi.toDouble();
        } else if (rawBmi is String) {
          bmi = double.tryParse(rawBmi) ?? 21.4;
        }
      }

      // 1. Body Composition (30 points max)
      double bodyScore = 30.0;
      if (bmi < 18.5) {
        bodyScore -= (18.5 - bmi) * 3;
      } else if (bmi >= 23 && bmi < 30) {
        bodyScore -= (bmi - 22.9) * 2;
      } else if (bmi >= 30) {
        bodyScore -= (bmi - 22.9) * 4;
      }
      bodyScore = bodyScore.clamp(0.0, 30.0);

      final steps =
          (todayRes['todaySteps'] != null &&
              (todayRes['todaySteps'] as int) > 0)
          ? todayRes['todaySteps'] as int
          : 8000;
      final calories =
          (todayRes['todayActiveCalories'] != null &&
              (todayRes['todayActiveCalories'] as double) > 0)
          ? todayRes['todayActiveCalories'] as double
          : 300.0;

      // 2. Activity (30 points max)
      double stepsScore = (steps / 8000.0) * 15.0;
      stepsScore = stepsScore.clamp(0.0, 15.0);

      double calScore = (calories / 300.0) * 15.0;
      calScore = calScore.clamp(0.0, 15.0);

      final double activityScore = stepsScore + calScore;

      // 3. Cardio (20 points max)
      final heartRate =
          (todayRes['latestHeartRate'] != null &&
              (todayRes['latestHeartRate'] as int) > 0)
          ? todayRes['latestHeartRate'] as int
          : 72;
      final hrv =
          (todayRes['latestHRV'] != null &&
              (todayRes['latestHRV'] as double) > 0)
          ? todayRes['latestHRV'] as double
          : 40.0;

      double hrScore = 10.0;
      if (heartRate < 60) {
        hrScore -= (60 - heartRate) * 0.5;
      } else if (heartRate > 80) {
        hrScore -= (heartRate - 80) * 0.5;
      }
      hrScore = hrScore.clamp(0.0, 10.0);

      double hrvScore = (hrv / 40.0) * 10.0;
      hrvScore = hrvScore.clamp(0.0, 10.0);

      final double cardioScore = hrScore + hrvScore;

      // 4. Sleep (20 points max)
      final sleepMins =
          (todayRes['lastSleepDuration'] != null &&
              (todayRes['lastSleepDuration'] as int) > 0)
          ? todayRes['lastSleepDuration'] as int
          : 420;
      double sleepScore = (sleepMins / 420.0) * 20.0;
      sleepScore = sleepScore.clamp(0.0, 20.0);

      final double totalCalculated =
          bodyScore + activityScore + cardioScore + sleepScore;
      final int calculatedScore = totalCalculated.round().clamp(0, 100);

      if (todayRes.isNotEmpty) {
        state = state.copyWith(
          todaySteps: todayRes['todaySteps'] as int,
          todayActiveCalories: todayRes['todayActiveCalories'] as double?,
          latestHeartRate: todayRes['latestHeartRate'] as int?,
          latestHRV: todayRes['latestHRV'] as double?,
          lastSleepDuration: todayRes['lastSleepDuration'] as int?,
          healthScore: calculatedScore,
        );
        print(
          '[HealthNotifier] Loaded latest database metrics successfully. Score: $calculatedScore%',
        );

        // เซฟคะแนนกลับเข้า Supabase
        if (profile != null && profile.healthInfo != null) {
          final healthInfo = profile.healthInfo!;
          if ((healthInfo['health_score'] as num?)?.toInt() !=
              calculatedScore) {
            final updatedInfo = {
              ...healthInfo,
              'health_score': calculatedScore,
            };
            await Supabase.instance.client
                .from('consumer_profiles')
                .update({
                  'health_info': updatedInfo,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('user_id', userId);
            print(
              '[HealthNotifier] Updated user dynamic health score in DB to $calculatedScore%',
            );
          }
        }
      }
    } catch (e) {
      print('loadMetricsFromDatabase error: $e');
    }
  }

  Future<void> recalculateScoreWithLiveState() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;

    try {
      final userRepo = ServiceLocator.get<UserRepository>();
      final profile = await userRepo.getConsumerProfile(userId);

      double bmi = 21.4; // default
      if (profile != null && profile.healthInfo != null) {
        final rawBmi = profile.healthInfo!['bmi'];
        if (rawBmi is num) {
          bmi = rawBmi.toDouble();
        } else if (rawBmi is String) {
          bmi = double.tryParse(rawBmi) ?? 21.4;
        }
      }

      // 1. Body Composition (30 points max)
      double bodyScore = 30.0;
      if (bmi < 18.5) {
        bodyScore -= (18.5 - bmi) * 3;
      } else if (bmi >= 23 && bmi < 30) {
        bodyScore -= (bmi - 22.9) * 2;
      } else if (bmi >= 30) {
        bodyScore -= (bmi - 22.9) * 4;
      }
      bodyScore = bodyScore.clamp(0.0, 30.0);

      final steps = (state.todaySteps > 0) ? state.todaySteps : 8000;
      final calories =
          (state.todayActiveCalories != null && state.todayActiveCalories! > 0)
          ? state.todayActiveCalories!
          : 300.0;

      // 2. Activity (30 points max)
      double stepsScore = (steps / 8000.0) * 15.0;
      stepsScore = stepsScore.clamp(0.0, 15.0);

      double calScore = (calories / 300.0) * 15.0;
      calScore = calScore.clamp(0.0, 15.0);

      final double activityScore = stepsScore + calScore;

      // 3. Cardio (20 points max)
      final heartRate =
          (state.latestHeartRate != null && state.latestHeartRate! > 0)
          ? state.latestHeartRate!
          : 72;
      final hrv = (state.latestHRV != null && state.latestHRV! > 0)
          ? state.latestHRV!
          : 40.0;

      double hrScore = 10.0;
      if (heartRate < 60) {
        hrScore -= (60 - heartRate) * 0.5;
      } else if (heartRate > 80) {
        hrScore -= (heartRate - 80) * 0.5;
      }
      hrScore = hrScore.clamp(0.0, 10.0);

      double hrvScore = (hrv / 40.0) * 10.0;
      hrvScore = hrvScore.clamp(0.0, 10.0);

      final double cardioScore = hrScore + hrvScore;

      // 4. Sleep (20 points max)
      final sleepMins =
          (state.lastSleepDuration != null && state.lastSleepDuration! > 0)
          ? state.lastSleepDuration!
          : 420;
      double sleepScore = (sleepMins / 420.0) * 20.0;
      sleepScore = sleepScore.clamp(0.0, 20.0);

      final double totalCalculated =
          bodyScore + activityScore + cardioScore + sleepScore;
      final int calculatedScore = totalCalculated.round().clamp(0, 100);

      state = state.copyWith(healthScore: calculatedScore);

      // เซฟคะแนนกลับเข้า Supabase
      if (profile != null && profile.healthInfo != null) {
        final healthInfo = profile.healthInfo!;
        if ((healthInfo['health_score'] as num?)?.toInt() != calculatedScore) {
          final updatedInfo = {...healthInfo, 'health_score': calculatedScore};
          await Supabase.instance.client
              .from('consumer_profiles')
              .update({
                'health_info': updatedInfo,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('user_id', userId);
          print(
            '[HealthNotifier] Live updated user dynamic health score in DB to $calculatedScore%',
          );
        }
      }
    } catch (e) {
      print('recalculateScoreWithLiveState error: $e');
    }
  }

  void _initSource() {
    HealthDataSource source;
    if (Platform.isIOS) {
      source = AppleHealthSource();
    } else if (Platform.isAndroid) {
      source = HealthConnectSource();
    } else {
      state = state.copyWith(
        connectionState: HealthConnectionState.error,
        errorMessage: 'OS not supported',
      );
      return;
    }
    state = state.copyWith(activeSource: source);
    checkCurrentPermissions();
  }

  Future<void> checkCurrentPermissions() async {
    final source = state.activeSource;
    if (source == null) return;

    state = state.copyWith(
      connectionState: HealthConnectionState.checking,
      clearError: true,
    );
    try {
      final isAvail = await source.isAvailable();
      if (!isAvail) {
        state = state.copyWith(
          connectionState: HealthConnectionState.error,
          errorMessage: '${source.sourceName} is not available on this device.',
        );
        return;
      }
      final hasPerm = await source.hasPermissions();
      if (hasPerm) {
        state = state.copyWith(
          connectionState: HealthConnectionState.connected,
          clearError: true,
        );
        await fetchLiveHealthData();
        await _triggerSyncIfNeeded(); // ← Sync ขึ้น Supabase ถ้าถึงเวลา
      } else {
        state = state.copyWith(
          connectionState: HealthConnectionState.disconnected,
          clearError: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        connectionState: HealthConnectionState.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> requestAccess() async {
    final source = state.activeSource;
    if (source == null) return;

    state = state.copyWith(
      connectionState: HealthConnectionState.checking,
      clearError: true,
    );
    try {
      final granted = await source.requestPermissions();
      if (granted) {
        state = state.copyWith(
          connectionState: HealthConnectionState.connected,
          clearError: true,
        );
        await fetchLiveHealthData();
        await _triggerSyncIfNeeded(); // ← Sync ครั้งแรกหลังเชื่อมต่อสำเร็จ
      } else {
        state = state.copyWith(
          connectionState: HealthConnectionState.disconnected,
          errorMessage: 'Permission denied by user.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        connectionState: HealthConnectionState.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> disconnect() async {
    final source = state.activeSource;
    if (source != null) {
      await source.revokeAccess();
    }
    state = state.copyWith(
      connectionState: HealthConnectionState.disconnected,
      clearError: true,
      todaySteps: 0,
      latestHeartRate: null,
      lastSleepDuration: null,
    );
  }

  /// ดึงข้อมูลสรุปสดๆ ทุก Type มาแสดงใน UI (ดึงพร้อมกันทั้งหมด)
  Future<void> fetchLiveHealthData() async {
    if (state.connectionState != HealthConnectionState.connected) return;
    final source = state.activeSource;
    if (source == null) return;

    try {
      // ดึงข้อมูลทั้งหมดพร้อมกัน (Parallel) เพื่อความเร็ว
      final results = await Future.wait([
        source.fetchTodaySteps(),
        source.fetchLatestHeartRate(),
        source.fetchLastSleepDuration(),
        source.fetchTodayActiveCalories(),
        source.fetchTodayDistance(),
        source.fetchLatestBloodOxygen(),
        source.fetchLatestHRV(),
        source.fetchTodayExerciseTime(),
      ]);

      state = state.copyWith(
        todaySteps: results[0] as int,
        latestHeartRate: results[1] as int?,
        lastSleepDuration: results[2] as int?,
        todayActiveCalories: results[3] as double?,
        todayDistance: results[4] as double?,
        latestBloodOxygen: results[5] as double?,
        latestHRV: results[6] as double?,
        todayExerciseTime: results[7] as int?,
      );
      await recalculateScoreWithLiveState();
    } catch (e) {
      print('fetchLiveHealthData error: $e');
    }
  }

  /// ตรวจสอบว่าควร Sync หรือไม่ (Delta Sync: ดึงข้อมูลที่ยังไม่เคย Sync)
  Future<void> _triggerSyncIfNeeded() async {
    if (state.isSyncing) return;

    final prefs = await SharedPreferences.getInstance();
    final lastSyncRaw = prefs.getString(_kLastSyncKey);
    final lastSync = lastSyncRaw != null
        ? DateTime.tryParse(lastSyncRaw)
        : null;
    final now = DateTime.now();

    // ถ้ายังไม่เคย Sync หรือผ่านมาเกิน interval ที่กำหนด
    final shouldSync =
        lastSync == null ||
        now.difference(lastSync).inHours >= _kSyncIntervalHours;

    if (shouldSync) {
      // ดึงข้อมูลตั้งแต่ last sync (หรือย้อน 7 วันถ้าครั้งแรก)
      final from = lastSync ?? now.subtract(const Duration(days: 7));
      await _syncToDatabase(from: from, to: now);
    }
  }

  /// ซิงค์ข้อมูลทั้งหมดขึ้น Supabase (Batch Insert)
  Future<void> _syncToDatabase({
    required DateTime from,
    required DateTime to,
  }) async {
    final source = state.activeSource;
    final userId = AuthService.instance.currentUser?.id;
    if (source == null || userId == null) return;

    state = state.copyWith(isSyncing: true);

    try {
      // 1. ดึงข้อมูลครบทุก type จาก OS
      final metrics = await source.fetchAllMetrics(
        userId: userId,
        from: from,
        to: to,
      );

      if (metrics.isNotEmpty) {
        // 2. Batch Insert เข้า Supabase
        await _repo.syncDeviceMetrics(metrics);
        print(
          '[HealthSync] ✅ Synced ${metrics.length} records from ${source.sourceName}',
        );

        // 3. ถ้ามีข้อมูลน้ำหนักใหม่จากตาชั่ง → อัปเดต consumer_profiles ด้วย
        final weightMetrics = metrics.where((m) => m.metricType == 'weight');
        if (weightMetrics.isNotEmpty) {
          weightMetrics.toList().sort(
            (a, b) => b.measuredAt.compareTo(a.measuredAt),
          );
          final latestWeight = weightMetrics.first.value.toDouble();
          await _repo.updateWeightFromDevice(
            userId: userId,
            weight: latestWeight,
            sourceName: source.sourceName,
          );
          print(
            '[HealthSync] ✅ Updated weight to $latestWeight kg in consumer_profiles',
          );
        }
      }

      // 4. บันทึกเวลา Sync ล่าสุด
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastSyncKey, to.toIso8601String());

      if (mounted) {
        state = state.copyWith(isSyncing: false, lastSyncedAt: to);
        await loadMetricsFromDatabase();
      }
    } catch (e) {
      print('[HealthSync] ❌ Sync error: $e');
      if (mounted) {
        state = state.copyWith(isSyncing: false);
      }
    }
  }

  /// บังคับ Sync ทันที (ให้ผู้ใช้กด Manual Sync ได้)
  Future<void> forceSync() async {
    if (state.connectionState != HealthConnectionState.connected) return;
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 7)); // Sync ย้อนหลัง 7 วัน
    await _syncToDatabase(from: from, to: now);
  }
}

// สร้าง Global Provider
final healthProvider = StateNotifierProvider<HealthNotifier, HealthState>((
  ref,
) {
  return HealthNotifier();
});
