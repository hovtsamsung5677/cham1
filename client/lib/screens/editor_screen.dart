import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/selection_tool.dart';
import '../widgets/selection_canvas.dart';
import '../services/image_processing_service.dart';
import '../services/segmentation_service.dart';
import 'package:image/image.dart' as img;
import 'color_picker_screen.dart';
import 'color_palette_screen.dart';
import '../utils/transitions.dart';
import 'camera_page.dart';
import 'export_screen.dart';
import 'projects_screen.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with TickerProviderStateMixin {
  // Local state
  SelectionTool _selectedTool = SelectionTool.interactiveSegmentation;
  final double _brushSize = 30;

  // Segmentation service
  late final SegmentationService _segmentationService;

  // FAB animation
  late AnimationController _fabPulseController;
  late Animation<double> _fabPulseAnimation;

  // State for segmentation mode (toggle)
  bool _isSegmentationModeActive = false;

  @override
  void initState() {
    super.initState();
    _segmentationService = SegmentationService();
    _fabPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _fabPulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _fabPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _segmentationService.dispose();
    _fabPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C2C2E),
      body: Stack(
        children: [
          // Canvas area — isolated rebuild scope via RepaintBoundary
          Positioned.fill(
            bottom: 220,
            child: Consumer<AppState>(
              builder: (context, appState, child) {
                final imageBytes = appState.capturedImage;
                final previewBytes = appState.previewImage;
                final displayBytes = previewBytes ?? imageBytes;
                
                if (imageBytes == null) {
                  return const _EmptyCanvasPlaceholder();
}

static Future<Map<String, dynamic>?> _analyzeSelectionBrightnessStatic(List<dynamic> args) async {
  final Uint8List imageBytes = args[0] as Uint8List;
  final Uint8List analysisMask = args[1] as Uint8List;

  if (imageBytes == null || analysisMask.isEmpty) {
    debugPrint('[BrightnessAnalysis] Нет выделенной области для анализа');
    return null;
  }

  try {
    // Декодируем изображение
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;

    if (analysisMask.length != width * height) {
      debugPrint(
        '[BrightnessAnalysis] Размер маски не совпадает с размером изображения',
      );
      return null;
    }

    // Получаем байты изображения для анализа
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      debugPrint(
        '[BrightnessAnalysis] Не удалось получить данные изображения',
      );
      return null;
    }

    final pixels = byteData.buffer.asUint8List();

    // Статистика яркости и цвета
    int darkPixelCount = 0;
    int brightPixelCount = 0;
    int mediumPixelCount = 0;
    int totalSelectedPixels = 0;

    double totalValue = 0;
    double totalRed = 0;
    double totalGreen = 0;
    double totalBlue = 0;

    // Проходим по всем пикселям маски
    for (int i = 0; i < analysisMask.length; i++) {
      if (analysisMask[i] == 1) {
        final pixelIndex = i * 4;
        if (pixelIndex + 3 >= pixels.length) continue;

        final r = pixels[pixelIndex];
        final g = pixels[pixelIndex + 1];
        final b = pixels[pixelIndex + 2];

        // Конвертируем в HSV для получения яркости (Value)
        final hsv = ImageProcessingService.rgbToHsv(r, g, b);
        final value = hsv[2]; // 0.0 - 1.0

        totalValue += value;
        totalRed += r;
        totalGreen += g;
        totalBlue += b;
        totalSelectedPixels++;

        // Классифицируем пиксель
        if (value < ImageProcessingService.darkThreshold) {
          darkPixelCount++;
        } else if (value > ImageProcessingService.brightThreshold) {
          brightPixelCount++;
        } else {
          mediumPixelCount++;
        }
      }
    }

    if (totalSelectedPixels == 0) {
      debugPrint('[BrightnessAnalysis] Нет выделенных пикселей');
      return null;
    }

    // Вычисляем средние значения
    final avgValue = totalValue / totalSelectedPixels;
    final meanR = (totalRed / totalSelectedPixels).round();
    final meanG = (totalGreen / totalSelectedPixels).round();
    final meanB = (totalBlue / totalSelectedPixels).round();

    final darkPercent = (darkPixelCount * 100 / totalSelectedPixels).round();
    final brightPercent = (brightPixelCount * 100 / totalSelectedPixels)
        .round();
    final mediumPercent = (mediumPixelCount * 100 / totalSelectedPixels)
        .round();

    // Определяем доминирующий тип пикселей
    String dominantType;
    if (darkPixelCount > brightPixelCount &&
        darkPixelCount > mediumPixelCount) {
      dominantType = 'dark';
    } else if (brightPixelCount > darkPixelCount &&
        brightPixelCount > mediumPixelCount) {
      dominantType = 'bright';
    } else if (mediumPixelCount > darkPixelCount &&
        mediumPixelCount > brightPixelCount) {
      dominantType = 'medium';
    } else {
      dominantType = 'mixed';
    }

    // Выводим подробный отчёт
    print('\n' + '=' * 60);
    print('  АНАЛИЗ ВЫДЕЛЕННОЙ ОБЛАСТИ');
    print('=' * 60);
    print('Доминирующий тип: $dominantType');
    print('Средняя яркость: ${(avgValue * 100).toStringAsFixed(1)}%');
    print(
      'Распределение: тёмные=${darkPercent}%, средние=${mediumPercent}%, яркие=${brightPercent}%',
    );
    print('Всего пикселей: $totalSelectedPixels');
    print('=' * 60);
    print('');

    // Порог цветового расстояния для фильтрации (в RGB пространстве 0-255)
    // Установлено в 100 - баланс между скоростью и точностью
    // Позволяет обрабатывать маску быстро, отфильтровывая сильно отличающиеся пиксели
    final colorThreshold = 100;

    return {
      'dominantType': dominantType,
      'meanR': meanR,
      'meanG': meanG,
      'meanB': meanB,
      'colorThreshold': colorThreshold,
    };
  } catch (e) {
    debugPrint('[BrightnessAnalysis] Ошибка анализа: $e');
    return null;
  }
}
                return RepaintBoundary(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.basic,
                    child: SelectionCanvas(
                      key: const ValueKey('selection_canvas'),
                      imageBytes: displayBytes!,
                      selectionMask: (appState.isPreviewMode && appState.previewImage != null) ? Uint8List(0) : appState.selectionMask,
                      currentTool: _selectedTool,
                      brushSize: _brushSize,
                      lassoPoints: const [],
                      polygonPoints: const [],
                      rectanglePoints: const [],
                      boundaryPoints: const [],
                      onSelectionUpdate: appState.setSelectionMask,
                      onLassoPointsUpdate: (_) {},
                      onPolygonPointsUpdate: (_) {},
                      onRectanglePointsUpdate: (_) {},
                      onBoundaryStart: null,
                      onBoundaryPoint: null,
                      onBoundaryEnd: null,
                      onDrawingStart: () {},
                      onDrawingEnd: () {},
                      onAutoSegmentTap:
                          _selectedTool ==
                                  SelectionTool.interactiveSegmentation &&
                              _isSegmentationModeActive
                          ? _handleAutoSegmentation
                          : null,
                      isSegmentationModeActive: _isSegmentationModeActive,
                    ),
                  ),
                );
              },
            ),
          ),

