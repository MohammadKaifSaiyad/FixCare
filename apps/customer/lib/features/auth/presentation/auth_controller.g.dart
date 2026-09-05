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

@ProviderFor(AuthController)
final authControllerProvider = AuthControllerProvider._();

/// Owns the session lifecycle: boot from storage, OTP verify, logout, and the
/// interceptor's session-lost signal. The auth interceptor is the ONLY place a
/// token refresh happens; this controller only reacts to the outcome.
final class AuthControllerProvider
    extends $AsyncNotifierProvider<AuthController, Session> {
  /// Owns the session lifecycle: boot from storage, OTP verify, logout, and the
  /// interceptor's session-lost signal. The auth interceptor is the ONLY place a
  /// token refresh happens; this controller only reacts to the outcome.
  AuthControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authControllerHash();

  @$internal
  @override
  AuthController create() => AuthController();
}

String _$authControllerHash() => r'6af8ffe440b204369b829854d5e9a6b629121365';

/// Owns the session lifecycle: boot from storage, OTP verify, logout, and the
/// interceptor's session-lost signal. The auth interceptor is the ONLY place a
/// token refresh happens; this controller only reacts to the outcome.

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
