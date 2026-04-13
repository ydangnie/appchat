import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;

// Configuration
// Change this to your machine's local IP if testing on separated devices!
// For Windows Desktop testing locally, localhost works.
const String API_URL = 'http://localhost:3000';

class User {
  final String id;
  final String username;
  bool isOnline;
  User({required this.id, required this.username, this.isOnline = false});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      isOnline: json['isOnline'] ?? false,
    );
  }
}

class ChatMessage {
  final String id;
  final String fromId;
  final String? fromName;
  final String toId;
  final String type; // 'text', 'image', 'video'
  String content;
  final int timestamp;

  ChatMessage({
    required this.id,
    required this.fromId,
    this.fromName,
    required this.toId,
    required this.type,
    required this.content,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      fromId: json['fromId'],
      fromName: json['fromName'],
      toId: json['toId'],
      type: json['type'],
      content: json['content'],
      timestamp: json['timestamp'],
    );
  }
}

class ChatService with ChangeNotifier {
  IO.Socket? _socket;
  User? currentUser;
  
  // Trạng thái bạn bè đang chat (Mảng những người có nhắn tin hoặc search)
  List<User> searchResults = [];
  List<User> friends = [];
  List<User> recentChats = []; // Danh sách tin nhắn gần đây
  
  // Lưu trạng thái ai đang gõ chữ
  Set<String> typingUsers = {};
  
  // Lịch sử tin nhắn giữa currentUser và partnerId
  final Map<String, List<ChatMessage>> _messages = {};

  void initSocket() {
    if (currentUser == null) return;
    
    _socket = IO.io(API_URL, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _socket!.connect();
    
    _socket!.onConnect((_) {
      print('✅ Connected to socket');
      _socket!.emit('register', currentUser!.id);
    });

    _socket!.on('receive_message', (data) {
      final msg = ChatMessage.fromJson(data);
      _addMessage(msg.fromId, msg);
      _addToRecent(msg.fromId, msg.fromName ?? 'Unknown');
    });

    _socket!.on('message_sent', (data) {
      final msg = ChatMessage.fromJson(data);
      _addMessage(msg.toId, msg);
    });

    _socket!.on('message_deleted', (data) {
      final msgId = data['msgId'];
      _removeMessageLocally(msgId);
    });

    _socket!.on('message_edited', (data) {
      final msgId = data['msgId'];
      final newContent = data['newContent'];
      _updateMessageLocally(msgId, newContent);
    });

    _socket!.on('user_typing', (data) {
      final fromId = data['fromId'];
      typingUsers.add(fromId);
      notifyListeners();
    });

    _socket!.on('user_stop_typing', (data) {
      final fromId = data['fromId'];
      typingUsers.remove(fromId);
      notifyListeners();
    });

    _socket!.on('user_status', (data) {
      // Cập nhật trạng thái online của bạn bè
      final userId = data['userId'];
      final isOnline = data['isOnline'];
      bool updated = false;
      for (var f in recentChats) {
        if (f.id == userId) {
          f.isOnline = isOnline;
          updated = true;
        }
      }
      if (updated) notifyListeners();
    });
  }

  void _addToRecent(String partnerId, String partnerName) {
    if (!recentChats.any((u) => u.id == partnerId)) {
      recentChats.insert(0, User(id: partnerId, username: partnerName, isOnline: true));
      notifyListeners();
    }
  }

  void openChatWith(User user) {
    if (!recentChats.any((u) => u.id == user.id)) {
      recentChats.insert(0, user);
      notifyListeners();
    }
  }

  void _addMessage(String partnerId, ChatMessage msg) {
    if (!_messages.containsKey(partnerId)) {
      _messages[partnerId] = [];
    }
    // Tránh trùng lặp
    if (!_messages[partnerId]!.any((m) => m.id == msg.id)) {
      _messages[partnerId]!.add(msg);
      notifyListeners();
    }
  }

  List<ChatMessage> getMessages(String partnerId) {
    return _messages[partnerId] ?? [];
  }

  Future<bool> login(String username) async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        currentUser = User.fromJson(data);
        initSocket();
        notifyListeners();
        return true;
      }
    } catch (e) {
      print('Login error: $e');
    }
    return false;
  }

  Future<void> searchUsers(String query) async {
    if (currentUser == null) return;
    try {
      final response = await http.get(
        Uri.parse('$API_URL/api/search?q=$query&currentUserId=${currentUser!.id}'),
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        searchResults = data.map((json) => User.fromJson(json)).toList();
        notifyListeners();
      }
    } catch (e) {
      print('Search error: $e');
    }
  }

  Future<void> loadChatHistory(String partnerId) async {
    if (currentUser == null) return;
    try {
      final response = await http.get(
        Uri.parse('$API_URL/api/messages/$partnerId'),
        headers: {'user-id': currentUser!.id},
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        _messages[partnerId] = data.map((json) => ChatMessage.fromJson(json)).toList();
        notifyListeners();
      }
    } catch (e) {
      print('Load history error: $e');
    }
  }

  void addFriend(User user) {
    if (!friends.any((f) => f.id == user.id)) {
      friends.add(user);
      notifyListeners();
    }
  }

  void sendMessage(String toId, String content, String type) {
    if (_socket != null && currentUser != null) {
      _socket!.emit('send_message', {
        'toId': toId,
        'type': type,
        'content': content,
      });
    }
  }

  void deleteMessage(String msgId, String toId) {
    if (_socket != null) {
      _socket!.emit('delete_message', {'msgId': msgId, 'toId': toId});
      _removeMessageLocally(msgId);
    }
  }

  void editMessage(String msgId, String newContent, String toId) {
    if (_socket != null) {
      _socket!.emit('edit_message', {'msgId': msgId, 'newContent': newContent, 'toId': toId});
      // Will be updated locally when socket receives ack
    }
  }

  void sendTyping(String toId) {
    if (_socket != null) _socket!.emit('typing', {'toId': toId});
  }

  void sendStopTyping(String toId) {
    if (_socket != null) _socket!.emit('stop_typing', {'toId': toId});
  }

  void _removeMessageLocally(String msgId) {
    _messages.forEach((key, list) {
      list.removeWhere((m) => m.id == msgId);
    });
    notifyListeners();
  }

  void _updateMessageLocally(String msgId, String newContent) {
    _messages.forEach((key, list) {
      for (var m in list) {
        if (m.id == msgId) m.content = newContent;
      }
    });
    notifyListeners();
  }

  Future<String?> uploadFile(Uint8List bytes, String fileName) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$API_URL/api/upload'));
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'];
      }
    } catch (e) {
      print('Upload error: $e');
    }
    return null;
  }

  void logout() {
    _socket?.disconnect();
    currentUser = null;
    friends.clear();
    _messages.clear();
    searchResults.clear();
    notifyListeners();
  }
}
