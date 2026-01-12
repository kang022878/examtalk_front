import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ChatPage extends StatefulWidget {
  final String studyTitle;

  const ChatPage({super.key, required this.studyTitle});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  late final List<Map<String, dynamic>> _messages;

  @override
  void initState() {
    super.initState();
    _messages = _initialMessagesByStudy(widget.studyTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 사진 첨부 기능
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _messages.add({
          'isMe': true,
          'nickname': '나',
          'message': '', // 텍스트 대신 이미지를 보냄
          'imagePath': image.path,
          'time': _formatNowTime(),
        });
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Map<String, dynamic>> _initialMessagesByStudy(String title) {
    if (title.contains('토익') || title.toUpperCase().contains('TOEIC')) {
      return [
        {'isMe': false, 'nickname': '토익고수', 'message': '안녕하세요!\n토익 850+ 목표로 같이 달려봐요 💪', 'time': '오후 12:23'},
        {'isMe': true, 'nickname': '나', 'message': '좋습니다!\n열심히 할게요!', 'time': '오후 12:25'},
      ];
    }
    return [
      {'isMe': false, 'nickname': '운영자', 'message': '안녕하세요!\n스터디 채팅방입니다 🙂', 'time': '오전 9:00'},
    ];
  }

  String _formatNowTime() {
    final now = DateTime.now();
    final isPm = now.hour >= 12;
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    return '${isPm ? "오후" : "오전"} $hour12:${now.minute.toString().padLeft(2, '0')}';
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _messages.add({
        'isMe': true,
        'nickname': '나',
        'message': _controller.text,
        'time': _formatNowTime(),
      });
      _controller.clear();
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCDE1AF),
      appBar: AppBar(
        title: Text(widget.studyTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildChatBubble(_messages[index]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.grey),
                    onPressed: _pickImage, // ✅ 사진 첨부 기능 연결
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)),
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: '메시지 입력',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.green),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg) {
    final bool isMe = msg['isMe'] as bool;
    final String? imagePath = msg['imagePath'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) const CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.face, size: 20, color: Colors.green)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe) Text(msg['nickname'] as String, style: const TextStyle(fontSize: 10, color: Colors.black54)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isMe) Text(msg['time'] as String, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFFFFF9C4) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: imagePath != null 
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(imagePath), fit: BoxFit.cover),
                        )
                      : Text(msg['message'] as String, style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 4),
                  if (!isMe) Text(msg['time'] as String, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
