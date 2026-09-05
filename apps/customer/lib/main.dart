import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme.dart';

void main() => runApp(const ProviderScope(child: FixCareApp()));

class FixCareApp extends ConsumerWidget {
  const FixCareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'FixCare',
      debugShowCheckedModeBanner: false,
      theme: buildFixCareTheme(),
      routerConfig: router,
    );
  }
}
