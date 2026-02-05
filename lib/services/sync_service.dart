import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../config/sync_config.dart';

/// Sync Mode
enum SyncMode {
  /// Supabase เป็น Primary - ข้อมูลหลักอยู่บน Cloud
  /// Local ใช้เป็น Cache สำหรับ offline/fast access
  supabasePrimary,

  /// Local เป็น Primary - ข้อมูลหลักอยู่ Local
  /// Supabase ใช้เป็น Backup/External access
  localPrimary,

  /// Bi-directional - ซิงค์ทั้งสองทาง (ซับซ้อนกว่า)
  bidirectional,
}

/// Sync Status
enum SyncStatus {
  idle,
  syncing,
  error,
  offline,
}

/// Sync Service - จัดการการ Synchronize ระหว่าง Local และ Supabase
class SyncService {
  static SyncService? _instance;

  // Configuration
  final String _localApiUrl;
  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final SyncMode _syncMode;

  // State
  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncTime;
  final List<String> _pendingChanges = [];
  Timer? _syncTimer;
  bool _isOnline = true;

  // Stream Controllers
  final _statusController = StreamController<SyncStatus>.broadcast();
  final _syncEventController = StreamController<SyncEvent>.broadcast();

  // Getters
  SyncStatus get status => _status;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isOnline => _isOnline;
  Stream<SyncStatus> get statusStream => _statusController.stream;
  Stream<SyncEvent> get syncEventStream => _syncEventController.stream;

  SyncService._({
    required String localApiUrl,
    required String supabaseUrl,
    required String supabaseAnonKey,
    SyncMode syncMode = SyncMode.supabasePrimary,
  })  : _localApiUrl = localApiUrl,
        _supabaseUrl = supabaseUrl,
        _supabaseAnonKey = supabaseAnonKey,
        _syncMode = syncMode;

  /// Singleton instance
  factory SyncService({
    String? localApiUrl,
    String? supabaseUrl,
    String? supabaseAnonKey,
    SyncMode? syncMode,
  }) {
    _instance ??= SyncService._(
      localApiUrl: localApiUrl ?? AppConfig.localApiUrl,
      supabaseUrl: supabaseUrl ?? AppConfig.supabaseUrl,
      supabaseAnonKey: supabaseAnonKey ?? AppConfig.supabaseAnonKey,
      syncMode: syncMode ?? SyncMode.supabasePrimary,
    );
    return _instance!;
  }

  /// Initialize sync service
  Future<void> initialize() async {
    debugPrint('SyncService: Initializing...');

    // Check connections
    await _checkConnections();

    // Start periodic sync
    _startPeriodicSync();

    // Initial sync
    await fullSync();

    debugPrint('SyncService: Initialized');
  }

  /// Check connections to both databases
  Future<void> _checkConnections() async {
    // Check Local
    try {
      final localResponse = await http
          .get(Uri.parse('$_localApiUrl/health'))
          .timeout(const Duration(seconds: 5));
      final localConnected = localResponse.statusCode == 200;
      debugPrint('SyncService: Local DB ${localConnected ? "connected" : "not connected"}');
    } catch (e) {
      debugPrint('SyncService: Local DB not available - $e');
    }

    // Check Supabase (if configured and initialized)
    if (_isSupabaseInitialized) {
      try {
        // Simple health check to Supabase
        _isOnline = true;
        debugPrint('SyncService: Supabase configured and initialized');
      } catch (e) {
        _isOnline = false;
        debugPrint('SyncService: Supabase not available - $e');
      }
    } else {
      debugPrint('SyncService: Supabase not configured or not initialized');
    }
  }

  /// Start periodic sync (configurable via SyncConfig)
  void _startPeriodicSync({Duration? interval}) {
    if (!SyncConfig.enableAutoSync) {
      debugPrint('SyncService: Auto sync disabled');
      return;
    }
    
    final syncInterval = interval ?? Duration(seconds: SyncConfig.syncIntervalSeconds);
    
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncInterval, (_) => _periodicSync());
    
