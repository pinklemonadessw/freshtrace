import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Shown after login/registration until the user's email is verified.
/// Polls every few seconds; once verified, the userChanges stream in
/// main.dart rebuilds the app past this screen automatically.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _pollTimer;
  bool _isResending = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => AuthService.refreshEmailVerifiedStatus(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      await AuthService.resendVerificationEmail();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send email: $e')),
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _checkNow() async {
    setState(() => _isChecking = true);
    final verified = await AuthService.refreshEmailVerifiedStatus();
    if (!mounted) return;
    setState(() => _isChecking = false);
    if (!verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Not verified yet. Click the link in the email, then try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.currentUser?.email ?? 'your email address';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Your Email'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 72),
                const SizedBox(height: 24),
                Text(
                  'Check your inbox',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'We sent a verification link to\n$email\n\n'
                  'Click the link to verify your account. This page will '
                  'update automatically once you\'re verified.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _isChecking ? null : _checkNow,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('I\'ve Verified My Email'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isResending ? null : _resendEmail,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Resend Verification Email'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: AuthService.signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
