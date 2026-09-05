import '../data/auth_dtos.dart';

/// The customer's resolved auth state.
///
/// The "still booting" state is NOT modelled here — it is represented by
/// `AsyncLoading` on the `AuthController`'s `AsyncValue` while `build()` reads
/// token storage (the router shows the splash for it). This type only ever
/// holds a *resolved* answer: authenticated or not.
sealed class Session {
  const Session();
}

class SessionUnauthenticated extends Session {
  const SessionUnauthenticated();
}

class SessionAuthenticated extends Session {
  final UserDto user;
  const SessionAuthenticated(this.user);
}
