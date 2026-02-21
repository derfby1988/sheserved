import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../features/admin/data/repositories/local_database_repository.dart';
import '../features/admin/data/repositories/unified_repository.dart';
import 'websocket_service.dart';
import 'database_service.dart';
import 'sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/data/repositories/user_repository.dart';
import '../features/health/data/repositories/health_repository.dart';
import '../features/health/data/repositories/health_article_repository.dart';
import '../features/chat/data/repositories/chat_repository.dart';
import '../features/chat/data/models/chat_models.dart';
import 'package:hive/hive.dart';
import 'auth_service.dart';

/// Service Locator สำหรับจัดการ Dependencies
/// ใช้รูปแบบ Singleton เพื่อให้เข้าถึงได้จากทุกที่
class ServiceLocator {
  static ServiceLocator? _instance;
  
  // Services
  LocalDatabaseRepository? _localRepository;
  UnifiedRepository? _unifiedRepository;
  WebSocketService? _websocketService;
  DatabaseService? _databaseService;
  SyncService? _syncService;
  UserRepository? _userRepository;
  HealthRepository? _healthRepository;
  HealthArticleRepository? _healthArticleRepository;
  ChatRepository? _chatRepository;
  
  // Flags
  bool _isInitialized = false;

  ServiceLocator._();

  /// Get singleton instance
  static ServiceLocator get instance {
    _instance ??= ServiceLocator._();
    return _instance!;
  }

  /// Static get method for generic repository access
  static T get<T>() {
    final instance = ServiceLocator.instance;
    if (T == UserRepository) return instance.userRepository as T;
    if (T == HealthRepository) return instance.healthRepository as T;
    throw Exception('ServiceLocator: Type $T not registered');
  }

  /// Get current logged in user from AuthService
  User? get currentUser {
    final authUser = AuthService.instance.currentUser;
    if (authUser == null) return null;
    
    // Convert UserModel to Supabase User format
    // Return a mock User object with the ID
    return User(
      id: authUser.id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: authUser.createdAt.toIso8601String(),
    );
  }

  /// Initialize all services
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('ServiceLocator: Initializing...');
    debugPrint('ServiceLocator: Database Mode = ${AppConfig.databaseMode.name}');

    // Initialize WebSocket Service (always available for real-time)
    _websocketService = WebSocketService(
      serverUrl: AppConfig.websocketUrl,
    );

    // Initialize based on database mode
    switch (AppConfig.databaseMode) {
      case DatabaseMode.unified:
        // ใช้ทั้ง Local และ Supabase ซิงค์กันอัตโนมัติ
        debugPrint('ServiceLocator: Using Unified Mode (Local + Supabase Sync)');
        
        _unifiedRepository = UnifiedRepository(
          localApiUrl: AppConfig.localApiUrl,
        );
        
        _localRepository = LocalDatabaseRepository(
          baseUrl: AppConfig.localApiUrl,
        );
        
        _databaseService = DatabaseService(
          baseUrl: AppConfig.localApiUrl,
        );

        // Initialize Sync Service if Supabase is configured
        if (AppConfig.isSupabaseConfigured && AppConfig.enableAutoSync) {
          _syncService = SyncService(
            localApiUrl: AppConfig.localApiUrl,
            supabaseUrl: AppConfig.supabaseUrl,
            supabaseAnonKey: AppConfig.supabaseAnonKey,
          );
          await _syncService!.initialize();
        }
        break;

      case DatabaseMode.localOnly:
        // ใช้แค่ Local PostgreSQL
        debugPrint('ServiceLocator: Using Local Only Mode');
        
        _localRepository = LocalDatabaseRepository(
          baseUrl: AppConfig.localApiUrl,
        );
        
        _databaseService = DatabaseService(
          baseUrl: AppConfig.localApiUrl,
        );
        break;

      case DatabaseMode.supabaseOnly:
        // ใช้แค่ Supabase Cloud
        debugPrint('ServiceLocator: Using Supabase Only Mode');
        // Supabase client will be initialized in main.dart
        break;
    }

