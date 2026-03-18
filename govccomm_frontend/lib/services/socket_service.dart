import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:io';
import 'dart:async';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  
  final _statusController = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get statusStream => _statusController.stream;

  final Map<String, String> _userStatuses = {};
  Map<String, String> get userStatuses => _userStatuses;

  final _processedController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get processedStream => _processedController.stream;

  void notifyUIOfNewMessage(Map<String, dynamic> data) {
    _processedController.add(data);
  }
  IO.Socket? _socket;
  
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  final _receiptController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get receiptStream => _receiptController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;
  
  bool get isConnected => _socket?.connected ?? false;
  
  final List<Map<String, dynamic>> _messageQueue = [];
  
  Function(dynamic)? onMessageReceived;

  SocketService._internal();

  IO.Socket? get socket => _socket;

  void connect(String token) {
    if (_socket != null) {
      if (_socket!.connected) {
        print('🔌 Socket already connected');
        return;
      } else {
        print('🔄 Reconnecting existing socket...');
        _socket!.io.options?['auth'] = {'token': token};
        _socket!.connect();
        return;
      }
    }

    print("🔌 Attempting to create new socket connection...");
    
    final url = Platform.isAndroid ? 'https://10.0.2.2:8080' : 'https://localhost:8080';

    _socket = IO.io(url, IO.OptionBuilder()
        .setTransports(['websocket']) 
        .setAuth({'token': token})   
        .enableReconnection()
        .setReconnectionAttempts(5)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .disableAutoConnect()
        .build());

    _setupEventListeners();
    
    _socket!.connect();
  }

  void _setupEventListeners() {

    _socket!.on('initialStatus', (data) {
        if (data is Map) {
            data.forEach((k, v) => _userStatuses[k.toString()] = v.toString());
            _statusController.add(_userStatuses);
        }
    });

    _socket!.on('userStatus', (data) {
        if (data != null && data['userId'] != null) {
            _userStatuses[data['userId'].toString()] = data['status'].toString();
            _statusController.add(_userStatuses);
        }
    });

    _socket!.on('readReceipt', (data) {
        print('🔵 Read Receipt received: $data');
        _receiptController.add({'type': 'read', ...Map<String, dynamic>.from(data)});
    });

    _socket!.on('messageAck', (data) {
        print('🔘 Message Ack received: $data');
        _receiptController.add({'type': 'ack', ...Map<String, dynamic>.from(data)});
    });

    _socket!.on('x3dhInit', (data) {
      print('🔐 X3DH Init Packet Received: $data');
      _messageController.add({
        'type': 'x3dhInit',
        ...Map<String, dynamic>.from(data),
      });
    });

    _socket!.on('sessionReset', (data) {
      final partnerId = data['senderId']?.toString();
      print('🤝 SECURITY HANDSHAKE REQUESTED FROM: $partnerId');
      if (partnerId != null) {
        _messageController.add({
          'type': 'sessionReset',
          'partnerId': partnerId,
        });
      }
    });

    _socket!.onConnect((_) {
      print('============================================');
      print('✅ SOCKET CONNECTED!');
      print(' - My Socket ID: ${_socket!.id}'); 
      print(' - Transport: ${_socket!.io.engine?.transport?.name}');
      print('============================================');
      _connectionController.add(true);
      _processMessageQueue();
    });

    _socket!.onConnectError((data) {
      print('❌ Socket Connection Error: $data');
      _connectionController.add(false);
    });

    _socket!.onError((data) {
      print('⚠️ Socket Error: $data');
    });

    _socket!.onReconnect((attempt) {
      print('🔄 Socket Reconnected after $attempt attempts');
      _connectionController.add(true);
      _processMessageQueue();
    });

    _socket!.on('receiveMessage', (data) {
      print('📩 Message Received via Socket: $data');
      
      if (data is Map<String, dynamic>) {
        _messageController.add(data);
      } else if (data is Map) {
        _messageController.add(Map<String, dynamic>.from(data));
      }
      
      if (onMessageReceived != null) {
        onMessageReceived!(data);
      }
    });

    _socket!.on('receipt', (data) {
      print('✅ Delivery Receipt: $data');
    });

    _socket!.onDisconnect((reason) {
      print('❌ Socket Disconnected: $reason');
      _connectionController.add(false);
    });
  }

  void sendMessage(Map<String, dynamic> payload) {
    if (_socket != null && _socket!.connected) {
      print("📤 Sending packet to ${payload['receiverId']}...");
      _socket!.emit('sendMessage', payload);
    } else {
      print('⚠️ Cannot send: Socket not connected. Queuing message...');
      _messageQueue.add(payload);
      _connectionController.add(false); 
    }
  }

  void sendDeliveryReceipt(String senderId, String messageId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('messageDelivered', {
        'senderId': senderId,
        'messageId': messageId
      });
    }
  }

  void _processMessageQueue() {
    if (_messageQueue.isEmpty) return;
    
    print('📤 Processing ${_messageQueue.length} queued messages...');
    
    for (final payload in List<Map<String, dynamic>>.from(_messageQueue)) {
      try {
        _socket!.emit('sendMessage', payload);
        _messageQueue.remove(payload);
        print('✅ Queued message sent to ${payload['receiverId']}');
      } catch (e) {
        print('❌ Failed to send queued message: $e');
      }
    }
  }

  void disconnect() {
    print('🔌 Disconnecting socket...');
    _socket?.disconnect();
  }
  
  void sendX3DHInit(Map<String, dynamic> payload) {
    if (_socket != null && _socket!.connected) {
      print("🔐 Sending X3DH Init Packet...");
      _socket!.emit('x3dhInit', payload);
    }
  }

  void requestSessionReset(String partnerId) {
    if (_socket != null && _socket!.connected) {
      print("🤝 Requesting Session Reset for $partnerId...");
      _socket!.emit('requestSessionReset', {'receiverId': partnerId});
    }
  }


  void dispose() {
    print('🗑️ Disposing SocketService...');
    disconnect();
  }
}