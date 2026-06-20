import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../presentation/chat/chat_screen.dart';
import '../presentation/ide/ide_screen.dart';
import '../presentation/terminal/terminal_screen.dart';
import '../presentation/settings/settings_screen.dart';
import '../presentation/history/history_screen.dart';

final router = GoRouter(
  initialLocation: '/chat',
  routes: [
    GoRoute(
      path: '/chat',
      builder: (context, state) {
        final chatId = state.extra as int?;
        return ChatScreen(chatId: chatId);
      },
    ),
    GoRoute(
      path: '/ide',
      builder: (context, state) => const IdeScreen(),
    ),
    GoRoute(
      path: '/terminal',
      builder: (context, state) => const TerminalScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
  ],
);
