import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message_model.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'govcomm_local.db');

    return await openDatabase(
      path,
      version: 5, // BUMPED TO VERSION 5
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute("DROP TABLE IF EXISTS messages");
          await db.execute("DROP TABLE IF EXISTS users_cache");
          await _createTables(db);
        } else if (oldVersion < 4) {
          try {
            await db.execute("ALTER TABLE messages ADD COLUMN isRead INTEGER DEFAULT 1");
          } catch (e) {
            print("isRead column already exists");
          }
        } 
        
        if (oldVersion < 5) {
          try {
             await db.execute("ALTER TABLE messages ADD COLUMN isDelivered INTEGER DEFAULT 0");
             if (oldVersion < 4) {
               await db.execute("ALTER TABLE messages ADD COLUMN isRead INTEGER DEFAULT 1");
             }
          } catch (e) {
             print("Column update error or already exists: $e");
          }
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE messages(
        id TEXT PRIMARY KEY,
        senderId TEXT,
        receiverId TEXT,
        content TEXT, 
        timestamp TEXT,
        isSentByMe INTEGER,
        isRead INTEGER DEFAULT 1,
        isDelivered INTEGER DEFAULT 0
      )
    ''');
    
    await db.execute('''
      CREATE TABLE users_cache(
        id TEXT PRIMARY KEY,
        username TEXT,
        email TEXT
      )
    ''');
  }

  Future<void> saveUserCache(String id, String username, String email) async {
    final db = await database;
    await db.insert('users_cache', {
      'id': id,
      'username': username,
      'email': email
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveMessage(Message msg, bool isSentByMe, {bool isRead = false, bool isDelivered = false}) async {
    final db = await database;
    try {
      await db.insert(
        'messages',
        {
          'id': msg.id,
          'senderId': msg.senderId,
          'receiverId': msg.receiverId,
          'content': msg.ciphertext, 
          'timestamp': msg.timestamp.toIso8601String(),
          'isSentByMe': isSentByMe ? 1 : 0,
          'isRead': isRead ? 1 : 0,
          'isDelivered': isDelivered ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print("❌ [DEBUG DB] Insert Failed: $e");
    }
  }

  Future<void> updateMessageStatus(String msgId, {bool? isRead, bool? isDelivered}) async {
    final db = await database;
    final Map<String, dynamic> values = {};
    if (isRead != null) values['isRead'] = isRead ? 1 : 0;
    if (isDelivered != null) values['isDelivered'] = isDelivered ? 1 : 0;
    
    if (values.isEmpty) return;
    
    await db.update('messages', values, where: 'id = ?', whereArgs: [msgId]);
  }

  Future<void> markAsRead(String partnerId, String myUserId) async {
    final db = await database;
    await db.update(
      'messages',
      {'isRead': 1},
      where: 'senderId = ? AND receiverId = ? AND isRead = 0',
      whereArgs: [partnerId, myUserId],
    );
  }

  Future<void> markSentMessagesAsRead(String partnerId, String myUserId) async {
    final db = await database;
    await db.update(
      'messages',
      {'isRead': 1},
      where: 'senderId = ? AND receiverId = ? AND isRead = 0',
      whereArgs: [myUserId, partnerId],
    );
  }

  Future<void> updateMessageId(String tempId, String newId) async {
    final db = await database;
    await db.update(
      'messages',
      {'id': newId},
      where: 'id = ?',
      whereArgs: [tempId],
    );
  }

Future<List<Map<String, dynamic>>> getRecentConversations(String myUserId) async {
    final db = await database;
    
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT m1.*, 
             COALESCE(u.username, 'Unknown User') as partnerUsername,
             CASE WHEN m1.senderId = ? THEN m1.receiverId ELSE m1.senderId END as partnerId,
             (SELECT COUNT(*) FROM messages m3 
              WHERE m3.senderId = (CASE WHEN m1.senderId = ? THEN m1.receiverId ELSE m1.senderId END) 
              AND m3.receiverId = ? AND m3.isRead = 0) as unreadCount
      FROM messages m1
      LEFT JOIN users_cache u ON u.id = (CASE WHEN m1.senderId = ? THEN m1.receiverId ELSE m1.senderId END)
      INNER JOIN (
          SELECT 
              CASE WHEN senderId = ? THEN receiverId ELSE senderId END as thread_id, 
              MAX(timestamp) as max_time
          FROM messages
          WHERE senderId = ? OR receiverId = ?
          GROUP BY CASE WHEN senderId = ? THEN receiverId ELSE senderId END
      ) m2 
      ON (CASE WHEN m1.senderId = ? THEN m1.receiverId ELSE m1.senderId END) = m2.thread_id 
      AND m1.timestamp = m2.max_time
      ORDER BY m1.timestamp DESC
    ''', [myUserId, myUserId, myUserId, myUserId, myUserId, myUserId, myUserId, myUserId, myUserId]);
    
    return maps;
  }

  Future<List<Message>> getLocalChat(String partnerId, String myUserId) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: '(senderId = ? AND receiverId = ?) OR (senderId = ? AND receiverId = ?)',
      whereArgs: [partnerId, myUserId, myUserId, partnerId],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return Message(
        id: maps[i]['id'] as String,
        senderId: maps[i]['senderId'] as String,
        receiverId: maps[i]['receiverId'] as String,
        ciphertext: maps[i]['content'] as String, 
        iv: '', 
        timestamp: DateTime.parse(maps[i]['timestamp'] as String),
        counter: 0, 
        isDelivered: maps[i]['isDelivered'] == 1,
        isRead: maps[i]['isRead'] == 1,
      );
    });
  }

  Future<void> deleteConversation(String myUserId, String partnerId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: '(senderId = ? AND receiverId = ?) OR (senderId = ? AND receiverId = ?)',
      whereArgs: [partnerId, myUserId, myUserId, partnerId],
    );
  }
}