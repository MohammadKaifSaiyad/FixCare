import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import 'auth_controller.dart';

/// Extra passed to the OTP route: the phone being verified plus, on dev
/// builds, the code the backend echoed back so the OTP screen can autofill.
class OtpArgs {
  final String phone;
  final String? devOtp;
  const OtpArgs(this.phone, this.devOtp);
}

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValid(String v) => RegExp(r'^[6-9]\d{9}$').hasMatch(v);

  Future<void> _continue() async {
    final phone = _controller.text.trim();
    if (!_isValid(phone)) {
      setState(() => _error = 'Enter a valid 10-digit mobile number.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final res = await ref.read(authControllerProvider.notifier).requestOtp(phone);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res) {
      case Ok(value: final r):
        context.go('/otp', extra: OtpArgs(phone, r.devOtp));
      case Failure(kind: FailureKind.rateLimited):
        setState(() => _error = 'Too many attempts. Try again shortly.');
      case Failure(kind: FailureKind.network):
        setState(() => _error = 'Network error. Check your connection.');
      case Failure(message: final m):
        setState(() => _error = m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Enter your mobile number',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text("We'll send you a one-time code to verify."),
            const SizedBox(height: 24),
            TextField(
              key: const Key('phoneField'),
              controller: _controller,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: '+91  ',
                labelText: 'Mobile number',
                border: const OutlineInputBorder(),
                errorText: _error,
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('continueBtn'),
              onPressed: _busy ? null : _continue,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
