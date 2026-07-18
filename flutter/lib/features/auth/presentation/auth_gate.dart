import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'home_screen.dart';
import 'google_sign_in_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    return authState.when(
      loading: () => const GoogleSignInScreen(),
      error: (_, _) => const GoogleSignInScreen(),
      data:
          (session) =>
              session == null
                  ? const GoogleSignInScreen()
                  : HomeScreen(
                    email: session.user.email,
                    token: session.accessToken,
                  ),
    );
  }
}
