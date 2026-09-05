import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/session.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/otp_entry_screen.dart';
import '../../features/auth/presentation/phone_entry_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/home/presentation/home_screen.dart';

/// Bridges the Riverpod auth state to a [Listenable] so GoRouter re-runs its
/// redirect whenever the session changes (login, logout, session-lost).
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _sub = _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final async = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      // Still booting → splash.
      if (async.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      // build() failed (e.g. secure-storage threw). We can't prove a session,
      // so treat it as logged-out and send the user to phone entry rather than
      // stranding them on an endless splash. onAuthLost/retry via re-login.
      if (async.hasError) {
        final onAuthScreenErr = loc == '/phone' || loc == '/otp';
        return onAuthScreenErr ? null : '/phone';
      }

      final session = async.requireValue;
      final onAuthScreen = loc == '/phone' || loc == '/otp';

      switch (session) {
        case SessionUnauthenticated():
          return onAuthScreen ? null : '/phone';
        case SessionAuthenticated():
          // An authed user has no business on splash/phone/otp.
          return (loc == '/splash' || onAuthScreen) ? '/home' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/phone', builder: (_, _) => const PhoneEntryScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final args = state.extra as OtpArgs?;
          // A direct hit on /otp with no args (e.g. deep link) falls back to
          // phone entry via the redirect on the next frame; guard here too.
          if (args == null) return const PhoneEntryScreen();
          return OtpEntryScreen(args: args);
        },
      ),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
    ],
  );
});
