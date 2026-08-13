import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_square/core/services/secure_storage_service.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class ApiClient {
  final String baseUrl;
  final SecureStorageService _storage = SecureStorageService();

  static bool _isRefreshing = false;
  static Future<bool>? _refreshFuture;

  static final ValueNotifier<bool> isOfflineNotifier = ValueNotifier<bool>(
    false,
  );

  ApiClient({required this.baseUrl});

  void _handleGenericError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String genericMessage = "Something went wrong. Please try again later.";

    if (response.statusCode == 401) {
      genericMessage = "Your session has expired. Please log in again.";
    } else if (response.statusCode == 403) {
      genericMessage = "You do not have permission to perform this action.";
    } else if (response.statusCode == 404) {
      genericMessage = "The requested resource could not be found.";
    } else if (response.statusCode == 422) {
      genericMessage = "Invalid data provided. Please check your inputs.";
    } else if (response.statusCode >= 500) {
      genericMessage = "Server error. Our team has been notified.";
    }

    throw Exception(genericMessage);
  }

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

    try {
      switch (method.toUpperCase()) {
        case "POST":
          response = await http
              .post(url, headers: finalHeaders, body: body)
              .timeout(const Duration(seconds: 15));
          break;
        case "DELETE":
          response = await http
              .delete(url, headers: finalHeaders, body: body)
              .timeout(const Duration(seconds: 15));
          break;
        case "PUT":
          response = await http
              .put(url, headers: finalHeaders, body: body)
              .timeout(const Duration(seconds: 15));
          break;
        case "PATCH":
          response = await http
              .patch(url, headers: finalHeaders, body: body)
              .timeout(const Duration(seconds: 15));
          break;
        case "GET":
        default:
          response = await http
              .get(url, headers: finalHeaders)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            isOfflineNotifier.value = false;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('CACHE_$path', response.body);
          }
          break;
      }
    } on SocketException catch (_) {
      if (!context.mounted) {
        return await _handleOfflineFallback(null, path, method);
      }
      return await _handleOfflineFallback(context, path, method);
    } on TimeoutException catch (_) {
      if (!context.mounted) {
        return await _handleOfflineFallback(null, path, method);
      }
      return await _handleOfflineFallback(context, path, method);
    } catch (e) {
      rethrow;
    }

    if (response.statusCode == 403) {
      try {
        final responseBody = jsonDecode(response.body);
        final detail = responseBody['detail']?.toString().toLowerCase() ?? '';
        if (detail.contains('suspended') || detail.contains('blocked')) {
          if (context.mounted) {
            Provider.of<CampusSquareAuth>(
              context,
              listen: false,
            ).logoutForcefully();
          }
        }
      } catch (_) {}
      _handleGenericError(response);
    }

    if (response.statusCode == 401) {
      final refreshSuccess = await _rotateTokensSafe();
      if (refreshSuccess) {
        final newAccessToken = await _storage.getAccessToken();
        if (newAccessToken != null) {
          finalHeaders["Authorization"] = "Bearer $newAccessToken";
          response = await http.get(url, headers: finalHeaders);

          if (response.statusCode >= 300) {
            _handleGenericError(response);
          }
          return response;
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

    if (response.statusCode >= 300) {
      _handleGenericError(response);
    }

    return response;
  }

  Future<String?> getCachedData(String path) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('CACHE_$path');
  }

  Future<http.Response> _handleOfflineFallback(
    BuildContext? context,
    String path,
    String method,
  ) async {
    if (method.toUpperCase() == 'GET') {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('CACHE_$path');

      if (cachedData != null) {
        isOfflineNotifier.value = true;

        return http.Response(
          cachedData,
          200,
          headers: {'content-type': 'application/json'},
        );
      }
    }

    throw Exception("No internet connection available.");
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

    try {
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode >= 300) {
        _handleGenericError(response);
      }
      return response;
    } catch (_) {
      throw Exception("Upload failed due to poor connection.");
    }
  }

  Future<bool> _rotateTokensSafe() async {
    if (_isRefreshing && _refreshFuture != null) return await _refreshFuture!;
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
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"refresh_token": refreshToken}),
          )
          .timeout(const Duration(seconds: 10));

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
    } catch (_) {}
    return false;
  }
}
