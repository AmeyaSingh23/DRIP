import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';
import '../../profile/presentation/archive_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({required this.email, required this.token, super.key});
  final String email;
  final String token;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(email, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArchiveScreen(token: token))),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Archive'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    ),
  );
}
