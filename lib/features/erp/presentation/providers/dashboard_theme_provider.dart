import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/dashboard_theme.dart';
import '../../data/models/theme_preset.dart';
import '../../data/repositories/dashboard_theme_repository.dart';

// ========================
// Repository Provider
// ========================

final dashboardThemeRepositoryProvider = Provider<DashboardThemeRepository>((ref) {
  return DashboardThemeRepository(Supabase.instance.client);
});

// ========================
// State
// ========================

class DashboardThemeState {
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final DashboardTheme? theme;
  final List<ThemePreset> presets;
  final String? userId;
  final String? professionId;

  const DashboardThemeState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.theme,
    this.presets = const [],
    this.userId,
    this.professionId,
  });

  DashboardThemeState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    DashboardTheme? theme,
    List<ThemePreset>? presets,
    String? userId,
    String? professionId,
  }) {
    final shouldClearError = clearError || ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return DashboardThemeState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      theme: theme ?? this.theme,
      presets: presets ?? this.presets,
      userId: userId ?? this.userId,
      professionId: professionId ?? this.professionId,
    );
  }

  /// มี theme หรือไม่
  bool get hasTheme => theme != null;

  /// กำลังโหลดครั้งแรก
  bool get isInitialLoading => isLoading && theme == null;
}

// ========================
// Notifier
// ========================

class DashboardThemeNotifier extends StateNotifier<DashboardThemeState> {
  final DashboardThemeRepository _repository;

  DashboardThemeNotifier(this._repository) : super(const DashboardThemeState());

  // ========================
  // Load Theme
  // ========================

