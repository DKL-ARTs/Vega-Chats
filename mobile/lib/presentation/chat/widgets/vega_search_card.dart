import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme.dart';

class VegaSearchCard extends StatefulWidget {
  final String query;
  final List<String> sources;
  final String? executionTime;
  final bool isSearching;

  const VegaSearchCard({
    super.key,
    required this.query,
    this.sources = const [],
    this.executionTime,
    this.isSearching = false,
  });

  @override
  State<VegaSearchCard> createState() => _VegaSearchCardState();
}

class _VegaSearchCardState extends State<VegaSearchCard> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _cleanDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst(RegExp(r'^www\.'), '');
    } catch (_) {
      return url.split('/').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanQuery = widget.query.replaceAll('"', '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Animated Magnifying Glass Icon (Animated Pulse/Scale)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: ScaleTransition(
                      scale: Tween(begin: 0.88, end: 1.15).animate(
                        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFFA855F7),
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Header Title
                  Expanded(
                    child: Row(
                      children: [
                        const Text(
                          'Vega Search',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget.isSearching)
                          const Text(
                            '•  Ищу в сети...',
                            style: TextStyle(color: Color(0xFFA855F7), fontSize: 12, fontStyle: FontStyle.italic),
                          )
                        else if (widget.sources.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.sources.length} источников',
                                  style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Execution time badge
                  if (widget.executionTime != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${widget.executionTime}',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                      ),
                    ),

                  // Expand Chevron Icon
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Details Section
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.05)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  // Query line
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.search_rounded, color: Color(0xFFA855F7), size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Запрос: "$cleanQuery"',
                          style: const TextStyle(
                            color: VegaTheme.textPrimary,
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Sources list if available
                  if (widget.sources.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'ИСТОЧНИКИ (${widget.sources.length}):',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.sources.map((src) {
                        final domain = _cleanDomain(src);
                        return InkWell(
                          onTap: () async {
                            try {
                              final uri = Uri.parse(src.startsWith('http') ? src : 'https://$src');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            } catch (_) {}
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.public_rounded, color: Color(0xFFA855F7), size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  domain,
                                  style: const TextStyle(
                                    color: Color(0xFFC4B5FD),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
