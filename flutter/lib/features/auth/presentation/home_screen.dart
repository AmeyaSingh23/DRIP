import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.email, required this.token, super.key});

  final String email;
  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DRIP'),
        actions: [
          IconButton(
            onPressed: () => context.push('/wardrobe/upload', extra: token),
            tooltip: 'Add wardrobe item',
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(child: Text('Signed in as $email')),
    );
  }
}
