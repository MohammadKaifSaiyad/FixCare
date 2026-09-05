import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

part 'auth_controller.g.dart';

/// Owns the session lifecycle: boot from storage, OTP verify, logout, and the
/// interceptor's session-lost signal. The auth interceptor is the ONLY place a
/// token refresh happens; this controller only reacts to the outcome.
@riverpod
class AuthController extends _$AuthController {
  @override
  Future<Session> build() async {
    final access = await ref.read(tokenStoreProvider).readAccess();
    // Slice 1: presence of a token = authenticated. We don't persist the user
    // object, so we surface a placeholder user until a later slice fetches
    // /me/profile. A fresh verify (submitOtp) replaces it with the real user.
    return access != null
        ? const SessionAuthenticated(
            UserDto(id: '', role: 'CUSTOMER', status: 'ACTIVE'),
          )
        : const SessionUnauthenticated();
  }

  Future<Result<SendOtpResponse>> requestOtp(String phone) =>
      ref.read(authRepositoryProvider).sendOtp(phone);

  Future<Result<void>> submitOtp(String phone, String code) async {
    final r = await ref.read(authRepositoryProvider).verifyOtp(phone, code);
    if (r is Ok<VerifyResponse>) {
      await ref.read(tokenStoreProvider).save(
            access: r.value.accessToken,
            refresh: r.value.refreshToken,
          );
      state = AsyncData(SessionAuthenticated(r.value.user));
      return const Ok(null);
    }
    final f = r as Failure<VerifyResponse>;
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
