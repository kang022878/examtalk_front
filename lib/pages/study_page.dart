import 'package:flutter/material.dart';
import 'package:toeic_master_front/pages/chat_page.dart';

class StudyPage extends StatefulWidget {
  final bool isLoggedIn;
  final String nickname;

  const StudyPage({
    super.key,
    required this.isLoggedIn,
    required this.nickname,
  });

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  bool _isSearching = true;
  String _selectedCategory = 'TOEIC';
  String _searchQuery = '';

  // 가상의 스터디 데이터
  final List<Map<String, dynamic>> _allStudies = [
    {
      'title': '대전 토익 850 +',
      'subtitle': 'TOEIC · 대전 · 850+ · 주 2회 · 온라인',
      'count': '3/4명',
      'category': 'TOEIC',
      'description': '안녕하세요~ 열심히 할 사람만 가입바랍니다\n다같이 파이팅!'
    },
    {
      'title': '로스쿨 대비 토플',
      'subtitle': 'TOEFL · 대전 · 105+ · 주 5회 · 오프라인',
      'count': '2/6명',
      'category': 'TOEFL',
      'description': '로스쿨 준비하시는 분들 모여서 빡세게 공부해요.'
    },
  ];

  // 내가 만든 스터디 데이터
  final List<Map<String, dynamic>> _myCreatedStudies = [
    {
      'title': '로스쿨 대비 토플1',
      'subtitle': 'TOEFL · 대전 · 110+ · 주 5회 · 오프라인',
      'members': [], // 초기 상태: 0명
      'maxCount': 6,
      'requests': [
        {
          'name': '토플마스터1',
          'email': 'helloworld1@gmail.com',
          'image': Icons.face,
          'message': '안녕하세요 카이스트 다니고 있는 학부생 홍길동 입니다.\n이번에 로스쿨 준비하게 되면서 가입하게 되었습니다.\n열심히 할 자신있습니다!'
        }
      ]
    }
  ];

  final List<Map<String, dynamic>> _myJoinedStudies = [
    {'title': '대전 토익 850 +', 'subtitle': 'TOEIC · 대전 · 850+ · 주 2회 · 온라인', 'count': '3/4명'},
  ];

