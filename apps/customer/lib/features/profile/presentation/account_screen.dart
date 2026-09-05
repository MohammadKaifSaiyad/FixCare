import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final name = session is SessionAuthenticated ? session.name : '';
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _NameTile(name: name),
          const SizedBox(height: 8),
          FutureBuilder<String?>(
            future: ref.read(tokenStoreProvider).readPhone(),
            builder: (c, snap) => _InfoRow(label: 'Mobile', value: snap.data == null ? '—' : '+91 ${snap.data}'),
          ),
          const SizedBox(height: 20),
          ListTile(
            key: const Key('myAddressesTile'),
            shape: RoundedRectangleBorder(
                side: const BorderSide(color: FixCareColors.border), borderRadius: BorderRadius.circular(FixCareRadii.card)),
            leading: const Icon(Icons.location_on_outlined, color: FixCareColors.primary),
            title: const Text('My addresses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/addresses'),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            key: const Key('signOutBtn'),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: FixCareColors.errorText,
              side: const BorderSide(color: FixCareColors.border),
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label; final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: FixCareColors.textMuted)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
    ]),
  );
}

class _NameTile extends ConsumerStatefulWidget {
  const _NameTile({required this.name});
  final String name;
  @override
  ConsumerState<_NameTile> createState() => _NameTileState();
}

class _NameTileState extends ConsumerState<_NameTile> {
  bool _editing = false;
  late final TextEditingController _c = TextEditingController(text: widget.name);
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  Future<void> _save() async {
    final n = _c.text.trim();
    if (n.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    final res = await ref.read(authControllerProvider.notifier).updateName(n);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res is Ok) {
        _editing = false;
      } else if (res case Failure(:final message)) {
        _error = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return _InfoRowEditable(
        label: 'Name', value: widget.name.isEmpty ? '—' : widget.name,
        onEdit: () => setState(() { _c.text = widget.name; _editing = true; _error = null; }));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: TextField(key: const Key('accountNameField'), controller: _c,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: 'Name', errorText: _error))),
      const SizedBox(width: 8),
      IconButton(
        key: const Key('accountNameSave'),
        onPressed: _busy ? null : _save,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, color: FixCareColors.success)),
    ]);
  }
}

class _InfoRowEditable extends StatelessWidget {
  const _InfoRowEditable({required this.label, required this.value, required this.onEdit});
  final String label; final String value; final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: FixCareColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
      ])),
      TextButton(key: const Key('editNameBtn'), onPressed: onEdit, child: const Text('Edit')),
    ]),
  );
}
