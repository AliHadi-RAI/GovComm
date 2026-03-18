import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart'; 
import 'package:file_picker/file_picker.dart';
import 'dart:io';            
import 'dart:typed_data';    
import 'dart:convert';
import 'package:dio/dio.dart'; 
import 'package:path_provider/path_provider.dart';

import '../../crypto/signal_service.dart';
import '../../crypto/file_crypto_service.dart';
import '../../services/dio_client.dart';
import '../../services/socket_service.dart';
import '../../services/chat_session_manager.dart';
import '../../services/key_management_service.dart';
import '../../services/database_service.dart';
import '../../services/voice_note_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import '../../models/message_model.dart';
import '../../models/user_model.dart';

final sharedSignalService = SignalService();

class ChatScaffold extends StatefulWidget {
  final User targetUser;

  const ChatScaffold({super.key, required this.targetUser});

  @override
  State<ChatScaffold> createState() => _ChatScaffoldState();
}

class _ChatScaffoldState extends State<ChatScaffold> {
  final _storage = const FlutterSecureStorage();
  final _socketService = SocketService();
  final _dbService = DatabaseService();
  
  late final ChatSessionManager _sessionManager;
  late final KeyManagementService _keyManager;

  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _voiceService = VoiceNoteService();
  final _audioPlayer = AudioPlayer();
  
  bool _isRecording = false;
  String? _currentlyPlayingId;
  
  StreamSubscription? _socketSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _receiptSubscription;
  StreamSubscription? _handshakeSubscription; 

  String _partnerStatus = 'offline';

