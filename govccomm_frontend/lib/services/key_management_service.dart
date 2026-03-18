import 'package:flutter/foundation.dart';
import '../crypto/signal_service.dart';
import 'dio_client.dart'; 

class KeyManagementService {
  final SignalService signalService;

  KeyManagementService(this.signalService);

  Future<void> ensureKeysPublished(int userId) async {
    try {
      bool hasLocalIdentity = await signalService.identityStore.loadFromStorage();
      
      await signalService.initializeLocalIdentity(userId);
      if (!hasLocalIdentity) {
        debugPrint("📦 [KeyManager] New local identity generated. Force publishing bundle...");
        await _publishCurrentBundle();
        return; 
      }

      final response = await DioClient().dio.get('/auth/keys/count');
      int count = response.data['count'] ?? 0;

      if (count < 10) { 
        debugPrint("📦 [KeyManager] Server prekeys low/empty ($count). Publishing bundle...");
        await _publishCurrentBundle();
      } else {
        debugPrint("🛡️ [KeyManager] Server already has $count keys. Skipping overwrite.");
      }
    } catch (e) {
      debugPrint("⚠️ [KeyManager] Key check failed: $e");
    }
  }

  Future<void> _publishCurrentBundle() async {
    final bundle = await signalService.getPublicBundleToPublish();
    await DioClient().dio.post('/auth/keys', data: bundle);
    debugPrint("✅ [KeyManager] Bundle published.");
  }

  Future<void> checkAndReplenishKeys(int userId) async {
    debugPrint("🔍 [KeyManager] Key replenishment check stubbed.");
  }
}