import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env.dart';
import '../../../core/result.dart';
import 'auth_controller.dart';
import 'phone_entry_screen.dart';

class OtpEntryScreen extends ConsumerStatefulWidget {
  const OtpEntryScreen({super.key, required this.args});

  final OtpArgs args;

  @override
  ConsumerState<OtpEntryScreen> createState() => _OtpEntryScreenState();
}

class _OtpEntryScreenState extends ConsumerState<OtpEntryScreen> {
  final _controller = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Dev builds only: prefill the code the backend echoed so testing is fast.
    // Release builds NEVER see devOtp (the backend omits it in prod).
    if (Env.isDev && widget.args.devOtp != null) {
      _controller.text = widget.args.devOtp!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the code we sent you.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final res =
        await ref.read(authControllerProvider.notifier).submitOtp(widget.args.phone, code);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res) {
      case Ok():
        // Session flips to Authenticated → the router redirect lands on /home.
        break;
      case Failure(kind: FailureKind.unauthorized):
        setState(() => _error = 'Wrong or expired code.');
      case Failure(kind: FailureKind.network):
        setState(() => _error = 'Network error. Check your connection.');
      case Failure(message: final m):
        setState(() => _error = m);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _notice = null;
    });
    final res = await ref.read(authControllerProvider.notifier).requestOtp(widget.args.phone);
    if (!mounted) return;
    switch (res) {
      case Ok(value: final r):
        if (Env.isDev && r.devOtp != null) _controller.text = r.devOtp!;
        setState(() => _notice = 'Code sent again.');
      case Failure(kind: FailureKind.rateLimited):
        setState(() => _error = 'Too many attempts. Try again shortly.');
      case Failure(message: final m):
        setState(() => _error = m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Enter the code',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Sent to +91 ${widget.args.phone}'),
            if (Env.isDev && widget.args.devOtp != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Dev code: ${widget.args.devOtp}'),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              key: const Key('otpField'),
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'One-time code',
                border: const OutlineInputBorder(),
                errorText: _error,
                helperText: _notice,
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('verifyBtn'),
              onPressed: _busy ? null : _verify,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Verify'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _resend,
              child: const Text('Resend code'),
            ),
          ],
        ),
      ),
    );
  }
}
