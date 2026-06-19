import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../presentation/chat/chat_screen.dart';
import '../presentation/ide/ide_screen.dart';
import '../presentation/settings/settings_screen.dart';

final router = GoRouter(
  initialLocation: '/chat',
  routes: [
    GoRoute(
      path: '/chat',
      builder: (context, state) => const ChatScreen(),
    ),
    GoRoute(
      path: '/ide',
      builder: (context, state) => const IdeScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
