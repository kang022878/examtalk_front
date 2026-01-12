import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:toeic_master_front/core/api.dart';
import 'package:toeic_master_front/core/api_client.dart';
import 'package:toeic_master_front/core/token_storage.dart';

/// ===============================
/// Models
/// ===============================
class TestSchedule {
  final String title;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final DateTime date;

  TestSchedule({
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.date,
  });
}

/// ===============================
/// MyPage
/// ===============================
class MyPage extends StatefulWidget {
  // ✅ 부모(main.dart)에서 내려주는 현재 상태
  final bool isLoggedIn;
  final String email;
  final String nickname;
  final String myGoal;
  final File? profileImage;

  // ✅ 부모 상태를 갱신하기 위한 콜백
  final void Function(String email, String nickname, String goal, File? profileImage) onLogin;
  final VoidCallback onLogout;
  final void Function(String nickname, String goal, File? profileImage) onProfileUpdated;

  const MyPage({
    super.key,
    required this.isLoggedIn,
    required this.email,
    required this.nickname,
    required this.myGoal,
    required this.profileImage,
    required this.onLogin,
    required this.onLogout,
    required this.onProfileUpdated,
  });

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  // ✅ 이 페이지 내부에서 “유저별 저장소”는 그대로 유지(로컬 UI용)
  final Map<String, Map<String, dynamic>> _userDataStorage = {};

  String? _profileImageUrl; // ✅ 서버에 저장된 프로필 이미지 URL

  // ✅ 페이지 내부 표시용 로컬 상태(부모 값과 동기화)
  late String _nickname;
  late String _myGoal;
  late String _email;
  File? _profileImage;

  // (백엔드 프로필 bio를 myGoal로 매핑해서 사용)
  String _bio = '';

  final Map<DateTime, List<TestSchedule>> _events = {};
  final CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  late final TokenStorage _tokenStorage;
  late final Api _api;

  @override
  void initState() {
    super.initState();
    _tokenStorage = TokenStorage();
    _api = Api(ApiClient(_tokenStorage));

    _syncFromParent();

    // ✅ 앱 재실행 시 토큰이 남아있으면 내 프로필 자동 로드
    _bootstrapAuth();
  }

