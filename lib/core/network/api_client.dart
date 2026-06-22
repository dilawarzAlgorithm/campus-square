import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:campus_square/core/services/secure_storage_service.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class ApiClient {
  final String baseUrl;
  final SecureStorageService _storage = SecureStorageService();

  ApiClient({required this.baseUrl});

  Future<http.Response> authenticatedRequest(
    BuildContext context,
    String path, {
    required String method,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final url = Uri.parse("$baseUrl$path");
    final accessToken = await _storage.getAccessToken();

    final finalHeaders = {"Content-Type": "application/json", ...?headers};
    if (accessToken != null) {
      finalHeaders["Authorization"] = "Bearer $accessToken";
    }

    http.Response response;
    if (method.toUpperCase() == "POST") {
      response = await http.post(url, headers: finalHeaders, body: body);
    } else {
      response = await http.get(url, headers: finalHeaders);
    }

    if (response.statusCode == 401) {
      debugPrint("⏳ Access token expired. Attempting silent token rotation...");
      final refreshSuccess = await _rotateTokens();

      if (refreshSuccess) {
        final newAccessToken = await _storage.getAccessToken();
        if (newAccessToken != null) {
          finalHeaders["Authorization"] = "Bearer $newAccessToken";
          if (method.toUpperCase() == "POST") {
            return await http.post(url, headers: finalHeaders, body: body);
          } else {
            return await http.get(url, headers: finalHeaders);
          }
        }
      } else {
        debugPrint("❌ Refresh token expired. Forcing user logout.");
        if (context.mounted) {
          Provider.of<CampusSquareAuth>(
            context,
            listen: false,
          ).logoutForcefully();
        }
      }
    }

    return response;
  }

  Future<bool> _rotateTokens() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final url = Uri.parse("$baseUrl/api/auth/refresh");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"refresh_token": refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userProfile = await _storage.getUserProfile() ?? {};

        await _storage.saveSession(
          accessToken: data["access_token"],
          refreshToken: data["refresh_token"],
          userProfile: userProfile,
        );
        return true;
      }
    } catch (e) {
      debugPrint("❌ Network error during token rotation: $e");
    }
    return false;
  }
}
