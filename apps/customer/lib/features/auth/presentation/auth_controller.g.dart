// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(AuthController)
final authControllerProvider = AuthControllerProvider._();

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
final class AuthControllerProvider
    extends $AsyncNotifierProvider<AuthController, Session> {
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
  AuthControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authControllerHash();

  @$internal
  @override
  AuthController create() => AuthController();
}

String _$authControllerHash() => r'44827a0c9c97424c4f4199180813cf8b48c6bfc1';

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

abstract class _$AuthController extends $AsyncNotifier<Session> {
  FutureOr<Session> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Session>, Session>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Session>, Session>,
              AsyncValue<Session>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
