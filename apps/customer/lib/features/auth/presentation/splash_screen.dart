import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fixcare_logo.dart';

/// Shown while the session boots (token storage read in progress).
/// Full-bleed terracotta with the white logo tile, wordmark, tagline, loader.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixCareColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FixCareLogoTile(size: 88),
            const SizedBox(height: 20),
            const FixCareWordmark(color: Colors.white, markSize: 26),
            const SizedBox(height: 20),
            const Text(
              'Sahi kaam, sahi daam.',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: FixCareColors.taglineTint,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: Color(0x47FFFFFF), // rgba(255,255,255,.28)
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
