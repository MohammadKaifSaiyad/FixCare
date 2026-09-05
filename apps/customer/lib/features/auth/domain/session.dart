import '../data/auth_dtos.dart';

/// The customer's auth state, as the router and UI see it.
///
/// `SessionUnknown` is the boot state while token storage is being read
/// (splash shown); it is distinct from `SessionUnauthenticated`, which means
/// we looked and there is no token.
sealed class Session {
  const Session();
}

class SessionUnknown extends Session {
  const SessionUnknown();
}

class SessionUnauthenticated extends Session {
  const SessionUnauthenticated();
}

class SessionAuthenticated extends Session {
  final UserDto user;
  const SessionAuthenticated(this.user);
}
