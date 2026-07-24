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

  Future<void> saveFailedMessages(
    String conversationId,
    List<dynamic> messages,
  ) async {
    await _storage.write(
      key: 'FAILED_MSG_$conversationId',
      value: jsonEncode(messages),
    );
  }

  Future<List<dynamic>> getFailedMessages(String conversationId) async {
    final data = await _storage.read(key: 'FAILED_MSG_$conversationId');
    if (data == null) return [];
    return jsonDecode(data);
  }

  Future<void> saveDraftMessage(String conversationId, String text) async {
    await _storage.write(key: 'DRAFT_$conversationId', value: text);
  }

  Future<String?> getDraftMessage(String conversationId) async {
    return await _storage.read(key: 'DRAFT_$conversationId');
  }

  Future<void> clearDraftMessage(String conversationId) async {
    await _storage.delete(key: 'DRAFT_$conversationId');
  }
}
