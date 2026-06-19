import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'core/router.dart';

void main() {
  runApp(const VegaChatApp());
}

class VegaChatApp extends StatelessWidget {
  const VegaChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Vega Chat',
      theme: VegaTheme.theme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
