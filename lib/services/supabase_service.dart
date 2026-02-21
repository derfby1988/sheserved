import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

/// Supabase Service for Sheserved
/// ใช้สำหรับเชื่อมต่อกับ Supabase Backend
class SupabaseService {
  static SupabaseClient? _client;
  static bool _isInitialized = false;

  /// Initialize Supabase (uses AppConfig for URL and key)
  static Future<void> initialize() async {
    if (!AppConfig.isSupabaseConfigured) {
      debugPrint('SupabaseService: Supabase not configured, skipping initialization');
      return;
    }

    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      _client = Supabase.instance.client;
      _isInitialized = true;
      debugPrint('SupabaseService: Initialized successfully');
    } catch (e) {
      debugPrint('SupabaseService: Failed to initialize - $e');
    }
  }

  /// Check if Supabase is initialized
  static bool get isInitialized => _isInitialized && _client != null;

  /// Get Supabase Client (returns null if not initialized)
  static SupabaseClient? get clientOrNull => _client;

  /// Get Supabase Client (throws if not initialized)
  static SupabaseClient get client {
    if (_client == null) {
      try {
        _client = Supabase.instance.client;
        _isInitialized = true;
      } catch (e) {
        throw Exception('Supabase not initialized. Call SupabaseService.initialize() first or check isInitialized. Error: $e');
      }
    }
    return _client!;
  }

  /// Check if user is logged in (DEPRECATED: Use AuthService.isLoggedIn)
  @Deprecated('Use AuthService.instance.isLoggedIn')
  static bool get isLoggedIn => false;

  /// Get current user (DEPRECATED: Use ServiceLocator.instance.currentUser)
  @Deprecated('Use ServiceLocator.instance.currentUser')
  static User? get currentUser => null;

  /// Get current session (DEPRECATED: We do not use Supabase sessions)
  @Deprecated('Supabase sessions are not used in this project')
  static Session? get currentSession => null;

  // ============ AUTH METHODS ============

  /// Sign up with email and password
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }

  /// Sign in with email and password
  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign in with phone (OTP)
  static Future<void> signInWithPhone({
    required String phone,
  }) async {
    await client.auth.signInWithOtp(phone: phone);
  }

  /// Verify OTP
  static Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) async {
    return await client.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  /// Sign out
  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  // ============ DATABASE METHODS ============

  /// Get data from table
  static Future<List<Map<String, dynamic>>> getAll(String table) async {
    final response = await client.from(table).select();
    return List<Map<String, dynamic>>.from(response);
  }

  /// Get single record by ID
  static Future<Map<String, dynamic>?> getById(String table, int id) async {
    final response = await client.from(table).select().eq('id', id).single();
    return response;
  }

  /// Insert data
  static Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> data,
  ) async {
    final response = await client.from(table).insert(data).select().single();
    return response;
  }

  /// Update data
  static Future<Map<String, dynamic>> update(
    String table,
    int id,
    Map<String, dynamic> data,
  ) async {
    final response = await client.from(table).update(data).eq('id', id).select().single();
    return response;
  }

  /// Delete data
  static Future<void> delete(String table, int id) async {
    await client.from(table).delete().eq('id', id);
  }

  // ============ STORAGE METHODS ============

  /// Upload file to storage
  static Future<String> uploadFile({
    required String bucket,
    required String path,
    required List<int> fileBytes,
    String? contentType,
  }) async {
    await client.storage.from(bucket).uploadBinary(
      path,
      Uint8List.fromList(fileBytes),
      fileOptions: FileOptions(
        contentType: contentType,
        upsert: true,
      ),
    );
    return client.storage.from(bucket).getPublicUrl(path);
  }

  /// Get public URL for file
  static String getPublicUrl(String bucket, String path) {
    return client.storage.from(bucket).getPublicUrl(path);
  }

  /// Delete file from storage
  static Future<void> deleteFile(String bucket, String path) async {
    await client.storage.from(bucket).remove([path]);
  }
}
