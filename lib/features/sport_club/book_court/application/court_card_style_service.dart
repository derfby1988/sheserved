import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/court_card_3d_params.dart';
import '../domain/court_card_style.dart';

/// Reads/writes the shared Book Court card style.
///
/// The value lives in `app_settings` under [preferenceKey] as
/// `{"style": "<wireValue>"}` — the same admin-config table the donation and
/// video panels already write to, so no migration is needed.
///
/// Every failure path is non-fatal: the in-memory [style] keeps the last
/// known value (defaulting to [CourtCardStyle.fallback]) so the feed always
/// renders, and [select] reports whether the choice reached the server.
class CourtCardStyleService {
  CourtCardStyleService._();

  static final CourtCardStyleService instance = CourtCardStyleService._();

  static const String preferenceKey = 'court_card_style';

  final ValueNotifier<CourtCardStyle> style = ValueNotifier<CourtCardStyle>(
    CourtCardStyle.fallback,
  );

  final ValueNotifier<CourtCard3DParams> params3d =
      ValueNotifier<CourtCard3DParams>(CourtCard3DParams.defaults);

  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Loads the stored style once per session unless [force] is set.
  Future<void> load({SupabaseClient? client, bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    final stored = await _read(client);
    if (stored != null) {
      style.value = stored.$1;
      params3d.value = stored.$2;
    }
  }

  /// Applies [next] immediately and persists it for every device.
  ///
  /// Returns true when the value was written to `app_settings`; false means
  /// the card style changed on this device only.
  Future<bool> select(CourtCardStyle next, {SupabaseClient? client}) async {
    style.value = next;
    return _persist(client);
  }

  /// Updates only the 3D parameters (locally + persist).
  Future<bool> update3DParams(
    CourtCard3DParams next, {
    SupabaseClient? client,
  }) async {
    params3d.value = next;
    return _persist(client);
  }

  Future<bool> _persist(SupabaseClient? client) async {
    try {
      await _client(client)
          .from('app_settings')
          .upsert({
            'key': preferenceKey,
            'value': {
              'style': style.value.wireValue,
              'params3d': params3d.value.toJson(),
            },
            'description': 'Book Court venue card style (21.7.22)',
          })
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<(CourtCardStyle, CourtCard3DParams)?> _read(
    SupabaseClient? client,
  ) async {
    try {
      final row = await _client(client)
          .from('app_settings')
          .select('value')
          .eq('key', preferenceKey)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      return parseSettingsWithParams(row?['value']);
    } catch (_) {
      return null;
    }
  }

  SupabaseClient _client(SupabaseClient? client) =>
      client ?? Supabase.instance.client;

  /// Accepts the stored JSONB in any of the shapes it may arrive in.
  static CourtCardStyle? parseSettingsValue(Object? value) {
    if (value is Map) {
      final wire = value['style']?.toString();
      if (wire != null) {
        return CourtCardStyle.fromWire(wire);
      }
      return null;
    }
    if (value is String && value.isNotEmpty) {
      return CourtCardStyle.fromWire(value);
    }
    return null;
  }

  /// Parses both style and 3D params from stored JSONB.
  static (CourtCardStyle, CourtCard3DParams)? parseSettingsWithParams(
    Object? value,
  ) {
    final style = parseSettingsValue(value);
    if (style == null) return null;
    final p3d = value is Map
        ? CourtCard3DParams.fromJson(value['params3d'])
        : CourtCard3DParams.defaults;
    return (style, p3d);
  }
}
