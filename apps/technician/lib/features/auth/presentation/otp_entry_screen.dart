import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import 'auth_controller.dart';
import 'phone_entry_screen.dart';

const _otpLength = 6;

class OtpEntryScreen extends ConsumerStatefulWidget {
  const OtpEntryScreen({super.key, required this.args});

  final OtpArgs args;

  @override
  ConsumerState<OtpEntryScreen> createState() => _OtpEntryScreenState();
}

class _OtpEntryScreenState extends ConsumerState<OtpEntryScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _error = false;
  String? _notice;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_error) _error = false; // clear error as the user edits
      setState(() {});
    });
    // Dev builds only: prefill the echoed code. Release never receives devOtp.
    if (Env.isDev && widget.args.devOtp != null) {
      _controller.text = widget.args.devOtp!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _maskedPhone() {
    final p = widget.args.phone;
    if (p.length != 10) return '+91 $p';
    return '+91 ${p.substring(0, 5)} ${p.substring(5, 7)}xxx';
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != _otpLength) {
      setState(() => _error = true);
      return;
    }
    setState(() {
      _error = false;
      _busy = true;
    });
    final res =
        await ref.read(authControllerProvider.notifier).submitOtp(widget.args.phone, code);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res) {
      case Ok():
        break; // session flips → router lands on /home
      case Failure(kind: FailureKind.unauthorized):
        setState(() => _error = true);
      case Failure():
        setState(() => _error = true);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = false;
      _notice = null;
    });
    final res = await ref.read(authControllerProvider.notifier).requestOtp(widget.args.phone);
    if (!mounted) return;
    switch (res) {
      case Ok(value: final r):
        if (Env.isDev && r.devOtp != null) _controller.text = r.devOtp!;
        setState(() => _notice = 'Code sent again.');
      case Failure(kind: FailureKind.rateLimited):
        setState(() => _notice = 'Too many attempts. Try again shortly.');
      case Failure():
        setState(() => _notice = 'Could not resend. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _controller.text;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify number')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // "Code sent to …" line with the phone bolded.
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 15, color: FixCareColors.textSecondary, height: 1.5),
                  children: [
                    const TextSpan(text: 'Code sent to '),
                    TextSpan(
                      text: _maskedPhone(),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: FixCareColors.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // The visible six boxes with a REAL, full-size transparent TextField
              // laid over them (Positioned.fill). The field owns the actual input,
              // focus, paste and — crucially — has real geometry so screen readers
              // can find and announce it (a zero-size field is invisible to
              // TalkBack/VoiceOver). Its glyphs/caret are transparent; the boxes
              // render the digits.
              SizedBox(
                height: 62,
                child: Stack(
                  children: [
                    _OtpBoxes(code: code, hasError: _error, focus: _focus),
                    Positioned.fill(
                      child: TextField(
                        key: const Key('otpField'),
                        controller: _controller,
                        focusNode: _focus,
                        keyboardType: TextInputType.number,
                        maxLength: _otpLength,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        showCursor: false,
                        cursorColor: Colors.transparent,
                        style: const TextStyle(color: Colors.transparent, height: 1),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error) ...[
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: FixCareColors.errorText),
                    SizedBox(width: 6),
                    Text('That code isn\'t right.',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w500, color: FixCareColors.errorText)),
                  ],
                ),
              ],
              if (Env.isDev && widget.args.devOtp != null) ...[
                const SizedBox(height: 18),
                _DevHint(code: widget.args.devOtp!),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_notice ?? 'Didn\'t get it?',
                      style: const TextStyle(fontSize: 14, color: FixCareColors.textMuted)),
                  GestureDetector(
                    onTap: _busy ? null : _resend,
                    child: const Text('Resend code',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: FixCareColors.primary)),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                key: const Key('verifyBtn'),
                onPressed: _busy ? null : _verify,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Verify & continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Six OTP boxes reflecting the backing controller's value + state.
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({required this.code, required this.hasError, required this.focus});

  final String code;
  final bool hasError;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    // Purely visual — the transparent TextField stacked above owns taps/focus.
    return IgnorePointer(
      child: Row(
        children: List.generate(_otpLength, (i) {
          final filled = i < code.length;
          final isActive = i == code.length && focus.hasFocus;
          final digit = filled ? code[i] : '';

          Color border;
          Color fill = FixCareColors.surface;
          Color text = FixCareColors.textPrimary;

          if (hasError) {
            fill = FixCareColors.errorFill;
            border = FixCareColors.errorBorder;
            text = FixCareColors.errorText;
          } else if (isActive) {
            border = FixCareColors.primary;
            text = FixCareColors.primary;
          } else if (filled) {
            border = FixCareColors.border;
          } else {
            border = FixCareColors.borderStrong; // pending (design shows dashed; solid faint here)
          }

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == _otpLength - 1 ? 0 : 10),
              child: Container(
                height: 62,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(FixCareRadii.field),
                  border: Border.all(color: border, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(digit,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: text)),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DevHint extends StatelessWidget {
  const _DevHint({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: FixCareColors.devHintFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FixCareColors.devHintBorder),
      ),
      child: Row(
        children: [
          const Text('🛠', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, color: FixCareColors.devHintText),
                children: [
                  const TextSpan(text: 'Dev code: '),
                  TextSpan(text: code, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
