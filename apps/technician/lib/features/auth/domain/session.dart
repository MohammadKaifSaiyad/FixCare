import '../../profile/data/technician_profile_dto.dart';

/// The technician's resolved auth state. "Booting" is AsyncLoading on the
/// controller, not a member here.
sealed class Session {
  const Session();
}

class SessionUnauthenticated extends Session {
  const SessionUnauthenticated();
}

/// Authenticated technician. [hydrated] is false when we have a token but the
/// boot profile fetch failed on a transient network error (stay logged in).
class SessionAuthenticated extends Session {
  final TechnicianProfileDto profile;
  final bool hydrated;
  const SessionAuthenticated(this.profile, {this.hydrated = true});

  String get name => profile.name;
  String get status => profile.status;
  bool get isVerified => profile.status == 'VERIFIED';
}
