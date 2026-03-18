import 'package:dio/dio.dart';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  late Dio dio;
  final _storage = const FlutterSecureStorage();

  String? _memoryToken; 
  String? get activeToken => _memoryToken;

  factory DioClient() => _instance;

  DioClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: Platform.isAndroid ? 'https://10.0.2.2:8080/api' : 'https://localhost:8080/api',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        String? tokenToUse = _memoryToken;

        if (tokenToUse == null) {
          tokenToUse = await _storage.read(key: 'jwt_token');
          _memoryToken = tokenToUse; 
        }

        if (tokenToUse != null) {
          options.headers['Authorization'] = 'Bearer $tokenToUse';
        }
        print("🌐 Request: ${options.method} ${options.path}");
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        print("❌ HTTP Error: ${e.response?.statusCode} - ${e.message}");
        return handler.next(e);
      }
    ));
  }

  void setToken(String? token) {
      _memoryToken = token;
    }

  Future<Response> login(String email, String password) async {
    return await dio.post('/auth/login', data: {
      'email': email, 
      'password': password
    });
  }

  Future<Response> register(String username, String email, String password) async {
    return await dio.post('/auth/register', data: {
      'username': username,
      'email': email, 
      'password': password
    });
  }

  Future<Map<String, dynamic>?> searchUser(String email) async {
    try {
      print("🔍 Searching for user: $email");
      
      final response = await dio.get('/auth/search', queryParameters: {'email': email});
      
      print("✅ User found: ${response.data}");
      return response.data;
    } catch (e) {
      print("❌ Search Failed. Reason: $e");
      return null;
    }
  }

  Future<List<dynamic>> getChatHistory(String partnerId) async {
    try {
      final response = await dio.get('/chat/history/$partnerId');
      return response.data;
    } catch (e) {
      print("⚠️ Could not fetch history: $e");
      return [];
    }
  }

  Future<String?> uploadEncryptedFile(List<int> encryptedBytes, String filename) async {
    try {
      FormData formData = FormData.fromMap({
        "file": MultipartFile.fromBytes(
          encryptedBytes,
          filename: "$filename.enc", 
        ),
      });

      Response response = await dio.post(
        '/upload', 
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data['attachment_id'];
      }
      return null;
    } catch (e) {
      print("❌ File upload failed: $e");
      return null;
    }
  }

  Future<Response> verifyOtp(String email, String otp) async {
    return await dio.post('/auth/verify-otp', data: {
      'email': email,
      'otp': otp,
    });
  }

  Future<Map<String, dynamic>?> getSettings() async {
    try {
      final response = await dio.get('/auth/settings');
      return response.data;
    } catch (e) {
      print("Get settings error: $e");
      return null;
    }
  }

  Future<bool> updateSettings(Map<String, bool> settings) async {
    try {
      await dio.post('/auth/settings', data: settings);
      return true;
    } catch (e) {
      print("Update settings error: $e");
      return false;
    }
  }
}