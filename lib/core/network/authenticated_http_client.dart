import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sheserved/config/app_config.dart';

/// Authenticated HTTP client with refresh-once / single-flight pattern.
///
/// Phase 13.2 (Decision Q6 = B):
/// - Stores access + refresh tokens in flutter_secure_storage
/// - Automatically adds Authorization: Bearer header
/// - On 401, attempts token refresh (single-flight: parallel 401s share one refresh)
/// - If refresh fails, logs out user
/// - Never logs token strings
class AuthenticatedHttpClient {
  static final AuthenticatedHttpClient _instance =
      AuthenticatedHttpClient._internal();
  static AuthenticatedHttpClient get instance => _instance;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;
  String? _baseUrl;

  // Single-flight refresh: parallel 401s share one refresh attempt.
  Completer<bool>? _refreshCompleter;

  /// W3.6 — token lifecycle broadcast: emits the new access token on every
  /// login/refresh, and `null` when tokens are cleared (logout/revoke).
  /// WebSocketService listens to reconnect with the fresh token or stop
  /// retrying — the socket must never keep using a replaced/revoked token.
  final _tokenChangeController = StreamController<String?>.broadcast();
  Stream<String?> get tokenChanges => _tokenChangeController.stream;

  AuthenticatedHttpClient._internal();

  /// Headers ที่ต้องส่งทุก backend call — Content-Type + app version
  /// (min-version gate ฝั่ง server fail-closed ถ้าไม่มี x-app-version)
  Map<String, String> get _baseHeaders => {
    'Content-Type': 'application/json',
    'x-app-version': AppConfig.appVersion,
  };

  /// Base URL of the backend API (e.g. 'https://api.sheserved.com')
  void configure({required String baseUrl}) {
    _baseUrl = baseUrl;
  }

  /// Load stored tokens on app start.
  Future<void> loadTokens() async {
    _accessToken = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
  }

