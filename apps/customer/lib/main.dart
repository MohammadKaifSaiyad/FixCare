import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';

void main() => runApp(const ProviderScope(child: FixCareApp()));

class FixCareApp extends StatelessWidget {
  const FixCareApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FixCare',
      debugShowCheckedModeBanner: false,
      theme: buildFixCareTheme(),
      home: const Scaffold(body: Center(child: Text('FixCare'))),
    );
  }
}
