import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() =>
      _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _updatePassword() async {
    if (_newPasswordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 8 characters.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final auth = context.read<CampusSquareAuth>();
      final apiClient = ApiClient(baseUrl: auth.baseUrl);

      final response = await apiClient.authenticatedRequest(
        context,
        "/api/auth/change-password",
        method: "POST",
        body: jsonEncode({
          "old_password": _oldPasswordController.text,
          "new_password": _newPasswordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final updatedUser = decoded['user'];
        await auth.updateUserProfileLocally(updatedUser);
      } else {
        throw Exception(jsonDecode(response.body)['detail']);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Required'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.security, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'For your security, please set a new permanent password for your account before proceeding.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Temporary/Old Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _updatePassword,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Update Password'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.read<CampusSquareAuth>().logout(),
              child: const Text('Logout', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}
