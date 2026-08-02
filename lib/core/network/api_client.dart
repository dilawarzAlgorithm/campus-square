import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:campus_square/core/services/secure_storage_service.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class ApiClient {
  final String baseUrl;
  final SecureStorageService _storage = SecureStorageService();

  static bool _isRefreshing = false;
  static Future<bool>? _refreshFuture;

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
    switch (method.toUpperCase()) {
      case "POST":
        response = await http.post(url, headers: finalHeaders, body: body);
        break;
      case "DELETE":
        response = await http.delete(url, headers: finalHeaders, body: body);
        break;
      case "PUT":
        response = await http.put(url, headers: finalHeaders, body: body);
        break;
      case "PATCH":
        response = await http.patch(url, headers: finalHeaders, body: body);
        break;
      case "GET":
      default:
        response = await http.get(url, headers: finalHeaders);
        break;
    }

    if (response.statusCode == 403) {
      try {
        final responseBody = jsonDecode(response.body);
        final detail = responseBody['detail']?.toString().toLowerCase() ?? '';
        if (detail.contains('suspended') || detail.contains('blocked')) {
          debugPrint("Account suspended. Forcing logout.");
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your account has been suspended by a Community Head.',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
            Provider.of<CampusSquareAuth>(
              context,
              listen: false,
            ).logoutForcefully();
          }
        }
      } catch (e) {
        debugPrint("Could not parse 403 body: $e");
      }
      return response;
    }

    if (response.statusCode == 401) {
      debugPrint("Access token expired. Attempting silent token rotation...");
      final refreshSuccess = await _rotateTokensSafe();

      if (refreshSuccess) {
        final newAccessToken = await _storage.getAccessToken();
        if (newAccessToken != null) {
          finalHeaders["Authorization"] = "Bearer $newAccessToken";
          switch (method.toUpperCase()) {
            case "POST":
              return await http.post(url, headers: finalHeaders, body: body);
            case "DELETE":
              return await http.delete(url, headers: finalHeaders, body: body);
            case "PUT":
              return await http.put(url, headers: finalHeaders, body: body);
            case "PATCH":
              return await http.patch(url, headers: finalHeaders, body: body);
            case "GET":
            default:
              return await http.get(url, headers: finalHeaders);
          }
        }
      } else {
        debugPrint("Refresh token expired. Forcing user logout.");
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

  Future<http.Response> authenticatedMultipartRequest(
    BuildContext context,
    String path, {
    required String filePath,
    required String fileField,
  }) async {
    final url = Uri.parse("$baseUrl$path");
    final accessToken = await _storage.getAccessToken();

    var request = http.MultipartRequest('POST', url);
    if (accessToken != null) {
      request.headers["Authorization"] = "Bearer $accessToken";
    }

    request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 401) {
      debugPrint("Access token expired during upload. Rotating...");
      final refreshSuccess = await _rotateTokensSafe();

      if (refreshSuccess) {
        final newAccessToken = await _storage.getAccessToken();
        if (newAccessToken != null) {
          var newRequest = http.MultipartRequest('POST', url);
          newRequest.headers["Authorization"] = "Bearer $newAccessToken";
          newRequest.files.add(
            await http.MultipartFile.fromPath(fileField, filePath),
          );
          var newStreamed = await newRequest.send();
          return await http.Response.fromStream(newStreamed);
        }
      } else {
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

  Future<bool> _rotateTokensSafe() async {
    if (_isRefreshing && _refreshFuture != null) {
      return await _refreshFuture!;
    }
    _isRefreshing = true;
    _refreshFuture = _rotateTokens();
    final result = await _refreshFuture!;
    _isRefreshing = false;
    return result;
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
      debugPrint("Network error during token rotation: $e");
    }

    return false;
  }
}
