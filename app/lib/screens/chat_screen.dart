// Remove dart:io for web support
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../chat_service.dart';

class ChatScreen extends StatefulWidget {
  final User partner;
  const ChatScreen({super.key, required this.partner});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  final ScrollController _scrollController = ScrollController();

  // Typing indicator vars
  Timer? _typingTimer;
  bool _isLocalTyping = false;

  // Edit message vars
  String? _editingMsgId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      Provider.of<ChatService>(context, listen: false)
          .loadChatHistory(widget.partner.id);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
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

  void _onTextChanged(String text) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    
    if (text.isEmpty && _isLocalTyping) {
      _isLocalTyping = false;
      chatService.sendStopTyping(widget.partner.id);
      _typingTimer?.cancel();
      return;
    }

    if (!_isLocalTyping) {
      _isLocalTyping = true;
      chatService.sendTyping(widget.partner.id);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _isLocalTyping = false;
      chatService.sendStopTyping(widget.partner.id);
    });
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_editingMsgId != null) {
      // Logic Update tin nhắn
      chatService.editMessage(_editingMsgId!, text, widget.partner.id);
      setState(() {
        _editingMsgId = null;
      });
    } else {
      // Logic Gửi tin nhắn mới
      chatService.sendMessage(widget.partner.id, text, 'text');
    }

    _msgController.clear();
    _onTextChanged(""); // Stop typing
    _scrollToBottom();
  }

  void _cancelEdit() {
    setState(() {
      _editingMsgId = null;
      _msgController.clear();
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) _uploadAndSend(image, 'image');
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) _uploadAndSend(video, 'video');
  }

  Future<void> _uploadAndSend(XFile file, String type) async {
    setState(() => _isUploading = true);
    final chatService = Provider.of<ChatService>(context, listen: false);
    
    // Read bytes instead of file path to support Web
    final bytes = await file.readAsBytes();
    final url = await chatService.uploadFile(bytes, file.name);
    
    setState(() => _isUploading = false);

    if (url != null) {
      chatService.sendMessage(widget.partner.id, url, type);
      _scrollToBottom();
    }
  }

  void _showMessageOptions(ChatMessage msg) {
    if (msg.fromId != Provider.of<ChatService>(context, listen: false).currentUser?.id) {
      return; // Không cho chỉnh sửa xóa tin nhắn ng khác
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (msg.type == 'text')
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Sửa tin nhắn (Edit)'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _editingMsgId = msg.id;
                    _msgController.text = msg.content;
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Xóa tin nhắn (Delete)', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                Provider.of<ChatService>(context, listen: false)
                    .deleteMessage(msg.id, widget.partner.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatService = Provider.of<ChatService>(context);
    final messages = chatService.getMessages(widget.partner.id);
    final isPartnerTyping = chatService.typingUsers.contains(widget.partner.id);

    // Scroll after build if messages length changed
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.partner.username),
            if (isPartnerTyping)
              const Text('đang soạn tin...', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          Icon(
            Icons.circle,
            color: widget.partner.isOnline ? Colors.green : Colors.grey,
            size: 14,
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isMe = msg.fromId == chatService.currentUser?.id;
                return GestureDetector(
                  onLongPress: () => _showMessageOptions(msg),
                  child: _buildMessageBubble(msg, isMe),
                );
              },
            ),
          ),
          if (_isUploading) const LinearProgressIndicator(),
          if (_editingMsgId != null) _buildEditBanner(),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildEditBanner() {
    return Container(
      color: Colors.yellow[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.edit, size: 20, color: Colors.orange),
          const SizedBox(width: 8),
          const Expanded(child: Text("Đang chỉnh sửa tin nhắn...", style: TextStyle(color: Colors.orange))),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black54),
            onPressed: _cancelEdit,
          )
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.type == 'text')
              Text(
                msg.content,
                style: const TextStyle(fontSize: 16),
              ),
            if (msg.type == 'image')
              SizedBox(
                width: 200,
                child: Image.network(
                  '$API_URL${msg.content}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.error),
                ),
              ),
            if (msg.type == 'video')
              VideoBubble(videoUrl: '$API_URL${msg.content}'),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: Row(
        children: [
          if (_editingMsgId == null) ...[
            IconButton(
              icon: const Icon(Icons.image, color: Colors.blue),
              onPressed: _pickImage,
            ),
            IconButton(
              icon: const Icon(Icons.videocam, color: Colors.blue),
              onPressed: _pickVideo,
            ),
          ],
          Expanded(
            child: TextField(
              controller: _msgController,
              onChanged: _onTextChanged,
              decoration: InputDecoration(
                hintText: 'Type a message',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 15),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: Icon(_editingMsgId != null ? Icons.check : Icons.send, color: Colors.blue),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}

class VideoBubble extends StatefulWidget {
  final String videoUrl;
  const VideoBubble({super.key, required this.videoUrl});

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const SizedBox(
        width: 200,
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      width: 200,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          IconButton(
            icon: Icon(
              _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: () {
              setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              });
            },
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
