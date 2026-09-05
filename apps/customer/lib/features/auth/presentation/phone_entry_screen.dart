import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
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
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {})); // repaint field border/caret
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand badge tile (52×52, left-aligned — not full width).
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: FixCareColors.primaryTint,
                    borderRadius: BorderRadius.circular(FixCareRadii.button),
                  ),
                  alignment: Alignment.center,
                  child: const Text('F',
                      style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: FixCareColors.primary)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Enter your mobile number', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text("We'll send a 6-digit code to verify it.",
                  style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted, height: 1.5)),
              const SizedBox(height: 26),
              _PhoneField(controller: _controller, focus: _focus, hasError: _error != null),
              const SizedBox(height: 10),
              Text(
                _error ?? 'Indian 10-digit mobile only',
                style: TextStyle(
                  fontSize: 13,
                  color: _error != null ? FixCareColors.errorText : FixCareColors.textMuted,
                ),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('continueBtn'),
                onPressed: _busy ? null : _continue,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Send code'),
              ),
              const SizedBox(height: 14),
              const Text(
                "By continuing you agree to FixCare's Terms and Privacy Policy.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: FixCareColors.textFaint, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The +91 · divider · digits field (60px, styled to the spec).
class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller, required this.focus, required this.hasError});

  final TextEditingController controller;
  final FocusNode focus;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final active = focus.hasFocus || controller.text.isNotEmpty;
    final borderColor = hasError
        ? FixCareColors.errorBorder
        : active
            ? FixCareColors.primary
            : FixCareColors.border;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        borderRadius: BorderRadius.circular(FixCareRadii.field),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('+91',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  color: FixCareColors.textPrimary,
                  height: 1.0)),
          const SizedBox(width: 10),
          Container(width: 1, height: 26, color: FixCareColors.border),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('phoneField'),
              controller: controller,
              focusNode: focus,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              // Center the field's text vertically so digits align with "+91".
              textAlignVertical: TextAlignVertical.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              cursorColor: FixCareColors.primary,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: FixCareColors.textPrimary,
                  letterSpacing: 1.5,
                  height: 1.0),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isCollapsed: true,
                hintText: '00000 00000',
                hintStyle: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: FixCareColors.placeholder,
                    letterSpacing: 1.5,
                    height: 1.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
