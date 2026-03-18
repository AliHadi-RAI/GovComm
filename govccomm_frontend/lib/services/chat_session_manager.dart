import '/crypto/signal_service.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

class ChatSessionManager {
  final SignalService signalService;

  ChatSessionManager(this.signalService);
  
  Future<bool> hasSession(int partnerId) async {
    final remoteAddress = SignalProtocolAddress(partnerId.toString(), 1);
    return await signalService.sessionStore.containsSession(remoteAddress);
  }

  Future<void> saveSession(int partnerId) async {}
  Future<void> loadSession(int partnerId) async {}
  dynamic getSession(int partnerId) => true; 
  dynamic get service => this; 

  Future<void> establishSession(int partnerId, Map<String, dynamic> remoteBundle) async {
    await signalService.buildSessionWithPartner(partnerId, remoteBundle);
  }

  Future<Map<String, dynamic>> encrypt(int partnerId, String text) async {
    return await signalService.encryptMessage(partnerId, text);
  }

  Future<String> decrypt(int partnerId, int type, String ciphertext) async {
    return await signalService.decryptMessage(partnerId, type, ciphertext);
  }
}