  List<Message> _messages = [];
  String? _myUserId; 
  bool _isHandshaking = false;

@override
  void initState() {
    super.initState();
    _sessionManager = ChatSessionManager(sharedSignalService);
    _keyManager = KeyManagementService(sharedSignalService);

    _socketSubscription = _socketService.processedStream.listen((data) async {
       final senderId = data['senderId'].toString();
       if (widget.targetUser.id == senderId) {
         debugPrint("🔔 [Chat] Message processed and saved. Refreshing UI...");
         if (mounted) {
           await _dbService.markAsRead(widget.targetUser.id, _myUserId!);
           _socketService.socket?.emit('markRead', {'senderId': widget.targetUser.id});
           await _loadChat(senderId);
           _scrollToBottom();
         }
       }
    });

    _statusSubscription = _socketService.statusStream.listen((statuses) {
      if (mounted) {
        setState(() {
          _partnerStatus = statuses[widget.targetUser.id] ?? 'offline';
        });
      }
    });

    _receiptSubscription = _socketService.receiptStream.listen((data) async {
      if (data['type'] == 'ack') {
        final String tempId = data['tempId']?.toString() ?? "";
        final String serverId = data['id']?.toString() ?? "";
        final bool isDelivered = data['isDelivered'] == true;

        if (tempId.isNotEmpty && serverId.isNotEmpty) {
           await _dbService.updateMessageId(tempId, serverId);
           await _dbService.updateMessageStatus(serverId, isDelivered: isDelivered);
        }
      } else if (data['type'] == 'read') {
        if (data['readBy'].toString() == widget.targetUser.id) {
           await _dbService.markSentMessagesAsRead(widget.targetUser.id, _myUserId!);
        }
      }
      if (mounted) _loadChat(widget.targetUser.id);
    });

    _handshakeSubscription = _socketService.messageStream.listen((data) async {
       if (data['type'] == 'sessionReset' && data['partnerId'] == widget.targetUser.id) {
         debugPrint("🤝 [Chat] Received Background Handshake Request. Wiping session...");
         await _sessionManager.signalService.deleteSession(int.parse(widget.targetUser.id));
         final address = SignalProtocolAddress(widget.targetUser.id, 1);
         await _sessionManager.signalService.identityStore.saveIdentity(address, null);
         
         // Trigger a fresh establish just to be sure
         final bundleResponse = await DioClient().dio.get('/auth/keys/${widget.targetUser.id}');
         await _sessionManager.establishSession(int.parse(widget.targetUser.id), bundleResponse.data);
       }
    });

    _initSetup();
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _statusSubscription?.cancel();
    _receiptSubscription?.cancel();
    _handshakeSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _voiceService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
Future<void> _initSetup() async {
    debugPrint("⚙️ [DEBUG] Starting _initSetup...");
    final token = DioClient().activeToken ?? await _storage.read(key: 'jwt_token');
    
    if (token != null) {
      debugPrint("⚙️ [DEBUG] Token found in storage.");
      if (!_socketService.isConnected) {
        debugPrint("⚙️ [DEBUG] Socket not connected. Attempting connection...");
        _socketService.connect(token);
      }
      
      try {
        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
        
        if (mounted) {
          setState(() {
            _myUserId = decodedToken['id']?.toString() ?? decodedToken['userId']?.toString();
            _partnerStatus = _socketService.userStatuses[widget.targetUser.id] ?? 'offline';
            debugPrint("🏁 [Chat] Initial Setup: MyID=$_myUserId, PartnerID=${widget.targetUser.id}, PartnerStatus=$_partnerStatus");
            debugPrint("🏁 [Chat] Known Statuses: ${_socketService.userStatuses}");
          });

          if (_myUserId != null) {
            await _dbService.markAsRead(widget.targetUser.id, _myUserId!);
            _socketService.socket?.emit('markRead', {'senderId': widget.targetUser.id});
            await _loadChat(widget.targetUser.id);
            _scrollToBottom();
          }
        }
        await _ensureKeysSynced();
      } catch (e) {
        debugPrint("❌ [DEBUG] Setup error: $e");
      }
    } else {
      debugPrint("❌ [DEBUG] CRITICAL: No token found in secure storage!");
    }
    await _dbService.saveUserCache(
      widget.targetUser.id, 
      widget.targetUser.username, 
      widget.targetUser.email
    );
  }

Future<void> _ensureKeysSynced() async {
  debugPrint("🛡️ Verifying Key Integrity...");
  if (_myUserId == null) return;
  
  int userId = int.parse(_myUserId!);

  bool hasLocalKeys = await sharedSignalService.identityStore.loadFromStorage();
  
  if (!hasLocalKeys) {
    debugPrint("⚠️ Local keys missing (fresh install or wiped). Regenerating & Overwriting Server...");
    await _keyManager.ensureKeysPublished(userId);
  }
}

Future<void> _loadChat(String partnerId) async {
    if (_myUserId == null) return;
    final localMsgs = await _dbService.getLocalChat(partnerId, _myUserId!);
    
    localMsgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    if (mounted) {
      setState(() => _messages = localMsgs);
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  Future<void> _handleIncomingUIUpdate(Map<String, dynamic> data) async {
    if (!mounted) return;

    final senderId = data['senderId'].toString();
    if (widget.targetUser.id != senderId) return;

    await Future.delayed(const Duration(milliseconds: 300));
    await _loadChat(senderId);
  }

Future<void> _sendMessage() async {
    debugPrint("========== SEND BUTTON TAPPED ==========");
    debugPrint("Current User ID: $_myUserId");
    debugPrint("Target User ID: ${widget.targetUser.id}");
    debugPrint("Message Text: '${_messageController.text}'");

    if (_messageController.text.isEmpty) {
      debugPrint("⚠️ [DEBUG] Aborting: Message is empty.");
      return;
    }
    
    if (_myUserId == null) {
      debugPrint("⚠️ [DEBUG] Aborting: _myUserId is null. Check _initSetup logs.");
      return;
    }

    debugPrint("🚀 [DEBUG] Validation passed. Starting Send Process...");
    final text = _messageController.text;

    try {
      final targetId = int.parse(widget.targetUser.id);

      bool hasSession = await _sessionManager.hasSession(targetId);
      
      if (!hasSession) {
        debugPrint("🤝 [DEBUG] No session. Initiating Handshake...");
        setState(() => _isHandshaking = true);
        final bundleResponse = await DioClient().dio.get('/auth/keys/$targetId');
        await _sessionManager.establishSession(targetId, bundleResponse.data);
        setState(() => _isHandshaking = false);
        debugPrint("✅ [DEBUG] Handshake complete.");
      }

      debugPrint("🔒 [DEBUG] Encrypting message...");
      final encrypted = await _sessionManager.encrypt(targetId, text);

      final msg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(), 
        senderId: _myUserId!, 
        receiverId: widget.targetUser.id, 
        ciphertext: text, 
        iv: '', 
        timestamp: DateTime.now(), 
        counter: 0
      );

      setState(() {
        _messages.add(msg);
        _messageController.clear();
      });
      
      await _dbService.saveMessage(msg, true);
      _scrollToBottom();

      final packet = {
        'receiverId': targetId.toString(),
        'messageType': encrypted['type'], 
        'ciphertext': encrypted['ciphertext'],
        'tempId': msg.id,
      };
      
      debugPrint("📡 [DEBUG] Emitting to Socket: $packet");
      _socketService.sendMessage(packet);

    } catch (e) { 
      debugPrint('❌ [DEBUG] Send Error: $e'); 
      setState(() => _isHandshaking = false);
    }
    debugPrint("========== SEND PROCESS FINISHED ==========");
  }

  Future<void> _pickAndSendFile(String recipientId) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result == null) return; 

      PlatformFile file = result.files.first;

      if (file.size > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File exceeds 5MB limit.')),
        );
        return;
      }