  Future<void> _bootstrapAuth() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) return;

    try {
      final profileRes = await _api.getMyProfile();
      final data = profileRes['data'] as Map<String, dynamic>?;

      final email = (data?['email'] ?? '') as String;
      final nickname = (data?['nickname'] ?? '닉네임') as String;
      final bio = (data?['bio'] ?? '') as String;

      final profileImageUrl = (data?['profileImageUrl'] as String?)?.trim();


      if (!mounted) return;

      setState(() {
        _email = email;
        _nickname = nickname;
        _bio = bio;
        _myGoal = bio.isEmpty ? '목표를 적어보세요' : bio;

        _profileImageUrl = (profileImageUrl != null && profileImageUrl.isNotEmpty)
            ? profileImageUrl
            : null;
      });

      // 부모에 로그인 상태 반영
      widget.onLogin(_email, _nickname, _myGoal, _profileImage);
    } catch (_) {
      // 토큰이 만료/무효면 정리
      await _tokenStorage.clear();
    }
  }

  @override
  void didUpdateWidget(covariant MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isLoggedIn != widget.isLoggedIn ||
        oldWidget.email != widget.email ||
        oldWidget.nickname != widget.nickname ||
        oldWidget.myGoal != widget.myGoal ||
        oldWidget.profileImage?.path != widget.profileImage?.path) {
      _syncFromParent();
    }
  }

  void _syncFromParent() {
    _nickname = widget.nickname;
    _myGoal = widget.myGoal;
    _email = widget.email;
    _profileImage = widget.profileImage;

    // myGoal이 bio 역할이므로 동기화
    _bio = (_myGoal == '목표를 적어보세요') ? '' : _myGoal;
  }

  Future<void> _pickImage(StateSetter setDialogState, BuildContext dialogContext) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final file = File(pickedFile.path);

    // 1) 로컬 미리보기 즉시 반영
    setDialogState(() => _profileImage = file);
    setState(() {});

    try {
      // 2) 서버 업로드
      final uploadRes = await _api.uploadMyProfileImage(file);

      // 3) 서버가 내려준 URL을 상태에 반영 (중요!)
      final data = uploadRes['data'] as Map<String, dynamic>?;
      final url = (data?['profileImageUrl'] as String?)?.trim();

      if (!mounted) return;
      setState(() {
        _profileImageUrl = (url != null && url.isNotEmpty) ? url : _profileImageUrl;
      });

      // 부모에도 반영 (StudyPage 등 즉시 갱신)
      widget.onProfileUpdated(_nickname, _myGoal, _profileImage);

      // 4) ✅ 사진 수정 완료 → 정보 수정 창 닫기
      Navigator.of(dialogContext).pop();

      _showSnack('프로필 사진이 저장됐어요.');
    } catch (e) {
      _showSnack('프로필 사진 업로드 실패: $e');
    }
  }



  Future<void> _logout() async {
    await _tokenStorage.clear();

    if (!mounted) return;
    setState(() {
      _email = '';
      _nickname = '닉네임';
      _myGoal = '목표를 적어보세요';
      _bio = '';
      _profileImage = null;
    });

    widget.onLogout();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = widget.isLoggedIn;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('마이페이지', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: isLoggedIn
            ? [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: InkWell(
                onTap: _logout,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Text('로그아웃',
                          style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]
            : null,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isLoggedIn ? _buildLoggedInHeader() : _buildLoggedOutHeader(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
              child: Text('내 리뷰', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            _buildReviewGallery(),
            const Divider(thickness: 8, color: Color(0xFFF5F5F5)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
              child: Text('내 시험 일정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (_events.isNotEmpty) _buildEventList(),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: _buildCalendar()),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInHeader() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE1E8DC),
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 35,
                backgroundColor: Colors.white,
                backgroundImage: _profileImage != null
                    ? FileImage(_profileImage!)
                    : (_profileImageUrl != null && _profileImageUrl!.isNotEmpty
                    ? NetworkImage(_profileImageUrl!)
                    : null) as ImageProvider?,
                child: (_profileImage == null && (_profileImageUrl == null || _profileImageUrl!.isEmpty))
                    ? const Icon(Icons.face, size: 50, color: Colors.lightGreen)
                    : null,
              ),

              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_nickname, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(_email, style: const TextStyle(color: Colors.black54, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('나의 목표', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Text(_myGoal, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF436B2D))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showEditInfoDialog,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('내 정보 수정하기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: const BorderSide(color: Colors.black12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.white.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditInfoDialog() async {
    bool imageChanged = false;
    final nameController = TextEditingController(text: _nickname);
    final goalController = TextEditingController(text: _myGoal == '목표를 적어보세요' ? '' : _myGoal);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('정보 수정', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    await _pickImage(setDialogState, context); // 여기 context는 다이얼로그 context
                  },
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.white,
                        backgroundImage: _profileImage != null
                            ? FileImage(_profileImage!)
                            : (_profileImageUrl != null && _profileImageUrl!.isNotEmpty
                            ? NetworkImage(_profileImageUrl!)
                            : null) as ImageProvider?,
                        child: (_profileImage == null && (_profileImageUrl == null || _profileImageUrl!.isEmpty))
                            ? const Icon(Icons.face, size: 50, color: Colors.lightGreen)
                            : null,
                      ),

                      const Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(radius: 12, backgroundColor: Colors.green, child: Icon(Icons.edit, size: 12, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: '닉네임')),
                const SizedBox(height: 16),
                TextField(controller: goalController, decoration: const InputDecoration(labelText: '나의 목표(=소개 bio)')),
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소'))),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final newNickname = nameController.text.trim().isEmpty ? '닉네임' : nameController.text.trim();
                      final newBio = goalController.text.trim();

                      try {
                        await _api.updateMyProfile(nickname: newNickname, bio: newBio);

                        if (!mounted) return;
                        setState(() {
                          _nickname = newNickname;
                          _bio = newBio;
                          _myGoal = newBio.isEmpty ? '목표를 적어보세요' : newBio;
                        });

                        widget.onProfileUpdated(_nickname, _myGoal, _profileImage);

                        Navigator.pop(context);
                        _showSnack('프로필이 저장됐어요.');
                      } catch (e) {
                        _showSnack('프로필 저장 실패: $e');
                      }
                    },

                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFCDE1AF), foregroundColor: Colors.black),
                    child: const Text('저장하기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLoginWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알림'),
        content: const Text('로그인 후 사용하세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggedOutHeader() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE1E8DC),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => LoginPage(api: _api, tokenStorage: _tokenStorage)),
              );

              // 로그인 성공 시: LoginResult 반환
              if (result != null && result is LoginResult) {
                final email = result.email;
                final nickname = result.nickname;
                final bio = result.bio;

                setState(() {
                  _email = email;
                  _nickname = nickname.isEmpty ? '닉네임' : nickname;
                  _bio = bio;
                  _myGoal = bio.isEmpty ? '목표를 적어보세요' : bio;

                  // (로컬 캐시 유지)
                  _userDataStorage[email] = {'nickname': _nickname, 'goal': _myGoal, 'image': _profileImage};
                });

                // ✅ 부모에게 로그인 상태 전달
                widget.onLogin(_email, _nickname, _myGoal, _profileImage);
              }
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.grey[400],
                    child: Icon(Icons.person, size: 50, color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(width: 15),
                const Text('로그인하세요', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            height: 120,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: const Text('나의 목표', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54)),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE1E8DC).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
      ),
      child: TableCalendar(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat,
        eventLoader: (day) => _events[DateTime(day.year, day.month, day.day)] ?? [],
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          if (widget.isLoggedIn) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
            _showAddEventDialog(selectedDay);
          } else {
            _showLoginWarning();
          }
        },
        headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
        calendarStyle: const CalendarStyle(
          todayDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
          markerDecoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          selectedDecoration: BoxDecoration(color: Colors.transparent, shape: BoxShape.circle),
          selectedTextStyle: TextStyle(color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildEventList() {
    final allEvents = _events.values.expand((e) => e).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: List.generate(allEvents.length, (index) {
          final event = allEvents[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: ListTile(
              onTap: () => _showEventDetailDialog(event),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(event.title, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text('${event.date.year}.${event.date.month}.${event.date.day}', style: const TextStyle(color: Colors.black87, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildTimeTag('시작', event.startTime.format(context)),
                      const SizedBox(width: 10),
                      _buildTimeTag('종료', event.endTime.format(context)),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTimeTag(String label, String time) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(time, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildReviewGallery() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: 6,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.image, color: Colors.white),
        ),
      ),
    );
  }

  void _showAddEventDialog(DateTime date) {
    final titleController = TextEditingController();
    TimeOfDay startTime = const TimeOfDay(hour: 13, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 15, minute: 0);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(hintText: '제목')),
              const SizedBox(height: 20),
              _buildTimePickerRow('시작', startTime, (time) => setDialogState(() => startTime = time)),
              _buildTimePickerRow('종료', endTime, (time) => setDialogState(() => endTime = time)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.isNotEmpty) {
                    setState(() {
                      final key = DateTime(date.year, date.month, date.day);
                      _events.putIfAbsent(key, () => []);
                      _events[key]!.add(TestSchedule(title: titleController.text, startTime: startTime, endTime: endTime, date: date));
                    });
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFCDE1AF), foregroundColor: Colors.black),
                child: const Text('일정 추가'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEventDetailDialog(TestSchedule event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(event.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Text('시작 ${event.date.year}.${event.date.month.toString().padLeft(2, '0')}.${event.date.day.toString().padLeft(2, '0')} ${event.startTime.format(context)}'),
            Text('종료 ${event.date.year}.${event.date.month.toString().padLeft(2, '0')}.${event.date.day.toString().padLeft(2, '0')} ${event.endTime.format(context)}'),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  final key = DateTime(event.date.year, event.date.month, event.date.day);
                  _events[key]?.remove(event);
                  if (_events[key]?.isEmpty ?? false) _events.remove(key);
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFCDE1AF), foregroundColor: Colors.black),
              child: const Text('삭제'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerRow(String label, TimeOfDay time, Function(TimeOfDay) onTimeSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          InkWell(
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: time);
              if (picked != null) onTimeSelected(picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
              child: Text(time.format(context)),
            ),
          )
        ],
      ),
    );
  }
}

/// ===============================
/// Login / Signup Pages
/// ===============================
class LoginResult {
  final String email;
  final String nickname;
  final String bio;

  LoginResult({
    required this.email,
    required this.nickname,
    required this.bio,
  });
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.api,
    required this.tokenStorage,
  });

  final Api api;
  final TokenStorage tokenStorage;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();

  bool _loading = false;

  String _prettyDioError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final msg = e.response?.data?['message'] ?? e.message ?? '요청 실패';
      return '($status) $msg';
    }
    return e.toString();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final pw = _pwController.text;

    if (email.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이메일/비밀번호를 입력하세요.')));
      return;
    }

    setState(() => _loading = true);

    try {
      final token = await widget.api.login(email: email, password: pw);
      await widget.tokenStorage.saveAccessToken(token);

      // 로그인 후 내 프로필까지 가져와서 닉네임/바이오 세팅
      final profileRes = await widget.api.getMyProfile();
      final data = profileRes['data'] as Map<String, dynamic>?;

      final nickname = (data?['nickname'] ?? '닉네임') as String;
      final bio = (data?['bio'] ?? '') as String;
      final profileEmail = (data?['email'] ?? email) as String;

      if (!mounted) return;
      Navigator.pop(
        context,
        LoginResult(email: profileEmail, nickname: nickname, bio: bio),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로그인 실패: ${_prettyDioError(e)}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE1E8DC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.close, color: Colors.black, size: 30), onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 10),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(left: 30.0, right: 30.0, bottom: 80.0),
          child: Column(
            children: [
              const Text('로그인', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: '이메일', labelStyle: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pwController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '비밀번호', labelStyle: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _loading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('로그인 하기', style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SignUpPage(api: widget.api)),
                      ),
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                          children: [
                            TextSpan(text: '계정이 없으신가요? '),
                            TextSpan(text: '회원가입', style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key, required this.api});

  final Api api;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _pwConfirmController = TextEditingController();

  bool _isPasswordCorrect = true;
  bool _isPasswordLengthValid = true;
  bool _loading = false;

  void _checkPassword() {
    setState(() {
      _isPasswordLengthValid = _pwController.text.length >= 6;
      _isPasswordCorrect =
          _pwController.text == _pwConfirmController.text;
    });
  }

  String _prettyDioError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final msg = e.response?.data?['message'] ?? e.message ?? '요청 실패';
      return '($status) $msg';
    }
    return e.toString();
  }

  Future<void> _handleSignup() async {
    final email = _emailController.text.trim();
    final nickname = _nicknameController.text.trim();
    final pw = _pwController.text;

    if (pw.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호는 6자 이상이어야 합니다.')),
      );
      return;
    }

    if (email.isEmpty || nickname.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이메일/닉네임/비밀번호를 모두 입력하세요.')));
      return;
    }
    if (!_isPasswordCorrect) return;

    setState(() => _loading = true);

    try {
      await widget.api.signup(email: email, password: pw, nickname: nickname);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('회원가입 성공! 로그인 해주세요.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('회원가입 실패: ${_prettyDioError(e)}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE1E8DC),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            children: [
              const Text('회원가입', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    TextField(controller: _nicknameController, decoration: const InputDecoration(labelText: '닉네임')),
                    const SizedBox(height: 20),
                    TextField(controller: _emailController, decoration: const InputDecoration(labelText: '이메일')),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pwController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: '비밀번호',
                        errorText: _isPasswordLengthValid
                            ? null
                            : '비밀번호는 6자 이상 입력하세요',
                      ),
                      onChanged: (_) => _checkPassword(),
                    ),

                    const SizedBox(height: 20),
                    TextField(
                      controller: _pwConfirmController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: '비밀번호 확인',
                        errorText: _isPasswordCorrect ? null : '같은 비밀번호가 아닙니다.',
                        errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                      onChanged: (_) => _checkPassword(),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _loading ? null : (_isPasswordCorrect ? _handleSignup : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('가입하기', style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
