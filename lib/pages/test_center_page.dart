import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';

class TestCenterPage extends StatefulWidget {
  const TestCenterPage({super.key});

  @override
  State<TestCenterPage> createState() => _TestCenterPageState();
}

class _TestCenterPageState extends State<TestCenterPage> {
  NaverMapController? _mapController;
  bool _isMovingToMyLocation = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          NaverMap(
            options: const NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: NLatLng(36.3504, 127.3845), // Daejeon
                zoom: 12,
              ),
              // (선택) 내 위치 버튼/레이어는 네이버맵 옵션에서 따로 제공할 수도 있음
              // locationButtonEnable: false,
            ),
            onMapReady: (controller) {
              _mapController = controller;
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: '고사장 검색',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // ✅ 오른쪽 하단 초록 핀 버튼: 내 위치로 카메라 이동
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

  Future<void> _moveToMyLocation() async {
    if (_mapController == null) return;

    setState(() => _isMovingToMyLocation = true);

    try {
      // 1) 위치 서비스 켜져있는지
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('위치 서비스가 꺼져있습니다. 켜주세요.');
        return;
      }

      // 2) 권한 체크/요청
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

      // 3) 현재 위치 가져오기
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final myLatLng = NLatLng(pos.latitude, pos.longitude);

      // 4) 지도 카메라 이동 (가운데로)
      await _mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: myLatLng,
          zoom: 15,
        ),
      );

      // (선택) 내 위치 마커도 찍고 싶으면 아래처럼 오버레이 추가 가능
      // final marker = NMarker(id: 'my_location', position: myLatLng);
      // await _mapController!.addOverlay(marker);

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

  // 기존 바텀시트 함수는 필요하면 그대로 유지 가능
  void _showTestCenterDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '대전 탄방중학교',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Text('대전 서구 문정로 148'),
            const SizedBox(height: 20),
            const Text('리뷰', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  _buildReviewItem('스피커 음질이 정말 좋아요!', '⭐⭐⭐⭐⭐'),
                  _buildReviewItem('의자가 조금 삐걱거려요.', '⭐⭐⭐'),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('리뷰 작성하기', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewItem(String text, String rating) {
    return ListTile(
      title: Text(text),
      subtitle: Text(rating),
      contentPadding: EdgeInsets.zero,
    );
  }
}
