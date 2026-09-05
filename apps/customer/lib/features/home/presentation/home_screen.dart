import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../address/data/address_repository.dart';
import '../../address/presentation/address_controller.dart';
import '../../catalog/data/catalog_repository.dart';

/// ₹ from integer paise, no trailing .00 when whole rupees.
String rupees(int paise) {
  final r = paise / 100;
  return r == r.roundToDouble() ? '₹${r.toInt()}' : '₹${r.toStringAsFixed(2)}';
}

/// Home shell — the logged-in landing. Header shows the default address'
/// label + zone; body lists the real catalog (categories + per-zone priced
/// services) resolved against that address' zone. No serviceable default
/// address → categories still render, but services are replaced by a CTA to
/// add an address (never crashes trying to fetch services without a zone).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: addressesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _ErrorRetry(onRetry: () => ref.invalidate(addressControllerProvider)),
          data: (addresses) {
            final AddressDto? def = addresses.isEmpty
                ? null
                : addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
            final zone = def?.zone;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(label: def?.label, zoneName: zone?.name),
                Expanded(
                  child: zone == null ? const _NoAddress() : _Catalog(zoneId: zone.id),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const _BottomBar(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label, required this.zoneName});
  final String? label;
  final String? zoneName;

  @override
  Widget build(BuildContext context) {
    final subtitle = (label != null && zoneName != null)
        ? '$label · $zoneName'
        : (label ?? 'Add your address');
    return Padding(
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
                  children: [
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                    const Icon(Icons.keyboard_arrow_down, size: 20, color: FixCareColors.textMuted),
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
    );
  }
}

/// No serviceable default address: still show the categories (browsable),
/// but replace the service list with a CTA to add an address.
class _NoAddress extends ConsumerWidget {
  const _NoAddress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(catalogRepositoryProvider);
    return FutureBuilder<Result<List<CategoryDto>>>(
      future: repo.categories(),
      builder: (context, snapshot) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const Text('What needs fixing?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
            const SizedBox(height: 14),
            if (snapshot.hasData && snapshot.data is Ok<List<CategoryDto>>)
              _CategoriesGrid(categories: (snapshot.data as Ok<List<CategoryDto>>).value),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: FixCareColors.surface,
                borderRadius: BorderRadius.circular(FixCareRadii.card),
                border: Border.all(color: FixCareColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, color: FixCareColors.primary, size: 28),
                  const SizedBox(height: 10),
                  const Text('Add an address to see services & book',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('We match services & pricing to your serviceable zone.',
                      style: TextStyle(fontSize: 13, color: FixCareColors.textMuted)),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('homeAddAddressCta'),
                    onPressed: () => context.push('/address/new'),
                    child: const Text('Add address'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Categories grid + per-category priced service list, resolved for [zoneId].
class _Catalog extends ConsumerWidget {
  const _Catalog({required this.zoneId});
  final String zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(catalogRepositoryProvider);
    return FutureBuilder<Result<List<CategoryDto>>>(
      future: repo.categories(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data!;
        return switch (result) {
          Failure() => _ErrorRetry(onRetry: () => ref.invalidate(catalogRepositoryProvider)),
          Ok(value: final categories) when categories.isEmpty =>
            const Center(child: Text('No services yet')),
          Ok(value: final categories) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                const Text('What needs fixing?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                const SizedBox(height: 14),
                _CategoriesGrid(categories: categories),
                const SizedBox(height: 24),
                for (final c in categories) _CategoryServices(zoneId: zoneId, category: c),
              ],
            ),
        };
      },
    );
  }
}

class _CategoriesGrid extends StatelessWidget {
  const _CategoriesGrid({required this.categories});
  final List<CategoryDto> categories;

  static const _icons = <String, (String, Color)>{
    'Refrigerator': ('❄️', Color(0xFFFDECE2)),
    'Air conditioner': ('🌬️', Color(0xFFE7F0F6)),
    'Washing machine': ('🌀', Color(0xFFEDEBF7)),
    'Water purifier': ('💧', Color(0xFFE9F5EF)),
  };

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [for (final c in categories) _CategoryTile(category: c)],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final CategoryDto category;

  @override
  Widget build(BuildContext context) {
    final iconEntry = _CategoriesGrid._icons[category.name] ?? ('🔧', FixCareColors.primaryTint);
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
            decoration: BoxDecoration(color: iconEntry.$2, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(iconEntry.$1, style: const TextStyle(fontSize: 19)),
          ),
          const Spacer(),
          Text(category.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
        ],
      ),
    );
  }
}

class _CategoryServices extends ConsumerWidget {
  const _CategoryServices({required this.zoneId, required this.category});
  final String zoneId;
  final CategoryDto category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(catalogRepositoryProvider);
    return FutureBuilder<Result<List<ServiceDto>>>(
      future: repo.services(zoneId: zoneId, categoryId: category.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final result = snapshot.data!;
        return switch (result) {
          Failure() => const SizedBox.shrink(),
          Ok(value: final services) when services.isEmpty => const SizedBox.shrink(),
          Ok(value: final services) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                  const SizedBox(height: 10),
                  for (final s in services) _ServiceRow(service: s),
                ],
              ),
            ),
        };
      },
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service});
  final ServiceDto service;

  @override
  Widget build(BuildContext context) {
    final teaser = service.laborPaise != null
        ? 'Visit fee ${rupees(service.visitFeePaise)} · Labor from ${rupees(service.laborPaise!)}'
        : 'Visit fee ${rupees(service.visitFeePaise)}';
    return InkWell(
      onTap: () => context.push('/book/${service.id}'),
      borderRadius: BorderRadius.circular(FixCareRadii.card),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FixCareColors.surface,
          borderRadius: BorderRadius.circular(FixCareRadii.card),
          border: Border.all(color: FixCareColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(service.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: FixCareColors.primaryTint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(service.tier,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600, color: FixCareColors.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(teaser, style: const TextStyle(fontSize: 13, color: FixCareColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: FixCareColors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 32, color: FixCareColors.errorBorder),
          const SizedBox(height: 10),
          const Text('Something went wrong.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: FixCareColors.surface,
        border: Border(top: BorderSide(color: FixCareColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      child: const Row(
        children: [
          _Tab(icon: Icons.home_rounded, label: 'Home', active: true),
          _Tab(icon: Icons.list_alt_rounded, label: 'Bookings', active: false),
          _Tab(icon: Icons.person_rounded, label: 'Account', active: false),
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
