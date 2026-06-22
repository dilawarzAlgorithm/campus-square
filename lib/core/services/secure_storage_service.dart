import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const String _accessTokenKey = "JWT_ACCESS_TOKEN";
  static const String _refreshTokenKey = "JWT_REFRESH_TOKEN";
  static const String _userProfileKey = "USER_PROFILE";

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> userProfile,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _userProfileKey, value: jsonEncode(userProfile));
  }

  Future<String?> getAccessToken() async =>
      await _storage.read(key: _accessTokenKey);
  Future<String?> getRefreshToken() async =>
      await _storage.read(key: _refreshTokenKey);

  Future<Map<String, dynamic>?> getUserProfile() async {
    final rawJson = await _storage.read(key: _userProfileKey);
    if (rawJson == null) return null;
    return jsonDecode(rawJson) as Map<String, dynamic>;
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userProfileKey);
  }
}