// Top toolbar — extracted to own widget to avoid canvas rebuilds
          _EditorTopToolbar(
            onBackToCamera: () => _onBackToCamera(context),
            onUndo: () => context.read<AppState>().undo(),
            onRedo: () => context.read<AppState>().redo(),
            onGoHome: () => Navigator.push(
              context,
              AppTransitions.fadeRoute(const ProjectsScreen()),
            ),
          ),

          // Bottom panel — state method for direct access to stateful FAB
          _buildBottomPanel(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomPanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // Central FAB for auto-segmentation
            _buildAutoSegmentationFAB(),
            const SizedBox(height: 30),

            // Bottom actions row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BottomAction(
                  child: const _ColorPreviewWidget(),
                  label: 'Цвет',
                  onTap: () => _showColorPicker(context),
                ),
                const SizedBox(width: 24),
                _BottomAction(
                  child: const _IconAssetWidget(
                    assetPath: 'assets/icons/Squared_Menu.png',
                    size: 26,
                  ),
                  label: 'Палитра',
                  onTap: () => _showColorPalette(context),
                ),
                const SizedBox(width: 24),
                _BottomAction(
                  child: const _IconAssetWidget(
                    assetPath: 'assets/icons/Eye.png',
                    size: 26,
                  ),
                  label: 'Превью',
                  onTap: () => _applyRecoloring(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-SEGMENTATION FAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAutoSegmentationFAB() {
    final bool isActive = _isSegmentationModeActive;

    return AnimatedBuilder(
      animation: _fabPulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _fabPulseAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isSegmentationModeActive = !_isSegmentationModeActive;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? const Color(0xFFFFC107) : Colors.grey,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFC107).withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ]
                : [],
          ),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 200),
            tween: Tween(begin: 0.0, end: 1.0),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Opacity(opacity: value, child: child);
            },
            child: Center(
              child: Image.asset(
                'assets/icons/Hand Cursor.png',
                width: 32,
                height: 32,
                color: isActive ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEGMENTATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Обрабатывает клик для авто-сегментации объекта с AI-перекраской.
  Future<void> _handleAutoSegmentation(Offset imagePosition) async {
    final appState = context.read<AppState>();

    if (appState.isLoading) {
      return;
    }

    appState.setLoading(true);

    try {
      final imageBytes = appState.capturedImage;
      if (imageBytes == null) return;

      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final int imageWidth = frame.image.width;
      final int imageHeight = frame.image.height;

      // AI recolor - получаем готовую картинку
      final resultBytes = await _segmentationService.segmentObject(
        imageBytes: imageBytes,
        imagePosition: imagePosition,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        material: appState.selectedMaterial,
        colorHex: appState.selectedColor.value,
        strength: 1.0,
      );

      if (mounted && resultBytes != null) {
        appState.setPreviewImage(resultBytes);
        if (!appState.isPreviewMode) appState.togglePreviewMode();
        _showSuccessSnackBar(context, 'Объект перекрашен');
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ошибка AI перекраски')));
      }
    } catch (e) {
      debugPrint('Ошибка AI: $e');
    } finally {
      appState.setLoading(false);
    }
  }

  /// Показывает красивое уведомление об успешной сегментации
  /// Стиль соответствует дизайну приложения (тёмная тема, акцентный цвет)
  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: const Color(0xFFFFC107), size: 20),
            const SizedBox(width: 8),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2C2C2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        duration: const Duration(seconds: 2),
        elevation: 4,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BRIGHTNESS ANALYSIS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Анализирует выделенную область и определяет её яркость и цветовые характеристики
  /// Возвращает Map с ключами:
  ///   - 'dominantType': 'dark', 'bright', 'medium', 'mixed'
  ///   - 'meanR', 'meanG', 'meanB': средний цвет
  ///   - 'colorThreshold': порог цветового расстояния для фильтрации
  Future<Map<String, dynamic>?> _analyzeSelectionBrightness({Uint8List? mask}) async {
    final appState = context.read<AppState>();
    final imageBytes = appState.capturedImage;
    final analysisMask = mask ?? appState.selectionMask;
    if (imageBytes == null || analysisMask.isEmpty) {
      debugPrint('[BrightnessAnalysis] Нет выделенной области для анализа');
      return null;
    }
    try {
      final result = await compute(
        _analyzeSelectionBrightnessStatic,
        [imageBytes, analysisMask],
      );
      if (result == null) {
        debugPrint('[BrightnessAnalysis] Ошибка анализа');
      }
      return result;
    } catch (e) {
      debugPrint('[BrightnessAnalysis] Ошибка анализа: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NAVIGATION / ACTION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showColorPicker(BuildContext context) async {
    final appState = context.read<AppState>();
    await Navigator.push(
      context,
      AppTransitions.fadeRoute(
        ColorPickerScreen(
          initialColor: appState.selectedColor,
          onColorChanged: (color) {
            appState.setSelectedColor(color);
            _applyLiveRecoloring(context, color);
          },
        ),
      ),
    );
    if (mounted && appState.isPreviewMode && appState.previewImage == null) {
      appState.togglePreviewMode();
    }
  }

  Future<void> _applyLiveRecoloring(BuildContext context, Color color) async {
    final appState = context.read<AppState>();
    final imageBytes = appState.capturedImage;
    final mask = appState.selectionMask;

    if (imageBytes == null || mask.isEmpty || !mask.any((m) => m == 1)) {
      return;
    }

    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;

      final r = (color.r * 255.0).round().clamp(0, 255);
      final g = (color.g * 255.0).round().clamp(0, 255);
      final b = (color.b * 255.0).round().clamp(0, 255);

      final analysisResult = await _analyzeSelectionBrightness();

      if (analysisResult == null) return;

      final dominantType = analysisResult['dominantType'] as String;
      final meanR = analysisResult['meanR'] as int;
      final meanG = analysisResult['meanG'] as int;
      final meanB = analysisResult['meanB'] as int;
      final colorThreshold = analysisResult['colorThreshold'] as int;

      final useScreenFilter = dominantType == 'dark';
      final useOverlay = dominantType == 'bright' || dominantType == 'medium' || dominantType == 'mixed';

      Uint8List? textureBytes;
      if (appState.selectedWoodTexture != null) {
        try {
          final byteData = await rootBundle.load('assets/textures/${appState.selectedWoodTexture}.png');
          textureBytes = byteData.buffer.asUint8List();
        } catch (e) {
          debugPrint('Error loading wood texture: $e');
        }
      } else if (appState.selectedMetalTexture != null) {
        try {
          final byteData = await rootBundle.load('assets/textures/${appState.selectedMetalTexture}.png');
          textureBytes = byteData.buffer.asUint8List();
        } catch (e) {
          debugPrint('Error loading metal texture: $e');
        }
      }

      final result = await compute(
        _recolorIsolateFunction,
        _RecolorParams(
          imageBytes: imageBytes,
          width: width,
          height: height,
          mask: mask,
          targetRed: r,
          targetGreen: g,
          targetBlue: b,
          woodTextureBytes: textureBytes,
          useScreenFilter: useScreenFilter,
          useOverlay: useOverlay,
          meanR: meanR,
          meanG: meanG,
          meanB: meanB,
          colorThreshold: colorThreshold,
          blendFactor: 1.0,
        ),
      );

      if (mounted) {
        appState.setPreviewImage(result);
        if (!appState.isPreviewMode) {
          appState.togglePreviewMode();
        }
      }
    } catch (e) {
      debugPrint('Live recolor error: $e');
    }
  }

  void _showColorPalette(BuildContext context) async {
    final appState = context.read<AppState>();
    final result = await Navigator.push(
      context,
      AppTransitions.fadeRoute(
        const ColorPaletteScreen(),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      appState.setSelectedColor(result);
      _applyRecoloring(context);
    }
  }

  Future<void> _applyRecoloring(BuildContext context) async {
    final appState = context.read<AppState>();
    final imageBytes = appState.capturedImage;
    final mask = appState.selectionMask;

    if (imageBytes == null || mask.isEmpty || !mask.any((m) => m == 1)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сначала выделите область для перекраски'),
          ),
        );
      }
      return;
    }

    // Анализируем яркость и цвет выделенной области для выбора метода перекраски
    final analysisResult = await _analyzeSelectionBrightness();

    if (analysisResult == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось проанализировать выделенную область'),
          ),
        );
      }
      return;
    }

    final dominantType = analysisResult['dominantType'] as String;
    final meanR = analysisResult['meanR'] as int;
    final meanG = analysisResult['meanG'] as int;
    final meanB = analysisResult['meanB'] as int;
    final colorThreshold = analysisResult['colorThreshold'] as int;

    // Определяем, какой метод перекраски использовать
    // Если доминируют тёмные пиксели → SCREEN фильтр для всех
    // Если доминируют яркие/средние → OVERLAY для всех
    final useScreenFilter = dominantType == 'dark';
    final useOverlay =
        dominantType == 'bright' ||
        dominantType == 'medium' ||
        dominantType == 'mixed';

    appState.setLoading(true);

    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;

      final color = appState.selectedColor;
      final r = (color.r * 255.0).round().clamp(0, 255);
      final g = (color.g * 255.0).round().clamp(0, 255);
      final b = (color.b * 255.0).round().clamp(0, 255);

      Uint8List? textureBytes;
      if (appState.selectedWoodTexture != null) {
        try {
          final byteData = await rootBundle.load(
            'assets/textures/${appState.selectedWoodTexture}.png',
          );
          textureBytes = byteData.buffer.asUint8List();
        } catch (e) {
          debugPrint('Error loading wood texture: $e');
        }
      } else if (appState.selectedMetalTexture != null) {
        try {
          final byteData = await rootBundle.load(
            'assets/textures/${appState.selectedMetalTexture}.png',
          );
          textureBytes = byteData.buffer.asUint8List();
        } catch (e) {
          debugPrint('Error loading metal texture: $e');
        }
      }

      final result = await compute(
        _recolorIsolateFunction,
        _RecolorParams(
          imageBytes: imageBytes,
          width: width,
          height: height,
          mask: mask,
          targetRed: r,
          targetGreen: g,
          targetBlue: b,
          woodTextureBytes: textureBytes,
          useScreenFilter: useScreenFilter,
          useOverlay: useOverlay,
          meanR: meanR,
          meanG: meanG,
          meanB: meanB,
          colorThreshold: colorThreshold,
          blendFactor: 1.0,
        ),
      );

      appState.setPreviewImage(result);
      if (!appState.isPreviewMode) appState.togglePreviewMode();
      appState.setLoading(false);
      appState.addProject(result);

      if (mounted) {
        Navigator.push(
          context,
          AppTransitions.slideRoute(
            const ExportScreen(),
            direction: SlideDirection.up,
          ),
        );
      }
    } catch (e) {
      appState.setLoading(false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INLINE TOOLBAR HELPERS (called from _EditorTopToolbar via context.read)
  // ═══════════════════════════════════════════════════════════════════════════

  void _onBackToCamera(BuildContext context) {
    final appState = context.read<AppState>();
    appState.setCapturedImage(null);
    appState.resetSelection();
    appState.setStage(AppStage.camera);
    Navigator.pushReplacement(
      context,
      AppTransitions.fadeRoute(const CameraPage()),
    );
  }

  void _toggleTool() {
    setState(() {
      _selectedTool = _selectedTool == SelectionTool.hand
          ? SelectionTool.interactiveSegmentation
          : SelectionTool.hand;
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXTRACTED WIDGETS — isolated rebuild scopes
// ═══════════════════════════════════════════════════════════════════════════════

/// Placeholder shown when no image is captured — const widget, never rebuilds
class _EmptyCanvasPlaceholder extends StatelessWidget {
  const _EmptyCanvasPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: const Center(
        child: Icon(Icons.image, color: Colors.white24, size: 80),
      ),
    );
  }
}

/// Top toolbar — separate widget so it never triggers canvas rebuilds
class _EditorTopToolbar extends StatelessWidget {
  final VoidCallback onBackToCamera;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onGoHome;

  const _EditorTopToolbar({
    required this.onBackToCamera,
    required this.onUndo,
    required this.onRedo,
    required this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _TopIconBtn('assets/icons/Vector.png', onTap: onBackToCamera),
            _TopSysBtn(Icons.undo, onTap: onUndo),
            _TopSysBtn(Icons.redo, onTap: onRedo),
            _TopSysBtn(Icons.home, filled: true, onTap: onGoHome),
          ],
        ),
      ),
    );
  }
}

