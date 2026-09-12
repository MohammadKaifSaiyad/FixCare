import '../data/booking_dtos.dart';

enum TrackingPhase {
  finding, assigned, enRoute, arrived, diagnosis, repairing,
  confirmCompletion, payment, disputed, completed, cancelled, declined,
}

enum TrackingGate { none, arrival, decision, completion }

/// Maps a backend booking state to a customer-facing phase. Unknown/future
/// states fall back to `finding` so the UI never renders a blank screen.
TrackingPhase phaseFor(BookingDto b) => switch (b.state) {
      'CREATED' || 'DISPATCHED' => TrackingPhase.finding,
      'ACCEPTED' => TrackingPhase.assigned,
      'EN_ROUTE' => TrackingPhase.enRoute,
      'ARRIVED' => TrackingPhase.arrived,
      'DIAGNOSED' => TrackingPhase.diagnosis,
      'CUSTOMER_APPROVED' || 'PARTS_REQUESTED' || 'PARTS_ACQUIRED' || 'REPAIR_IN_PROGRESS' =>
        TrackingPhase.repairing,
      'REPAIR_COMPLETE' => TrackingPhase.confirmCompletion,
      'CUSTOMER_CONFIRMED' || 'PAYMENT_RECEIVED' => TrackingPhase.payment,
      'DISPUTED' => TrackingPhase.disputed,
      'CLOSED' => TrackingPhase.completed,
      'CANCELLED_BY_CUSTOMER' || 'CANCELLED_BY_TECHNICIAN' => TrackingPhase.cancelled,
      'DECLINED_BY_CUSTOMER' => TrackingPhase.declined,
      _ => TrackingPhase.finding,
    };

/// The active customer gate for a state (the one interactive action available).
TrackingGate gateFor(BookingDto b) => switch (b.state) {
      'EN_ROUTE' => TrackingGate.arrival,
      'DIAGNOSED' => TrackingGate.decision,
      'REPAIR_COMPLETE' => TrackingGate.completion,
      _ => TrackingGate.none,
    };

bool isCancellable(BookingDto b) =>
    b.state == 'CREATED' || b.state == 'DISPATCHED' || b.state == 'ACCEPTED' || b.state == 'EN_ROUTE';

bool isTerminal(BookingDto b) =>
    b.state == 'CLOSED' ||
    b.state == 'CANCELLED_BY_CUSTOMER' ||
    b.state == 'CANCELLED_BY_TECHNICIAN' ||
    (b.state == 'DECLINED_BY_CUSTOMER' && b.payment != null);
