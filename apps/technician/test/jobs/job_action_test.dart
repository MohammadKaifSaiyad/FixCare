import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_dto.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_action.dart';

TechnicianJobDto _j(String state) => TechnicianJobDto.fromJson({
  'id': 'b1', 'bookingNumber': 'FC-1', 'state': state, 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Svc', 'requiredSkill': 'FAN'}, 'zone': {'name': 'Padra'},
  'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'x', 'line2': null, 'landmark': null, 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
});

void main() {
  final cases = <String, JobAction>{
    'ACCEPTED': JobAction.enRoute,
    'EN_ROUTE': JobAction.arrive,
    'ARRIVED': JobAction.diagnose,
    'DIAGNOSED': JobAction.waitingApproval,
    'CUSTOMER_APPROVED': JobAction.startRepair,
    'PARTS_REQUESTED': JobAction.partsAcquired,
    'PARTS_ACQUIRED': JobAction.startRepair,
    'REPAIR_IN_PROGRESS': JobAction.completeRepair,
    'REPAIR_COMPLETE': JobAction.confirmCompletion,
    'CUSTOMER_CONFIRMED': JobAction.confirmCash,
    'DECLINED_BY_CUSTOMER': JobAction.confirmCash,
    'PAYMENT_RECEIVED': JobAction.terminal,
    'CLOSED': JobAction.terminal,
    'CANCELLED_BY_CUSTOMER': JobAction.terminal,
    'CANCELLED_BY_TECHNICIAN': JobAction.terminal,
  };
  cases.forEach((state, expected) {
    test('jobActionFor($state) -> $expected', () => expect(jobActionFor(_j(state)), expected));
  });

  test('requiredPhotoKinds by state', () {
    expect(requiredPhotoKinds('ARRIVED'), ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP']);
    expect(requiredPhotoKinds('REPAIR_IN_PROGRESS'), ['REPAIR_OLD_PART', 'REPAIR_NEW_PACKAGING', 'REPAIR_INSTALLED']);
    expect(requiredPhotoKinds('ACCEPTED'), isEmpty);
  });

  test('unknown state -> terminal (never throws / never a wrong action)', () {
    expect(jobActionFor(_j('SOME_FUTURE_STATE')), JobAction.terminal);
  });

  test('isTerminalJob: DECLINED_BY_CUSTOMER is non-terminal (poll continues for cash)', () {
    expect(isTerminalJob(_j('DECLINED_BY_CUSTOMER')), false);
  });

  test('isTerminalJob: genuinely terminal states return true', () {
    expect(isTerminalJob(_j('PAYMENT_RECEIVED')), true);
    expect(isTerminalJob(_j('CLOSED')), true);
    expect(isTerminalJob(_j('CANCELLED_BY_CUSTOMER')), true);
    expect(isTerminalJob(_j('CANCELLED_BY_TECHNICIAN')), true);
  });

  test('isTerminalJob: mid-flow states return false', () {
    expect(isTerminalJob(_j('ACCEPTED')), false);
    expect(isTerminalJob(_j('REPAIR_IN_PROGRESS')), false);
    expect(isTerminalJob(_j('CUSTOMER_CONFIRMED')), false);
  });

  test('every JobAction value is reachable from some state (no dead UI branches)', () {
    expect(cases.values.toSet(), JobAction.values.toSet());
  });
}
