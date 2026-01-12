import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:toeic_master_front/core/api.dart';
import 'package:toeic_master_front/core/api_client.dart';
import 'package:toeic_master_front/core/token_storage.dart';

class ChatPage extends StatefulWidget {
  final String studyTitle;
  final int? studyId;

  const ChatPage({super.key, required this.studyTitle, this.studyId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  late final TokenStorage _tokenStorage;
  late final Api _api;

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isSending = false;

  StompClient? _stompClient;
  int? _currentUserId;

  // 페이징
  int _currentPage = 0;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _tokenStorage = TokenStorage();
    _api = Api(ApiClient(_tokenStorage));

    if (widget.studyId != null) {
      _initChat();
    } else {
      setState(() => _isLoading = false);
    }

    // 스크롤 리스너 (이전 메시지 로드)
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // reverse: true이므로 maxScrollExtent가 오래된 메시지 방향
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
      _loadMoreMessages();
    }
  }

  Future<void> _initChat() async {
    await _loadCurrentUser();
    await _loadMessages();
    await _connectWebSocket();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final profileRes = await _api.getMyProfile();
      final data = profileRes['data'] as Map<String, dynamic>?;
      _currentUserId = data?['id'] as int?;
    } catch (e) {
      debugPrint('사용자 정보 로드 실패: $e');
    }
  }

  Future<void> _loadMessages() async {
    if (widget.studyId == null) return;

    try {
      final res = await _api.getChatMessages(
        widget.studyId!,
        page: 0,
        size: 50,
        sort: 'createdAt,desc',
      );

      final data = res['data'] as Map<String, dynamic>?;
      final content = (data?['content'] as List<dynamic>?) ?? [];
      final isLast = (data?['last'] as bool?) ?? true;

      if (!mounted) return;
      setState(() {
        // reverse: true 사용하므로 최신순 그대로 (index 0이 최신)
        _messages.clear();
        _messages.addAll(content.map((e) => e as Map<String, dynamic>));
        _hasMoreMessages = !isLast;
        _currentPage = 1;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('메시지 로딩 실패: $e');
    }
  }

  Future<void> _loadMoreMessages() async {
    if (widget.studyId == null || !_hasMoreMessages || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final res = await _api.getChatMessages(
        widget.studyId!,
        page: _currentPage,
        size: 50,
        sort: 'createdAt,desc',
      );

      final data = res['data'] as Map<String, dynamic>?;
      final content = (data?['content'] as List<dynamic>?) ?? [];
      final isLast = (data?['last'] as bool?) ?? true;

      if (!mounted) return;
      setState(() {
        // reverse: true이므로 이전(오래된) 메시지를 맨 뒤에 추가
        _messages.addAll(content.map((e) => e as Map<String, dynamic>));
        _hasMoreMessages = !isLast;
        _currentPage++;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _connectWebSocket() async {
    if (widget.studyId == null) return;

    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) {
      _showSnack('로그인이 필요합니다.');
      return;
    }

    final wsUrl = 'http://13.209.42.76:8080/ws?token=$token';

    _stompClient = StompClient(
      config: StompConfig.sockJS(
        url: wsUrl,
        onConnect: _onStompConnect,
        onWebSocketError: (error) {
          debugPrint('WebSocket 에러: $error');
          if (mounted) {
            setState(() => _isConnected = false);
          }
        },
        onStompError: (frame) {
          debugPrint('STOMP 에러: ${frame.body}');
        },
        onDisconnect: (frame) {
          debugPrint('STOMP 연결 해제');
          if (mounted) {
            setState(() => _isConnected = false);
          }
        },
        reconnectDelay: const Duration(seconds: 5),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
      ),
    );

    _stompClient!.activate();
  }

  void _onStompConnect(StompFrame frame) {
    debugPrint('STOMP 연결 성공');
    if (!mounted) return;
    setState(() => _isConnected = true);

    // 채팅방 구독
    _stompClient!.subscribe(
      destination: '/topic/study/${widget.studyId}',
      callback: (frame) {
        if (frame.body != null) {
          final message = jsonDecode(frame.body!) as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              // reverse: true이므로 최신 메시지는 맨 앞에 추가
              _messages.insert(0, message);
            });
            _scrollToBottom();
          }
        }
      },
    );
  }

  void _scrollToBottom() {
    // reverse: true이므로 0이 최신 메시지 위치
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty || !_isConnected || _isSending) return;

    final content = _controller.text.trim();
    _controller.clear();

    _stompClient?.send(
      destination: '/app/chat/${widget.studyId}',
      body: jsonEncode({
        'content': content,
        'imageKey': null,
      }),
    );
  }

  Future<void> _pickAndSendImage() async {
    if (widget.studyId == null || !_isConnected) return;

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _isSending = true);

    try {
      // 이미지 업로드
      final imageKey = await _api.uploadChatImage(widget.studyId!, File(image.path));

      // WebSocket으로 이미지 메시지 전송
      _stompClient?.send(
        destination: '/app/chat/${widget.studyId}',
        body: jsonEncode({
          'content': null,
          'imageKey': imageKey,
        }),
      );
    } catch (e) {
      _showSnack('이미지 전송 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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
        actions: [
          if (widget.studyId != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : widget.studyId == null
                    ? const Center(child: Text('채팅을 사용할 수 없습니다.'))
                    : _messages.isEmpty
                        ? const Center(child: Text('메시지가 없습니다.\n첫 메시지를 보내보세요!', textAlign: TextAlign.center))
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true, // 최신 메시지가 아래에서 시작
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              // reverse: true이므로 맨 마지막 인덱스가 오래된 메시지 위치
                              if (_isLoadingMore && index == _messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              }
                              return _buildChatBubble(_messages[index]);
                            },
                          ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, color: Colors.grey),
                    onPressed: _isSending ? null : _pickAndSendImage,
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
                    icon: Icon(
                      Icons.send,
                      color: _isConnected ? Colors.green : Colors.grey,
                    ),
                    onPressed: _isConnected ? _sendMessage : null,
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
    final senderId = msg['senderId'] as int?;
    final bool isMe = senderId == _currentUserId;
    final String? imageUrl = msg['imageUrl'] as String?;
    final String content = (msg['content'] as String?) ?? '';
    final String nickname = (msg['senderNickname'] as String?) ?? '알 수 없음';
    final String time = _formatTime(msg['createdAt'] as String?);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe)
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Icon(Icons.face, size: 20, color: Colors.green),
            ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Text(nickname, style: const TextStyle(fontSize: 10, color: Colors.black54)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isMe)
                    Text(time, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  const SizedBox(width: 4),
                  Container(
                    padding: imageUrl != null ? const EdgeInsets.all(4) : const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFFFFF9C4) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                );
                              },
                            ),
                          )
                        : Text(content, style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 4),
                  if (!isMe)
                    Text(time, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final isPm = dt.hour >= 12;
      final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      return '${isPm ? "오후" : "오전"} $hour12:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}
