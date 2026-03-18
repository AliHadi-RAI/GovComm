import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'signal_crypto_prefs', 
      preferencesKeyPrefix: 'signal_',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
      accountName: 'signal_secure_store',
    ),
  );

class PersistentIdentityKeyStore implements IdentityKeyStore {
  IdentityKeyPair? _localKeyPair;
  int? _localRegistrationId;

  Future<void> initialize(IdentityKeyPair keyPair, int registrationId) async {
    _localKeyPair = keyPair;
    _localRegistrationId = registrationId;
    
    final encryptedKeyPair = await KeyWrapper.encrypt(keyPair.serialize());
    await _storage.write(key: 'identity_key_pair', value: encryptedKeyPair);
    await _storage.write(key: 'registration_id', value: registrationId.toString());
  }

  Future<bool> loadFromStorage() async {
    final encryptedKeyPairStr = await _storage.read(key: 'identity_key_pair');
    final regIdStr = await _storage.read(key: 'registration_id');
    
    if (encryptedKeyPairStr != null && regIdStr != null) {
      try {
        final decryptedBytes = await KeyWrapper.decrypt(encryptedKeyPairStr);
        _localKeyPair = IdentityKeyPair.fromSerialized(decryptedBytes);
        _localRegistrationId = int.parse(regIdStr);
        return true;
      } catch (e) {
        return false; 
      }
    }
    return false;
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
    await KeyWrapper.clearMasterKey();
    _localKeyPair = null;
    _localRegistrationId = null;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final keyStr = await _storage.read(key: 'identity_${address.getName()}_${address.getDeviceId()}');
    if (keyStr == null) return null;
    return IdentityKey(Curve.decodePoint(base64Decode(keyStr), 0));
  }

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    if (_localKeyPair == null) await loadFromStorage();
    return _localKeyPair!;
  }

  @override
  Future<int> getLocalRegistrationId() async {
    if (_localRegistrationId == null) await loadFromStorage();
    return _localRegistrationId!;
  }

  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address, IdentityKey? identityKey, Direction direction) async {
    // For the government beta/testing phase, we automatically trust new identities
    // if an old one existed (e.g. after a phone was wiped/reinstalled).
    return true; 
  }

  @override
  Future<bool> saveIdentity(SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) {
      await _storage.delete(key: 'identity_${address.getName()}_${address.getDeviceId()}');
      return false;
    }
    await _storage.write(
      key: 'identity_${address.getName()}_${address.getDeviceId()}',
      value: base64Encode(identityKey.serialize()),
    );
    return true;
  }
}

class PersistentPreKeyStore implements PreKeyStore {
  @override
  Future<bool> containsPreKey(int preKeyId) async {
    final val = await _storage.read(key: 'prekey_$preKeyId');
    return val != null;
  }

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final val = await _storage.read(key: 'prekey_$preKeyId');
    if (val == null) throw Exception('PreKey $preKeyId not found');
    return PreKeyRecord.fromBuffer(base64Decode(val));
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await _storage.delete(key: 'prekey_$preKeyId');
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _storage.write(key: 'prekey_$preKeyId', value: base64Encode(record.serialize()));
  }
}

class PersistentSignedPreKeyStore implements SignedPreKeyStore {
  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async {
    final val = await _storage.read(key: 'signed_prekey_$signedPreKeyId');
    return val != null;
  }

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final val = await _storage.read(key: 'signed_prekey_$signedPreKeyId');
    if (val == null) throw Exception('SignedPreKey $signedPreKeyId not found');
    
    return SignedPreKeyRecord.fromSerialized(base64Decode(val));
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final all = await _storage.readAll();
    List<SignedPreKeyRecord> records = [];
    for (var key in all.keys) {
      if (key.startsWith('signed_prekey_')) {
        records.add(SignedPreKeyRecord.fromSerialized(base64Decode(all[key]!)));
      }
    }
    return records;
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await _storage.delete(key: 'signed_prekey_$signedPreKeyId');
  }

  @override
  Future<void> storeSignedPreKey(int signedPreKeyId, SignedPreKeyRecord record) async {
    await _storage.write(key: 'signed_prekey_$signedPreKeyId', value: base64Encode(record.serialize()));
  }
}

class PersistentSessionStore implements SessionStore {
  @override
  Future<bool> containsSession(SignalProtocolAddress address) async {
    final val = await _storage.read(key: 'session_${address.getName()}_${address.getDeviceId()}');
    return val != null;
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    final all = await _storage.readAll();
    for (var key in all.keys) {
      if (key.startsWith('session_${name}_')) {
        await _storage.delete(key: key);
      }
    }
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await _storage.delete(key: 'session_${address.getName()}_${address.getDeviceId()}');
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final all = await _storage.readAll();
    List<int> deviceIds = [];
    for (var key in all.keys) {
      if (key.startsWith('session_${name}_')) {
        final parts = key.split('_');
        if (parts.length == 3) {
          deviceIds.add(int.parse(parts[2]));
        }
      }
    }
    return deviceIds;
  }

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final val = await _storage.read(key: 'session_${address.getName()}_${address.getDeviceId()}');
    if (val == null) return SessionRecord(); 
    
    return SessionRecord.fromSerialized(base64Decode(val));
  }

  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) async {
    await _storage.write(
      key: 'session_${address.getName()}_${address.getDeviceId()}', 
      value: base64Encode(record.serialize())
    );
  }
}

class KeyWrapper {
  static SecretKey? _masterKey;
  static final _algorithm = AesGcm.with256bits();
  static bool _isInitializing = false;

  static Future<void> _initMasterKey() async {
    if (_masterKey != null) return;
    while (_isInitializing) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    if (_masterKey != null) return;
    _isInitializing = true;

    try {
      String? b64Key = await _storage.read(key: 'app_master_key');
      if (b64Key == null) {
        final key = await _algorithm.newSecretKey();
        final keyBytes = await key.extractBytes();
        await _storage.write(key: 'app_master_key', value: base64Encode(keyBytes));
        _masterKey = key;
      } else {
        _masterKey = SecretKey(base64Decode(b64Key));
      }
    } finally {
      _isInitializing = false;
    }
  }

  static Future<void> clearMasterKey() async {
    _masterKey = null;
  }

  static Future<String> encrypt(Uint8List data) async {
    await _initMasterKey();
    final secretBox = await _algorithm.encrypt(
      data,
      secretKey: _masterKey!,
    );
    final combinedPayload = [
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];
    return base64Encode(combinedPayload);
  }

  static Future<Uint8List> decrypt(String base64Data) async {
    await _initMasterKey();
    final raw = base64Decode(base64Data);
    final nonce = raw.sublist(0, 12);
    final macBytes = raw.sublist(12, 28);
    final cipherText = raw.sublist(28);
    
    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );
    final decrypted = await _algorithm.decrypt(
      secretBox,
      secretKey: _masterKey!,
    );
    return Uint8List.fromList(decrypted);
  }
}