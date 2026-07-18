import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class GoogleSignInScreen extends ConsumerStatefulWidget {
  const GoogleSignInScreen({super.key});

  @override
  ConsumerState<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends ConsumerState<GoogleSignInScreen> {
  String? _errorMessage;

  Future<void> _signIn() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final message =
        await ref.read(authControllerProvider.notifier).googleSignIn();
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final isSigningIn = ref.watch(authControllerProvider).isLoading;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'DRIP',
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your wardrobe, ready when you are.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: colors.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed: isSigningIn ? null : _signIn,
                  icon:
                      isSigningIn
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.g_mobiledata),
                  label: Text(
                    isSigningIn ? 'Signing in…' : 'Sign in with Google',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
