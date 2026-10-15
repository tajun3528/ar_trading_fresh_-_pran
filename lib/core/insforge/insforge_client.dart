import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env.dart';
import 'auth_session.dart';
import 'insforge_exception.dart';
import 'query_builder.dart';

/// Thin REST client for InsForge. There is no official Flutter/Dart SDK, so
/// this talks to the real wire protocol directly: PostgREST-style CRUD/RPC at
/// `/api/database/...` and token auth at `/api/auth/...` (with
/// `client_type=mobile` so refresh tokens come back in the JSON body instead
/// of a browser cookie, since Flutter has no cookie jar to rely on).
class InsforgeClient {
  InsforgeClient() : _dio = Dio(BaseOptions(baseUrl: Env.insforgeBaseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Authorization'] = 'Bearer ${_accessToken ?? Env.insforgeAnonKey}';
          handler.next(options);
        },
        onError: (error, handler) async {
          final isAuthEndpoint = error.requestOptions.path.startsWith('/api/auth/');
          final alreadyRetried = error.requestOptions.extra['retried'] == true;
          if (error.response?.statusCode == 401 &&
              !isAuthEndpoint &&
              !alreadyRetried &&
              _refreshToken != null) {
            try {
              await refreshSession();
              final opts = error.requestOptions;
              opts.extra['retried'] = true;
              opts.headers['Authorization'] = 'Bearer $_accessToken';
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } catch (_) {
              await clearSession();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final _storage = const FlutterSecureStorage();
  static const _storageKey = 'insforge_session';

  String? _accessToken;
  String? _refreshToken;

  bool get isAuthenticated => _accessToken != null;

  /// Bumped after every successful write (insert/update/delete/rpc). Screens
  /// listen to this (see AutoRefreshMixin) so a save on one screen — or one
  /// tab kept alive in memory by the router — refreshes every other screen
  /// currently showing related data, instead of requiring a manual reload.
  final ValueNotifier<int> dataVersion = ValueNotifier(0);

  // ==========================================================================
  // Session persistence
  // ==========================================================================

  Future<void> _saveSession(AuthSession session) async {
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    await _storage.write(key: '${_storageKey}_access', value: session.accessToken);
    if (session.refreshToken != null) {
      await _storage.write(key: '${_storageKey}_refresh', value: session.refreshToken);
    }
  }

  /// Loads any persisted tokens into memory. Call once at app startup, then
  /// call [getCurrentUser] to verify/hydrate — an expired access token will
  /// be transparently refreshed by the 401 interceptor above.
  Future<void> restoreSession() async {
    _accessToken = await _storage.read(key: '${_storageKey}_access');
    _refreshToken = await _storage.read(key: '${_storageKey}_refresh');
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: '${_storageKey}_access');
    await _storage.delete(key: '${_storageKey}_refresh');
  }

  // ==========================================================================
  // Auth
  // ==========================================================================

  Future<AuthSession> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final data = await _post(
      '/api/auth/users',
      data: {'email': email, 'password': password, 'name': name},
      query: {'client_type': 'mobile'},
    );
    final session = AuthSession.fromJson(data as Map<String, dynamic>);
    await _saveSession(session);
    return session;
  }

  Future<AuthSession> signIn({required String email, required String password}) async {
    final data = await _post(
      '/api/auth/sessions',
      data: {'email': email, 'password': password},
      query: {'client_type': 'mobile'},
    );
    final session = AuthSession.fromJson(data as Map<String, dynamic>);
    await _saveSession(session);
    return session;
  }

  Future<void> signOut() async {
    try {
      await _post('/api/auth/logout', query: {'client_type': 'mobile'});
    } catch (_) {
      // best-effort — clear the local session regardless
    }
    await clearSession();
  }

  Future<void> refreshSession() async {
    if (_refreshToken == null) {
      throw InsforgeException('No session to refresh');
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      queryParameters: {'client_type': 'mobile'},
      data: {'refreshToken': _refreshToken},
    );
    final data = response.data!;
    _accessToken = data['accessToken'] as String;
    await _storage.write(key: '${_storageKey}_access', value: _accessToken);
    if (data['refreshToken'] != null) {
      _refreshToken = data['refreshToken'] as String;
      await _storage.write(key: '${_storageKey}_refresh', value: _refreshToken);
    }
  }

  /// Returns the current user, or null if not signed in / session invalid.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (_accessToken == null) return null;
    try {
      final data = await _get('/api/auth/sessions/current');
      return (data as Map<String, dynamic>)['user'] as Map<String, dynamic>?;
    } on InsforgeException {
      return null;
    }
  }

  /// Resolves a mobile number or email to the real auth email, so the login
  /// screen can accept either (FR-1.2). Runs pre-authentication.
  Future<String?> resolveLoginEmail(String identifier) async {
    final data = await rpc('resolve_login_email', {'p_identifier': identifier});
    return data as String?;
  }

  // ==========================================================================
  // Database (PostgREST-style)
  // ==========================================================================

  QueryBuilder from(String table) => QueryBuilder(this, table);

  Future<dynamic> rpc(String function, [Map<String, dynamic>? params]) async {
    final result = await _post('/api/database/rpc/$function', data: params ?? <String, dynamic>{});
    dataVersion.value++;
    return result;
  }

  Future<List<Map<String, dynamic>>> getRecords(String table, Map<String, dynamic> query) async {
    final data = await _get('/api/database/records/$table', query: query);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> insertRecords(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final data = await _post(
      '/api/database/records/$table',
      data: rows,
      extraHeaders: {'Prefer': 'return=representation'},
    );
    dataVersion.value++;
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> updateRecords(
    String table,
    Map<String, dynamic> patch,
    Map<String, dynamic> query,
  ) async {
    final data = await _patch(
      '/api/database/records/$table',
      data: patch,
      query: query,
      extraHeaders: {'Prefer': 'return=representation'},
    );
    dataVersion.value++;
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> deleteRecords(String table, Map<String, dynamic> query) async {
    await _delete('/api/database/records/$table', query: query);
    dataVersion.value++;
  }

  // ==========================================================================
  // Low-level HTTP helpers — translate Dio failures into InsforgeException
  // with the plain-language message InsForge already returns (NFR-4).
  // ==========================================================================

  // Flutter web's Dio adapter goes through the browser's own HTTP cache.
  // Without explicit no-cache headers, the browser can serve a stale GET
  // response for an identical URL right after a write — the app then shows
  // old data until a hard reload forces the browser to skip its cache.
  static final Options _noCacheOptions = Options(
    headers: {'Cache-Control': 'no-cache, no-store, must-revalidate', 'Pragma': 'no-cache'},
  );

  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) {
    return _send(() => _dio.get<dynamic>(path, queryParameters: query, options: _noCacheOptions));
  }

  Future<dynamic> _post(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Map<String, String>? extraHeaders,
  }) {
    return _send(
      () => _dio.post<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: extraHeaders != null ? Options(headers: extraHeaders) : null,
      ),
    );
  }

  Future<dynamic> _patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Map<String, String>? extraHeaders,
  }) {
    return _send(
      () => _dio.patch<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: extraHeaders != null ? Options(headers: extraHeaders) : null,
      ),
    );
  }

  Future<dynamic> _delete(String path, {Map<String, dynamic>? query}) {
    return _send(() => _dio.delete<dynamic>(path, queryParameters: query));
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      throw _toInsforgeException(e);
    }
  }

  InsforgeException _toInsforgeException(DioException e) {
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      final message = (body['message'] ?? body['error'] ?? e.message) as String? ?? 'Request failed';
      return InsforgeException(
        message,
        statusCode: e.response?.statusCode,
        code: body['code'] as String? ?? body['error'] as String?,
      );
    }
    return InsforgeException(e.message ?? 'Network error', statusCode: e.response?.statusCode);
  }
}
