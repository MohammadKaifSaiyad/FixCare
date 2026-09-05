import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../address/data/address_dtos.dart';
import '../../address/presentation/address_controller.dart';
import '../../address/presentation/widgets/serviceability_chip.dart';
import '../../catalog/data/catalog_dtos.dart';
import '../../home/presentation/home_screen.dart' show rupees;
import '../data/booking_repository.dart';
import 'booking_wizard_controller.dart';
import 'slot.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day}';
String _fullDateLabel(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// Formats a scheduledSlot ISO (UTC) string for display in local time, e.g.
/// "Wed, 10 Sep · Morning · 9–12" (falls back to the window whose startHour
/// matches, else just the time).
String formatScheduledSlot(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  final window = SlotWindow.values.firstWhere(
    (w) => w.startHour == dt.hour,
    orElse: () => SlotWindow.morning,
  );
  return '${_fullDateLabel(dt)} · ${window.label}';
}

/// The booking wizard: address -> slot -> confirm. `service` (from the route
/// `extra`) supplies the name/fee teaser on the confirm step; when null
/// (e.g. a deep link) we fall back to a generic "Service" label and the
/// chosen address' zone visit fee.
class BookingWizardScreen extends ConsumerStatefulWidget {
  const BookingWizardScreen({super.key, required this.serviceId, this.service});
  final String serviceId;
  final ServiceDto? service;

  @override
  ConsumerState<BookingWizardScreen> createState() => _BookingWizardScreenState();
}

class _BookingWizardScreenState extends ConsumerState<BookingWizardScreen> {
  int _step = 0;
  String? _error;
  bool _busy = false;
  bool _addressPreselected = false;

  // Slot step's own transient picks: which date is selected (defaults to
  // tomorrow so the morning window is always in the future — see brief's
  // determinism note) and which window (if any) has been chosen for it.
  late DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  SlotWindow? _selectedWindow;

  void _next() => setState(() => _step += 1);
  void _back() {
    if (_step == 0) {
      context.pop();
    } else {
      setState(() => _step -= 1);
    }
  }

  Future<void> _confirm(BookingWizardState wizard) async {
    final addressId = wizard.addressId;
    final scheduledSlot = wizard.scheduledSlot;
    if (addressId == null || scheduledSlot == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(bookingRepositoryProvider);
    final result = await repo.create(
      addressId: addressId,
      serviceId: widget.serviceId,
      scheduledSlot: scheduledSlot,
    );
    if (!mounted) return;
    switch (result) {
      case Ok(value: final booking):
        context.go('/booking/${booking.id}');
      case Failure(message: final m):
        setState(() {
          _busy = false;
          _error = m;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wizard = ref.watch(bookingWizardProvider(widget.serviceId));
    final notifier = ref.read(bookingWizardProvider(widget.serviceId).notifier);
    final addressesAsync = ref.watch(addressControllerProvider);

    // Preselect the default address into the wizard exactly once, after the
    // addresses have loaded (a post-frame callback, since this mutates a
    // different provider's state — never call notifier methods mid-build).
    addressesAsync.whenData((addresses) {
      if (!_addressPreselected && wizard.addressId == null && addresses.isNotEmpty) {
        _addressPreselected = true;
        final def = addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
        WidgetsBinding.instance.addPostFrameCallback((_) => notifier.setAddress(def.id));
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text(switch (_step) {
          0 => 'Choose address',
          1 => 'Choose a time',
          _ => 'Confirm booking',
        }),
      ),
      body: SafeArea(
        child: switch (_step) {
          0 => _AddressStep(
              addressesAsync: addressesAsync,
              selectedId: wizard.addressId,
              onSelect: notifier.setAddress,
            ),
          1 => _SlotStep(
              selectedDate: _selectedDate,
              selectedWindow: _selectedWindow,
              onSelectDate: (d) => setState(() {
                _selectedDate = d;
                _selectedWindow = null;
              }),
              onSelectWindow: (w) {
                setState(() => _selectedWindow = w);
                final iso = slotToIso(_selectedDate, w);
                if (iso != null) notifier.setSlot(iso);
              },
            ),
          _ => _ConfirmStep(
              service: widget.service,
              address: addressesAsync.value?.cast<AddressDto?>().firstWhere(
                    (a) => a?.id == wizard.addressId,
                    orElse: () => null,
                  ),
              scheduledSlot: wizard.scheduledSlot,
              error: _error,
              busy: _busy,
              onConfirm: () => _confirm(wizard),
            ),
        },
      ),
      bottomNavigationBar: _step == 2
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton(
                  onPressed: _canContinue(wizard) ? _next : null,
                  child: const Text('Continue'),
                ),
              ),
            ),
    );
  }

  bool _canContinue(BookingWizardState wizard) => switch (_step) {
        0 => wizard.addressId != null,
        1 => wizard.scheduledSlot != null,
        _ => true,
      };
}

class _AddressStep extends StatelessWidget {
  const _AddressStep({required this.addressesAsync, required this.selectedId, required this.onSelect});
  final AsyncValue<List<AddressDto>> addressesAsync;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('wizardAddress'),
      child: addressesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load addresses.')),
        data: (addresses) => RadioGroup<String>(
          groupValue: selectedId,
          onChanged: (id) {
            if (id != null) onSelect(id);
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final a in addresses)
                _AddressTile(address: a, selected: a.id == selectedId, onTap: () => onSelect(a.id)),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('wizardAddAddress'),
                onPressed: () => context.push('/address/new'),
                child: const Text('Add address'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.address, required this.selected, required this.onTap});
  final AddressDto address;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FixCareRadii.card),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FixCareColors.surface,
          borderRadius: BorderRadius.circular(FixCareRadii.card),
          border: Border.all(color: selected ? FixCareColors.primary : FixCareColors.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: address.id,
              activeColor: FixCareColors.primary,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(address.label,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(address.line1, style: const TextStyle(fontSize: 13, color: FixCareColors.textMuted)),
                  const SizedBox(height: 8),
                  ServiceabilityChip(serviceable: address.serviceable),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotStep extends StatelessWidget {
  const _SlotStep({
    required this.selectedDate,
    required this.selectedWindow,
    required this.onSelectDate,
    required this.onSelectWindow,
  });
  final DateTime selectedDate;
  final SlotWindow? selectedWindow;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<SlotWindow> onSelectWindow;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(8, (i) => DateTime.now().add(Duration(days: i)));
    return Container(
      key: const Key('wizardSlot'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Date', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final d = days[i];
                final isSelected = d.year == selectedDate.year && d.month == selectedDate.month && d.day == selectedDate.day;
                return ChoiceChip(
                  label: Text(_dayLabel(d)),
                  selected: isSelected,
                  onSelected: (_) => onSelectDate(d),
                  selectedColor: FixCareColors.primaryTint,
                  labelStyle: TextStyle(
                    color: isSelected ? FixCareColors.primary : FixCareColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text('Time window', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in SlotWindow.values)
                _WindowChip(
                  window: w,
                  day: selectedDate,
                  selected: selectedWindow == w,
                  onSelected: () => onSelectWindow(w),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({required this.window, required this.day, required this.selected, required this.onSelected});
  final SlotWindow window;
  final DateTime day;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final enabled = slotToIso(day, window) != null;
    return ChoiceChip(
      label: Text(window.label),
      selected: selected,
      onSelected: enabled ? (_) => onSelected() : null,
      selectedColor: FixCareColors.primaryTint,
      disabledColor: FixCareColors.disabledFill,
      labelStyle: TextStyle(
        color: !enabled
            ? FixCareColors.disabledText
            : (selected ? FixCareColors.primary : FixCareColors.textPrimary),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.service,
    required this.address,
    required this.scheduledSlot,
    required this.error,
    required this.busy,
    required this.onConfirm,
  });
  final ServiceDto? service;
  final AddressDto? address;
  final String? scheduledSlot;
  final String? error;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final visitFeePaise = address?.zone?.visitFeePaise;
    return Container(
      key: const Key('wizardConfirm'),
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          Text(service?.name ?? 'Service',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          const SizedBox(height: 20),
          _SummaryCard(
            children: [
              _SummaryRow(label: 'Address', value: address == null ? '—' : '${address!.label} · ${address!.line1}'),
              _SummaryRow(label: 'Time', value: scheduledSlot == null ? '—' : formatScheduledSlot(scheduledSlot!)),
              _SummaryRow(
                label: 'Visit fee',
                value: visitFeePaise == null ? '—' : rupees(visitFeePaise),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: FixCareColors.errorText, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            key: const Key('confirmBookingBtn'),
            onPressed: busy ? null : onConfirm,
            child: busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Confirm booking'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        borderRadius: BorderRadius.circular(FixCareRadii.card),
        border: Border.all(color: FixCareColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 13, color: FixCareColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