    // Check local connection
    if (_localRepository != null) {
      final isConnected = await _localRepository!.healthCheck();
      if (isConnected) {
        debugPrint('ServiceLocator: Local database connected');
      } else {
        debugPrint('ServiceLocator: WARNING - Local database not connected');
        debugPrint('  Run: cd websocket-server && npm start');
      }
    }

    // Initialize repositories for Supabase
    if (AppConfig.isSupabaseConfigured) {
      final supabaseClient = Supabase.instance.client;
      _userRepository = UserRepository(supabaseClient);
      _healthRepository = HealthRepository(supabaseClient);
      _healthArticleRepository = HealthArticleRepository(supabaseClient);
      
      _chatRepository = ChatRepository(
        supabaseClient,
        Hive.box<ChatRoom>('chat_rooms'),
        Hive.box<ChatMessage>('chat_messages'),
        Hive.box<ChatParticipant>('chat_participants'),
        _webSocketService,
      );
    }


    _isInitialized = true;
    debugPrint('ServiceLocator: Initialized successfully');
  }

  UserRepository get userRepository {
    if (_userRepository == null) {
      _userRepository = UserRepository(Supabase.instance.client);
    }
    return _userRepository!;
  }

  HealthRepository get healthRepository {
    if (_healthRepository == null) {
      _healthRepository = HealthRepository(Supabase.instance.client);
    }
    return _healthRepository!;
  }

  HealthArticleRepository get healthArticleRepository {
    if (_healthArticleRepository == null) {
      _healthArticleRepository = HealthArticleRepository(Supabase.instance.client);
    }
    return _healthArticleRepository!;
  }

  ChatRepository get chatRepository {
    if (_chatRepository == null) {
      _chatRepository = ChatRepository(
        Supabase.instance.client,
        Hive.box<ChatRoom>('chat_rooms'),
        Hive.box<ChatMessage>('chat_messages'),
        Hive.box<ChatParticipant>('chat_participants'),
        _webSocketService,
      );
    }
    return _chatRepository!;
  }


  /// Get Unified Repository (recommended)
  UnifiedRepository get repository {
    if (_unifiedRepository != null) return _unifiedRepository!;
    
    // Fallback to creating a new instance
    _unifiedRepository = UnifiedRepository(
      localApiUrl: AppConfig.localApiUrl,
    );
    return _unifiedRepository!;
  }

  /// Get Local Database Repository
  LocalDatabaseRepository get localRepository {
    if (_localRepository == null) {
      _localRepository = LocalDatabaseRepository(
        baseUrl: AppConfig.localApiUrl,
      );
    }
    return _localRepository!;
  }

  /// Get WebSocket Service
  WebSocketService get websocketService {
    if (_websocketService == null) {
      _websocketService = WebSocketService(
        serverUrl: AppConfig.websocketUrl,
      );
    }
    return _websocketService!;
  }

  /// Get Database Service
  DatabaseService get databaseService {
    if (_databaseService == null) {
      _databaseService = DatabaseService(
        baseUrl: AppConfig.localApiUrl,
      );
    }
    return _databaseService!;
  }

  /// Get Sync Service
  SyncService? get syncService => _syncService;

  /// Check current database mode
  DatabaseMode get databaseMode => AppConfig.databaseMode;

  /// Check if using local database
  bool get isUsingLocalDatabase => 
      AppConfig.databaseMode == DatabaseMode.localOnly ||
      AppConfig.databaseMode == DatabaseMode.unified;

  /// Check if Supabase is configured
  bool get isSupabaseConfigured => AppConfig.isSupabaseConfigured;

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Force sync now
  Future<void> forceSync() async {
    if (_syncService != null) {
      await _syncService!.fullSync();
    } else if (_unifiedRepository != null) {
      await _unifiedRepository!.forceFullSync();
    }
  }

  /// Dispose all services
  void dispose() {
    _websocketService?.dispose();
    _syncService?.dispose();
    _unifiedRepository?.dispose();
    _localRepository = null;
    _unifiedRepository = null;
    _websocketService = null;
    _databaseService = null;
    _syncService = null;
    _isInitialized = false;
  }
}

/// Convenience getter for ServiceLocator
ServiceLocator get services => ServiceLocator.instance;
