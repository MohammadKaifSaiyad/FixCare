import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/presentation/auth_controller.dart';

class NameCaptureScreen extends ConsumerStatefulWidget {
  const NameCaptureScreen({super.key});
  @override
  ConsumerState<NameCaptureScreen> createState() => _NameCaptureScreenState();
}

class _NameCaptureScreenState extends ConsumerState<NameCaptureScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final res = await ref.read(authControllerProvider.notifier).updateName(name);
    if (!mounted) return;
    setState(() => _busy = false);
    // On Ok the session flips to a named profile → the router redirect lands /home.
    if (res case Failure(:final message)) {
      setState(() => _error = message);
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
              Text('What should we call you?', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text('This is the name your technician will see.',
                  style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted, height: 1.5)),
              const SizedBox(height: 26),
              TextField(
                key: const Key('nameField'),
                controller: _controller,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Your name', errorText: _error),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('nameContinueBtn'),
                onPressed: _busy ? null : _continue,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
