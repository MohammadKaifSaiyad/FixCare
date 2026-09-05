import '../../profile/data/profile_dtos.dart';

/// The customer's resolved auth state. "Booting" is AsyncLoading on the
/// controller, not a member here.
sealed class Session {
  const Session();
}

class SessionUnauthenticated extends Session {
  const SessionUnauthenticated();
}

/// Authenticated. [profile] is the real user. [hydrated] is true when the
/// profile was fetched successfully this session; false means we have a token
/// but the boot fetch failed on network (option a: stay logged in, don't
/// name-gate). The name-gate only fires when hydrated && name is empty.
class SessionAuthenticated extends Session {
  final CustomerProfileDto profile;
  final bool hydrated;
  const SessionAuthenticated(this.profile, {this.hydrated = true});

  String get name => profile.name;
}
