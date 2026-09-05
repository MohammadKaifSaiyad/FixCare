import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';

/// Home shell (stub) — the logged-in landing, built to the design chrome:
/// header (address switcher + avatar), search stub, "What needs fixing?"
/// heading + category grid, bottom tab bar. The active-booking card and live
/// catalog data are later slices.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _categories = [
    (_CatIcon('❄️', Color(0xFFFDECE2)), 'Refrigerator'),
    (_CatIcon('🌬️', Color(0xFFE7F0F6)), 'Air conditioner'),
    (_CatIcon('🌀', Color(0xFFEDEBF7)), 'Washing machine'),
    (_CatIcon('💧', Color(0xFFE9F5EF)), 'Water purifier'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SERVICE AT',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: FixCareColors.textMuted,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 2),
                        Row(
                          children: const [
                            Text('Home · Padra',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                            Icon(Icons.keyboard_arrow_down, size: 20, color: FixCareColors.textMuted),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Avatar chip opens the Account screen (sign out lives there).
                  // 42px visual circle inside a 48dp hit target (min tap size).
                  InkResponse(
                    key: const Key('accountAvatar'),
                    onTap: () => context.push('/account'),
                    radius: 28,
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(color: FixCareColors.primaryTint, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Text('RP',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.primary)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  // Search stub.
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: FixCareColors.surface,
                      borderRadius: BorderRadius.circular(FixCareRadii.field),
                      border: Border.all(color: FixCareColors.border),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.search, size: 20, color: FixCareColors.placeholder),
                        SizedBox(width: 10),
                        Text('Search appliances & services',
                            style: TextStyle(fontSize: 15, color: FixCareColors.placeholder)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('What needs fixing?',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                  const SizedBox(height: 14),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [for (final c in _categories) _CategoryTile(icon: c.$1, label: c.$2)],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: FixCareColors.surface,
          border: Border(top: BorderSide(color: FixCareColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
        child: Row(
          children: const [
            _Tab(icon: Icons.home_rounded, label: 'Home', active: true),
            _Tab(icon: Icons.list_alt_rounded, label: 'Bookings', active: false),
            _Tab(icon: Icons.person_rounded, label: 'Account', active: false),
          ],
        ),
      ),
    );
  }
}

class _CatIcon {
  final String emoji;
  final Color bg;
  const _CatIcon(this.emoji, this.bg);
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.icon, required this.label});
  final _CatIcon icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        borderRadius: BorderRadius.circular(FixCareRadii.tile),
        border: Border.all(color: FixCareColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: icon.bg, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(icon.emoji, style: const TextStyle(fontSize: 19)),
          ),
          const Spacer(),
          Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.active});
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? FixCareColors.primary : FixCareColors.textFaint;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}
