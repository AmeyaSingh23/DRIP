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
                Center(
                  child: SizedBox(
                    width: 240,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: isSigningIn ? null : _signIn,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF757575),
                        side: const BorderSide(color: Color(0xFFDADCE0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.network(
                            'https://developers.google.com/identity/images/g-logo.png',
                            width: 18,
                            height: 18,
                            errorBuilder:
                                (_, _, _) =>
                                    const SizedBox(width: 18, height: 18),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Sign in with Google',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              color: Color(0xFF757575),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
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
