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
      loading: () => const _AuthRestoreScreen(),
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

class _AuthRestoreScreen extends StatefulWidget {
  const _AuthRestoreScreen();

  @override
  State<_AuthRestoreScreen> createState() => _AuthRestoreScreenState();
}

class _AuthRestoreScreenState extends State<_AuthRestoreScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // A gentle swinging pendulum animation for the clothes hanger
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -0.05, end: 0.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App Logo
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB6C1).withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/images/app_logo.jpg',
                        width: 140,
                        height: 140,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 64),
                  
                  // Custom Wardrobe Loader: Glassmorphism Hanger on a Nail
                  SizedBox(
                    height: 100,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        // The Nail stuck in the wall (BEHIND the hanger)
                        Positioned(
                          top: 20,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6D5D61), // Dark metallic
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // The Hanger (Swinging in FRONT of the nail)
                        Positioned(
                          top: 3,
                          child: RotationTransition(
                            turns: _animation,
                            alignment: const Alignment(0, -0.65),
                            child: Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                // Glass Drop Shadow
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, left: 4),
                                  child: Icon(
                                    Icons.checkroom_rounded,
                                    size: 72,
                                    color: Colors.black.withOpacity(0.25),
                                  ),
                                ),
                                // More Opaque Glass Hanger
                                ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: isDark 
                                        ? const [
                                            Color(0xFFFFB6C1), // Baby pink
                                            Color(0xBBFFFFFF), // Soft white
                                            Color(0xFFC2185B), // Deep rose
                                          ]
                                        : const [
                                            Color(0xFFFF8DA1), // Solid Baby Pink
                                            Color(0xFFFFFFFF), // Solid White shine
                                            Color(0xFFFF4E84), // Solid Hot Pink
                                          ],
                                    stops: const [0.0, 0.5, 1.0],
                                  ).createShader(bounds),
                                  blendMode: BlendMode.srcIn,
                                  child: const Icon(
                                    Icons.checkroom_rounded,
                                    size: 72,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

