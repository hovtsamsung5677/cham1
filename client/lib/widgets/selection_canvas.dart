import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/selection_tool.dart';

class SelectionCanvas extends StatefulWidget {
  final Uint8List imageBytes;
  final Uint8List selectionMask;
  final SelectionTool currentTool;
  final double brushSize;
  final List<Offset> lassoPoints;
  final List<List<int>> polygonPoints;
  final List<Offset> rectanglePoints;
  final List<Offset> boundaryPoints;
  final Function(Offset)? onBoundaryPoint;
  final VoidCallback? onBoundaryStart;
  final VoidCallback? onBoundaryEnd;
  final Function(Uint8List) onSelectionUpdate;
  final Function(List<Offset>) onLassoPointsUpdate;
  final Function(List<List<int>>) onPolygonPointsUpdate;
  final Function(List<Offset>) onRectanglePointsUpdate;
  final VoidCallback? onDrawingStart;
  final VoidCallback? onDrawingEnd;
  final Function(Offset)? onAutoSegmentTap;
  final bool isSegmentationModeActive;
  final Uint8List? aiMask;
  final List<Offset> positivePoints;
  final List<Offset> negativePoints;
  final Function(Offset)? onAiMaskTap;

  const SelectionCanvas({
    super.key,
    required this.imageBytes,
    required this.selectionMask,
    required this.currentTool,
    required this.brushSize,
    required this.lassoPoints,
    required this.polygonPoints,
    this.rectanglePoints = const [],
    this.boundaryPoints = const [],
    this.onBoundaryPoint,
    this.onBoundaryStart,
    this.onBoundaryEnd,
    required this.onSelectionUpdate,
    required this.onLassoPointsUpdate,
    required this.onPolygonPointsUpdate,
    required this.onRectanglePointsUpdate,
    this.onDrawingStart,
    this.onDrawingEnd,
    this.onAutoSegmentTap,
    this.isSegmentationModeActive = false,
    this.aiMask,
    this.positivePoints = const [],
    this.negativePoints = const [],
    this.onAiMaskTap,
  });

  @override
  State<SelectionCanvas> createState() => _SelectionCanvasState();
}

class _SelectionCanvasState extends State<SelectionCanvas> with TickerProviderStateMixin {
  ui.Image? _decodedImage;
  Size _imageSize = const Size(800, 600);

  double _currentScale = 1.0;
  double _targetScale = 1.0;
  Offset _currentOffset = Offset.zero;
  Offset _targetOffset = Offset.zero;
  Offset? _lastFocalPoint;
  double? _lastScale;
  int _currentPointerCount = 0;
  bool _isZooming = false;
  bool _isPanning = false;

