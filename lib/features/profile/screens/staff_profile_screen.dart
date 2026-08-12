import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class StaffProfileScreen extends StatelessWidget {
  const StaffProfileScreen({super.key});

  void _showChangePasswordDialog(BuildContext context, CampusSquareAuth auth) {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Change Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New Password'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (oldController.text.isEmpty ||
                            newController.text.length < 8) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "New password must be at least 8 chars",
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isLoading = true);
                        try {
                          final success = await auth.changePassword(
                            oldController.text,
                            newController.text,
                          );

                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? "Password updated successfully!"
                                      : "Failed to update password",
                                ),
                                backgroundColor: success
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceAll("Exception: ", ""),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } finally {
                          if (context.mounted) {
                            setDialogState(() => isLoading = false);
                          }
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, CampusSquareAuth auth) {
    final firstController = TextEditingController(
      text: auth.user?["first_name"],
    );
    final lastController = TextEditingController(text: auth.user?["last_name"]);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstController,
              decoration: const InputDecoration(labelText: 'First Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastController,
              decoration: const InputDecoration(labelText: 'Last Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (firstController.text.trim().isEmpty ||
                  lastController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx);
              bool success = await auth.updateName(
                firstController.text.trim(),
                lastController.text.trim(),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? "Name updated!" : "Failed to update name",
                  ),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showRecoveryEmailDialog(BuildContext context, CampusSquareAuth auth) {
    final emailController = TextEditingController(
      text: auth.user?["recovery_email"],
    );
    final otpController = TextEditingController();

    bool isOtpStage = false;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isOtpStage ? 'Verify OTP' : 'Set Recovery Email'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isOtpStage) ...[
                  const Text(
                    'This email will be used to receive OTPs for password resets instead of your primary admin ID.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Recovery Email',
                      hintText: 'e.g. personal@email.com',
                    ),
                  ),
                ] else ...[
                  Text(
                    'Enter the OTP sent to ${emailController.text.trim()}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-digit OTP',
                      counterText: "",
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (!isOtpStage) {
                          if (emailController.text.trim().isEmpty ||
                              !emailController.text.contains('@')) {
                            return;
                          }
                          setDialogState(() => isLoading = true);
                          final success = await auth.requestRecoveryEmailOtp(
                            emailController.text.trim(),
                          );
                          setDialogState(() {
                            isLoading = false;
                            if (success) isOtpStage = true;
                          });

                          if (!success && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Failed to send OTP to that email",
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } else {
                          if (otpController.text.trim().length < 6) return;

                          setDialogState(() => isLoading = true);
                          final success = await auth.verifyAndSetRecoveryEmail(
                            emailController.text.trim(),
                            otpController.text.trim(),
                          );

                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? "Recovery email updated!"
                                      : "Invalid or expired OTP",
                                ),
                                backgroundColor: success
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isOtpStage ? 'Verify & Save' : 'Send OTP'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<CampusSquareAuth>();
    final user = auth.user;
    final theme = Theme.of(context);
    final role = user?["role"] ?? "STAFF";

    final isGlobalAdmin = role == 'ADMIN';

    return RefreshIndicator(
      onRefresh: () => auth.refreshProfile(),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const SizedBox(height: 16),
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.secondary.withValues(
                alpha: 0.1,
              ),
              child: Icon(
                isGlobalAdmin ? Icons.admin_panel_settings : Icons.shield,
                size: 48,
                color: theme.colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 45),
              Text(
                '${user?["first_name"] ?? "Staff"} ${user?["last_name"] ?? "Member"}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: Colors.grey,
                ),
                onPressed: () => _showEditNameDialog(context, auth),
              ),
            ],
          ),
          Center(
            child: Text(
              user?["email"] ?? "admin@system.local",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified, color: Colors.teal, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    isGlobalAdmin ? "Global Administrator" : "Community Head",
                    style: TextStyle(
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('Change Password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showChangePasswordDialog(context, auth),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.mark_email_read_outlined),
                  title: const Text('Recovery Email'),
                  subtitle: Text(
                    user?["recovery_email"] ?? 'Not set',
                    style: TextStyle(
                      color: user?["recovery_email"] != null
                          ? theme.textTheme.bodyMedium?.color
                          : Colors.grey,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showRecoveryEmailDialog(context, auth),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.red.shade200),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
