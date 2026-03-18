class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String ciphertext; 
  final String iv;       
  final DateTime timestamp;
  
  final String? ratchetPublicKey; 
  final int counter;             
  final bool isDelivered;
  final bool isRead;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.ciphertext,
    required this.iv,
    required this.timestamp,
    this.ratchetPublicKey,
    required this.counter,
    this.isDelivered = false,
    this.isRead = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      receiverId: json['receiverId']?.toString() ?? '',
      ciphertext: json['ciphertext'] ?? '',
      iv: json['iv'] ?? '',
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : DateTime.now(),
      ratchetPublicKey: json['ratchetPublicKey'],
      counter: json['counter'] ?? 0,
      isDelivered: json['isDelivered'] == true || json['isDelivered'] == 1,
      isRead: json['isRead'] == true || json['isRead'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'ciphertext': ciphertext,
      'iv': iv,
      'timestamp': timestamp.toIso8601String(),
      'ratchetPublicKey': ratchetPublicKey,
      'counter': counter,
      'isDelivered': isDelivered ? 1 : 0,
      'isRead': isRead ? 1 : 0,
    };
  }
}