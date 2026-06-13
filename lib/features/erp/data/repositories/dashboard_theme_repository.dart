import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dashboard_theme.dart';
import '../models/theme_preset.dart';

/// Repository สำหรับจัดการ Dashboard Theme + Glassmorphism settings
class DashboardThemeRepository {
  final SupabaseClient _client;

  DashboardThemeRepository(this._client);

  // ========================
  // READ — Resolved Theme
  // ========================

  /// ดึง resolved theme (light/dark + glass settings) ของ user
  Future<DashboardTheme?> getResolvedTheme(String userId, String professionId) async {
    try {
      final response = await _client.rpc(
        'get_resolved_dashboard_theme',
        params: {'p_user_id': userId, 'p_profession_id': professionId},
      );
      if (response == null) return null;
      return DashboardTheme.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[ThemeRepo] getResolvedTheme error: $e');
      debugPrint('[ThemeRepo] stackTrace: $st');
      return null;
    }
  }

  /// บันทึก layout ของโมดูลใน dashboard
  Future<bool> saveModuleLayout(String userId, String professionId, Map<String, dynamic> moduleLayoutJson) async {
    try {
      await _client.rpc('save_dashboard_module_layout', params: {
        'p_user_id': userId,
        'p_profession_id': professionId,
        'p_module_layout_json': moduleLayoutJson,
      });
      return true;
    } catch (e) {
      debugPrint('[ThemeRepo] saveModuleLayout error: $e');
      return false;
    }
  }

  // ========================
  // READ — Glass Settings
  // ========================

  /// ดึง glass settings อย่างเดียว
  Future<Map<String, dynamic>?> getGlassSettings(String userId, String professionId) async {
    try {
      final response = await _client.rpc(
        'get_user_glass_settings',
        params: {'p_user_id': userId, 'p_profession_id': professionId},
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ThemeRepo] getGlassSettings error: $e');
      return null;
    }
  }

  // ========================
  // READ — All Presets
  // ========================

  /// ดึงรายการ theme presets ทั้งหมด
  Future<List<ThemePreset>> getAllPresets() async {
    try {
      final response = await _client.rpc('get_all_theme_presets');
      if (response == null) return [];
      final list = response as List<dynamic>;
      return list.map((e) => ThemePreset.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[ThemeRepo] getAllPresets error: $e');
      return [];
    }
  }

  // ========================
  // UPDATE — Theme Preset
  // ========================

  /// บันทึก preset ที่เลือก
  Future<bool> saveThemePreset(String userId, String professionId, String presetKey) async {
    try {
      await _client.rpc('save_dashboard_theme_preset', params: {
        'p_user_id': userId,
        'p_profession_id': professionId,
        'p_preset_key': presetKey,
      });
      return true;
    } catch (e) {
      debugPrint('[ThemeRepo] saveThemePreset error: $e');
      return false;
    }
  }

  // ========================
  // UPDATE — Custom Colors
  // ========================

  /// บันทึก custom colors (preset = 'custom')
  Future<bool> saveCustomColors(
    String userId,
    String professionId, {
    required String primary,
    required String accent,
    required String surface,
    required String textPrimary,
    required String textSecondary,
    required String error,
  }) async {
    try {
      await _client.rpc('save_dashboard_custom_colors', params: {
        'p_user_id': userId,
        'p_profession_id': professionId,
        'p_custom_primary': primary,
        'p_custom_accent': accent,
        'p_custom_surface': surface,
        'p_custom_text_primary': textPrimary,
        'p_custom_text_secondary': textSecondary,
        'p_custom_error': error,
      });
      return true;
    } catch (e) {
      debugPrint('[ThemeRepo] saveCustomColors error: $e');
      return false;
    }
  }

  // ========================
  // UPDATE — Toggle Dark Mode
  // ========================

  /// สลับ Light/Dark mode
  Future<bool> toggleDarkMode(String userId, String professionId) async {
    try {
      await _client.rpc('toggle_dark_mode', params: {
        'p_user_id': userId,
        'p_profession_id': professionId,
      });
      return true;
    } catch (e) {
      debugPrint('[ThemeRepo] toggleDarkMode error: $e');
      return false;
    }
  }

  // ========================
  // UPDATE — Glass Settings
  // ========================

  /// บันทึก glassmorphism settings
  Future<bool> saveGlassSettings(
    String userId,
    String professionId, {
    required double sidebarOpacity,
    required double cardsOpacity,
    required double dialogOpacity,
    required int blurLevel,
  }) async {
    try {
      await _client.rpc('save_user_glass_settings', params: {
        'p_user_id': userId,
        'p_profession_id': professionId,
        'p_sidebar_opacity': sidebarOpacity,
        'p_cards_opacity': cardsOpacity,
        'p_dialog_opacity': dialogOpacity,
        'p_blur_level': blurLevel,
      });
      return true;
    } catch (e) {
      debugPrint('[ThemeRepo] saveGlassSettings error: $e');
      return false;
    }
  }
}
