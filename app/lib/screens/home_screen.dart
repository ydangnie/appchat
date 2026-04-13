import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../chat_service.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<ChatService>(context, listen: false).searchUsers(query);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatService = Provider.of<ChatService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Chats - ${chatService.currentUser?.username}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search users to chat...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
          
          Expanded(
            child: _searchController.text.isEmpty
                ? (chatService.recentChats.isEmpty
                    ? const Center(child: Text('Chưa có tin nhắn nào. Hãy tìm kiếm để chat!'))
                    : ListView.builder(
                        itemCount: chatService.recentChats.length,
                        itemBuilder: (context, index) {
                          final user = chatService.recentChats[index];
                          return ListTile(
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.blueAccent,
                                  child: Text(user.username.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white)),
                                ),
                                if (user.isOnline)
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
                                  )
                              ],
                            ),
                            title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(user.isOnline ? 'Online' : 'Offline', style: TextStyle(color: user.isOnline ? Colors.green : Colors.grey)),
                            onTap: () {
                              chatService.openChatWith(user); // Add to recent if not already
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(partner: user),
                                ),
                              );
                            },
                          );
                        },
                      ))
                : ListView.builder(
                    itemCount: chatService.searchResults.length,
                    itemBuilder: (context, index) {
                      final user = chatService.searchResults[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(user.username.substring(0, 1).toUpperCase()),
                        ),
                        title: Text(user.username),
                        onTap: () {
                          chatService.openChatWith(user); // Add to recent
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(partner: user),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