  /// โหลด theme ของ user (ต้องเรียกหลัง login / เปิด ERP Dashboard)
  Future<void> loadTheme({required String userId, required String professionId}) async {
    debugPrint('[Theme] loadTheme — userId=$userId, professionId=$professionId');
    state = state.copyWith(isLoading: true, clearError: true, userId: userId, professionId: professionId);

    try {
      // โหลด theme + presets พร้อมกัน
      final results = await Future.wait([
        _repository.getResolvedTheme(userId, professionId),
        _repository.getAllPresets(),
      ]);

      final theme = results[0] as DashboardTheme?;
      final presets = results[1] as List<ThemePreset>;

      debugPrint('[Theme] loaded — isDark=${theme?.isDarkMode}, preset=${theme?.themePreset}, presets=${presets.length}');

      state = state.copyWith(
        isLoading: false,
        theme: theme,
        presets: presets,
      );
    } catch (e, st) {
      debugPrint('[Theme] loadTheme ERROR: $e');
      debugPrint('[Theme] stackTrace: $st');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลดธีมล้มเหลว: $e',
      );
    }
  }

  // ========================
  // Toggle Light / Dark
  // ========================

  /// สลับ Light/Dark mode
  Future<bool> toggleDarkMode() async {
    final userId = state.userId;
    final professionId = state.professionId;
    if (userId == null || professionId == null) {
      state = state.copyWith(errorMessage: 'ไม่พบ User ID หรือ Profession ID');
      return false;
    }

    state = state.copyWith(isSaving: true, clearError: true);

    // Optimistic update — เปลี่ยน UI ทันที
    final currentTheme = state.theme;
    if (currentTheme != null) {
      state = state.copyWith(
        theme: currentTheme.copyWith(isDarkMode: !currentTheme.isDarkMode),
      );
    }

    try {
      final success = await _repository.toggleDarkMode(userId, professionId);
      if (success) {
        // Reload theme เพื่อได้ resolvedPreset ใหม่
        await loadTheme(userId: userId, professionId: professionId);
        state = state.copyWith(isSaving: false);
        return true;
      } else {
        state = state.copyWith(isSaving: false, errorMessage: 'สลับโหมดไม่สำเร็จ');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'สลับโหมดล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // Change Preset
  // ========================

  /// เปลี่ยน theme preset (ใช้กับ Light mode)
  Future<bool> selectPreset(String presetKey) async {
    final userId = state.userId;
    final professionId = state.professionId;
    if (userId == null || professionId == null) return false;

    state = state.copyWith(isSaving: true, clearError: true);

    // Optimistic update
    final currentTheme = state.theme;
    if (currentTheme != null) {
      final selected = state.presets.firstWhere(
        (p) => p.presetKey == presetKey,
        orElse: () => currentTheme.resolvedPreset ?? state.presets.first,
      );
      state = state.copyWith(
        theme: currentTheme.copyWith(themePreset: presetKey, resolvedPreset: selected),
      );
    }

    try {
      final success = await _repository.saveThemePreset(userId, professionId, presetKey);
      if (success) {
        await loadTheme(userId: userId, professionId: professionId);
        state = state.copyWith(isSaving: false);
        return true;
      } else {
        state = state.copyWith(isSaving: false, errorMessage: 'บันทึกไม่สำเร็จ');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึกล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // Save Custom Colors
  // ========================

  /// บันทึก custom colors
  Future<bool> saveCustomColors({
    required String primary,
    required String accent,
    required String surface,
    required String textPrimary,
    required String textSecondary,
    required String error,
  }) async {
    final userId = state.userId;
    final professionId = state.professionId;
    if (userId == null || professionId == null) return false;

    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final success = await _repository.saveCustomColors(
        userId, professionId,
        primary: primary, accent: accent, surface: surface,
        textPrimary: textPrimary, textSecondary: textSecondary, error: error,
      );
      if (success) {
        await loadTheme(userId: userId, professionId: professionId);
        state = state.copyWith(isSaving: false);
        return true;
      } else {
        state = state.copyWith(isSaving: false, errorMessage: 'บันทึกไม่สำเร็จ');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึกล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // Glassmorphism — Optimistic
  // ========================

  /// ปรับ opacity แบบ optimistic (UI เปลี่ยนทันที ไม่ต้องรอ DB)
  void setOpacity(GlassSection section, double value) {
    final currentTheme = state.theme;
    if (currentTheme == null) return;

    switch (section) {
      case GlassSection.sidebar:
        state = state.copyWith(theme: currentTheme.copyWith(glassOpacitySidebar: value));
      case GlassSection.card:
        state = state.copyWith(theme: currentTheme.copyWith(glassOpacityCards: value));
      case GlassSection.dialog:
        state = state.copyWith(theme: currentTheme.copyWith(glassOpacityDialog: value));
    }
  }

  /// ปรับ blur level แบบ optimistic
  void setBlurLevel(int value) {
    final currentTheme = state.theme;
    if (currentTheme == null) return;
    state = state.copyWith(theme: currentTheme.copyWith(glassBlurLevel: value));
  }

  /// บันทึก glassmorphism settings ลง DB
  Future<bool> saveGlassSettings() async {
    final userId = state.userId;
    final professionId = state.professionId;
    final theme = state.theme;
    if (userId == null || professionId == null || theme == null) return false;

    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final success = await _repository.saveGlassSettings(
        userId, professionId,
        sidebarOpacity: theme.glassOpacitySidebar,
        cardsOpacity: theme.glassOpacityCards,
        dialogOpacity: theme.glassOpacityDialog,
        blurLevel: theme.glassBlurLevel,
      );
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึกล้มเหลว: $e');
      return false;
    }
  }

  /// คืนค่า glassmorphism เริ่มต้น (default)
  void resetGlassSettings() {
    final currentTheme = state.theme;
    if (currentTheme == null) return;
    state = state.copyWith(
      theme: currentTheme.copyWith(
        glassOpacitySidebar: 0.12,
        glassOpacityCards: 0.12,
        glassOpacityDialog: 0.12,
        glassBlurLevel: 12,
      ),
    );
  }
}

// ========================
// Global Provider
// ========================

final dashboardThemeProvider =
    StateNotifierProvider<DashboardThemeNotifier, DashboardThemeState>((ref) {
  final repo = ref.watch(dashboardThemeRepositoryProvider);
  return DashboardThemeNotifier(repo);
});
