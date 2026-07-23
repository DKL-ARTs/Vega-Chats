import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file_plus/open_file_plus.dart';

class FullScreenImageViewer extends StatefulWidget {
  final String? imagePath;
  final String? base64Data;
  final String? imageUrl;
  final String? title;

  const FullScreenImageViewer({
    super.key,
    this.imagePath,
    this.base64Data,
    this.imageUrl,
    this.title,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late TransformationController _transformationController;
  TapDownDetails? _doubleTapDetails;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transformationController.value = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (widget.base64Data != null && widget.base64Data!.isNotEmpty) {
      imageWidget = Image.memory(
        base64Decode(widget.base64Data!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
              SizedBox(height: 12),
              Text('Не удалось загрузить изображение', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    } else if (widget.imagePath != null && widget.imagePath!.isNotEmpty) {
      imageWidget = Image.file(
        File(widget.imagePath!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
              SizedBox(height: 12),
              Text('Файл изображения не найден', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      imageWidget = Image.network(
        widget.imageUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
              SizedBox(height: 12),
              Text('Не удалось загрузить URL', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    } else {
      imageWidget = const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
      );
    }

    final titleText = widget.title ??
        (widget.imagePath != null ? widget.imagePath!.split('/').last : 'Просмотр изображения');

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,
        child: Stack(
          children: [
            // Center Image with InteractiveViewer for zoom/pan
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.8,
                maxScale: 5.0,
                child: Center(child: imageWidget),
              ),
            ),

            // Top Animated Controls Bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _showControls ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  bottom: 12,
                  left: 12,
                  right: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titleText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.imagePath != null && widget.imagePath!.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                        tooltip: 'Открыть с помощью',
                        onPressed: () {
                          OpenFile.open(widget.imagePath!);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showImageViewer(
  BuildContext context, {
  String? imagePath,
  String? base64Data,
  String? imageUrl,
  String? title,
}) {
  Navigator.push(
    context,
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black,
      pageBuilder: (BuildContext context, _, __) {
        return FullScreenImageViewer(
          imagePath: imagePath,
          base64Data: base64Data,
          imageUrl: imageUrl,
          title: title,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    ),
  );
}
