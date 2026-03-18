import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../services/database_service.dart';
import '../../services/dio_client.dart';
import '../../services/socket_service.dart';
import '../../services/key_management_service.dart';
import '../../services/chat_session_manager.dart';
import '../../models/user_model.dart';
import 'chat_scaffold.dart';
import '../../services/global_message_handler.dart';
import '../../services/secure_storage_service.dart';
import '../auth/login_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  _ConversationsScreenState createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _dbService = DatabaseService();
  final _storage = const FlutterSecureStorage();
  final _socketService = SocketService();
  
  late final KeyManagementService _keyManager;
  late final ChatSessionManager _sessionManager;
  
  StreamSubscription? _socketSubscription;
  StreamSubscription? _statusSubscription;

  Map<String, String> _userStatuses = {};
  bool _showOnline = true;
  bool _showReadReceipts = true;

  List<Map<String, dynamic>> _conversations = [];
  String? _myUserId;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _keyManager = KeyManagementService(sharedSignalService);
    _sessionManager = ChatSessionManager(sharedSignalService);
    
    _initAppLogic();
    _socketSubscription = _socketService.processedStream.listen((_) async {
      debugPrint("🔔 [Conversations] Message processed. Refreshing UI...");
      if (mounted) await _refreshList();
    });

    _statusSubscription = _socketService.statusStream.listen((statuses) {
      if (mounted) setState(() => _userStatuses = statuses);
    });

    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await DioClient().getSettings();
    if (settings != null && mounted) {
      setState(() {
        _showOnline = settings['show_online'] ?? true;
        _showReadReceipts = settings['show_read_receipts'] ?? true;
      });
    }
  }

  Future<void> _updateSettings(String type, bool value) async {
    final Map<String, bool> newSettings = {
      'show_online': type == 'online' ? value : _showOnline,
      'show_read_receipts': type == 'read' ? value : _showReadReceipts,
    };
    
    final success = await DioClient().updateSettings(newSettings);
    if (success && mounted) {
      setState(() {
        if (type == 'online') _showOnline = value;
        if (type == 'read') _showReadReceipts = value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settings updated!'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Privacy Settings"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text("Show Online Status"),
                subtitle: Text("Others will see when you're online"),
                value: _showOnline,
                onChanged: (val) async {
                  await _updateSettings('online', val);
                  setDialogState(() {});
                },
              ),
              SwitchListTile(
                title: Text("Show Read Receipts"),
                subtitle: Text("Two blue ticks when you read messages"),
                value: _showReadReceipts,
                onChanged: (val) async {
                  await _updateSettings('read', val);
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("Close"))
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initAppLogic() async {
    final token = DioClient().activeToken ?? await _storage.read(key: 'jwt_token');
    
    if (token != null) {
      final decoded = JwtDecoder.decode(token);
      _myUserId = decoded['id']?.toString() ?? decoded['userId']?.toString();
      GlobalMessageHandler().initialize(_myUserId!, _sessionManager);
      
      await _refreshList();
    } 

    if (mounted) {
      setState(() {
        _isOnline = _socketService.isConnected;
      });
    }
    
    _socketService.socket?.on('connect', (_) {
      if (mounted) setState(() => _isOnline = true);
    });

    _socketService.socket?.on('disconnect', (_) {
      if (mounted) setState(() => _isOnline = false);
    });

    if (_myUserId != null) {
      await _keyManager.checkAndReplenishKeys(int.parse(_myUserId!));
    }
  }

  Future<void> _refreshList() async {
    if (_myUserId == null) return;
    final list = await _dbService.getRecentConversations(_myUserId!);
    if (mounted) {
      setState(() => _conversations = list);
    }
  }

  void _openChat(User user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScaffold(targetUser: user)),
    ).then((_) {
      debugPrint("🔙 Returned from chat. Refreshing conversation list...");
      _refreshList();
    });
  }

  Future<void> _searchAndStartChat(String email) async {
    try {
      final data = await DioClient().searchUser(email);
      if (data != null) {
        final foundUser = User.fromJson(data);
        
        await _dbService.saveUserCache(foundUser.id, foundUser.username, foundUser.email);
        
        if (mounted) _openChat(foundUser);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User not found or not verified"))
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await SecureStorageService().deleteKey('jwt_token');
      DioClient().setToken(null);
      _socketService.socket?.disconnect();

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Logout failed: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text("GovComm Chats"),
            const SizedBox(width: 8),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOnline ? Colors.green : Colors.red,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Logout"),
                  content: const Text("Are you sure? Your secure chats will remain on this device."),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _handleLogout();
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text("Logout"),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _conversations.isEmpty
          ? const Center(child: Text("No active chats. Tap search button below."))
          : ListView.builder(
              itemCount: _conversations.length,
              itemBuilder: (context, index) {
                final conv = _conversations[index];
                final partnerId = conv['partnerId']; 
                final String displayUsername = conv['partnerUsername'] ?? "User $partnerId";
                
                return Dismissible(
                  key: Key(partnerId.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Delete Chat"),
                        content: Text("Are you sure you want to delete the chat with $displayUsername? all history will be erased."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text("Delete"),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (direction) async {
                    await _dbService.deleteConversation(_myUserId!, partnerId.toString());
                    await _refreshList();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Chat with $displayUsername deleted")),
                      );
                    }
                  },
                  child: ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Text(
                            displayUsername.isNotEmpty ? displayUsername.substring(0, 1).toUpperCase() : "?",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ), 
                        ),
                        if (_userStatuses[partnerId.toString()] == 'online')
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      displayUsername, 
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ), 
                    subtitle: Text(
                      conv['content'], 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey),
                    ),
                      trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          conv['timestamp'].toString().length > 16 
                            ? conv['timestamp'].toString().substring(11, 16) 
                            : "",
                          style: TextStyle(
                            fontSize: 12,
                            color: (conv['unreadCount'] ?? 0) > 0 ? Colors.blue : Colors.grey,
                            fontWeight: (conv['unreadCount'] ?? 0) > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if ((conv['unreadCount'] ?? 0) > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "${conv['unreadCount']}",
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    onTap: () => _openChat(User(
                      id: partnerId.toString(), 
                      username: displayUsername, 
                      email: ""
                    )),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSearchDialog(),
        child: const Icon(Icons.search),
      ),
    );
  }

  void _showSearchDialog() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Start New Chat"),
        content: TextField(
          controller: c, 
          decoration: const InputDecoration(hintText: "Colleague Email (@gov.qa)")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (c.text.isNotEmpty) _searchAndStartChat(c.text);
            },
            child: const Text("Search"),
          ),
        ],
      ),
    );
  }
}