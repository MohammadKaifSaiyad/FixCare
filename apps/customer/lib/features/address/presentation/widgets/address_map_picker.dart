import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/env.dart';
import '../../../../core/theme.dart';

/// A tap-to-drop-pin map for the address lat/lng. If no Maps API key is
/// configured, renders a bordered placeholder instead of crashing — the rest
/// of the form still works. Whether a key exists is signalled by
/// Env.mapsEnabled (a --dart-define, default false) so debug/test builds
/// without a key don't attempt to instantiate the native map view.
class AddressMapPicker extends StatefulWidget {
  const AddressMapPicker({super.key, this.lat, this.lng, required this.onPicked});
  final double? lat;
  final double? lng;
  final void Function(double lat, double lng) onPicked;

  @override
  State<AddressMapPicker> createState() => _AddressMapPickerState();
}

class _AddressMapPickerState extends State<AddressMapPicker> {
  static const _vadodara = LatLng(22.3072, 73.1812);
  LatLng? _pin;

  @override
  void initState() {
    super.initState();
    if (widget.lat != null && widget.lng != null) _pin = LatLng(widget.lat!, widget.lng!);
  }

  @override
  Widget build(BuildContext context) {
    if (!Env.mapsEnabled) return const _MapPlaceholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(FixCareRadii.card),
      child: SizedBox(
        height: 180,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: _pin ?? _vadodara, zoom: 14),
          onTap: (pos) {
            setState(() => _pin = pos);
            widget.onPicked(pos.latitude, pos.longitude);
          },
          markers: _pin == null ? {} : {Marker(markerId: const MarkerId('pin'), position: _pin!)},
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
      ),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    decoration: BoxDecoration(
      color: FixCareColors.surface,
      borderRadius: BorderRadius.circular(FixCareRadii.card),
      border: Border.all(color: FixCareColors.border),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: Text(
      kReleaseMode
          ? 'Map unavailable'
          : 'Map disabled — set MAPS_API_KEY + run with --dart-define=MAPS_ENABLED=true (see README).',
      textAlign: TextAlign.center,
      style: const TextStyle(color: FixCareColors.textMuted, fontSize: 13),
    ),
  );
}
