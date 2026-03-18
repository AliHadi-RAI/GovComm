import 'dart:typed_data';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class FileCryptoService {
  static Future<Map<String, dynamic>> encryptFileBytes(Uint8List fileBytes) async {
    final algorithm = AesGcm.with256bits();
    
    final secretKey = await algorithm.newSecretKey();
    final nonce = algorithm.newNonce();

    final secretBox = await algorithm.encrypt(
      fileBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    final keyBytes = await secretKey.extractBytes();

    return {
      'encryptedBytes': secretBox.cipherText,        
      'aesKeyBase64': base64Encode(keyBytes),         
      'nonceBase64': base64Encode(nonce),             
      'macBase64': base64Encode(secretBox.mac.bytes), 
    };
  }

  static Future<Uint8List> decryptFileBytes({
    required List<int> encryptedBytes,
    required String aesKeyBase64,
    required String nonceBase64,
    required String macBase64,
  }) async {
    final algorithm = AesGcm.with256bits();
    
    final secretKey = SecretKey(base64Decode(aesKeyBase64));
    final nonce = base64Decode(nonceBase64);
    final mac = Mac(base64Decode(macBase64));
    
    final secretBox = SecretBox(encryptedBytes, nonce: nonce, mac: mac);
    
    final decrypted = await algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decrypted);
  }
}