import 'package:flutter/material.dart';

import '../../wardrobe/presentation/wardrobe_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.email, required this.token, super.key});

  final String email;
  final String token;

  @override
  Widget build(BuildContext context) =>
      WardrobeScreen(email: email, token: token);
}
