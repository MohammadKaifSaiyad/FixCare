import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';

void main() {
  test('403 → forbidden, 404 → notFound', () {
    expect(failureKindFromStatus(403), FailureKind.forbidden);
    expect(failureKindFromStatus(404), FailureKind.notFound);
  });

  test('existing mappings are unchanged', () {
    expect(failureKindFromStatus(401), FailureKind.unauthorized);
    expect(failureKindFromStatus(429), FailureKind.rateLimited);
    expect(failureKindFromStatus(400), FailureKind.validation);
    expect(failureKindFromStatus(408), FailureKind.network);
    expect(failureKindFromStatus(500), FailureKind.server);
    expect(failureKindFromStatus(409), FailureKind.unknown);
    expect(failureKindFromStatus(422), FailureKind.unknown);
    expect(failureKindFromStatus(null), FailureKind.unknown);
  });
}