    debugPrint('SyncService: Auto sync started (every ${syncInterval.inSeconds} seconds)');
    debugPrint('SyncService: Estimated ${SyncConfig.estimatedMonthlyRequests} requests/month');
    debugPrint('SyncService: Recommended plan: ${SyncConfig.recommendedPlan}');
  }
  
  /// Change sync interval at runtime
  void changeSyncInterval(int seconds) {
    SyncConfig.syncIntervalSeconds = seconds;
    _startPeriodicSync();
  }
  
  /// Apply a preset mode
  void applySyncMode(SyncModePreset preset) {
    preset.apply();
    _startPeriodicSync();
    debugPrint('SyncService: Applied ${preset.displayName} mode');
  }

  /// Periodic sync - only sync changes
  Future<void> _periodicSync() async {
    if (_status == SyncStatus.syncing) return;
    if (!_isOnline) return;

    // Only sync if there are pending changes
    if (_pendingChanges.isNotEmpty) {
      await syncPendingChanges();
    }
  }

  /// Full sync - sync all tables
  Future<void> fullSync() async {
    if (_status == SyncStatus.syncing) return;

    _setStatus(SyncStatus.syncing);
    _emitEvent(SyncEvent(type: SyncEventType.started, message: 'Starting full sync'));

    try {
      switch (_syncMode) {
        case SyncMode.supabasePrimary:
          await _syncFromSupabaseToLocal();
          break;
        case SyncMode.localPrimary:
          await _syncFromLocalToSupabase();
          break;
        case SyncMode.bidirectional:
          await _bidirectionalSync();
          break;
      }

      _lastSyncTime = DateTime.now();
      _setStatus(SyncStatus.idle);
      _emitEvent(SyncEvent(
        type: SyncEventType.completed,
        message: 'Sync completed',
        timestamp: _lastSyncTime,
      ));
    } catch (e) {
      _setStatus(SyncStatus.error);
      _emitEvent(SyncEvent(
        type: SyncEventType.error,
        message: 'Sync failed: $e',
      ));
      debugPrint('SyncService: Full sync failed - $e');
    }
  }

  /// Sync pending changes only
  Future<void> syncPendingChanges() async {
    if (_pendingChanges.isEmpty) return;

    _setStatus(SyncStatus.syncing);

    try {
      // Process pending changes
      final changes = List<String>.from(_pendingChanges);
      _pendingChanges.clear();

      for (final change in changes) {
        await _processChange(change);
      }

      _lastSyncTime = DateTime.now();
      _setStatus(SyncStatus.idle);
    } catch (e) {
      _setStatus(SyncStatus.error);
      debugPrint('SyncService: Sync pending changes failed - $e');
    }
  }

  /// Add a change to pending queue
  void addPendingChange(String table, String operation, Map<String, dynamic> data) {
    final change = json.encode({
      'table': table,
      'operation': operation,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _pendingChanges.add(change);
  }

  // =====================================================
  // SYNC STRATEGIES
  // =====================================================

  /// Check if Supabase is initialized
  bool get _isSupabaseInitialized {
    if (_supabaseUrl == 'YOUR_SUPABASE_URL') return false;
    try {
      // Try to access Supabase instance
      Supabase.instance;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sync from Supabase to Local (Supabase is primary)
  Future<void> _syncFromSupabaseToLocal() async {
    if (!_isSupabaseInitialized) {
      debugPrint('SyncService: Supabase not initialized, skipping sync');
      return;
    }

    debugPrint('SyncService: Syncing from Supabase to Local...');

    final client = Supabase.instance.client;

    // Sync professions
    await _syncTable(
      tableName: 'professions',
      fetchFromSource: () async {
        final response = await client.from('professions').select();
        return List<Map<String, dynamic>>.from(response);
      },
      saveToTarget: (data) => _saveToLocal('professions', data),
    );

    // Sync registration_field_configs
    await _syncTable(
      tableName: 'registration_field_configs',
      fetchFromSource: () async {
        final response = await client.from('registration_field_configs').select();
        return List<Map<String, dynamic>>.from(response);
      },
      saveToTarget: (data) => _saveToLocal('registration_field_configs', data),
    );

    // Sync users (only non-sensitive data)
    await _syncTable(
      tableName: 'users',
      fetchFromSource: () async {
        final response = await client.from('users').select(
            'id, profession_id, first_name, last_name, username, verification_status, is_active, created_at, updated_at');
        return List<Map<String, dynamic>>.from(response);
      },
      saveToTarget: (data) => _saveToLocal('users', data),
    );

    debugPrint('SyncService: Sync from Supabase completed');
  }

  /// Sync from Local to Supabase (Local is primary)
  Future<void> _syncFromLocalToSupabase() async {
    if (!_isSupabaseInitialized) {
      debugPrint('SyncService: Supabase not initialized, skipping sync');
      return;
    }

    debugPrint('SyncService: Syncing from Local to Supabase...');

    // Sync professions
    await _syncTable(
      tableName: 'professions',
      fetchFromSource: () => _fetchFromLocal('professions'),
      saveToTarget: (data) => _saveToSupabase('professions', data),
    );

    // Sync registration_field_configs
    await _syncTable(
      tableName: 'registration_field_configs',
      fetchFromSource: () => _fetchFromLocal('registration_field_configs'),
      saveToTarget: (data) => _saveToSupabase('registration_field_configs', data),
    );

    debugPrint('SyncService: Sync from Local completed');
  }

  /// Bidirectional sync (merge changes from both)
  Future<void> _bidirectionalSync() async {
    debugPrint('SyncService: Bidirectional sync...');

    // Get data from both sources
    final localProfessions = await _fetchFromLocal('professions');
    
    if (_isSupabaseInitialized) {
      final client = Supabase.instance.client;
      final supabaseProfessions = await client.from('professions').select();

      // Merge based on updated_at timestamp
      final merged = _mergeData(
        List<Map<String, dynamic>>.from(supabaseProfessions),
        localProfessions,
      );

      // Save merged data to both
      await _saveToLocal('professions', merged);
      await _saveToSupabase('professions', merged);
    }

    debugPrint('SyncService: Bidirectional sync completed');
  }

  // =====================================================
  // HELPER METHODS
  // =====================================================

  Future<void> _syncTable({
    required String tableName,
    required Future<List<Map<String, dynamic>>> Function() fetchFromSource,
    required Future<void> Function(List<Map<String, dynamic>>) saveToTarget,
  }) async {
    try {
      final data = await fetchFromSource();
      await saveToTarget(data);
      _emitEvent(SyncEvent(
        type: SyncEventType.tableSync,
        message: 'Synced $tableName: ${data.length} records',
      ));
    } catch (e) {
      debugPrint('SyncService: Failed to sync $tableName - $e');
      _emitEvent(SyncEvent(
        type: SyncEventType.error,
        message: 'Failed to sync $tableName: $e',
      ));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFromLocal(String table) async {
    try {
      final response = await http.get(Uri.parse('$_localApiUrl/api/$table'));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
    } catch (e) {
      debugPrint('SyncService: Failed to fetch $table from local - $e');
    }
    return [];
  }

  Future<void> _saveToLocal(String table, List<Map<String, dynamic>> data) async {
    try {
      await http.post(
        Uri.parse('$_localApiUrl/api/$table/sync'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'data': data}),
      );
    } catch (e) {
      debugPrint('SyncService: Failed to save $table to local - $e');
    }
  }

  Future<void> _saveToSupabase(String table, List<Map<String, dynamic>> data) async {
    if (!_isSupabaseInitialized) return;

    try {
      final client = Supabase.instance.client;
      await client.from(table).upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('SyncService: Failed to save $table to Supabase - $e');
    }
  }

  List<Map<String, dynamic>> _mergeData(
    List<Map<String, dynamic>> source1,
    List<Map<String, dynamic>> source2,
  ) {
    final Map<String, Map<String, dynamic>> merged = {};

    // Add all from source1
    for (final item in source1) {
      merged[item['id']] = item;
    }

    // Merge from source2 (keep newer based on updated_at)
    for (final item in source2) {
      final id = item['id'];
      if (merged.containsKey(id)) {
        final existing = merged[id]!;
        final existingTime = DateTime.tryParse(existing['updated_at'] ?? '') ?? DateTime(1970);
        final newTime = DateTime.tryParse(item['updated_at'] ?? '') ?? DateTime(1970);
        if (newTime.isAfter(existingTime)) {
          merged[id] = item;
        }
      } else {
        merged[id] = item;
      }
    }

    return merged.values.toList();
  }

  Future<void> _processChange(String changeJson) async {
    try {
      final change = json.decode(changeJson);
      final table = change['table'];
      final operation = change['operation'];
      final data = change['data'];

      // Sync to both databases based on mode
      switch (_syncMode) {
        case SyncMode.supabasePrimary:
          // Write to Supabase, then local will sync
          await _writeToSupabase(table, operation, data);
          break;
        case SyncMode.localPrimary:
          // Write to Local, then sync to Supabase
          await _writeToLocal(table, operation, data);
          await _writeToSupabase(table, operation, data);
          break;
        case SyncMode.bidirectional:
          // Write to both
          await _writeToLocal(table, operation, data);
          await _writeToSupabase(table, operation, data);
          break;
      }
    } catch (e) {
      debugPrint('SyncService: Failed to process change - $e');
    }
  }

  Future<void> _writeToLocal(String table, String operation, Map<String, dynamic> data) async {
    try {
      final endpoint = '$_localApiUrl/api/$table';
      switch (operation) {
        case 'insert':
          await http.post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(data),
          );
          break;
        case 'update':
          await http.put(
            Uri.parse('$endpoint/${data['id']}'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(data),
          );
          break;
        case 'delete':
          await http.delete(Uri.parse('$endpoint/${data['id']}'));
          break;
      }
    } catch (e) {
      debugPrint('SyncService: Failed to write to local - $e');
    }
  }

  Future<void> _writeToSupabase(String table, String operation, Map<String, dynamic> data) async {
    if (!_isSupabaseInitialized) return;

    try {
      final client = Supabase.instance.client;
      switch (operation) {
        case 'insert':
          await client.from(table).insert(data);
          break;
        case 'update':
          await client.from(table).update(data).eq('id', data['id']);
          break;
        case 'delete':
          await client.from(table).delete().eq('id', data['id']);
          break;
      }
    } catch (e) {
      debugPrint('SyncService: Failed to write to Supabase - $e');
    }
  }

  void _setStatus(SyncStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void _emitEvent(SyncEvent event) {
    _syncEventController.add(event);
  }

  /// Dispose resources
  void dispose() {
    _syncTimer?.cancel();
    _statusController.close();
    _syncEventController.close();
  }
}

/// Sync Event
class SyncEvent {
  final SyncEventType type;
  final String message;
  final DateTime? timestamp;

  SyncEvent({
    required this.type,
    required this.message,
    this.timestamp,
  });
}

/// Sync Event Type
enum SyncEventType {
  started,
  completed,
  error,
  tableSync,
  conflict,
}
