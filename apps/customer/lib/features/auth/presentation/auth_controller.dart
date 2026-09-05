import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/token_store.dart';
import '../../profile/data/profile_repository.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

part 'auth_controller.g.dart';

/// Owns the session lifecycle: boot from storage, OTP verify, logout, and the
/// interceptor's session-lost signal. The auth interceptor is the ONLY place a
/// token refresh happens; this controller only reacts to the outcome.
///
/// keepAlive: this is app-wide session state that must live for the whole app
/// session. It is read from several places (the router bridge, the dio
/// interceptor's onAuthLost, screens) at different times; an auto-dispose
/// controller would risk being torn down and re-booting the session between
/// uses. Keep the lifetime explicit rather than relying on an incidental
/// long-lived listener.
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  @override
  Future<Session> build() async {
    final access = await ref.read(tokenStoreProvider).readAccess();
    if (access == null) return const SessionUnauthenticated();
    return _hydrate();
  }

  /// Token present → fetch the real profile. 401 = stale token → clear + logout.
  /// network/other = stay logged in but unhydrated (option a): don't eject the
  /// user or name-gate on a transient blip.
  Future<Session> _hydrate() async {
    final r = await ref.read(profileRepositoryProvider).getProfile();
    switch (r) {
      case Ok(value: final profile):
        return SessionAuthenticated(profile, hydrated: true);
      case Failure(kind: FailureKind.unauthorized):
        await ref.read(tokenStoreProvider).clear();
        return const SessionUnauthenticated();
      case Failure():
        return const SessionAuthenticated(
          CustomerProfileDto(id: '', role: 'CUSTOMER', name: '', status: 'ACTIVE'),
          hydrated: false,
        );
    }
  }

  Future<Result<SendOtpResponse>> requestOtp(String phone) =>
      ref.read(authRepositoryProvider).sendOtp(phone);

  Future<Result<void>> submitOtp(String phone, String code) async {
    final r = await ref.read(authRepositoryProvider).verifyOtp(phone, code);
    if (r is Ok<VerifyResponse>) {
      final store = ref.read(tokenStoreProvider);
      await store.save(access: r.value.accessToken, refresh: r.value.refreshToken);
      await store.savePhone(phone);
      // verify's user has no name — fetch the real profile so the name-gate works.
      state = AsyncData(await _hydrate());
      return const Ok(null);
    }
    final f = r as Failure<VerifyResponse>;
    return Failure(f.kind, f.message);
  }

  /// Update the display name; on success re-emit the session with the new name.
  Future<Result<void>> updateName(String name) async {
    final r = await ref.read(profileRepositoryProvider).updateName(name);
    if (r is Ok<CustomerProfileDto>) {
      state = AsyncData(SessionAuthenticated(r.value, hydrated: true));
      return const Ok(null);
    }
    final f = r as Failure<CustomerProfileDto>;
    return Failure(f.kind, f.message);
  }

  Future<void> logout() async {
    final refresh = await ref.read(tokenStoreProvider).readRefresh();
    if (refresh != null) {
      // Best-effort server-side revoke; local clear happens regardless.
      await ref.read(authRepositoryProvider).logout(refresh);
    }
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(SessionUnauthenticated());
  }

  /// Called by the auth interceptor when a refresh fails: drop to
  /// unauthenticated so the router pushes the phone screen.
  void onAuthLost() => state = const AsyncData(SessionUnauthenticated());
}
