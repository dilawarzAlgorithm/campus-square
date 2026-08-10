import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:campus_square/core/theme/app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color? _customPrimaryColor;

  ThemeMode get themeMode => _themeMode;

  ThemeData get lightTheme => AppTheme.getLightTheme(_customPrimaryColor);
  ThemeData get darkTheme => AppTheme.getDarkTheme(_customPrimaryColor);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('is_dark_mode');
    if (isDark != null) {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }

    final savedColorHex = prefs.getString('custom_primary_color');
    if (savedColorHex != null && savedColorHex.isNotEmpty) {
      _parseAndSetColor(savedColorHex);
    }

    notifyListeners();
  }

  Future<void> toggleTheme(bool isOn) async {
    _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', isOn);
    notifyListeners();
  }

  Future<void> updatePrimaryColor(String? hexString) async {
    final prefs = await SharedPreferences.getInstance();

    if (hexString == null || hexString.trim().isEmpty) {
      await prefs.remove('custom_primary_color');
      _customPrimaryColor = null;
    } else {
      await prefs.setString('custom_primary_color', hexString);
      _parseAndSetColor(hexString);
    }
    notifyListeners();
  }

  void _parseAndSetColor(String hexString) {
    try {
      final colorInt = int.parse(hexString.replaceFirst('#', '0xFF'));
      _customPrimaryColor = Color(colorInt);
    } catch (_) {}
  }
}
