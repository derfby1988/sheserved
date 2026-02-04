import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Service for Sheserved
/// ใช้สำหรับเชื่อมต่อกับ Supabase Backend
class SupabaseService {
  static SupabaseClient? _client;

  // TODO: เปลี่ยนเป็น URL และ Key จาก Supabase Project จริง
  static const String _supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String _supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  /// Initialize Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
    _client = Supabase.instance.client;
  }

  /// Get Supabase Client
  static SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase not initialized. Call SupabaseService.initialize() first.');
    }
    return _client!;
  }

  /// Check if user is logged in
  static bool get isLoggedIn => _client?.auth.currentUser != null;

  /// Get current user
  static User? get currentUser => _client?.auth.currentUser;

  /// Get current session
  static Session? get currentSession => _client?.auth.currentSession;

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
      fileBytes as dynamic,
      fileOptions: FileOptions(contentType: contentType),
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
