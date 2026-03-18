import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Adjust this import path to point to your actual SignalService location
import 'file:///C:/Users/User/Desktop/Project_Govcomm/APP/govccomm_frontend/lib/crypto/signal_service.dart';
void main() {
  // 1. Initialize the Flutter test binding
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 2. Mock the secure storage so it doesn't crash trying to access native Android/iOS APIs
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('Identity Key Pinning (TOFU) prevents MITM attacks', () async {
    // Initialize local SignalService
    final signalService = SignalService();
    await signalService.initializeLocalIdentity(1); // Local User ID 1
    
    final partnerUserId = 2; // The user we are connecting to

    // ==========================================
    // GENERATE LEGITIMATE BUNDLE (User 2)
    // ==========================================
    final legitIdentityKeyPair = generateIdentityKeyPair();
    final legitSignedPreKey = generateSignedPreKey(legitIdentityKeyPair, 1);
    final legitPreKey = generatePreKeys(1, 1)[0];

    final legitBundle = {
      'identityKey': base64Encode(legitIdentityKeyPair.getPublicKey().serialize()),
      'signedPreKey': {
        'keyId': legitSignedPreKey.id,
        'publicKey': base64Encode(legitSignedPreKey.getKeyPair().publicKey.serialize()),
        'signature': base64Encode(legitSignedPreKey.signature),
      },
      'preKey': {
        'keyId': legitPreKey.id,
        'publicKey': base64Encode(legitPreKey.getKeyPair().publicKey.serialize()),
      },
      'registrationId': 12345
    };

    // ==========================================
    // GENERATE ATTACKER BUNDLE (Fake User 2)
    // ==========================================
    // The attacker generates their OWN keys, trying to pretend to be User 2
    final attackerIdentityKeyPair = generateIdentityKeyPair(); // DIFFERENT Identity Key!
    final attackerSignedPreKey = generateSignedPreKey(attackerIdentityKeyPair, 1);
    final attackerPreKey = generatePreKeys(1, 1)[0];

    final attackerBundle = {
      'identityKey': base64Encode(attackerIdentityKeyPair.getPublicKey().serialize()),
      'signedPreKey': {
        'keyId': attackerSignedPreKey.id,
        'publicKey': base64Encode(attackerSignedPreKey.getKeyPair().publicKey.serialize()),
        'signature': base64Encode(attackerSignedPreKey.signature),
      },
      'preKey': {
        'keyId': attackerPreKey.id,
        'publicKey': base64Encode(attackerPreKey.getKeyPair().publicKey.serialize()),
      },
      'registrationId': 67890
    };

    // ==========================================
    // EXECUTE TEST ASSERTONS
    // ==========================================

    // ACTION 1: Process the legitimate bundle first. 
    // EXPECTATION: It should process normally and pin/save the Identity Key.
    await expectLater(
      () async => await signalService.buildSessionWithPartner(partnerUserId, legitBundle),
      returnsNormally,
      reason: 'First time connection (TOFU) with legitimate keys should succeed',
    );

    // ACTION 2: Server is compromised! It sends the Attacker's bundle for the same partnerUserId.
    // EXPECTATION: The TOFU check must detect the Identity Key mismatch and throw our Exception.
    await expectLater(
      () async => await signalService.buildSessionWithPartner(partnerUserId, attackerBundle),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(), 
          'message', 
          contains('SECURITY HOLE PREVENTED'), // Matches the exception string we added
        )
      ),
      reason: 'Should reject new bundle if the Identity Key does not match the pinned key',
    );
  });
}