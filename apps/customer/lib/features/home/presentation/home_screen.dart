import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';

/// Stub home for slice 1 — proves the authed landing. Real home content
/// (bookings list, service discovery) is a later slice.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FixCare'),
        actions: [
          IconButton(
            key: const Key('logoutBtn'),
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 56, color: Color(0xFF1D6B4F)),
            SizedBox(height: 16),
            Text(
              "You're logged in",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text('Your bookings will show up here.'),
          ],
        ),
      ),
    );
  }
}
