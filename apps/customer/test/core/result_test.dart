import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/core/result.dart';

void main() {
  test('failureKindFromStatus maps HTTP codes', () {
    expect(failureKindFromStatus(401), FailureKind.unauthorized);
    expect(failureKindFromStatus(429), FailureKind.rateLimited);
    expect(failureKindFromStatus(400), FailureKind.validation);
    expect(failureKindFromStatus(500), FailureKind.server);
    expect(failureKindFromStatus(503), FailureKind.server);
    expect(failureKindFromStatus(null), FailureKind.unknown);
  });
}