  /// Save tokens after login/refresh.
  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
    _tokenChangeController.add(accessToken);
  }

  /// Clear tokens on logout.
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    _tokenChangeController.add(null);
  }

  /// W3.6 — refresh outside the HTTP-401 path (e.g. socket handshake rejected
  /// an expired access token). Single-flight shared with the HTTP path.
  /// Returns false when there is no refresh token or the session is revoked.
  Future<bool> refreshTokens() async {
    if (_refreshToken == null) return false;
    return _refreshOnce();
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _accessToken != null;

  /// Base URL the client was configured with — needed by repositories that
  /// build raw [http.MultipartRequest] URIs via [sendMultipart].
  String? get backendApiUrl => _baseUrl;

  /// Make an authenticated HTTP request.
  ///
  /// Automatically adds Authorization header. On 401, attempts refresh
  /// (single-flight) and retries once. If refresh fails, clears tokens.
  Future<http.Response> request(
    String method,
    String path, {
    Map<String, String>? headers,
    body,
    Map<String, dynamic>? queryParams,
  }) async {
    if (_baseUrl == null) {
      throw StateError(
        'AuthenticatedHttpClient not configured — call configure() first',
      );
    }

    final uri = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: queryParams);
    final reqHeaders = Map<String, String>.from(headers ?? {});
    reqHeaders.putIfAbsent('x-app-version', () => AppConfig.appVersion);

    // Add auth header if we have a token.
    if (_accessToken != null) {
      reqHeaders['Authorization'] = 'Bearer $_accessToken';
    }

    http.Response response;
    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(uri, headers: reqHeaders);
        break;
      case 'POST':
        reqHeaders['Content-Type'] =
            reqHeaders['Content-Type'] ?? 'application/json';
        response = await http.post(uri, headers: reqHeaders, body: body);
        break;
      case 'PUT':
        reqHeaders['Content-Type'] =
            reqHeaders['Content-Type'] ?? 'application/json';
        response = await http.put(uri, headers: reqHeaders, body: body);
        break;
      case 'PATCH':
        reqHeaders['Content-Type'] =
            reqHeaders['Content-Type'] ?? 'application/json';
        response = await http.patch(uri, headers: reqHeaders, body: body);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: reqHeaders, body: body);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }

    // On 401, attempt refresh + retry once.
    if (response.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        // Retry with new token.
        reqHeaders['Authorization'] = 'Bearer $_accessToken';
        switch (method.toUpperCase()) {
          case 'GET':
            return http.get(uri, headers: reqHeaders);
          case 'POST':
            return http.post(uri, headers: reqHeaders, body: body);
          case 'PUT':
            return http.put(uri, headers: reqHeaders, body: body);
          case 'PATCH':
            return http.patch(uri, headers: reqHeaders, body: body);
          case 'DELETE':
            return http.delete(uri, headers: reqHeaders, body: body);
          default:
            throw ArgumentError('Unsupported HTTP method: $method');
        }
      } else {
        // Refresh failed — clear tokens (caller should redirect to login).
        await clearTokens();
      }
    }

    return response;
  }

  /// Send a multipart/form-data request with Bearer + refresh-once retry.
  ///
  /// [buildRequest] must return a FRESH [http.MultipartRequest] on every
  /// call — a sent request's byte stream is consumed and cannot be replayed
  /// for the retry attempt.  Phase 13.3 upload path (video/photo/watermark).
  Future<http.StreamedResponse> sendMultipart(
    Future<http.MultipartRequest> Function() buildRequest,
  ) async {
    if (_baseUrl == null) {
      throw StateError(
        'AuthenticatedHttpClient not configured — call configure() first',
      );
    }

    var request = await buildRequest();
    _applyAuthHeaders(request.headers);
    var response = await request.send();

    if (response.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        request = await buildRequest();
        _applyAuthHeaders(request.headers);
        response = await request.send();
      } else {
        await clearTokens();
      }
    }
    return response;
  }

  void _applyAuthHeaders(Map<String, String> headers) {
    headers.putIfAbsent('x-app-version', () => AppConfig.appVersion);
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
  }

  /// Single-flight refresh: if multiple requests get 401 simultaneously,
  /// only one refresh attempt is made; others share the result.
  Future<bool> _refreshOnce() async {
    // If a refresh is already in progress, wait for it.
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();
    try {
      final refreshUri = Uri.parse('$_baseUrl/api/auth/refresh');
      final response = await http.post(
        refreshUri,
        headers: _baseHeaders,
        body: jsonEncode({'refreshToken': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data['accessToken'], data['refreshToken']);
        _refreshCompleter!.complete(true);
        return true;
      } else {
        debugPrint('[AuthHttpClient] Refresh failed: ${response.statusCode}');
        _refreshCompleter!.complete(false);
        return false;
      }
    } catch (err) {
      debugPrint('[AuthHttpClient] Refresh error: $err');
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      // Reset completer so future 401s can attempt refresh again.
      _refreshCompleter = null;
    }
  }

  /// Submit a profession change and application atomically through the gateway.
  Future<Map<String, dynamic>> submitProfessionChange({
    required String professionId,
    required String firstName,
    required String username,
    String? lastName,
    String? phone,
    String? profileImageUrl,
    Map<String, dynamic>? registrationData,
  }) async {
    if (_baseUrl == null) {
      throw StateError(
        'AuthenticatedHttpClient not configured — call configure() first',
      );
    }

    final response = await request(
      'POST',
      '/api/profession-change',
      body: jsonEncode({
        'professionId': professionId,
        'firstName': firstName,
        'lastName': lastName,
        'username': username,
        'phone': phone,
        'profileImageUrl': profileImageUrl,
        'registrationData': registrationData ?? <String, dynamic>{},
      }),
    );
    final data = _safeDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        data['error']?.toString() ?? 'Profession change failed',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  /// Submit a new sport-type proposal through the gateway.
  ///
  /// The gateway writes the pending sport row and notifies every active admin,
  /// mirroring [submitProfessionChange]. Returns the created sport id.
  Future<String> proposeSportType({
    required String nameTh,
    String? nameEn,
    String? fieldLayout,
    Map<String, dynamic>? fieldStyle,
  }) async {
    if (_baseUrl == null) {
      throw StateError(
        'AuthenticatedHttpClient not configured — call configure() first',
      );
    }

    final response = await request(
      'POST',
      '/api/sports/propose',
      body: jsonEncode({
        'nameTh': nameTh,
        'nameEn': nameEn,
        'fieldLayout': fieldLayout,
        'fieldStyle': fieldStyle,
      }),
    );
    final data = _safeDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        data['error']?.toString() ?? 'Sport proposal failed',
        statusCode: response.statusCode,
      );
    }
    return data['sportId']?.toString() ?? '';
  }

  /// Login via backend — stores tokens on success.
  /// [identifier] may be a phone number or a username (backend resolves both).
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    if (_baseUrl == null) {
      throw StateError(
        'AuthenticatedHttpClient not configured — call configure() first',
      );
    }

    // Backend accepts { phone } or { username } — detect which one we have.
    final isPhone = _looksLikePhone(identifier);
    final body = isPhone
        ? {'phone': identifier, 'password': password}
        : {'username': identifier, 'password': password};

    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/login'),
      headers: _baseHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['accessToken'] != null && data['refreshToken'] != null) {
        await _saveTokens(data['accessToken'], data['refreshToken']);
      }
      return data;
    } else {
      final error = _safeDecode(response.body);
      throw AuthException(
        error['error'] ?? 'Login failed',
        statusCode: response.statusCode,
      );
    }
  }

  /// Register via backend (server-side Argon2id hash — client never writes
  /// password_hash).  Stores tokens on success.
  Future<Map<String, dynamic>> register({
    required String username,
    required String phone,
    required String password,
    required String firstName,
    String? lastName,
    String? email,
  }) async {
    if (_baseUrl == null) {
      throw StateError(
        'AuthenticatedHttpClient not configured — call configure() first',
      );
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/register'),
      headers: _baseHeaders,
      body: jsonEncode({
        'username': username,
        'phone': phone,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['accessToken'] != null && data['refreshToken'] != null) {
        await _saveTokens(data['accessToken'], data['refreshToken']);
      }
      return data;
    } else {
      final error = _safeDecode(response.body);
      throw AuthException(
        error['error'] ?? 'Registration failed',
        statusCode: response.statusCode,
      );
    }
  }

  /// Social login via backend — backend verifies the provider token
  /// (Google/Apple JWKS) server-side.  Never trusts client identity.
  Future<Map<String, dynamic>> socialLogin({
    required String provider,
    required String providerToken,
    String? nonce,
  }) async {
    if (_baseUrl == null) {
      throw StateError(
        'AuthenticatedHttpClient not configured — call configure() first',
      );
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/social/$provider'),
      headers: _baseHeaders,
      body: jsonEncode({
        'providerToken': providerToken,
        if (nonce != null) 'nonce': nonce,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['accessToken'] != null && data['refreshToken'] != null) {
        await _saveTokens(data['accessToken'], data['refreshToken']);
      }
      return data;
    } else {
      final error = _safeDecode(response.body);
      throw AuthException(
        error['error'] ?? 'Social login failed',
        statusCode: response.statusCode,
      );
    }
  }

  /// Fetch current user info from backend (/me) — used for session restore.
  Future<Map<String, dynamic>> getMe() async {
    final response = await request('GET', '/api/auth/me');
    if (response.statusCode == 200) {
      return _safeDecode(response.body);
    }
    throw AuthException(
      'Failed to restore session',
      statusCode: response.statusCode,
    );
  }

  /// Restore session on app start: load tokens from secure storage, then
  /// validate via /me.  Returns the user map, or null when not logged in.
  Future<Map<String, dynamic>?> restoreSession() async {
    await loadTokens();
    if (_accessToken == null) return null;
    try {
      return await getMe();
    } on AuthException {
      await clearTokens();
      return null;
    }
  }

  bool _looksLikePhone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    // Phone: digits with optional leading +, spaces, dashes.
    return RegExp(r'^\+?[0-9][0-9\s\-]*$').hasMatch(trimmed);
  }

  Map<String, dynamic> _safeDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Logout — revokes session and clears tokens.
  Future<void> logout() async {
    if (_refreshToken == null) return;

    try {
      await http.post(
        Uri.parse('$_baseUrl/api/auth/logout'),
        headers: _baseHeaders,
        body: jsonEncode({'refreshToken': _refreshToken}),
      );
    } catch (_) {
      // Best-effort logout — clear tokens regardless.
    }

    await clearTokens();
  }
}

class AuthException implements Exception {
  final String message;
  final int statusCode;

  AuthException(this.message, {required this.statusCode});

  @override
  String toString() => 'AuthException($statusCode): $message';
}
