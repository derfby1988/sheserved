import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/sources/health_data_source.dart';
import '../../data/sources/apple_health_source.dart';
import '../../data/sources/health_connect_source.dart';

// สถานะของการเชื่อมต่ออุปกรณ์
enum HealthConnectionState { initial, checking, connected, disconnected, error }

class HealthState {
  final HealthConnectionState connectionState;
  final String? errorMessage;
  final HealthDataSource? activeSource;
  final int todaySteps;
  final int? latestHeartRate;

  HealthState({
    this.connectionState = HealthConnectionState.initial,
    this.errorMessage,
    this.activeSource,
    this.todaySteps = 0,
    this.latestHeartRate,
  });

  HealthState copyWith({
    HealthConnectionState? connectionState,
    String? errorMessage,
    bool clearError = false,
    HealthDataSource? activeSource,
    int? todaySteps,
    int? latestHeartRate,
  }) {
    // ล้าง error อัตโนมัติเมื่อสถานะเปลี่ยนเป็นสถานะที่ไม่ใช่ error
    bool shouldClearError = clearError || (connectionState != null && connectionState != HealthConnectionState.error);

    return HealthState(
      connectionState: connectionState ?? this.connectionState,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      activeSource: activeSource ?? this.activeSource,
      todaySteps: todaySteps ?? this.todaySteps,
      latestHeartRate: latestHeartRate ?? this.latestHeartRate,
    );
  }
}

class HealthNotifier extends StateNotifier<HealthState> {
  HealthNotifier() : super(HealthState()) {
    _initSource();
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

    state = state.copyWith(connectionState: HealthConnectionState.checking, clearError: true);
    
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
        state = state.copyWith(connectionState: HealthConnectionState.connected, clearError: true);
        await fetchLiveHealthData();
      } else {
        state = state.copyWith(connectionState: HealthConnectionState.disconnected, clearError: true);
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

    state = state.copyWith(connectionState: HealthConnectionState.checking, clearError: true);
    
    try {
      final granted = await source.requestPermissions();
      if (granted) {
        state = state.copyWith(connectionState: HealthConnectionState.connected, clearError: true);
        await fetchLiveHealthData();
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
    );
  }

  Future<void> fetchLiveHealthData() async {
    if (state.connectionState != HealthConnectionState.connected) return;
    
    final source = state.activeSource;
    if (source == null) return;

    try {
      final steps = await source.fetchTodaySteps();
      final hr = await source.fetchLatestHeartRate();
      
      state = state.copyWith(todaySteps: steps, latestHeartRate: hr);
    } catch (e) {
      print('Error fetching health data: $e');
    }
  }
}

// สร้าง Global Provider
final healthProvider = StateNotifierProvider<HealthNotifier, HealthState>((ref) {
  return HealthNotifier();
});
