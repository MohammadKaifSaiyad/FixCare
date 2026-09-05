import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/main.dart';

void main() {
  testWidgets('app boots and shows the brand name', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FixCareApp()));
    expect(find.text('FixCare'), findsOneWidget);
  });
}
