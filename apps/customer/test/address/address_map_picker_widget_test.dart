import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/features/address/presentation/widgets/address_map_picker.dart';

void main() {
  testWidgets('renders the placeholder (not a live GoogleMap) when mapsEnabled is false',
      (tester) async {
    // Tests never set --dart-define=MAPS_ENABLED, so Env.mapsEnabled is false
    // here — this proves the widget never attempts to construct the native
    // GoogleMap view in an environment with no API key, which is exactly
    // what keeps `flutter test` (and any keyless build) from crashing.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddressMapPicker(onPicked: (_, _) {}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Map disabled — set MAPS_API_KEY'),
      findsOneWidget,
    );
    // No GoogleMap widget type should exist in the tree at all — the gate
    // must short-circuit before construction, not merely hide it visually.
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'GoogleMap'), findsNothing);
  });

  testWidgets('placeholder still renders when lat/lng are pre-filled (edit mode)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddressMapPicker(lat: 22.3072, lng: 73.1812, onPicked: (_, _) {}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Map disabled — set MAPS_API_KEY'),
      findsOneWidget,
    );
  });
}