      File localFile = File(file.path!);
      Uint8List fileBytes = await localFile.readAsBytes();

      final cryptoData = await FileCryptoService.encryptFileBytes(fileBytes);

      String? attachmentId = await DioClient().uploadEncryptedFile(
        cryptoData['encryptedBytes'], 
        file.name
      );

      if (attachmentId == null) throw Exception("Upload failed");

      Map<String, dynamic> filePayload = {
        "type": "file",
        "attachment_id": attachmentId,
        "file_name": file.name,
        "aes_key": cryptoData['aesKeyBase64'],
        "nonce": cryptoData['nonceBase64'],
        "mac": cryptoData['macBase64']
      };
      
      final payloadString = jsonEncode(filePayload);
      final targetId = int.parse(recipientId);

      bool hasSession = await _sessionManager.hasSession(targetId);
      if (!hasSession) {
        debugPrint("🤝 [Chat] No session for file. Handshaking...");
        final bundleResponse = await DioClient().dio.get('/auth/keys/$targetId');
        await _sessionManager.establishSession(targetId, bundleResponse.data);
      }

      final encrypted = await _sessionManager.encrypt(targetId, payloadString);

      final msg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(), 
        senderId: _myUserId!, 
        receiverId: recipientId, 
        ciphertext: payloadString, 
        iv: '', 
        timestamp: DateTime.now(), 
        counter: 0
      );

      setState(() {
        _messages.add(msg);
      });
      await _dbService.saveMessage(msg, true);
      _scrollToBottom();

      final packet = {
        'receiverId': recipientId,
        'messageType': encrypted['type'], 
        'ciphertext': encrypted['ciphertext'],
      };
      _socketService.sendMessage(packet);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send file: $e')),
      );
    }
  }

  Future<void> _toggleRecording() async {
    debugPrint("🎙️ [_toggleRecording] isRecording: $_isRecording");
    if (_isRecording) {
      final path = await _voiceService.stopRecording();
      debugPrint("🎙️ [_toggleRecording] Stopped. Path: $path");
      setState(() => _isRecording = false);
      if (path != null) {
        await _sendVoiceNote(path);
      }
    } else {
      debugPrint("🎙️ [_toggleRecording] Starting...");
      final started = await _voiceService.startRecording();
      if (started) {
        debugPrint("🎙️ [_toggleRecording] Started successfully.");
        setState(() => _isRecording = true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Microphone permission required")),
          );
        }
      }
    }
  }

  Future<void> _sendVoiceNote(String path) async {
    debugPrint("🎙️ [_sendVoiceNote] Start. Path: $path");
    try {
      File audioFile = File(path);
      Uint8List fileBytes = await audioFile.readAsBytes();
      debugPrint("🎙️ [_sendVoiceNote] Read file bytes. Size: ${fileBytes.length}");

      final cryptoData = await FileCryptoService.encryptFileBytes(fileBytes);
      debugPrint("🎙️ [_sendVoiceNote] Encrypted file.");

      String? attachmentId = await DioClient().uploadEncryptedFile(
        cryptoData['encryptedBytes'], 
        "voice_note.m4a"
      );
      debugPrint("🎙️ [_sendVoiceNote] Uploaded. ID: $attachmentId");

      if (attachmentId == null) throw Exception("Upload failed");

      Map<String, dynamic> voicePayload = {
        "type": "voice",
        "attachment_id": attachmentId,
        "aes_key": cryptoData['aesKeyBase64'],
        "nonce": cryptoData['nonceBase64'],
        "mac": cryptoData['macBase64']
      };
      
      final payloadString = jsonEncode(voicePayload);
      final targetId = int.parse(widget.targetUser.id);

      bool hasSession = await _sessionManager.hasSession(targetId);
      if (!hasSession) {
        debugPrint("🤝 [Chat] No session for voice. Handshaking...");
        final bundleResponse = await DioClient().dio.get('/auth/keys/$targetId');
        await _sessionManager.establishSession(targetId, bundleResponse.data);
      }

      final encrypted = await _sessionManager.encrypt(targetId, payloadString);

      final msg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(), 
        senderId: _myUserId!, 
        receiverId: widget.targetUser.id, 
        ciphertext: payloadString, 
        iv: '', 
        timestamp: DateTime.now(), 
        counter: 0
      );

      setState(() => _messages.add(msg));
      await _dbService.saveMessage(msg, true);
      _scrollToBottom();

      final packet = {
        'receiverId': widget.targetUser.id,
        'messageType': encrypted['type'], 
        'ciphertext': encrypted['ciphertext'],
        'tempId': msg.id,
      };
      _socketService.sendMessage(packet);
    } catch (e) {
      debugPrint("❌ Voice Note error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice note: $e')),
        );
      }
    }
  }