  @override
  Widget build(BuildContext context) {
    final greetingName = widget.nickname.isNotEmpty ? widget.nickname : '닉네임';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('스터디', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isLoggedIn ? '$greetingName 님 합격하세요! 🍀' : '로그인하세요',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    _buildTabButton('스터디 찾기', _isSearching, () => setState(() => _isSearching = true)),
                    const SizedBox(width: 10),
                    _buildTabButton('내 스터디', !_isSearching, () {
                      if (!widget.isLoggedIn) {
                        _showLoginWarning();
                        return;
                      }
                      setState(() => _isSearching = false);
                    }),
                  ],
                ),
                const SizedBox(height: 15),
                _isSearching ? _buildSearchTab() : _buildMyStudyTab(),
              ],
            ),
          ),
          if (_isSearching)
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton.extended(
                heroTag: 'study_create_fab',
                onPressed: () {
                  if (widget.isLoggedIn) {
                    _showCreateStudyDialog();
                  } else {
                    _showLoginWarning();
                  }
                },
                label: const Text('스터디 만들기', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                backgroundColor: const Color(0xFFCDE1AF),
                elevation: 2,
              ),
            ),
        ],
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인', style: TextStyle(color: Colors.green))),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.grey[300] : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.black : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildSearchTab() {
    final query = _searchQuery.trim();

    final filteredStudies = _allStudies.where((s) {
      final bool categoryMatch = s['category'] == _selectedCategory;

      // 검색어가 비어있으면 제목 필터는 통과
      if (query.isEmpty) return categoryMatch;

      final title = (s['title'] ?? '').toString();
      final bool titleMatch = title.contains(query); // 한글도 contains로 OK
      return categoryMatch && titleMatch;
    }).toList();

    return Expanded(
      child: Column(
        children: [
          TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: '스터디 검색',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.green),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            children: ['TOEIC', 'TOEFL', 'TEPS', 'OPIc', 'GRE', 'IELTS', 'G-TELP']
                .map((cat) => ChoiceChip(
              label: Text(cat),
              selected: _selectedCategory == cat,
              onSelected: (_) => setState(() => _selectedCategory = cat),
              selectedColor: const Color(0xFFCDE1AF),
            ))
                .toList(),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: ListView.builder(
              itemCount: filteredStudies.length,
              itemBuilder: (context, index) {
                final s = filteredStudies[index];
                return _buildStudyListItem(s, isSearchTab: true);
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMyStudyTab() {
    return Expanded(
      child: ListView(
        children: [
          ..._myJoinedStudies.map((s) => _buildStudyListItem(s, isSearchTab: false)),
          const SizedBox(height: 20),
          const Text('내가 만든 스터디', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(height: 10),
          if (_myCreatedStudies.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('만든 스터디가 없습니다.'))),
          ..._myCreatedStudies.map((s) => _buildStudyListItem(s, isSearchTab: false, isOwner: true)),
        ],
      ),
    );
  }

  Widget _buildStudyListItem(Map<String, dynamic> study, {required bool isSearchTab, bool isOwner = false}) {
    String displayCount = study['count'] ?? "0/0명";
    if (isOwner && study['members'] != null) {
      displayCount = "${(study['members'] as List).length}/${study['maxCount']}명";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
      child: ListTile(
        onTap: () {
          if (isSearchTab) {
            // 스터디 찾기 탭: 상세보기
            _showStudyDetail(study);
          } else {
            // 내 스터디 탭: 채팅방 이동
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPage(studyTitle: study['title'] as String),
              ),
            );
          }
        },
        title: Text(study['title']!, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(study['subtitle']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (isOwner) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildSmallButton('회원 관리', () => _showMemberManagement(study)),
                  const SizedBox(width: 8),
                  _buildSmallButton('신규 가입 요청', () => _showApplicationRequests(study)),
                ],
              ),
            ],
          ],
        ),
        trailing: Text(displayCount, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSmallButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showStudyDetail(Map<String, dynamic> study) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text(''), backgroundColor: Colors.white, elevation: 0),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 50),
                Text(study['title']!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text(study['subtitle']!, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 10),
                Text(study['count']!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Text(study['description'] ?? '설명이 없습니다.', style: const TextStyle(fontSize: 14)),
                const Spacer(),
                Center(
                  child: ElevatedButton(
                    onPressed: () {
                      if (widget.isLoggedIn) {
                        _showApplyForm(study);
                      } else {
                        _showLoginWarning();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7CB342),
                      minimumSize: const Size(200, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('가입 신청', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showApplyForm(Map<String, dynamic> study) {
    final controller = TextEditingController();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text(''), backgroundColor: Colors.white, elevation: 0),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text('가입 신청서', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text(study['title']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(study['subtitle']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 20),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: controller,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: '가입 신청서를 작성해주세요.\n방장이 읽고 수락을 결정합니다.',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); 
                      Navigator.pop(context); 
                      ScaffoldMessenger.of(context).showSnackBar(
                        ApiResponseSnackBar(message: '가입 신청이 제출되었습니다.')
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7CB342),
                      minimumSize: const Size(120, 45),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('제출', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMemberManagement(Map<String, dynamic> study) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setPageState) => Scaffold(
            appBar: AppBar(title: const Text(''), backgroundColor: Colors.white, elevation: 0),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('회원 관리', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(study['title']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(study['subtitle']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      Text("${(study['members'] as List).length}/${study['maxCount']}명", 
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: (study['members'] as List).length,
                      itemBuilder: (context, index) {
                        final member = study['members'][index];
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.grey[200], child: Icon(member['image'])),
                          title: Text(member['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(member['email']),
                          trailing: _buildSmallButton('내보내기', () {
                            _showConfirmDialog('정말 내보내시겠습니까?', () {
                              setState(() {
                                study['members'].removeAt(index);
                              });
                              setPageState(() {}); 
                            });
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showApplicationRequests(Map<String, dynamic> study) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setPageState) => Scaffold(
            appBar: AppBar(title: const Text(''), backgroundColor: Colors.white, elevation: 0),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('신규 가입 요청', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(study['title']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(study['subtitle']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      Text("${(study['members'] as List).length}/${study['maxCount']}명", 
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: (study['requests'] as List).length,
                      itemBuilder: (context, index) {
                        final req = study['requests'][index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              leading: CircleAvatar(backgroundColor: Colors.grey[200], child: Icon(req['image'])),
                              title: Text(req['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(req['email']),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSmallButton('수락', () {
                                    _showConfirmDialog('정말 수락하시겠습니까?', () {
                                      setState(() {
                                        study['members'].add({
                                          'name': req['name'],
                                          'email': req['email'],
                                          'image': req['image']
                                        });
                                        study['requests'].removeAt(index);
                                      });
                                      setPageState(() {}); 
                                    });
                                  }),
                                  const SizedBox(width: 4),
                                  _buildSmallButton('거절', () {
                                    _showConfirmDialog('수락을 거절하시겠습니까?', () {
                                      setState(() {
                                        study['requests'].removeAt(index);
                                      });
                                      setPageState(() {});
                                    });
                                  }),
                                ],
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.all(12),
                              width: double.infinity,
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(4)),
                              child: Text(req['message'], style: const TextStyle(fontSize: 13, color: Colors.black87)),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showConfirmDialog(String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
            },
            child: const Text('확인', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  void _showCreateStudyDialog() {
    String examType = 'TOEIC';
    String city = '대전';
    final TextEditingController scoreController = TextEditingController();
    String meetingType = '온라인';
    final TextEditingController peopleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFCDE1AF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Center(child: Text('스터디 만들기', style: TextStyle(fontWeight: FontWeight.bold))),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogDropdown('시험 종류', examType, ['TOEIC', 'TOEFL', 'TEPS', 'OPIc', 'GRE', 'IELTS', 'G-TELP'], (val) => setDialogState(() => examType = val!)),
                  _buildDialogDropdown('시도', city, ['서울', '대전', '부산', '인천'], (val) => setDialogState(() => city = val!)),
                  _buildDialogTextField('목표 점수', scoreController, '점수 입력', isNumber: true),
                  _buildDialogDropdown('모임 횟수', '주 2회', ['주 1회', '주 2회', '주 3회', '주 4회', '주 5회', '주 6회', '매일'], (_) {}),
                  _buildDialogDropdown('형태', meetingType, ['온라인', '오프라인', '혼합'], (val) => setDialogState(() => meetingType = val!)),
                  _buildDialogTextField('모집 인원', peopleController, '인원수 입력', isNumber: true),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _myCreatedStudies.add({
                          'title': '$city $examType ${scoreController.text}+',
                          'subtitle': '$examType · $city · ${scoreController.text}+ · 주 2회 · $meetingType',
                          'members': [],
                          'maxCount': int.tryParse(peopleController.text) ?? 6,
                          'requests': []
                        });
                        _isSearching = false;
                      });
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    child: const Text('방 생성', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildDialogDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: DropdownButton<String>(value: value, isExpanded: true, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged)),
        ],
      ),
    );
  }

  Widget _buildDialogTextField(String label, TextEditingController controller, String hint, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: TextField(controller: controller, keyboardType: isNumber ? TextInputType.number : TextInputType.text, decoration: InputDecoration(hintText: hint, isDense: true))),
        ],
      ),
    );
  }
}

class ApiResponseSnackBar extends SnackBar {
  ApiResponseSnackBar({super.key, required String message}) 
    : super(content: Text(message), duration: const Duration(seconds: 2));
}
