import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:campus_square/core/services/secure_storage_service.dart';

enum ApplicationState { initializing, unauthenticated, authenticated }

class RegistrationResult {
  final bool success;
  final bool requiresOnboarding;
  final String message;
  final String? userId;

  RegistrationResult({
    required this.success,
    required this.requiresOnboarding,
    required this.message,
    this.userId,
  });
}

class AuthResult {
  final bool success;
  final bool requiresOnboarding;
  final String message;

  AuthResult({
    required this.success,
    required this.requiresOnboarding,
    required this.message,
  });
}

class CampusSquareAuth extends ChangeNotifier {
  final _storage = SecureStorageService();

  final String baseUrl = dotenv.env['API_BASE_URL'] ?? "";

  ApplicationState _status = ApplicationState.initializing;
  Map<String, dynamic>? _user;

  ApplicationState get status => _status;
  Map<String, dynamic>? get user => _user;

  CampusSquareAuth() {
    checkActiveSession();
  }

  Future<void> checkActiveSession() async {
    await Future.delayed(const Duration(milliseconds: 1000));
    final refreshToken = await _storage.getRefreshToken();
    final profile = await _storage.getUserProfile();

    if (refreshToken != null && profile != null) {
      _user = profile;
      _status = ApplicationState.authenticated;
    } else {
      _status = ApplicationState.unauthenticated;
    }
    notifyListeners();
  }

  Future<RegistrationResult> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? institutionName,
    String? institutionShortName,
  }) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/register");

      final bodyMap = {
        "email": email,
        "password": password,
        "first_name": firstName,
        "last_name": lastName,
        "requested_role": "STUDENT",
        "institution_name": ?institutionName,
        "institution_short_name": ?institutionShortName,
      };

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyMap),
      );

      final data = jsonDecode(response.body);

      if (data is Map && data["requires_onboarding"] == true) {
        return RegistrationResult(
          success: false,
          requiresOnboarding: true,
          message: data["message"] ?? "Campus setup required.",
        );
      }

      if (response.statusCode == 201) {
        return RegistrationResult(
          success: true,
          requiresOnboarding: false,
          message: data["message"] ?? "Successfully registered!",
          userId: data["user_id"],
        );
      } else {
        throw Exception(data["detail"] ?? "Failed to register.");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> verifyOtp({required String email, required String otp}) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/verify-otp");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "otp": otp}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data["success"] == true;
      } else {
        throw Exception(data["detail"] ?? "Invalid verification code.");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> resendOtp({
    required String email,
    required String password,
  }) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/resend-otp");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception(
          data["detail"] ?? "Failed to resend verification code.",
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/login");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _storage.saveSession(
          accessToken: data["access_token"],
          refreshToken: data["refresh_token"],
          userProfile: data["user"],
        );

        _user = data["user"];
        _status = ApplicationState.authenticated;
        notifyListeners();
        return true;
      } else {
        throw Exception(data["detail"] ?? "Invalid email or password.");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<AuthResult> staffLogin({
    required String email,
    required String password,
    String? institutionName,
    String? institutionShortName,
  }) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/login-staff");
      final bodyMap = {
        "email": email,
        "password": password,
        "institution_name": ?institutionName,
        "institution_short_name": ?institutionShortName,
      };

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyMap),
      );

      final data = jsonDecode(response.body);

      if (data is Map && data["requires_onboarding"] == true) {
        return AuthResult(
          success: false,
          requiresOnboarding: true,
          message: data["message"] ?? "Campus setup required.",
        );
      }

      if (response.statusCode == 200) {
        await _storage.saveSession(
          accessToken: data["access_token"],
          refreshToken: data["refresh_token"],
          userProfile: data["user"],
        );

        _user = data["user"];
        _status = ApplicationState.authenticated;
        notifyListeners();
        return AuthResult(
          success: true,
          requiresOnboarding: false,
          message: "Logged in successfully.",
        );
      } else {
        throw Exception(data["detail"] ?? "Invalid email or password.");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateUserProfileLocally(
    Map<String, dynamic> updatedProfile,
  ) async {
    _user = updatedProfile;
    final accessToken = await _storage.getAccessToken();
    final refreshToken = await _storage.getRefreshToken();

    if (accessToken != null && refreshToken != null) {
      await _storage.saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userProfile: updatedProfile,
      );
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _storage.clearSession();
    _user = null;
    _status = ApplicationState.unauthenticated;
    notifyListeners();
  }

  void logoutForcefully() {
    _storage.clearSession();
    _user = null;
    _status = ApplicationState.unauthenticated;
    notifyListeners();
  }
}
