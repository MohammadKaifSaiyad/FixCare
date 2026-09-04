import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/core/storage/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write': store[call.arguments['key']] = call.arguments['value']; return null;
          case 'read': return store[call.arguments['key']];
          case 'delete': store.remove(call.arguments['key']); return null;
          case 'deleteAll': store.clear(); return null;
          case 'readAll': return Map<String, String>.from(store);
          case 'containsKey': return store.containsKey(call.arguments['key']);
        }
        return null;
      },
    );
  });

  test('save then read returns the tokens; clear removes them', () async {
    final ts = TokenStore();
    await ts.save(access: 'a1', refresh: 'r1');
    expect(await ts.readAccess(), 'a1');
    expect(await ts.readRefresh(), 'r1');
    await ts.clear();
    expect(await ts.readAccess(), isNull);
    expect(await ts.readRefresh(), isNull);
  });
}
