import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class ShimmerThinkingIndicator extends StatefulWidget {
  final double fontSize;

  const ShimmerThinkingIndicator({
    super.key,
    this.fontSize = 13.5,
  });

  @override
  State<ShimmerThinkingIndicator> createState() => _ShimmerThinkingIndicatorState();
}

class _ShimmerThinkingIndicatorState extends State<ShimmerThinkingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  Timer? _phraseTimer;
  int _phraseIndex = 0;

  static const List<String> _thinkingPhrases = [
    'Думаю...',
    'Анализирую...',
    'Генерирую...',
    'Проверяю...',
    'Обдумываю...',
    'Формирую...',
    'Синтезирую...',
  ];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _phraseTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (mounted) {
        setState(() {
          _phraseIndex = (_phraseIndex + 1) % _thinkingPhrases.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _phraseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Glowing pulsing icon
          RotationTransition(
            turns: Tween(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: VegaTheme.accent,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),

          // Shimmering Gradient Text with AnimatedSwitcher for phrase transitions
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              return ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: const [
                      Color(0xFF94A3B8), // Slate gray
                      Color(0xFFA855F7), // Purple
                      Color(0xFF38BDF8), // Cyan / Sky blue
                      Color(0xFFF43F5E), // Rose / Magenta
                      Color(0xFF94A3B8), // Slate gray
                    ],
                    stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                    begin: Alignment(-1.0 + (_shimmerController.value * 2.6), -0.2),
                    end: Alignment(1.0 + (_shimmerController.value * 2.6), 0.2),
                    tileMode: TileMode.clamp,
                  ).createShader(bounds);
                },
                child: child,
              );
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.2),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                _thinkingPhrases[_phraseIndex],
                key: ValueKey<int>(_phraseIndex),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