Future<void> _downloadFile(Map<String, dynamic> fileData) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading file...')),
      );

      final response = await DioClient().dio.get(
        '/download/${fileData['attachment_id']}', 
        options: Options(responseType: ResponseType.bytes),
      );

      final List<int> encryptedBytes = response.data;

      final decryptedBytes = await FileCryptoService.decryptFileBytes(
        encryptedBytes: encryptedBytes,
        aesKeyBase64: fileData['aes_key'],
        nonceBase64: fileData['nonce'],
        macBase64: fileData['mac'],
      );

      Directory dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final file = File('${dir.path}/${fileData['file_name']}');
      await file.writeAsBytes(decryptedBytes);
      
      if (!mounted) return; 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File saved to: ${file.path}')),
      );

    } catch (e) {
      debugPrint("Download error: $e");
      
      if (!mounted) return; 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to download or decrypt file.')),
      );
    }
  }
@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.targetUser.username),
            Text(
              _partnerStatus.toUpperCase(),
              style: TextStyle(
                fontSize: 11, 
                color: _partnerStatus == 'online' ? Colors.green : Colors.grey[400],
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2
              ),
            ),
          ],
        ),
        elevation: 1,
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          if (_isHandshaking) const LinearProgressIndicator(color: Colors.black),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg.senderId == _myUserId;
                
                final localTime = msg.timestamp.toLocal();
                final timeString = "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}";

                bool isFile = false;
                bool isVoice = false;
                Map<String, dynamic>? fileData;
                String displayFileName = "";

                try {
                  fileData = jsonDecode(msg.ciphertext);
                  if (fileData != null) {
                    if (fileData['type'] == 'file') {
                      isFile = true;
                      displayFileName = fileData['file_name'] ?? 'Unknown File';
                    } else if (fileData['type'] == 'voice') {
                      isVoice = true;
                    }
                  }
                } catch (e) {
                  if (msg.ciphertext.startsWith('[File] ')) {
                    isFile = true;
                    displayFileName = msg.ciphertext.replaceFirst('[File] ', '');
                  } else if (msg.ciphertext == '[Voice Note]') {
                    isVoice = true;
                  }
                }

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75, 
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF111111) : const Color(0xFFF4F4F5), 
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(isMe ? 12 : 2),
                        bottomRight: Radius.circular(isMe ? 2 : 12),
                      ),
                      border: Border.all(
                        color: isMe ? Colors.transparent : const Color(0xFFE4E4E7),
                        width: 1,
                      )
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        
                        if (isFile)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.insert_drive_file, 
                                color: isMe ? Colors.white70 : Colors.black54,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  displayFileName,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!isMe && fileData != null && fileData['attachment_id'] != null)
                                IconButton(
                                  icon: const Icon(Icons.download, color: Colors.black87),
                                  onPressed: () => _downloadFile(fileData!),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.only(left: 8),
                                )
                            ],
                          )
                        else if (isVoice)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _currentlyPlayingId == msg.id ? Icons.pause : Icons.play_arrow,
                                  color: isMe ? Colors.white : Colors.black87,
                                ),
                                onPressed: () => _playVoiceNote(msg.id, fileData),
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(width: 8),
                              const Text("Voice Note", style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                              const SizedBox(width: 20),
                            ],
                          )
                        else
                          Text(
                            msg.ciphertext, 
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),

                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeString,
                              style: TextStyle(
                                color: isMe ? Colors.white60 : Colors.black45,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                msg.isRead ? Icons.done_all : (msg.isDelivered ? Icons.done_all : Icons.done),
                                size: 14,
                                color: msg.isRead ? Colors.blueAccent : Colors.white60,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE4E4E7)),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.black54),
                  onPressed: () => _pickAndSendFile(widget.targetUser.id),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController, 
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: "Secure message...",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  )
                ),
                IconButton(
                  icon: Icon(
                    _isRecording ? Icons.stop : Icons.mic, 
                    color: _isRecording ? Colors.red : Colors.black54
                  ),
                  onPressed: _toggleRecording,
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.black), 
                  onPressed: _sendMessage
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playVoiceNote(String msgId, Map<String, dynamic>? fileData) async {
    if (_currentlyPlayingId == msgId) {
      await _audioPlayer.pause();
      setState(() => _currentlyPlayingId = null);
      return;
    }

    if (fileData == null) return;

    try {
      final response = await DioClient().dio.get(
        '/download/${fileData['attachment_id']}', 
        options: Options(responseType: ResponseType.bytes),
      );

      final decryptedBytes = await FileCryptoService.decryptFileBytes(
        encryptedBytes: response.data,
        aesKeyBase64: fileData['aes_key'],
        nonceBase64: fileData['nonce'],
        macBase64: fileData['mac'],
      );

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/play_${msgId}.m4a');
      await tempFile.writeAsBytes(decryptedBytes);

      await _audioPlayer.play(DeviceFileSource(tempFile.path));
      setState(() => _currentlyPlayingId = msgId);

      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _currentlyPlayingId = null);
      });

    } catch (e) {
      debugPrint("❌ Play error: $e");
    }
  }
}