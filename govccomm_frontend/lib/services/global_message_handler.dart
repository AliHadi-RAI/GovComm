import 'dart:async'; 
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'chat_session_manager.dart';
import 'database_service.dart';
import 'socket_service.dart';
import '../models/message_model.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

class GlobalMessageHandler {
  static final GlobalMessageHandler _instance = GlobalMessageHandler._internal();
  factory GlobalMessageHandler() => _instance;

  final _socketService = SocketService();
  final _dbService = DatabaseService();
  final _audioPlayer = AudioPlayer();
  
  late ChatSessionManager _sessionManager;
  String? _myUserId;
  
  StreamSubscription? _subscription; 

  GlobalMessageHandler._internal();

  void initialize(String myUserId, ChatSessionManager sessionManager) {
    _myUserId = myUserId;
    _sessionManager = sessionManager;
    
    if (_subscription != null) {
      debugPrint("🛡️ [GMH] Background listener already active. Skipping duplicate.");
      return;
    }

    debugPrint("🧠 GMH INIT for $_myUserId");

    _subscription = _socketService.messageStream.listen((data) async {
      debugPrint("🌐 GMH RAW PACKET: ${jsonEncode(data)}");
      await _processAndSaveMessage(data);
    });
  }

  Future<void> _processAndSaveMessage(Map<String, dynamic> data) async {
    try {
      final senderId = data['senderId']?.toString();
      final senderUsername = data['senderUsername']?.toString(); 

      if (senderId == null || senderId == _myUserId) return;


      if (senderUsername != null) {
        await _dbService.saveUserCache(senderId, senderUsername, ""); 
        debugPrint("👤 [GMH] Cached identity for: $senderUsername");
      }

      debugPrint("============================================");
      debugPrint("📥 [DEBUG] RECEIVED PACKET FROM: $senderId");

      String ciphertext = data['ciphertext'] ?? '';
      String displayText = ciphertext; 
      bool isDecrypted = false;

      try {
        debugPrint("🔐 [DEBUG] Attempting Decryption...");
        int partnerId = int.parse(senderId);
        int messageType = data['messageType'] ?? 2; 

        if (ciphertext.isNotEmpty) {
          displayText = await _sessionManager.decrypt(partnerId, messageType, ciphertext);
          isDecrypted = true;
          debugPrint("✅ [DEBUG] DECRYPTION SUCCESS: $displayText");
        }
      } catch (e) {
          debugPrint("❌ [DEBUG] DECRYPTION FAILED: $e");
          displayText = "⚠️ Keys out of sync.";
          
          int partnerId = int.parse(senderId);
          await _sessionManager.signalService.deleteSession(partnerId);
          await _sessionManager.signalService.identityStore.saveIdentity(
              SignalProtocolAddress(senderId, 1), null
          );
          _socketService.requestSessionReset(senderId);
      }

      final msg = Message(
        id: data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: senderId,
        receiverId: _myUserId!,
        ciphertext: displayText,
        iv: '', 
        timestamp: data['timestamp'] != null ? DateTime.parse(data['timestamp']) : DateTime.now(),
        counter: isDecrypted ? 0 : -1, 
      );

      await _dbService.saveMessage(msg, false, isRead: false, isDelivered: true); 
      
      try {
        await _audioPlayer.play(AssetSource('sounds/ding.mp3'));
      } catch (e) {
        debugPrint("🔈 [GMH] Audio error: $e");
      }
      
      _socketService.notifyUIOfNewMessage(data);

      debugPrint("============================================");

    } catch (e) {
      debugPrint("🔥 GMH EXCEPTION: $e");
    }
  }
}