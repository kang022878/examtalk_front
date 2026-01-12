import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:toeic_master_front/core/api.dart';
import 'package:toeic_master_front/core/api_client.dart';
import 'package:toeic_master_front/core/token_storage.dart';
import 'package:dio/dio.dart';

import 'package:image_picker/image_picker.dart';

/// ====== Models ======
class School {
  final int id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double avgRating;
  final int reviewCount;

  const School({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.avgRating,
    required this.reviewCount,
  });

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      id: (json['id'] as num).toInt(),
      name: (json['name'] ?? '') as String,
      address: (json['address'] ?? '') as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      avgRating: (json['avgRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReviewItem {
  final int id;
  final String authorNickname;
  final bool recommended; // 추천/비추천
  final bool facilityGood; // 시설 좋아요/별로예요
  final bool quiet; // 조용해요/시끄러워요
  final bool accessible; // 자가용/대중교통
  final int rating;
  final String content;
  final int likeCount;
  final List<String> imageUrls;

  const ReviewItem({
    required this.id,
    required this.authorNickname,
    required this.recommended,
    required this.facilityGood,
    required this.quiet,
    required this.accessible,
    required this.rating,
    required this.content,
    required this.likeCount,
    required this.imageUrls,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    final images = (json['images'] as List<dynamic>?) ?? const [];
    final urls = <String>[];
    for (final e in images) {
      final m = e as Map<String, dynamic>;
      final u = m['imageUrl'] as String?;
      if (u != null && u.isNotEmpty) urls.add(u);
    }

    return ReviewItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      authorNickname: (json['authorNickname'] ?? '') as String,
      recommended: (json['recommended'] ?? false) as bool,
      facilityGood: (json['facilityGood'] ?? false) as bool,
      quiet: (json['quiet'] ?? false) as bool,
      accessible: (json['accessible'] ?? false) as bool,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      content: (json['content'] ?? '') as String,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      imageUrls: urls,
    );
  }
}

/// ====== Page ======
class TestCenterPage extends StatefulWidget {
  const TestCenterPage({super.key});

  @override
  State<TestCenterPage> createState() => _TestCenterPageState();
}

class _TestCenterPageState extends State<TestCenterPage> {

  late final ApiClient _apiClient;
  late final Api _api;

  NaverMapController? _mapController;

  final TextEditingController _searchController = TextEditingController();

  bool _isMovingToMyLocation = false;
  bool _isLoadingSchools = false;
  bool _isSchoolSheetOpen = false;

  List<School> _schools = [];
  final Map<int, NMarker> _schoolMarkers = {}; // schoolId -> marker

  Position? _myPosition;

  String? _myNickname;

  void _closeSchoolSheetIfOpen() {
    if (_isSchoolSheetOpen) {
      _isSchoolSheetOpen = false; // ✅ 중요: 닫기 전에 먼저 내려줘야 재오픈 가드에 안 걸림
      Navigator.of(context).pop();
    }
  }


  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(TokenStorage());
    _api = Api(_apiClient);

    _loadMyPositionSilently();

    _loadMyNicknameSilently();
  }

  Future<void> _loadMyNicknameSilently() async {
    try {
      final res = await _apiClient.dio.get('/api/users/me');
      final decoded = res.data as Map<String, dynamic>;
      final data = decoded['data'];

      String? nickname;
      if (data is Map<String, dynamic>) {
        nickname = (data['nickname'] ?? data['name'] ?? data['userNickname']) as String?;
      }

      if (!mounted) return;
      setState(() => _myNickname = nickname);
    } catch (_) {
      // 로그인 안 했거나 /me 엔드포인트 없으면 null로 둠
    }
  }


  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// ====== 위치 로드 ======
  Future<void> _loadMyPositionSilently() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() => _myPosition = pos);
    } catch (_) {
      // ignore
    }
  }

  /// ====== API: 전체 학교 ======
  Future<List<School>> _fetchAllSchools() async {
    final res = await _apiClient.dio.get('/api/schools');
    final data = (res.data as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    return data.map((e) => School.fromJson(e as Map<String, dynamic>)).toList();
  }


  /// ====== API: 학교 검색 ======
  Future<List<School>> _searchSchoolsByName(String name) async {
    final res = await _apiClient.dio.get(
      '/api/schools/search',
      queryParameters: {'name': name},
    );
    final data = (res.data as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    return data.map((e) => School.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ====== API: 주변 학교 ======
  Future<List<School>> _fetchNearbySchools({
    required double lat,
    required double lng,
  }) async {
    final res = await _apiClient.dio.get(
      '/api/schools/nearby',
      queryParameters: {'lat': lat, 'lng': lng},
    );
    final data = (res.data as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    return data.map((e) => School.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ====== API: 리뷰 목록 ======
  Future<List<ReviewItem>> _fetchReviewsForSchool(int schoolId) async {
    final res = await _apiClient.dio.get(
      '/api/schools/$schoolId/reviews',
      queryParameters: {
        'page': 0,
        'size': 50,
        'sort': 'createdAt,desc',
      },
    );

    final decoded = res.data as Map<String, dynamic>;
    final data = decoded['data'];

    List<dynamic> list;
    if (data is List) {
      list = data;
    } else if (data is Map<String, dynamic>) {
      if (data['content'] is List) {
        list = data['content'] as List<dynamic>;
      } else if (data['data'] is List) {
        list = data['data'] as List<dynamic>;
      } else {
        list = const [];
      }
    } else {
      list = const [];
    }

    return list.map((e) => ReviewItem.fromJson(e as Map<String, dynamic>)).toList();
  }


  /// ====== API: 리뷰 작성 ======
  Future<int> _createReview({
    required int schoolId,
    required int rating,
    required String content,
    required bool recommended,
    required bool facilityGood,
    required bool quiet,
    required bool accessible,
  }) async {
    final body = {
      'rating': rating,
      'content': content,
      'recommended': recommended,
      'facilityGood': facilityGood,
      'quiet': quiet,
      'accessible': accessible,
    };

    final res = await _apiClient.dio.post(
      '/api/schools/$schoolId/reviews',
      data: body,
    );

    final decoded = res.data as Map<String, dynamic>;
    final data = decoded['data'];

    if (data is Map<String, dynamic>) {
      final idNum = data['id'] as num?;
      if (idNum != null) return idNum.toInt();
    }

    throw Exception('리뷰 작성 응답에서 reviewId를 찾을 수 없음');
  }

  /// ====== API: 리뷰 수정 ======
  Future<void> _updateReview({
    required int reviewId,
    required int rating,
    required String content,
    required bool recommended,
    required bool facilityGood,
    required bool quiet,
    required bool accessible,
  }) async {
    final body = {
      'rating': rating,
      'content': content,
      'recommended': recommended,
      'facilityGood': facilityGood,
      'quiet': quiet,
      'accessible': accessible,
    };

    await _apiClient.dio.put(
      '/api/reviews/$reviewId',
      data: body,
    );
  }

  Future<bool?> _showAlreadyReviewedDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('알림'),
          content: const Text('이미 리뷰를 작성한 장소입니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('닫기'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5E9B4B),
                foregroundColor: Colors.white,
              ),
              child: const Text('수정하기'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showEditReviewDialog({
    required School school,
    required ReviewItem review,
  }) async {
    bool recommended = review.recommended;
    bool facilityGood = review.facilityGood;
    bool quiet = review.quiet;
    bool accessible = review.accessible;

    File? pickedImage;
    String contentText = review.content;

    bool submitting = false;

    Future<void> pickImage(StateSetter setStateDialog) async {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      setStateDialog(() => pickedImage = File(xfile.path));
    }

    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF8DBB6A), width: 1),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('리뷰 수정', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 14),

                      const Text('이 고사장을 추천하나요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _toggleButton(
                            label: '추천',
                            selected: recommended == true,
                            onTap: submitting ? () {} : () => setStateDialog(() => recommended = true),
                          ),
                          const SizedBox(width: 10),
                          _toggleButton(
                            label: '비추천',
                            selected: recommended == false,
                            onTap: submitting ? () {} : () => setStateDialog(() => recommended = false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Text('시험장 시설은 어땠나요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _toggleButton(
                            label: '좋아요',
                            selected: facilityGood == true,
                            onTap: submitting ? () {} : () => setStateDialog(() => facilityGood = true),
                          ),
                          const SizedBox(width: 10),
                          _toggleButton(
                            label: '별로예요',
                            selected: facilityGood == false,
                            onTap: submitting ? () {} : () => setStateDialog(() => facilityGood = false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Text('전체적으로 조용한 환경인가요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _toggleButton(
                            label: '조용해요',
                            selected: quiet == true,
                            onTap: submitting ? () {} : () => setStateDialog(() => quiet = true),
                          ),
                          const SizedBox(width: 10),
                          _toggleButton(
                            label: '시끄러워요',
                            selected: quiet == false,
                            onTap: submitting ? () {} : () => setStateDialog(() => quiet = false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Text('교통은 어떤가요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Column(
                        children: [
                          _toggleButton(
                            label: '자가용도 괜찮아요',
                            selected: accessible == true,
                            onTap: submitting ? () {} : () => setStateDialog(() => accessible = true),
                          ),
                          const SizedBox(width: 10),
                          _toggleButton(
                            label: '대중교통을 추천해요',
                            selected: accessible == false,
                            onTap: submitting ? () {} : () => setStateDialog(() => accessible = false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      const Text('사진 업로드(선택)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: submitting ? null : () => pickImage(setStateDialog),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[200],
                              foregroundColor: Colors.black87,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('파일 선택'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              pickedImage == null ? '선택한 파일이 없습니다' : pickedImage!.path.split('/').last,
                              style: const TextStyle(color: Colors.black54),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (pickedImage != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '선택 취소',
                              onPressed: submitting ? null : () => setStateDialog(() => pickedImage = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 18),

                      const Text('리뷰 내용', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      TextField(
                        minLines: 4,
                        maxLines: 6,
                        enabled: !submitting,
                        controller: TextEditingController(text: contentText),
                        onChanged: (v) => contentText = v,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: submitting ? null : () => Navigator.pop(dialogContext, false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                                side: const BorderSide(color: Colors.black26),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                              child: const Text('취소', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: submitting
                                  ? null
                                  : () async {
                                final text = contentText.trim();
                                if (text.isEmpty) {
                                  _showSnack('리뷰 내용을 입력해주세요!');
                                  return;
                                }

                                setStateDialog(() => submitting = true);

                                try {
                                  final rating = recommended ? 5 : 1;

                                  await _updateReview(
                                    reviewId: review.id,
                                    rating: rating,
                                    content: text,
                                    recommended: recommended,
                                    facilityGood: facilityGood,
                                    quiet: quiet,
                                    accessible: accessible,
                                  );

                                  if (pickedImage != null) {
                                    await _uploadReviewImage(reviewId: review.id, imageFile: pickedImage!);
                                  }

                                  if (!mounted) return;
                                  Navigator.pop(dialogContext, true);
                                } catch (e) {
                                  _showSnack('수정 실패: $e');
                                  if (mounted) setStateDialog(() => submitting = false);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5E9B4B),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                              child: submitting
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Text('수정하기', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// ====== API: 리뷰 이미지 업로드 (multipart) ======
  Future<void> _uploadReviewImage({
    required int reviewId,
    required File imageFile,
  }) async {
    final formData = FormData.fromMap({
      'files': [
        await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      ],
    });

    await _apiClient.dio.post(
      '/api/reviews/$reviewId/images',
      data: formData,
      options: Options(
        headers: {Headers.contentTypeHeader: null}, // boundary 자동
      ),
    );
  }

  /// ====== (4)+(5) 합쳐서: 리뷰 작성 + 이미지 업로드 ======
  Future<void> _submitReview({
    required int schoolId,
    required bool recommended,
    required bool facilityGood,
    required bool quiet,
    required bool accessible,
    required String content,
    File? imageFile,
  }) async {
    final rating = recommended ? 5 : 1;

    final reviewId = await _createReview(
      schoolId: schoolId,
      rating: rating,
      content: content,
      recommended: recommended,
      facilityGood: facilityGood,
      quiet: quiet,
      accessible: accessible,
    );

    if (imageFile != null) {
      await _uploadReviewImage(reviewId: reviewId, imageFile: imageFile);
    }
  }

  /// ====== 지도/마커 적용 ======
  Future<void> _applySchoolsToMap(List<School> schools) async {
    if (_mapController == null) return;

    for (final m in _schoolMarkers.values) {
      try {
        await _mapController!.deleteOverlay(m.info);
      } catch (_) {}
    }
    _schoolMarkers.clear();

    setState(() => _schools = schools);

    for (final s in schools) {
      final marker = NMarker(
        id: 'school_${s.id}',
        position: NLatLng(s.latitude, s.longitude),
      );

      marker.setOnTapListener((overlay) async {
        await _onSchoolMarkerTapped(s);
      });

      await _mapController!.addOverlay(marker);
      _schoolMarkers[s.id] = marker;
    }
  }

  Future<void> _loadSchoolsAndPlaceMarkers() async {
    if (_mapController == null) return;

    setState(() => _isLoadingSchools = true);
    try {
      final schools = await _fetchAllSchools();
      if (!mounted) return;
      await _applySchoolsToMap(schools);
    } finally {
      if (mounted) setState(() => _isLoadingSchools = false);
    }
  }

  Future<void> _onSchoolMarkerTapped(School school) async {
    try {
      final reviews = await _fetchReviewsForSchool(school.id);
      if (!mounted) return;
      _showSchoolBottomSheet(school: school, reviews: reviews);
    } catch (e) {
      _showSnack('리뷰 불러오기 실패: $e');
    }
  }

  /// ====== UI ======
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          NaverMap(
            options: const NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: NLatLng(36.3504, 127.3845),
                zoom: 12,
              ),
            ),
            onMapReady: (controller) async {
              _mapController = controller;
              await _loadSchoolsAndPlaceMarkers();
            },
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _buildSearchBar(),
            ),
          ),

          if (_isLoadingSchools)
            const Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _isMovingToMyLocation ? null : _moveToMyLocation,
        backgroundColor: Colors.white,
        child: _isMovingToMyLocation
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Icon(Icons.location_on, color: Colors.green),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '고사장 검색',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              _searchController.clear();
              setState(() {});
              setState(() => _isLoadingSchools = true);
              try {
                final schools = await _fetchAllSchools();
                if (!mounted) return;
                await _applySchoolsToMap(schools);
              } finally {
                if (mounted) setState(() => _isLoadingSchools = false);
              }
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.95),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (q) async {
          final keyword = q.trim();
          if (keyword.isEmpty) return;

          setState(() => _isLoadingSchools = true);
          try {
            final schools = await _searchSchoolsByName(keyword);
            if (!mounted) return;
            await _applySchoolsToMap(schools);

            if (schools.isNotEmpty && _mapController != null) {
              await _mapController!.updateCamera(
                NCameraUpdate.scrollAndZoomTo(
                  target: NLatLng(schools.first.latitude, schools.first.longitude),
                  zoom: 14,
                ),
              );
            }
          } catch (e) {
            _showSnack('검색 실패: $e');
          } finally {
            if (mounted) setState(() => _isLoadingSchools = false);
          }
        },
      ),
    );
  }

  Future<void> _moveToMyLocation() async {
    if (_mapController == null) return;

    setState(() => _isMovingToMyLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('위치 서비스가 꺼져있습니다. 켜주세요.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showSnack('위치 권한이 거부되었습니다.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack('설정에서 위치 권한을 허용해주세요.');
        await Geolocator.openAppSettings();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;

      setState(() => _myPosition = pos);

      final myLatLng = NLatLng(pos.latitude, pos.longitude);
      await _mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: myLatLng,
          zoom: 15,
        ),
      );

      setState(() => _isLoadingSchools = true);
      try {
        final nearby = await _fetchNearbySchools(
          lat: pos.latitude,
          lng: pos.longitude,
        );
        if (!mounted) return;
        await _applySchoolsToMap(nearby);
      } finally {
        if (mounted) setState(() => _isLoadingSchools = false);
      }
    } catch (e) {
      _showSnack('내 위치로 이동 실패: $e');
    } finally {
      if (mounted) setState(() => _isMovingToMyLocation = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// ====== (1) 마커 클릭 시: 장소/리뷰 바텀시트 ======
  void _showSchoolBottomSheet({
    required School school,
    required List<ReviewItem> reviews,
  }) {

    if (_isSchoolSheetOpen) return;
    _isSchoolSheetOpen = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final distanceText = _distanceTextToSchool(school);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context), // ✅ 상단 빈 공간 터치 시 닫기 기능 복구
          child: DraggableScrollableSheet(
            initialChildSize: 0.62,
            minChildSize: 0.35,
            maxChildSize: 0.88,
            builder: (context, scrollController) {
              return GestureDetector(
                onTap: () {}, // 시트 내부 터치 시 닫히는 것 방지
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(color: const Color(0xFF8DBB6A), width: 1),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                          children: [
                            Text(
                              school.name,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$distanceText · ${_guessRegionFromAddress(school.address)}',
                              style: const TextStyle(fontSize: 14, color: Colors.black54),
                            ),
                            const SizedBox(height: 14),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '리뷰 ${school.reviewCount}개',
                                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    Navigator.pop(context); // 현재 열려있는 바텀시트 닫기

                                    // ✅ 현재 학교 리뷰에서 “내 리뷰” 탐색
                                    ReviewItem? myReview;
                                    final myNick = _myNickname;
                                    if (myNick != null && myNick.isNotEmpty) {
                                      for (final r in reviews) {
                                        if (r.authorNickname == myNick) {
                                          myReview = r;
                                          break;
                                        }
                                      }
                                    }

                                    bool? ok;

                                    if (myReview != null) {
                                      // ✅ 이미 작성했으면 경고 + 수정하기 유도
                                      final goEdit = await _showAlreadyReviewedDialog();
                                      if (goEdit == true) {
                                        ok = await _showEditReviewDialog(school: school, review: myReview);
                                      } else {
                                        ok = false;
                                      }
                                    } else {
                                      // ✅ 처음이면 작성 다이얼로그
                                      ok = await _showWriteReviewDialog(school: school);
                                    }

                                    if (ok == true) {
                                      _showSnack('리뷰 제출이 완료되었습니다');
                                      await _loadSchoolsAndPlaceMarkers();

                                      final updatedSchool = _schools.firstWhere(
                                        (s) => s.id == school.id,
                                        orElse: () => school,
                                      );
                                      final newReviews = await _fetchReviewsForSchool(school.id);
                                      
                                      if (!mounted) return;
                                      _showSchoolBottomSheet(school: updatedSchool, reviews: newReviews);
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF5E9B4B),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                    elevation: 0,
                                  ),
                                  child: const Text('리뷰 작성하기', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),
                            const Divider(height: 1),

                            const SizedBox(height: 14),
                            for (final r in reviews) ...[
                              _buildReviewCard(school: school, r: r),
                              const Divider(height: 20),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      _isSchoolSheetOpen = false;
    });
  }

  String _distanceTextToSchool(School s) {
    final pos = _myPosition;
    if (pos == null) return '거리 정보 없음';
    final meters = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      s.latitude,
      s.longitude,
    );
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)}km';
  }

  String _guessRegionFromAddress(String address) {
    final parts = address.trim().split(' ');
    if (parts.length >= 2) return '${parts[0]} ${parts[1]}';
    if (parts.isNotEmpty) return parts[0];
    return '';
  }

  Widget _buildReviewCard({
    required School school,
    required ReviewItem r,
  }) {
    final firstImage = r.imageUrls.isNotEmpty ? r.imageUrls.first : null;
    final isMine = (_myNickname != null &&
        _myNickname!.isNotEmpty &&
        r.authorNickname == _myNickname);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text(
                r.authorNickname.isNotEmpty ? r.authorNickname.characters.first : '🙂',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                r.authorNickname,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // ✅ 내 리뷰면 수정 버튼
            if (isMine)
              TextButton.icon(
                onPressed: () async {
                  // ✅ 1) 바텀시트 먼저 닫기 (write-review 흐름과 동일하게)
                  _closeSchoolSheetIfOpen();

                  // ✅ 2) 한 프레임 뒤에 다이얼로그 열기 (pop 애니메이션 정리 시간)
                  await Future.delayed(const Duration(milliseconds: 50));

                  final ok = await _showEditReviewDialog(school: school, review: r);

                  if (ok == true) {
                    _showSnack('리뷰가 수정되었습니다');
                    await _loadSchoolsAndPlaceMarkers();

                    // ✅ school 정보(리뷰카운트 등)도 최신으로 가져오기
                    final updatedSchool = _schools.firstWhere(
                          (s) => s.id == school.id,
                      orElse: () => school,
                    );

                    final newReviews = await _fetchReviewsForSchool(school.id);
                    if (!mounted) return;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _showSchoolBottomSheet(school: updatedSchool, reviews: newReviews);
                    });
                  }
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('수정'),
              ),
          ],
        ),
        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill(
              r.recommended ? '추천' : '비추천',
              borderColor: r.recommended ? Colors.blue : Colors.red,
              textColor: r.recommended ? Colors.blue : Colors.red,
            ),
            _pill(
              r.facilityGood ? '시설이 좋아요' : '시설이 별로예요',
              borderColor: r.facilityGood ? Colors.blue : Colors.red,
              textColor: r.facilityGood ? Colors.blue : Colors.red,
            ),
            _pill(
              r.quiet ? '조용해요' : '시끄러워요',
              borderColor: r.quiet ? Colors.blue : Colors.red ,
              textColor: r.quiet ? Colors.blue : Colors.red,
            ),
            _pill(
              r.accessible ? '자가용도 괜찮아요' : '대중교통을 추천해요',
              borderColor: Colors.green,
              textColor: Colors.green,
            ),
          ],
        ),

        const SizedBox(height: 14),

        if (firstImage != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              firstImage,
              width: 160,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 160,
                height: 120,
                color: Colors.grey[200],
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                r.content,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Row(
              children: [
                const Icon(Icons.thumb_up_alt_outlined, size: 18, color: Colors.black45),
                const SizedBox(width: 4),
                Text('${r.likeCount}', style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _pill(
      String text, {
        required Color borderColor,
        required Color textColor,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.4),
        color: Colors.transparent,
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<bool?> _showWriteReviewDialog({required School school}) async {
    bool recommended = true;
    bool facilityGood = true;
    bool quiet = true;
    bool accessible = true;

    File? pickedImage;
    String contentText = '';

    bool submitting = false;

    Future<void> pickImage(StateSetter setStateDialog) async {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      setStateDialog(() => pickedImage = File(xfile.path));
    }

    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF8DBB6A), width: 1),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('리뷰 작성', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 14),

                      const Text('이 고사장을 추천하나요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _toggleButton(
                            label: '추천',
                            selected: recommended == true,
                            onTap: submitting ? () {} : () => setStateDialog(() => recommended = true),
                          ),
                          const SizedBox(width: 10),
                          _toggleButton(
                            label: '비추천',
                            selected: recommended == false,
                            onTap: submitting ? () {} : () => setStateDialog(() => recommended = false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Text('시험장 시설은 어땠나요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _toggleButton(
                            label: '좋아요',
                            selected: facilityGood == true,
                            onTap: submitting ? () {} : () => setStateDialog(() => facilityGood = true),
                          ),
                          const SizedBox(width: 10),
                          _toggleButton(
                            label: '별로예요',
                            selected: facilityGood == false,
                            onTap: submitting ? () {} : () => setStateDialog(() => facilityGood = false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Text('전체적으로 조용한 환경인가요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _toggleButton(
                            label: '조용해요',
                            selected: quiet == true,
                            onTap: submitting ? () {} : () => setStateDialog(() => quiet = true),
                          ),
                          const SizedBox(width: 10),
                          _toggleButton(
                            label: '시끄러워요',
                            selected: quiet == false,
                            onTap: submitting ? () {} : () => setStateDialog(() => quiet = false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Text('교통은 어떤가요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Column(
                        children: [
                          _toggleButton(
                            label: '자가용도 괜찮아요',
                            selected: accessible == true,
                            onTap: submitting ? () {} : () => setStateDialog(() => accessible = true),
                          ),
                          const SizedBox(width: 10),
                          _toggleButton(
                            label: '대중교통을 추천해요',
                            selected: accessible == false,
                            onTap: submitting ? () {} : () => setStateDialog(() => accessible = false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      const Text('사진 업로드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: submitting ? null : () => pickImage(setStateDialog),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[200],
                              foregroundColor: Colors.black87,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('파일 선택'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              pickedImage == null ? '선택한 파일이 없습니다' : pickedImage!.path.split('/').last,
                              style: const TextStyle(color: Colors.black54),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (pickedImage != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '선택 취소',
                              onPressed: submitting ? null : () => setStateDialog(() => pickedImage = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 18),

                      const Text('리뷰 쓰기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      TextField(
                        minLines: 4,
                        maxLines: 6,
                        onChanged: (v) => contentText = v,
                        enabled: !submitting,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: submitting
                                  ? null
                                  : () {
                                Navigator.pop(dialogContext, false); 
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                                side: const BorderSide(color: Colors.black26),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                              child: const Text('취소', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: submitting
                                  ? null
                                  : () async {
                                final text = contentText.trim();
                                if (text.isEmpty) {
                                  _showSnack('리뷰 내용을 입력해주세요!');
                                  return;
                                }

                                setStateDialog(() => submitting = true);

                                try {
                                  await _submitReview(
                                    schoolId: school.id,
                                    recommended: recommended,
                                    facilityGood: facilityGood,
                                    quiet: quiet,
                                    accessible: accessible,
                                    content: text,
                                    imageFile: pickedImage,
                                  );

                                  if (!mounted) return;
                                  Navigator.pop(dialogContext, true); 
                                } catch (e) {
                                  _showSnack('제출 실패: $e');
                                  if (mounted) setStateDialog(() => submitting = false);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5E9B4B),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                              child: submitting
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Text('제출하기', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  Widget _toggleButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black, width: 1.2),
          color: selected ? Colors.black : Colors.white,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
