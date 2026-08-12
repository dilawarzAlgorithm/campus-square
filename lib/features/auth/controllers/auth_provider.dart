import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:campus_square/core/services/secure_storage_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

enum ApplicationState { initializing, unauthenticated, authenticated }

class RegistrationResult {
  final bool success;
  final String message;
  final String? userId;

  RegistrationResult({
    required this.success,
    required this.message,
    this.userId,
  });
}

class AuthResult {
  final bool success;
  final String message;

  AuthResult({required this.success, required this.message});
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
    try {
      await Future.delayed(const Duration(milliseconds: 1000));

      final refreshToken = await _storage.getRefreshToken();
      final profile = await _storage.getUserProfile();

      if (refreshToken != null && profile != null) {
        _user = profile;
        _status = ApplicationState.authenticated;
        final prefs = await SharedPreferences.getInstance();
        final isMessageEnabled = prefs.getBool('fcm_message_hub') ?? true;
        final allEnabled = prefs.getBool('fcm_all_notifications') ?? true;

        updateFCMTokenStatus(allEnabled && isMessageEnabled);
        syncTopics();
      } else {
        _status = ApplicationState.unauthenticated;
      }
    } catch (e) {
      _status = ApplicationState.unauthenticated;
      debugPrint("Session restore failed: $e");
    } finally {
      notifyListeners();
    }
  }

  void clearTopics() {
    try {
      final fcm = FirebaseMessaging.instance;
      final instId = _user?['institution_id'] ?? '';
      if (instId.isNotEmpty) {
        fcm.unsubscribeFromTopic('${instId}_all_notices');
        fcm.unsubscribeFromTopic('${instId}_important_notices');
        fcm.unsubscribeFromTopic('${instId}_resources');
      }
    } catch (_) {}
  }

  Future<void> syncTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fcm = FirebaseMessaging.instance;
      final instId = _user?['institution_id'] ?? '';
      if (instId.isEmpty) return;

      final allEnabled = prefs.getBool('fcm_all_notifications') ?? true;
      if (allEnabled) {
        if (prefs.getBool('fcm_all_notices') ?? true) {
          await fcm.subscribeToTopic('${instId}_all_notices');
        }
        if (prefs.getBool('fcm_important_notices') ?? true) {
          await fcm.subscribeToTopic('${instId}_important_notices');
        }
        if (prefs.getBool('fcm_resources') ?? true) {
          await fcm.subscribeToTopic('${instId}_resources');
        }
      }
    } catch (_) {}
  }

  Future<void> updateFCMTokenStatus(bool isEnabled) async {
    try {
      final accessToken = await _storage.getAccessToken();
      if (accessToken == null) return;

      String? tokenToSend;
      if (isEnabled) {
        tokenToSend = await FirebaseMessaging.instance.getToken();
      }

      await http.patch(
        Uri.parse("$baseUrl/api/auth/fcm-token"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
        body: jsonEncode({"token": tokenToSend}),
      );
    } catch (e) {
      debugPrint("Failed to update FCM token status: $e");
    }
  }

  Future<RegistrationResult> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? departmentId,
  }) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/register");
      final bodyMap = {
        "email": email,
        "password": password,
        "first_name": firstName,
        "last_name": lastName,
        "requested_role": "STUDENT",
        "department_id": departmentId,
      };

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyMap),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return RegistrationResult(
          success: true,
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

  Future<bool> requestPasswordReset(String email) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/forgot-password");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Forgot password error: $e");
      return false;
    }
  }

  Future<bool> resetPasswordWithOtp(
    String email,
    String otp,
    String newPassword,
  ) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/reset-password");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": email,
          "otp": otp,
          "new_password": newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data["detail"] ?? "Failed to reset password.");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    try {
      final accessToken = await _storage.getAccessToken();
      if (accessToken == null) return false;

      final url = Uri.parse("$baseUrl/api/auth/change-password");
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
        body: jsonEncode({
          "old_password": oldPassword,
          "new_password": newPassword,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await updateUserProfileLocally(data['user']);
        return true;
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['detail'] ?? "Failed to change password.");
      }
    } catch (e) {
      debugPrint("Change password error: $e");
      rethrow;
    }
  }

  Future<bool> requestRecoveryEmailOtp(String email) async {
    try {
      final accessToken = await _storage.getAccessToken();
      if (accessToken == null) return false;

      final url = Uri.parse("$baseUrl/api/auth/recovery-email/request-otp");
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
        body: jsonEncode({"recovery_email": email}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Request recovery OTP error: $e");
      return false;
    }
  }

  Future<bool> verifyAndSetRecoveryEmail(String email, String otp) async {
    try {
      final accessToken = await _storage.getAccessToken();
      if (accessToken == null) return false;

      final url = Uri.parse("$baseUrl/api/auth/recovery-email/verify");
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
        body: jsonEncode({"recovery_email": email, "otp": otp}),
      );

      if (response.statusCode == 200) {
        await refreshProfile();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Verify recovery email error: $e");
      return false;
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

        final prefs = await SharedPreferences.getInstance();
        final isMessageEnabled = prefs.getBool('fcm_message_hub') ?? true;
        final allEnabled = prefs.getBool('fcm_all_notifications') ?? true;
        updateFCMTokenStatus(allEnabled && isMessageEnabled);
        syncTopics();

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
  }) async {
    try {
      final url = Uri.parse("$baseUrl/api/auth/login-staff");
      final bodyMap = {"email": email, "password": password};

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyMap),
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

        final prefs = await SharedPreferences.getInstance();
        final isMessageEnabled = prefs.getBool('fcm_message_hub') ?? true;
        final allEnabled = prefs.getBool('fcm_all_notifications') ?? true;
        updateFCMTokenStatus(allEnabled && isMessageEnabled);
        syncTopics();

        notifyListeners();
        return AuthResult(success: true, message: "Logged in successfully.");
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

  Future<void> refreshProfile() async {
    try {
      final accessToken = await _storage.getAccessToken();
      if (accessToken == null) return;

      final response = await http.get(
        Uri.parse("$baseUrl/api/auth/me"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await updateUserProfileLocally(data);
      }
    } catch (e) {
      debugPrint("Error refreshing profile: $e");
    }
  }

  Future<bool> updateName(String firstName, String lastName) async {
    try {
      final accessToken = await _storage.getAccessToken();

      final response = await http.patch(
        Uri.parse("$baseUrl/api/auth/name"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
        body: jsonEncode({"first_name": firstName, "last_name": lastName}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await updateUserProfileLocally(data);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error updating name: $e");
      return false;
    }
  }

  Future<bool> updatePreferences(
    String dietary,
    String sleep,
    String study,
  ) async {
    try {
      final accessToken = await _storage.getAccessToken();

      final response = await http.patch(
        Uri.parse("$baseUrl/api/auth/profile"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
        body: jsonEncode({
          "dietary_preference": dietary,
          "sleep_schedule": sleep,
          "study_habits": study,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await updateUserProfileLocally(data);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error updating preferences: $e");
      return false;
    }
  }

  Future<void> _wipeAllData() async {
    try {
      clearTopics();
      await _storage.clearSession();

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      debugPrint("Error wiping data during logout: $e");
    }
  }

  Future<void> logout() async {
    await _wipeAllData();
    _user = null;
    _status = ApplicationState.unauthenticated;
    notifyListeners();
  }

  void logoutForcefully() {
    _wipeAllData();
    _user = null;
    _status = ApplicationState.unauthenticated;
    notifyListeners();
  }
}
