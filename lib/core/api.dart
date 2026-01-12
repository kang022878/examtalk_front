import 'package:dio/dio.dart';
import 'api_client.dart';
import 'dart:io';

class Api {
  Api(this._client);

  final ApiClient _client;

  // 로그인: /api/auth/login
  Future<String> login({
    required String email,
    required String password,
  }) async {
    final res = await _client.dio.post(
      '/api/auth/login',
      data: {'email': email, 'password': password},
    );

    // 서버 응답 형태: { success, message, data: { accessToken, ... } }
    final data = res.data['data'];
    final token = data['accessToken'] as String?;
    if (token == null || token.isEmpty) {
      throw DioException(
        requestOptions: res.requestOptions,
        message: 'accessToken이 응답에 없습니다.',
      );
    }
    return token;
  }

  // 고사장 목록: /api/schools
  Future<List<dynamic>> getSchools() async {
    final res = await _client.dio.get('/api/schools');
    return (res.data['data'] as List<dynamic>);
  }

  Future<Map<String, dynamic>> uploadMyProfileImage(File imageFile) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });

    final res = await _client.dio.post(
      '/api/users/me/profile-image',
      data: formData,
      // ✅ Dio가 multipart boundary까지 자동으로 설정하게 둔다
      options: Options(
        headers: {
          // ❗ ApiClient의 기본 Content-Type: application/json 을 덮어씌우기 위해 null로 제거
          Headers.contentTypeHeader: null,
        },
      ),
    );

    return (res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> deleteMyProfileImage() async {
    final res = await _client.dio.delete('/api/users/me/profile-image');
    return (res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final res = await _client.dio.post(
      '/api/auth/signup',
      data: {'email': email, 'password': password, 'nickname': nickname},
    );
    return (res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getMyProfile() async {
    final res = await _client.dio.get('/api/users/me');
    return (res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> updateMyProfile({
    required String nickname,
    required String bio,
  }) async {
    final res = await _client.dio.put(
      '/api/users/me',
      data: {'nickname': nickname, 'bio': bio},
    );
    return (res.data as Map<String, dynamic>);
  }

}
