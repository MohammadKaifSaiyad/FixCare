import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../data/address_dtos.dart';
import 'address_controller.dart';
import 'widgets/serviceability_chip.dart';

class AddressListScreen extends ConsumerWidget {
  const AddressListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(addressControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My addresses')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addAddressBtn'),
        backgroundColor: FixCareColors.primary,
        onPressed: () => context.push('/address/new'),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add address', style: TextStyle(color: Colors.white)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Retry(onRetry: () => ref.read(addressControllerProvider.notifier).refresh()),
        data: (list) => list.isEmpty
            ? const _Empty()
            : RefreshIndicator(
                onRefresh: () => ref.read(addressControllerProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (c, i) => _AddressCard(a: list[i]),
                ),
              ),
      ),
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.a});
  final AddressDto a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        borderRadius: BorderRadius.circular(FixCareRadii.card),
        border: Border.all(color: FixCareColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(a.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          const SizedBox(width: 8),
          if (a.isDefault) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: FixCareColors.primaryTint, borderRadius: BorderRadius.circular(999)),
            child: const Text('Default', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: FixCareColors.primary)),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            key: Key('addrMenu_${a.id}'),
            onSelected: (v) async {
              final ctrl = ref.read(addressControllerProvider.notifier);
              if (v == 'edit') { if (context.mounted) context.push('/address/${a.id}/edit'); }
              if (v == 'default') await ctrl.setDefault(a.id);
              if (v == 'delete') await ctrl.remove(a.id);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (!a.isDefault) const PopupMenuItem(value: 'default', child: Text('Set as default')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        const SizedBox(height: 4),
        Text([a.line1, if (a.line2 != null) a.line2, a.pincode].join(', '),
            style: const TextStyle(fontSize: 14, color: FixCareColors.textSecondary)),
        const SizedBox(height: 10),
        ServiceabilityChip(serviceable: a.serviceable),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(padding: EdgeInsets.all(24),
      child: Text('No addresses yet.\nAdd your first address to book a repair.',
          textAlign: TextAlign.center, style: TextStyle(color: FixCareColors.textMuted))),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text("Couldn't load your addresses.", style: TextStyle(color: FixCareColors.textMuted)),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
    ]),
  );
}
