import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    return authState.when(
      // Keep the same LoginScreen mounted while a sign-in request is active.
      // Replacing it with a loading Scaffold disposes its controllers and clears
      // the email/password whenever the request fails.
      loading: () => const LoginScreen(),
      error: (_, _) => const LoginScreen(),
      data:
          (session) =>
              session == null
                  ? const LoginScreen()
                  : HomeScreen(
                    email: session.user.email,
                    token: session.accessToken,
                  ),
    );
  }
}
