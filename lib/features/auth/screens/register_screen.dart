import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.otpScreen = false,
    this.initialEmail,
    this.initialPassword,
  });
  final bool otpScreen;
  final String? initialEmail;
  final String? initialPassword;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  final _instNameController = TextEditingController();
  final _instShortNameController = TextEditingController();

  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _needsOnboarding = false;
  late bool _otpVerificationStage;

  Timer? _resendTimer;
  int _resendCountdown = 30;
  bool _canResendOtp = false;

  @override
  void initState() {
    super.initState();
    _otpVerificationStage = widget.otpScreen;
    _emailController = TextEditingController(text: widget.initialEmail ?? "");
    _passwordController = TextEditingController(
      text: widget.initialPassword ?? "",
    );

    if (_otpVerificationStage) {
      _startResendTimer();
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _instNameController.dispose();
    _instShortNameController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _canResendOtp = false;
      _resendCountdown = 30;
    });

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        timer.cancel();
        setState(() {
          _canResendOtp = true;
        });
      }
    });
  }

  void _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final auth = context.read<CampusSquareAuth>();

    try {
      final result = await auth.register(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        institutionName: _needsOnboarding
            ? _instNameController.text.trim()
            : null,
        institutionShortName: _needsOnboarding
            ? _instShortNameController.text.trim()
            : null,
      );

      if (result.requiresOnboarding) {
        setState(() {
          _needsOnboarding = true;
        });
        _showSnackBar(result.message, isError: false);
      } else if (result.success) {
        setState(() {
          _otpVerificationStage = true;
        });
        _startResendTimer();
        _showSnackBar(result.message, isError: false);
      }
    } catch (e) {
      _showSnackBar(e.toString().replaceAll("Exception: ", ""), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _submitOtp() async {
    if (_otpController.text.trim().length < 6) {
      _showSnackBar(
        "Please enter a valid 6-digit verification code.",
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final success = await context.read<CampusSquareAuth>().verifyOtp(
        email: _emailController.text.trim(),
        otp: _otpController.text.trim(),
      );

      if (success) {
        _resendTimer?.cancel();
        _showSnackBar(
          "Account verified successfully! Please login.",
          isError: false,
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar(e.toString().replaceAll("Exception: ", ""), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleResendOtp() async {
    if (_passwordController.text.trim().isEmpty) {
      _showSnackBar(
        "Session missing password data. Please return to login.",
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final success = await context.read<CampusSquareAuth>().resendOtp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (success) {
        _showSnackBar("Verification code resent successfully!", isError: false);
        _startResendTimer();
      }
    } catch (e) {
      _showSnackBar(e.toString().replaceAll("Exception: ", ""), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _otpVerificationStage ? 'Verify Email' : 'Join Campus Square',
        ),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Icon(
                _otpVerificationStage
                    ? Icons.mark_email_unread_outlined
                    : Icons.school_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                _otpVerificationStage
                    ? 'Verify Your Account'
                    : _needsOnboarding
                    ? 'First Time Campus Onboarding'
                    : 'Create an Account',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _otpVerificationStage
                    ? 'We have sent a verification code to ${_emailController.text}'
                    : _needsOnboarding
                    ? 'You are the first to register this email domain! Please fill in your university credentials to onboard.'
                    : 'Enter your details below using your academic email address.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),

              if (_otpVerificationStage) ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: '000000',
                    border: OutlineInputBorder(),
                    counterText: "",
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitOtp,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Verify and Proceed',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
                TextButton(
                  onPressed: _canResendOtp && !_isLoading
                      ? _handleResendOtp
                      : null,
                  child: Text(
                    _canResendOtp
                        ? 'Resend Verification Code'
                        : 'Resend code in $_resendCountdown seconds',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _canResendOtp
                          ? theme.colorScheme.primary
                          : Colors.grey,
                    ),
                  ),
                ),
              ] else ...[
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (!_needsOnboarding) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _firstNameController,
                                decoration: const InputDecoration(
                                  labelText: 'First Name',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (val) => val == null || val.isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _lastNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Last Name',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (val) => val == null || val.isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Academic Email',
                            helperText: "e.g., student@yourcollege.edu",
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            if (!val.contains('@')) {
                              return 'Invalid email format';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password (min. 8 chars)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) => val == null || val.length < 8
                              ? 'Password must be >= 8 characters'
                              : null,
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _instNameController,
                          decoration: const InputDecoration(
                            labelText: 'Institution Full Name',
                            hintText:
                                'e.g. Massachusetts Institute of Technology',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) => val == null || val.isEmpty
                              ? 'Required for Onboarding'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _instShortNameController,
                          decoration: const InputDecoration(
                            labelText: 'Institution Short Name / Acronym',
                            hintText: 'e.g. MIT',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) => val == null || val.isEmpty
                              ? 'Required for Onboarding'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _submitRegistration,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _needsOnboarding
                                    ? 'Onboard Campus'
                                    : 'Register Account',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