/// Icon button for the top toolbar
class _TopIconBtn extends StatelessWidget {
  final String assetPath;
  final VoidCallback onTap;

  const _TopIconBtn(this.assetPath, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Image.asset(
          assetPath,
          width: 24,
          height: 24,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// System icon button for the top toolbar
class _TopSysBtn extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _TopSysBtn(this.icon, {this.filled = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: filled ? Colors.white24 : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

/// Color preview circle — only rebuilds when selectedColor changes
class _ColorPreviewWidget extends StatelessWidget {
  const _ColorPreviewWidget();

  @override
  Widget build(BuildContext context) {
    final color = context.select<AppState, Color>((s) => s.selectedColor);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Reusable asset icon widget
class _IconAssetWidget extends StatelessWidget {
  final String assetPath;
  final double size;

  const _IconAssetWidget({required this.assetPath, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(assetPath, color: Colors.white),
    );
  }
}

/// Bottom action button with icon and label
class _BottomAction extends StatelessWidget {
  final Widget child;
  final String label;
  final VoidCallback onTap;

  const _BottomAction({
    required this.child,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ISOLATE HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

// Helper for isolate recoloring
Uint8List _recolorIsolateFunction(_RecolorParams params) {
  // Choose method based on brightness analysis
  if (params.useScreenFilter) {
    // Use SCREEN filter for all pixels (for dark-dominant objects)
    return ImageProcessingService.recolorAllWithScreen(
      imageBytes: params.imageBytes,
      width: params.width,
      height: params.height,
      selectionMask: params.mask,
      targetRed: params.targetRed,
      targetGreen: params.targetGreen,
      targetBlue: params.targetBlue,
      woodTextureBytes: params.woodTextureBytes,
      blendFactor: params.blendFactor,
    );
  } else if (params.useOverlay) {
    // Use OVERLAY from grayscale for bright/medium objects
    // Converts to grayscale first (preserves texture), then applies overlay color
    return ImageProcessingService.recolorBrightWithOverlayFromGrayscale(
      imageBytes: params.imageBytes,
      width: params.width,
      height: params.height,
      selectionMask: params.mask,
      targetRed: params.targetRed,
      targetGreen: params.targetGreen,
      targetBlue: params.targetBlue,
      blendFactor: params.blendFactor,
      woodTextureBytes: params.woodTextureBytes,
    );
  } else {
    // Fallback to standard mixed method
    return ImageProcessingService.recolorImage(
      imageBytes: params.imageBytes,
      width: params.width,
      height: params.height,
      selectionMask: params.mask,
      targetRed: params.targetRed,
      targetGreen: params.targetGreen,
      targetBlue: params.targetBlue,
      woodTextureBytes: params.woodTextureBytes,
    );
  }
}

class _RecolorParams {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final Uint8List mask;
  final int targetRed;
  final int targetGreen;
  final int targetBlue;
  final Uint8List? woodTextureBytes;
  final bool useScreenFilter;
  final bool useOverlay;
  final int meanR;
  final int meanG;
  final int meanB;
  final int colorThreshold;
  final double blendFactor;

  _RecolorParams({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.mask,
    required this.targetRed,
    required this.targetGreen,
    required this.targetBlue,
    this.woodTextureBytes,
    this.useScreenFilter = false,
    this.useOverlay = false,
    required this.meanR,
    required this.meanG,
    required this.meanB,
    required this.colorThreshold,
    this.blendFactor = 1.0,
  });
}