  late AnimationController _selectionMaskController;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _selectionMaskController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _startSmoothZoomTicker();
  }

  @override
  void didUpdateWidget(SelectionCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageBytes != oldWidget.imageBytes) {
      _loadImage();
    }
    if (widget.selectionMask != oldWidget.selectionMask && widget.selectionMask.any((m) => m == 1)) {
      _selectionMaskController.forward(from: 0);
    }
    if (widget.aiMask != oldWidget.aiMask) {
      setState(() {});
    }
  }

  void _startSmoothZoomTicker() {
    createTicker((elapsed) {
      final scaleDiff = _targetScale - _currentScale;
      final offsetDiff = _targetOffset - _currentOffset;

      if (scaleDiff.abs() > 0.0001 || offsetDiff.distance > 0.01) {
        setState(() {
          _currentScale += scaleDiff * 0.15;
          _currentOffset += offsetDiff * 0.15;
        });
      } else if (_targetOffset != _currentOffset || _targetScale != _currentScale) {
        setState(() {
          _currentScale = _targetScale;
          _currentOffset = _targetOffset;
        });
      }
    })..start();
  }

  @override
  void dispose() {
    _selectionMaskController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decodedImage = frame.image;
          _imageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
        });
      }
    } catch (e) {
      debugPrint('Error loading image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) => _onTap(details.localPosition, constraints),
          onScaleStart: (details) => _onScaleStart(details),
          onScaleUpdate: (details) => _onScaleUpdate(details),
          onScaleEnd: (details) => _onScaleEnd(details),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              if (_decodedImage != null)
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _SelectionCanvasPainter(
                    image: _decodedImage,
                    selectionMask: widget.selectionMask,
                    imageSize: _imageSize,
                    currentScale: _currentScale,
                    currentOffset: _currentOffset,
                    isZooming: _isZooming,
                    isPanning: _isPanning,
                    maskAnimationValue: _selectionMaskController.value,
                    aiMask: widget.aiMask,
                    positivePoints: widget.positivePoints,
                    negativePoints: widget.negativePoints,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Offset _screenToImageCoordinates(Offset screenPosition, BoxConstraints constraints) {
    final size = Size(constraints.maxWidth, constraints.maxHeight);
    final aspectRatio = _imageSize.width / _imageSize.height;
    double baseWidth, baseHeight;

    if (size.width / size.height > aspectRatio) {
      baseHeight = size.height;
      baseWidth = baseHeight * aspectRatio;
    } else {
      baseWidth = size.width;
      baseHeight = baseWidth / aspectRatio;
    }

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final baseOffsetX = centerX - baseWidth / 2;
    final baseOffsetY = centerY - baseHeight / 2;

    final srcWidth = _imageSize.width / _currentScale;
    final srcHeight = _imageSize.height / _currentScale;

    final pixelsPerImageX = srcWidth / baseWidth;
    final pixelsPerImageY = srcHeight / baseHeight;

    final srcX = ((_imageSize.width - srcWidth) / 2 - _currentOffset.dx * pixelsPerImageX).clamp(0.0, _imageSize.width - srcWidth);
    final srcY = ((_imageSize.height - srcHeight) / 2 - _currentOffset.dy * pixelsPerImageY).clamp(0.0, _imageSize.height - srcHeight);

    final imageX = (srcX + (screenPosition.dx - baseOffsetX) / baseWidth * srcWidth).clamp(0.0, _imageSize.width.toDouble());
    final imageY = (srcY + (screenPosition.dy - baseOffsetY) / baseHeight * srcHeight).clamp(0.0, _imageSize.height.toDouble());

    return Offset(imageX.toDouble(), imageY.toDouble());
  }

  void _onTap(Offset position, BoxConstraints constraints) {
    final imagePos = _screenToImageCoordinates(position, constraints);

    // AI segmentation mode: first tap = positive point (create mask)
    // Subsequent taps ON the mask = negative point (exclude from mask)
    if (widget.isSegmentationModeActive) {
      if (widget.aiMask != null &&
          widget.aiMask!.isNotEmpty &&
          widget.onAiMaskTap != null) {
        final imgWidth = _imageSize.width.toInt();
        final imgHeight = _imageSize.height.toInt();
        final px = imagePos.dx.round().clamp(0, imgWidth - 1);
        final py = imagePos.dy.round().clamp(0, imgHeight - 1);
        final idx = py * imgWidth + px;
        if (idx < widget.aiMask!.length && widget.aiMask![idx] == 1) {
          widget.onAiMaskTap!(imagePos);
          return;
        }
      }

      if (widget.currentTool == SelectionTool.interactiveSegmentation &&
          widget.onAutoSegmentTap != null) {
        widget.onAutoSegmentTap!(imagePos);
      }
      return;
    }

    if (widget.currentTool == SelectionTool.interactiveSegmentation &&
        widget.onAutoSegmentTap != null) {
      widget.onAutoSegmentTap!(imagePos);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.focalPoint;
    _lastScale = _currentScale;
    _targetScale = _currentScale;
    _targetOffset = _currentOffset;

    if (details.pointerCount != 1) {
      setState(() {
        _isZooming = true;
        _isPanning = false;
      });
      return;
    }

    if (widget.currentTool == SelectionTool.hand) {
      setState(() {
        _isPanning = true;
        _isZooming = false;
      });
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _currentPointerCount = details.pointerCount;

    final bool nowZooming = _currentPointerCount != 1;
    if (nowZooming != _isZooming) {
      setState(() {
        _isZooming = nowZooming;
        if (_isZooming) {
          _isPanning = false;
        }
      });
    }

    if (widget.isSegmentationModeActive && _currentPointerCount != 1) {
      return;
    }

    if (_currentPointerCount == 1) {
      if (_isPanning) {
        final delta = details.focalPoint - _lastFocalPoint!;
        setState(() {
          _targetOffset += delta;
        });
        _lastFocalPoint = details.focalPoint;
      }
    } else {
      _lastScale ??= _currentScale;
      _lastFocalPoint ??= details.focalPoint;

      if (details.scale != 1.0) {
        final oldScale = _targetScale;
        _targetScale = (_lastScale! * details.scale).clamp(1.0, 3.0);

        if (oldScale != _targetScale && oldScale > 0) {
          final scaleChange = _targetScale / oldScale;
          final focalDelta = details.focalPoint - _lastFocalPoint!;
          _targetOffset = _targetOffset - focalDelta * (scaleChange - 1.0);
        }
      }

      if (details.focalPoint != _lastFocalPoint) {
        final delta = details.focalPoint - _lastFocalPoint!;
        _targetOffset += delta;
        _lastFocalPoint = details.focalPoint;
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isZooming) {
      setState(() {
        _isZooming = false;
      });
    }

    if (_isPanning) {
      setState(() {
        _isPanning = false;
      });
    }

    _lastFocalPoint = null;
    _lastScale = null;
    _currentPointerCount = 0;
  }
}

class _SelectionCanvasPainter extends CustomPainter {
  final ui.Image? image;
  final Uint8List selectionMask;
  final Size imageSize;
  final double currentScale;
  final Offset currentOffset;
  final bool isZooming;
  final bool isPanning;
  final double maskAnimationValue;
  final Uint8List? aiMask;
  final List<Offset> positivePoints;
  final List<Offset> negativePoints;

  _SelectionCanvasPainter({
    required this.image,
    required this.selectionMask,
    required this.imageSize,
    this.currentScale = 1.0,
    this.currentOffset = Offset.zero,
    this.isZooming = false,
    this.isPanning = false,
    this.maskAnimationValue = 0.0,
    this.aiMask,
    this.positivePoints = const [],
    this.negativePoints = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    if (image == null) return;

    final aspectRatio = imageSize.width / imageSize.height;
    double baseWidth, baseHeight;

    if (size.width / size.height > aspectRatio) {
      baseHeight = size.height;
      baseWidth = baseHeight * aspectRatio;
    } else {
      baseWidth = size.width;
      baseHeight = baseWidth / aspectRatio;
    }

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final baseOffsetX = centerX - baseWidth / 2;
    final baseOffsetY = centerY - baseHeight / 2;

    final srcWidth = imageSize.width / currentScale;
    final srcHeight = imageSize.height / currentScale;

    final pixelsPerImageX = srcWidth / baseWidth;
    final pixelsPerImageY = srcHeight / baseHeight;

    final srcX = ((imageSize.width - srcWidth) / 2 - currentOffset.dx * pixelsPerImageX).clamp(0.0, imageSize.width - srcWidth).toDouble();
    final srcY = ((imageSize.height - srcHeight) / 2 - currentOffset.dy * pixelsPerImageY).clamp(0.0, imageSize.height - srcHeight).toDouble();

    final imagePaint = Paint();
    canvas.drawImageRect(
      image!,
      Rect.fromLTWH(srcX, srcY, srcWidth, srcHeight),
      Rect.fromLTWH(baseOffsetX, baseOffsetY, baseWidth, baseHeight),
      imagePaint,
    );

    final scaleX = baseWidth / srcWidth;
    final scaleY = baseHeight / srcHeight;

    if (selectionMask.isNotEmpty) {
      _drawSelectionOverlay(
        canvas,
        size,
        baseOffsetX,
        baseOffsetY,
        baseWidth,
        baseHeight,
        scaleX,
        scaleY,
        srcX,
        srcY,
        srcWidth,
        srcHeight,
      );
    }
  }

  void _drawSelectionOverlay(
    Canvas canvas,
    Size size,
    double offsetX,
    double offsetY,
    double drawWidth,
    double drawHeight,
    double scaleX,
    double scaleY,
    double srcX,
    double srcY,
    double srcWidth,
    double srcHeight,
  ) {
    final imgWidth = imageSize.width.toInt();
    final imgHeight = imageSize.height.toInt();
    final visibleWidth = srcWidth;
    final visibleHeight = srcHeight;

    final overlayPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3 * (0.5 + 0.5 * maskAnimationValue))
      ..style = PaintingStyle.fill;

    for (int y = 0; y < imgHeight; y += 4) {
      if (y < srcY || y >= srcY + visibleHeight) continue;

      int x = 0;
      while (x < imgWidth) {
        if (x < srcX) {
          x++;
          continue;
        }
        if (x >= srcX + visibleWidth) break;

        while (x < imgWidth) {
          if (x >= srcX + visibleWidth) break;
          final idx = y * imgWidth + x;
          if (idx < selectionMask.length && selectionMask[idx] == 1) break;
          x++;
        }
        if (x >= imgWidth || x >= srcX + visibleWidth) break;
        int startX = x;
        while (x < imgWidth) {
          if (x >= srcX + visibleWidth) break;
          final idx = y * imgWidth + x;
          if (idx >= selectionMask.length || selectionMask[idx] != 1) break;
          x++;
        }
        int endX = x - 1;
        final screenX = offsetX + (startX - srcX) * scaleX;
        final screenY = offsetY + (y - srcY) * scaleY;
        final screenWidth = (endX - startX + 1) * scaleX;
        final screenHeight = scaleY * 4;
        canvas.drawRect(
          Rect.fromLTWH(screenX, screenY, screenWidth, screenHeight),
          overlayPaint,
        );
      }
    }

    for (int x = 0; x < imgWidth; x += 4) {
      if (x < srcX || x >= srcX + visibleWidth) continue;

      int y = 0;
      while (y < imgHeight) {
        if (y < srcY) {
          y++;
          continue;
        }
        if (y >= srcY + visibleHeight) break;

        while (y < imgHeight) {
          if (y >= srcY + visibleHeight) break;
          final idx = y * imgWidth + x;
          if (idx < selectionMask.length && selectionMask[idx] == 1) break;
          y++;
        }
        if (y >= imgHeight || y >= srcY + visibleHeight) break;
        int startY = y;
        while (y < imgHeight) {
          if (y >= srcY + visibleHeight) break;
          final idx = y * imgWidth + x;
          if (idx >= selectionMask.length || selectionMask[idx] != 1) break;
          y++;
        }
        int endY = y - 1;
        final screenX = offsetX + (x - srcX) * scaleX;
        final screenY = offsetY + (startY - srcY) * scaleY;
        final screenWidth = scaleX * 4;
        final screenHeight = (endY - startY + 1) * scaleY;
        canvas.drawRect(
          Rect.fromLTWH(screenX, screenY, screenWidth, screenHeight),
          overlayPaint,
        );
      }
    }

    // Draw AI mask overlay (light blue transparent)
    if (aiMask != null && aiMask!.isNotEmpty) {
      final aiMaskPaint = Paint()
        ..color = const Color(0xFF6495ED).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      for (int y = 0; y < imgHeight; y += 4) {
        if (y < srcY || y >= srcY + visibleHeight) continue;
        int x = 0;
        while (x < imgWidth) {
          if (x < srcX) { x++; continue; }
          if (x >= srcX + visibleWidth) break;
          while (x < imgWidth) {
            if (x >= srcX + visibleWidth) break;
            final idx = y * imgWidth + x;
            if (idx < aiMask!.length && aiMask![idx] == 1) break;
            x++;
          }
          if (x >= imgWidth || x >= srcX + visibleWidth) break;
          int startX = x;
          while (x < imgWidth) {
            if (x >= srcX + visibleWidth) break;
            final idx = y * imgWidth + x;
            if (idx >= aiMask!.length || aiMask![idx] != 1) break;
            x++;
          }
          int endX = x - 1;
          final screenX = offsetX + (startX - srcX) * scaleX;
          final screenY = offsetY + (y - srcY) * scaleY;
          final screenWidth = (endX - startX + 1) * scaleX;
          final screenHeight = scaleY * 4;
          canvas.drawRect(
            Rect.fromLTWH(screenX, screenY, screenWidth, screenHeight),
            aiMaskPaint,
          );
        }
      }

      // Draw positive points (green)
      final greenDotPaint = Paint()
        ..color = const Color(0xFF4CAF50)
        ..style = PaintingStyle.fill;
      for (final point in positivePoints) {
        final screenX = offsetX + (point.dx - srcX) * scaleX;
        final screenY = offsetY + (point.dy - srcY) * scaleY;
        canvas.drawCircle(Offset(screenX, screenY), 8.0, greenDotPaint);
        canvas.drawCircle(Offset(screenX, screenY), 8.0, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0);
      }

      // Draw negative points (red)
      final redDotPaint = Paint()
        ..color = const Color(0xFFF44336)
        ..style = PaintingStyle.fill;
      for (final point in negativePoints) {
        final screenX = offsetX + (point.dx - srcX) * scaleX;
        final screenY = offsetY + (point.dy - srcY) * scaleY;
        canvas.drawCircle(Offset(screenX, screenY), 8.0, redDotPaint);
        canvas.drawCircle(Offset(screenX, screenY), 8.0, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionCanvasPainter oldDelegate) {
    return image != oldDelegate.image ||
        selectionMask != oldDelegate.selectionMask ||
        imageSize != oldDelegate.imageSize ||
        currentScale != oldDelegate.currentScale ||
        currentOffset != oldDelegate.currentOffset ||
        isZooming != oldDelegate.isZooming ||
        isPanning != oldDelegate.isPanning ||
        maskAnimationValue != oldDelegate.maskAnimationValue ||
        aiMask != oldDelegate.aiMask ||
        positivePoints != oldDelegate.positivePoints ||
        negativePoints != oldDelegate.negativePoints;
  }
}