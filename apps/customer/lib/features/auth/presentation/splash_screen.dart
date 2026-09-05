import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Shown while the session boots (token storage read in progress).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _BrandMark(),
            SizedBox(height: 24),
            Text(
              'FixCare',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: fixCarePrimary,
              ),
            ),
            SizedBox(height: 6),
            Text('Sahi kaam, sahi daam.'),
            SizedBox(height: 32),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: fixCarePrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(Icons.build_rounded, size: 44, color: fixCarePrimary),
    );
  }
}
