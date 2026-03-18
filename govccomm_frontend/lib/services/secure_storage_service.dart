import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  Future<void> persistKey(String label, String keyContent) async {
    await _storage.write(key: label, value: keyContent);
  }

  Future<String?> retrieveKey(String label) async {
    return await _storage.read(key: label);
  }

  Future<void> deleteKey(String label) async {
    await _storage.delete(key: label);
  }
}