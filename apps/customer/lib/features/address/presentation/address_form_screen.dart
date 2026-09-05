import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/address_repository.dart';
import 'address_controller.dart';
import 'widgets/address_map_picker.dart';
import 'widgets/serviceability_chip.dart';

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, required this.addressId, this.initial});
  final String? addressId;
  /// The existing address to pre-fill in edit mode, passed as router `extra`
  /// from the list screen. May be null (e.g. a deep link with no extra) —
  /// the form then falls back to blank fields for edit mode.
  final AddressDto? initial;
  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _label = TextEditingController();
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _landmark = TextEditingController();
  final _pincode = TextEditingController();
  double? _lat, _lng;
  bool _isDefault = false;

  Timer? _debounce;
  bool _checking = false;
  ServiceabilityDto? _svc;
  String? _svcError;
  bool _busy = false;
  String? _formError;
  // Bumped on every _check() call; a response is applied only if its
  // captured id is still the latest — guards against an older request's
  // response arriving after a newer one (out-of-order network replies)
  // and overwriting the UI with the wrong pincode's result.
  int _svcReqId = 0;

  bool get _isEdit => widget.addressId != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _label.text = initial.label;
      _line1.text = initial.line1;
      _line2.text = initial.line2 ?? '';
      _landmark.text = initial.landmark ?? '';
      _pincode.text = initial.pincode;
      _isDefault = initial.isDefault;
      _lat = initial.lat;
      _lng = initial.lng;
    }
    _pincode.addListener(_onPincodeChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_label, _line1, _line2, _landmark, _pincode]) { c.dispose(); }
    super.dispose();
  }

  void _onPincodeChanged() {
    _debounce?.cancel();
    final p = _pincode.text.trim();
    if (p.length != 6) { setState(() { _svc = null; _svcError = null; }); return; }
    _debounce = Timer(const Duration(milliseconds: 400), _check);
  }

  Future<void> _check() async {
    final reqId = ++_svcReqId;
    setState(() { _checking = true; _svcError = null; });
    final r = await ref.read(addressRepositoryProvider).checkServiceability(_pincode.text.trim());
    if (!mounted) return;
    // A newer _check() (later pincode edit) has already started — drop this
    // stale response instead of overwriting the UI with the wrong result.
    if (reqId != _svcReqId) return;
    setState(() {
      _checking = false;
      switch (r) {
        case Ok(value: final s): _svc = s;
        case Failure(): _svc = null; _svcError = "Couldn't check — you can still save.";
      }
    });
  }

  // CREATE omits empty optionals (nothing to clear yet). EDIT must be able to
  // CLEAR a previously-set optional, and the backend only clears a nullable
  // field when the client sends explicit `null` (an omitted key leaves the
  // stored value untouched) — so in edit mode we send `null` for an
  // emptied line2/landmark, and both-null for lat/lng when the pin was
  // removed (both-or-neither, preserved either way).
  Map<String, dynamic> _body() {
    final line2 = _line2.text.trim();
    final landmark = _landmark.text.trim();
    return {
      'label': _label.text.trim(),
      'line1': _line1.text.trim(),
      if (_isEdit)
        'line2': line2.isNotEmpty ? line2 : null
      else if (line2.isNotEmpty)
        'line2': line2,
      if (_isEdit)
        'landmark': landmark.isNotEmpty ? landmark : null
      else if (landmark.isNotEmpty)
        'landmark': landmark,
      'pincode': _pincode.text.trim(),
      if (_isEdit || (_lat != null && _lng != null)) ...{
        'lat': (_lat != null && _lng != null) ? _lat : null,
        'lng': (_lat != null && _lng != null) ? _lng : null,
      },
      'isDefault': _isDefault,
    };
  }

  Future<void> _save() async {
    if (_label.text.trim().isEmpty || _line1.text.trim().isEmpty || _pincode.text.trim().length != 6) {
      setState(() => _formError = 'Fill label, address line 1 and a 6-digit pincode.');
      return;
    }
    setState(() { _formError = null; _busy = true; });
    final repo = ref.read(addressRepositoryProvider);
    final r = _isEdit ? await repo.update(widget.addressId!, _body()) : await repo.create(_body());
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Ok():
        // Best-effort: if nothing else is currently watching the list
        // controller (e.g. this form was opened without the list screen
        // still on the stack), the autoDispose provider may already be
        // torn down — it will simply refetch fresh next time something
        // watches it, so a disposed controller here must not block
        // navigating back to a successful save.
        //
        // riverpod's `UnmountedRefException` (the specific exception this
        // guards against) is not part of the public API surface (it lives
        // in `riverpod`'s `src/core/ref.dart`, unreachable from app code),
        // so we narrow via the public `ref.exists(...)` pre-check instead
        // of naming the exception type, plus an `Exception`-only catch
        // (not a bare `catch`) for the residual dispose-mid-await race —
        // programming errors (`Error` subtypes) still propagate.
        if (ref.exists(addressControllerProvider)) {
          try {
            await ref.read(addressControllerProvider.notifier).refresh();
          } on Exception {
            // Provider was torn down mid-refresh — nothing to refresh; ignore.
          }
        }
        if (mounted) context.pop();
      case Failure(message: final m):
        setState(() => _formError = m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit address' : 'Add address')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(key: const Key('labelField'), controller: _label,
              decoration: const InputDecoration(labelText: 'Label (Home, Work…)')),
          const SizedBox(height: 12),
          TextField(key: const Key('line1Field'), controller: _line1,
              decoration: const InputDecoration(labelText: 'Address line 1')),
          const SizedBox(height: 12),
          TextField(key: const Key('line2Field'), controller: _line2,
              decoration: const InputDecoration(labelText: 'Address line 2 (optional)')),
          const SizedBox(height: 12),
          TextField(key: const Key('landmarkField'), controller: _landmark,
              decoration: const InputDecoration(labelText: 'Landmark (optional)')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pincodeField'), controller: _pincode,
            keyboardType: TextInputType.number, maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Pincode', counterText: ''),
          ),
          const SizedBox(height: 8),
          if (_checking) const Text('Checking serviceability…', style: TextStyle(color: FixCareColors.textMuted, fontSize: 13)),
          if (!_checking && _svc != null) ServiceabilityChip(serviceable: _svc!.serviceable),
          if (!_checking && _svc != null && !_svc!.serviceable)
            const Padding(padding: EdgeInsets.only(top: 6),
              child: Text("We don't serve this area yet — you can still save it.",
                  style: TextStyle(color: FixCareColors.textMuted, fontSize: 13))),
          if (_svcError != null) Text(_svcError!, style: const TextStyle(color: FixCareColors.textMuted, fontSize: 13)),
          const SizedBox(height: 16),
          AddressMapPicker(
            lat: _lat, lng: _lng,
            onPicked: (lat, lng) => setState(() { _lat = lat; _lng = lng; }),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('defaultSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Set as default address'),
            value: _isDefault,
            activeThumbColor: FixCareColors.primary,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
          if (_formError != null) Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text(_formError!, style: const TextStyle(color: FixCareColors.errorText, fontSize: 13))),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('saveAddressBtn'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(_isEdit ? 'Save changes' : 'Save address'),
          ),
        ],
      ),
    );
  }
}
