import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

import 'domain.dart';

class AppConfig {
  final String baseUrl, authMode, supabaseUrl, supabaseKey;
  const AppConfig({
    this.baseUrl = const String.fromEnvironment(
      'YARDLINE_API_BASE_URL',
      defaultValue: 'https://yardline-bhavya0303.netlify.app',
    ),
    this.authMode = const String.fromEnvironment(
      'YARDLINE_AUTH_MODE',
      defaultValue: 'demo',
    ),
    this.supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
    this.supabaseKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
  });
  void validate() {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const ApiFailure(
        'CONFIGURATION',
        'Use an HTTPS API origin without a path, query, or credentials.',
      );
    }
    if (authMode != 'demo' && authMode != 'supabase') {
      throw const ApiFailure(
        'CONFIGURATION',
        'Auth mode must be demo or supabase.',
      );
    }
    if (authMode == 'supabase' &&
        (supabaseUrl.isEmpty || supabaseKey.isEmpty)) {
      throw const ApiFailure(
        'CONFIGURATION',
        'Provide the existing SUPABASE_URL and public SUPABASE_ANON_KEY at build time.',
      );
    }
  }
}

abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceStore implements LocalStore {
  final FlutterSecureStorage secure;
  const DeviceStore([this.secure = const FlutterSecureStorage()]);
  @override
  Future<String?> read(String key) => secure.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      secure.write(key: key, value: value);
  @override
  Future<void> delete(String key) => secure.delete(key: key);
}

class SecureSessionStorage extends LocalStorage {
  final LocalStore store;
  final String key;
  const SecureSessionStorage(this.store, this.key);
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await store.read(key) != null;
  @override
  Future<String?> accessToken() => store.read(key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      store.write(key, persistSessionString);
  @override
  Future<void> removePersistedSession() => store.delete(key);
}

class ApiFailure implements Exception {
  final String code, message;
  final int? status;
  final bool uncertain;
  const ApiFailure(
    this.code,
    this.message, {
    this.status,
    this.uncertain = false,
  });
  @override
  String toString() => message;
}

abstract class YardApi {
  Future<void> operatorSession();
  Future<Snapshot> state(String? yardId);
  Future<Json> action(String action, Json payload);
  Future<Uint8List> photo(String id);
}

class HttpYardApi implements YardApi {
  final Dio dio;
  final AppConfig config;
  final String? Function() accessToken;
  HttpYardApi(this.config, {Dio? client, String? Function()? token})
    : dio = client ?? Dio(),
      accessToken = token ?? (() => null) {
    dio.options = BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      sendTimeout: const Duration(seconds: 25),
      headers: {'Accept': 'application/json'},
    );
    dio.interceptors.add(CookieManager(CookieJar()));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (config.authMode == 'supabase') {
            final token = accessToken();
            if (token == null) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  error: const ApiFailure(
                    'UNAUTHENTICATED',
                    'Sign in with your worker account.',
                    status: 401,
                  ),
                ),
              );
              return;
            }
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }
  ApiFailure failure(Object e, {bool mutation = false}) {
    if (e is ApiFailure) return e;
    if (e is DioException) {
      if (e.error is ApiFailure) return e.error as ApiFailure;
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (data is Map && data['error'] is Map) {
        final error = data['error'] as Map;
        return ApiFailure(
          string(error['code']),
          string(error['message']),
          status: status,
          uncertain: mutation && (status == null || status >= 500),
        );
      }
      return ApiFailure(
        status == null ? 'CONNECTION' : 'HTTP_$status',
        status == null
            ? 'Cannot reach Yardline. Check the connection and refresh.'
            : 'The server returned HTTP $status. Refresh before continuing.',
        status: status,
        uncertain: mutation && (status == null || status >= 500),
      );
    }
    return ApiFailure(
      'INVALID_RESPONSE',
      'Could not read the server response. Refresh before continuing.',
      uncertain: mutation,
    );
  }

  Snapshot checked(dynamic value) {
    final state = Snapshot(value as Json);
    if (state.authMode != config.authMode) {
      throw const ApiFailure(
        'AUTH_MODE_MISMATCH',
        'The API authentication mode differs from this app configuration.',
      );
    }
    if (config.authMode == 'demo' && state.actor['role'] != 'operator') {
      throw const ApiFailure(
        'SESSION_MISMATCH',
        'Demo operator session was lost. Reconnect to continue.',
        status: 401,
      );
    }
    return state;
  }

  @override
  Future<void> operatorSession() async {
    try {
      await dio.post('/api/session', data: {'role': 'operator'});
    } catch (e) {
      throw failure(e);
    }
  }

  @override
  Future<Snapshot> state(String? yardId) async {
    try {
      return checked(
        (await dio.get(
          '/api/state',
          queryParameters: yardId == null ? null : {'yard': yardId},
        )).data,
      );
    } catch (e) {
      throw failure(e);
    }
  }

  @override
  Future<Json> action(String action, Json payload) async {
    try {
      if (utf8.encode(jsonEncode(payload)).length > 3000000) {
        throw const ApiFailure(
          'TOO_LARGE',
          'The image makes this request too large. Remove it or take a smaller photo.',
        );
      }
      final response = await dio.post('/api/actions/$action', data: payload);
      final result = response.data as Json;
      checked(result['state']);
      return result;
    } catch (e) {
      if (e is ApiFailure &&
          (e.code == 'AUTH_MODE_MISMATCH' || e.code == 'SESSION_MISMATCH')) {
        throw ApiFailure(e.code, e.message, status: e.status, uncertain: true);
      }
      throw failure(e, mutation: true);
    }
  }

  @override
  Future<Uint8List> photo(String id) async {
    try {
      final response = await dio.get<List<int>>(
        '/api/containers/${Uri.encodeComponent(id)}/photo',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } catch (e) {
      throw failure(e);
    }
  }
}

class OcrResult {
  final String text;
  final List<String> candidates;
  const OcrResult(this.text, this.candidates);
}

class OcrService {
  Future<OcrResult> recognize(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      return OcrResult(result.text, extractCandidates(result.text));
    } finally {
      await recognizer.close();
    }
  }

  /// Attachments are optional; OCR and confirmed identity work without an upload.
  Future<String?> attachment(XFile file) async {
    final bytes = await file.readAsBytes();
    final jpeg = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;
    final png =
        bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final webp =
        bytes.length > 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    if (!jpeg && !png && !webp) return null;
    final result =
        'data:image/${jpeg
            ? 'jpeg'
            : png
            ? 'png'
            : 'webp'};base64,${base64Encode(bytes)}';
    return result.length <= 2800000 ? result : null;
  }
}
