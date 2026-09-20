import '../data/technician_job_dto.dart';

enum JobAction {
  enRoute,
  arrive,
  waitingConfirm,
  diagnose,
  waitingApproval,
  startRepair,
  partsNeeded,
  partsAcquired,
  completeRepair,
  confirmCompletion,
  confirmCash,
  terminal,
}

JobAction jobActionFor(TechnicianJobDto b) {
  switch (b.state) {
    case 'ACCEPTED':
      return JobAction.enRoute;
    case 'EN_ROUTE':
      return JobAction.arrive;
    case 'ARRIVED':
      return JobAction.diagnose;
    case 'DIAGNOSED':
      return JobAction.waitingApproval;
    case 'CUSTOMER_APPROVED':
      return JobAction.startRepair;
    case 'PARTS_REQUESTED':
      return JobAction.partsAcquired;
    case 'PARTS_ACQUIRED':
      return JobAction.startRepair;
    case 'REPAIR_IN_PROGRESS':
      return JobAction.completeRepair;
    case 'REPAIR_COMPLETE':
      return JobAction.confirmCompletion;
    case 'CUSTOMER_CONFIRMED':
      return JobAction.confirmCash;
    case 'DECLINED_BY_CUSTOMER':
      return JobAction.confirmCash;
    case 'PAYMENT_RECEIVED':
      return JobAction.terminal;
    case 'CLOSED':
      return JobAction.terminal;
    case 'CANCELLED_BY_CUSTOMER':
      return JobAction.terminal;
    case 'CANCELLED_BY_TECHNICIAN':
      return JobAction.terminal;
    default:
      return JobAction.terminal;
  }
}

List<String> requiredPhotoKinds(String state) {
  switch (state) {
    case 'ARRIVED':
      return ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP'];
    case 'REPAIR_IN_PROGRESS':
      return ['REPAIR_OLD_PART', 'REPAIR_NEW_PACKAGING', 'REPAIR_INSTALLED'];
    default:
      return [];
  }
}

bool isTerminalJob(TechnicianJobDto b) {
  return {
    'PAYMENT_RECEIVED',
    'CLOSED',
    'CANCELLED_BY_CUSTOMER',
    'CANCELLED_BY_TECHNICIAN',
  }.contains(b.state);
}
