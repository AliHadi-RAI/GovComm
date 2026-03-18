import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; 
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'persistent_signal_stores.dart';

class SignalService {
  late PersistentSessionStore sessionStore;
  late PersistentPreKeyStore preKeyStore;
  late PersistentSignedPreKeyStore signedPreKeyStore;
  late PersistentIdentityKeyStore identityStore;

  SignalService() {
    sessionStore = PersistentSessionStore();
    preKeyStore = PersistentPreKeyStore();
    signedPreKeyStore = PersistentSignedPreKeyStore();
    identityStore = PersistentIdentityKeyStore();
  }

  Future<void> initializeLocalIdentity(int localUserId) async {
    bool hasIdentity = await identityStore.loadFromStorage();
    
    if (hasIdentity) {
      debugPrint("🛡️ [KeyManager] Local identity verified.");
      return;
    }

    debugPrint("⚠️ [KeyManager] Generating new cryptographic identity in background...");
    
    final bundle = await compute(_generateInitialBundle, null);

    await identityStore.clearAll(); 
    await identityStore.initialize(bundle.identityKeyPair, bundle.registrationId);
    await signedPreKeyStore.storeSignedPreKey(bundle.signedPreKey.id, bundle.signedPreKey);

    for (var preKey in bundle.preKeys) {
      await preKeyStore.storePreKey(preKey.id, preKey);
    }
    
    debugPrint("✅ [KeyManager] Identity initialized successfully.");
  }

  static _InitialBundle _generateInitialBundle(_) {
    final identityKeyPair = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    final signedPreKey = generateSignedPreKey(identityKeyPair, 1);
    final preKeys = generatePreKeys(0, 30); 

    return _InitialBundle(identityKeyPair, registrationId, signedPreKey, preKeys);
  }

  Future<Map<String, dynamic>> getPublicBundleToPublish() async {
    final identityKeyPair = await identityStore.getIdentityKeyPair();
    final signedPreKey = await signedPreKeyStore.loadSignedPreKey(1);
    
    List<Map<String, dynamic>> preKeyList = [];
    for (int i = 0; i < 30; i++) {
       try {
         final pk = await preKeyStore.loadPreKey(i);
         final rawPublicKeyBytes = pk.getKeyPair().publicKey.serialize();
         
         preKeyList.add({
           'keyId': pk.id,
           'publicKey': base64Encode(rawPublicKeyBytes),
         });
       } catch (e) {
         continue;
       }
    }

    return {
      'identityKey': base64Encode(identityKeyPair.getPublicKey().serialize()),
      'signedPreKey': {
        'keyId': signedPreKey.id,
        'publicKey': base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
        'signature': base64Encode(signedPreKey.signature),
      },
      'preKeys': preKeyList,
    };
  }

  Future<void> buildSessionWithPartner(int partnerUserId, Map<String, dynamic> remoteBundle) async {
    final idKeyB64 = remoteBundle['identityKey'];
    final spkPublicB64 = remoteBundle['signedPreKey']?['publicKey'];
    final spkSigB64 = remoteBundle['signedPreKey']?['signature'];

    if (idKeyB64 == null || spkPublicB64 == null || spkSigB64 == null) {
      throw Exception("CRITICAL: Server returned missing keys in the bundle!");
    }

    final remoteIdentityBytes = base64Decode(idKeyB64);
    final signedPreKeyPublicBytes = base64Decode(spkPublicB64);
    final spkSignature = Uint8List.fromList(base64Decode(spkSigB64));

    final remoteIdentity = IdentityKey.fromBytes(remoteIdentityBytes, 0); 
    final signedPreKeyPublic = Curve.decodePoint(signedPreKeyPublicBytes, 0);
    final remoteAddress = SignalProtocolAddress(partnerUserId.toString(), 1);
    
    final isTrusted = await identityStore.isTrustedIdentity(remoteAddress, remoteIdentity, Direction.sending);
    
    if (!isTrusted) {
      debugPrint("⚠️ [Crypto] Identity changed for $partnerUserId. Updating trust...");
      // For this app's testing phase, we allow updating the identity automatically.
      await identityStore.saveIdentity(remoteAddress, remoteIdentity);
    } else {
      await identityStore.saveIdentity(remoteAddress, remoteIdentity);
    }

    final sessionBuilder = SessionBuilder(
      sessionStore, preKeyStore, signedPreKeyStore, identityStore, remoteAddress
    );

    ECPublicKey? preKeyPublic;
    if (remoteBundle['preKey'] != null) {
      preKeyPublic = Curve.decodePoint(base64Decode(remoteBundle['preKey']['publicKey']), 0);
    }

    final preKeyBundle = PreKeyBundle(
      remoteBundle['registrationId'] ?? 0, 
      1, 
      remoteBundle['preKey']?['keyId'],
      preKeyPublic,
      remoteBundle['signedPreKey']['keyId'],
      signedPreKeyPublic,
      spkSignature,
      remoteIdentity
    );

    await sessionBuilder.processPreKeyBundle(preKeyBundle);
  }

  Future<Map<String, dynamic>> encryptMessage(int partnerUserId, String plaintext) async {
    final remoteAddress = SignalProtocolAddress(partnerUserId.toString(), 1);
    final sessionCipher = SessionCipher(
      sessionStore, preKeyStore, signedPreKeyStore, identityStore, remoteAddress
    );

    final ciphertextMessage = await sessionCipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    
    return {
      'type': ciphertextMessage.getType(), 
      'ciphertext': base64Encode(ciphertextMessage.serialize()),
    };
  }

  Future<String> decryptMessage(int partnerUserId, int messageType, String base64Ciphertext) async {
    final remoteAddress = SignalProtocolAddress(partnerUserId.toString(), 1);
    final sessionCipher = SessionCipher(
      sessionStore, preKeyStore, signedPreKeyStore, identityStore, remoteAddress
    );

    final decodedCiphertext = base64Decode(base64Ciphertext);
    Uint8List plaintextBytes;

    if (messageType == CiphertextMessage.prekeyType) {
      final preKeyMessage = PreKeySignalMessage(decodedCiphertext);
      plaintextBytes = await sessionCipher.decrypt(preKeyMessage); 
    } else {
      final whisperMessage = SignalMessage.fromSerialized(decodedCiphertext);
      plaintextBytes = await sessionCipher.decryptFromSignal(whisperMessage); 
    }

    return utf8.decode(plaintextBytes);
  }

  Future<void> deleteSession(int partnerUserId) async {
    final remoteAddress = SignalProtocolAddress(partnerUserId.toString(), 1);
    await sessionStore.deleteAllSessions(remoteAddress.getName());
  }
}

class _InitialBundle {
  final IdentityKeyPair identityKeyPair;
  final int registrationId;
  final SignedPreKeyRecord signedPreKey;
  final List<PreKeyRecord> preKeys;
  _InitialBundle(this.identityKeyPair, this.registrationId, this.signedPreKey, this.preKeys);
}