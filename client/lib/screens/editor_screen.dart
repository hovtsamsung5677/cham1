import 'dart:async';
import 'dart:convert';
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

// ============================================================================
//  НОРМАЛИЗАЦИЯ PNG МАСКИ В ДВОИЧНУЮ (сервер возвращает grayscale PNG)
// ============================================================================
Future<Uint8List?> _normalizePngMaskToBinary(List<dynamic> args) async {
  final Uint8List pngBytes = args[0] as Uint8List;
  print('📥 [normalize] Получено ${pngBytes.length} байт PNG');

  try {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    print('📐 [normalize] Размер маски: $width x $height');

    // Используем rawRgba для получения пиксельных данных
    final byteData = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      print('❌ [normalize] byteData == null');
      return null;
    }

    final pixels = byteData.buffer.asUint8List();
    final result = Uint8List(width * height);

    int whiteCount = 0;
    // rawRgba даёт RGBA (4 байта на пиксель), сервер возвращает grayscale
    for (int i = 0; i < result.length; i++) {
      final idx = i * 4;
      final r = pixels[idx];
      result[i] = r > 128 ? 1 : 0;
      if (result[i] == 1) whiteCount++;
    }

    print(
      '✅ [normalize] Белых пикселей в маске: $whiteCount из ${width * height}',
    );
    return result;
  } catch (e) {
    print('❌ [normalize] Ошибка: $e');
    return null;
  }
}

// ============================================================================
//  АНАЛИЗ ЯРКОСТИ (БЕЗ ИЗМЕНЕНИЙ)
// ============================================================================
Future<Map<String, dynamic>?> _analyzeSelectionBrightnessStatic(
  List<dynamic> args,
) async {
  final Uint8List imageBytes = args[0] as Uint8List;
  final Uint8List analysisMask = args[1] as Uint8List;

  if (imageBytes == null || analysisMask.isEmpty) {
    return null;
  }

  try {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;

    if (analysisMask.length != width * height) {
      return null;
    }

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final pixels = byteData.buffer.asUint8List();

    int darkPixelCount = 0;
    int brightPixelCount = 0;
    int mediumPixelCount = 0;
    int totalSelectedPixels = 0;

    double totalValue = 0;
    double totalRed = 0;
    double totalGreen = 0;
    double totalBlue = 0;

    for (int i = 0; i < analysisMask.length; i++) {
      if (analysisMask[i] == 1) {
        final pixelIndex = i * 4;
        if (pixelIndex + 3 >= pixels.length) continue;

        final r = pixels[pixelIndex];
        final g = pixels[pixelIndex + 1];
        final b = pixels[pixelIndex + 2];

        final hsv = ImageProcessingService.rgbToHsv(r, g, b);
        final value = hsv[2];

        totalValue += value;
        totalRed += r;
        totalGreen += g;
        totalBlue += b;
        totalSelectedPixels++;

        if (value < ImageProcessingService.darkThreshold) {
          darkPixelCount++;
        } else if (value > ImageProcessingService.brightThreshold) {
          brightPixelCount++;
        } else {
          mediumPixelCount++;
        }
      }
    }

    if (totalSelectedPixels == 0) return null;

    final avgValue = totalValue / totalSelectedPixels;
    final meanR = (totalRed / totalSelectedPixels).round();
    final meanG = (totalGreen / totalSelectedPixels).round();
    final meanB = (totalBlue / totalSelectedPixels).round();

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

    return {
      'dominantType': dominantType,
      'meanR': meanR,
      'meanG': meanG,
      'meanB': meanB,
      'colorThreshold': 100,
    };
  } catch (e) {
    return null;
  }
}

// ============================================================================
//  ОСНОВНОЙ ВИДЖЕТ РЕДАКТОРА
// ============================================================================
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

  // AI segmentation state
  Uint8List? _currentAiMask;
  final List<Offset> _segPositivePoints = [];
  final List<Offset> _segNegativePoints = [];

  // Base64 strings from /get-mask response
  String? _currentMaskB64;
  String? _currentPreviewB64;

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

                if (_currentAiMask != null) {
                  print(
                    '🖼️ [build] _currentAiMask не null, длина: ${_currentAiMask!.length}',
                  );
                } else {
                  print('🖼️ [build] _currentAiMask == null');
                }

                return RepaintBoundary(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.basic,
                    child: SelectionCanvas(
                      key: const ValueKey('selection_canvas'),
                      imageBytes: displayBytes!,
                      selectionMask:
                          (appState.isPreviewMode &&
                              appState.previewImage != null)
                          ? Uint8List(0)
                          : appState.selectionMask,
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
                      aiMask: _currentAiMask,
                      positivePoints: _segPositivePoints,
                      negativePoints: _segNegativePoints,
                      onAiMaskTap: _handleAiMaskExclusionTap,
                    ),
                  ),
                );
              },
            ),
          ),
          // Top toolbar
          _EditorTopToolbar(
            onBackToCamera: () => _onBackToCamera(context),
            onUndo: () => context.read<AppState>().undo(),
            onRedo: () => context.read<AppState>().redo(),
            onGoHome: () => Navigator.push(
              context,
              AppTransitions.fadeRoute(const ProjectsScreen()),
            ),
          ),
          // Bottom panel
          _buildBottomPanel(),
        ],
      ),
    );
  }

  // ==========================================================================
  //  BOTTOM PANEL
  // ==========================================================================
  Widget _buildBottomPanel() {
    final appState = context.watch<AppState>();
    final editorState = appState.editorScreenState;

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

            // State-dependent content
            if (editorState == EditorScreenState.idle) ...[
              _buildAutoSegmentationFAB(),
              const SizedBox(height: 10),
              const Text(
                'Нажмите на объект для выделения',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ] else if (editorState == EditorScreenState.maskPreview) ...[
              const Text(
                'Это выделенный объект. Выберите цвет и параметры.',
                style: TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MaskConfirmButton(
                    label: 'Выглядит верно',
                    icon: Icons.check_circle,
                    color: Colors.green,
                    onTap: _confirmMask,
                  ),
                  const SizedBox(width: 16),
                  _MaskConfirmButton(
                    label: 'Выбрать заново',
                    icon: Icons.close,
                    color: Colors.red,
                    onTap: _resetMask,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildAutoSegmentationFAB(),
            ] else if (editorState == EditorScreenState.paramsSelect) ...[
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
                    child: Icon(
                      Icons.brush,
                      size: 26,
                      color: Colors.white,
                    ),
                    label: 'Блеск',
                    onTap: () => _showGlossSlider(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _GlossIndicator(gloss: appState.glossLevel),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _runAiRecolor,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Перекрасить',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ] else if (editorState == EditorScreenState.recoloring) ...[
              const CircularProgressIndicator(color: Color(0xFFFFC107)),
              const SizedBox(height: 8),
              const Text(
                'Перекрашиваем...',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // AUTO-SEGMENTATION FAB
  // ==========================================================================
  Widget _buildAutoSegmentationFAB() {
    final bool isActive = _isSegmentationModeActive;
    final appState = context.watch<AppState>();
    final editorState = appState.editorScreenState;

    return SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentAiMask != null && editorState == EditorScreenState.idle) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _currentAiMask = null;
                  _segPositivePoints.clear();
                  _segNegativePoints.clear();
                  context.read<AppState>().setAiMask(null);
                });
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFF44336),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(height: 10),
          ],
          AnimatedBuilder(
            animation: _fabPulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _fabPulseAnimation.value,
                child: child,
              );
            },
            child: GestureDetector(
              onTap: () {
                if (editorState == EditorScreenState.maskPreview) {
                  _resetMask();
                  setState(() {
                    _isSegmentationModeActive = true;
                  });
                  return;
                }
                setState(() {
                  _isSegmentationModeActive = !_isSegmentationModeActive;
                  if (!_isSegmentationModeActive) {
                    _currentAiMask = null;
                    _segPositivePoints.clear();
                    _segNegativePoints.clear();
                    context.read<AppState>().setAiMask(null);
                  }
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
                            color: const Color(
                              0xFFFFC107,
                            ).withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.transparent,
                            blurRadius: 0,
                            spreadRadius: 0,
                          ),
                        ],
                ),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 200),
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Opacity(opacity: value, child: child);
                  },
                  child: const Center(
                    child: Icon(
                      Icons.center_focus_strong,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  //  ОБРАБОТЧИК АВТОСЕГМЕНТАЦИИ (ДОБАВЛЕНЫ PRINT)
  // ==========================================================================
  Future<void> _handleAutoSegmentation(Offset imagePosition) async {
    final appState = context.read<AppState>();

    if (appState.isLoading) {
      print('⏳ [seg] Уже идёт загрузка, пропускаем');
      return;
    }

    print(
      '👆 [seg] Тап по координатам: ${imagePosition.dx.round()}, ${imagePosition.dy.round()}',
    );
    appState.setLoading(true);

    try {
      final imageBytes = appState.capturedImage;
      if (imageBytes == null) {
        print('❌ [seg] Нет изображения');
        return;
      }

      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final int imageWidth = frame.image.width;
      final int imageHeight = frame.image.height;
      print('📐 [seg] Размер изображения: $imageWidth x $imageHeight');

      setState(() {
        _segPositivePoints.add(imagePosition);
        _segNegativePoints.clear();
        print(
          '➕ [seg] Добавлена положительная точка, всего: ${_segPositivePoints.length}',
        );
      });

      print('📤 [seg] Отправка запроса к серверу...');
      final maskResponse = await _segmentationService.getMask(
        imageBytes: imageBytes,
        positivePoint: imagePosition,
        negativePoints: const [],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );

      print(
        '📥 [seg] Получен ответ, maskResponse = ${maskResponse != null ? "not null" : "null"}',
      );

      if (mounted && maskResponse != null) {
        final maskB64 = maskResponse['mask'];
        final previewB64 = maskResponse['preview'];

        if (maskB64 != null && previewB64 != null) {
          final maskBytes = base64Decode(maskB64);
          final previewBytes = base64Decode(previewB64);

          print('🔄 [seg] Запуск нормализации через compute...');
          final normalizedMask = await compute(_normalizePngMaskToBinary, [
            maskBytes,
          ]);

          if (normalizedMask != null) {
            print('✅ [seg] Маска нормализована, длина: ${normalizedMask.length}');
            int ones = normalizedMask.where((v) => v == 1).length;
            print('🔢 [seg] Количество единиц в маске: $ones');
            setState(() {
              _currentAiMask = normalizedMask;
              _currentMaskB64 = maskB64;
              _currentPreviewB64 = previewB64;
              print('🔄 [seg] setState: _currentAiMask установлен');
            });
            appState.setAiMask(normalizedMask);
            appState.setAiMaskPreview(previewBytes);
            appState.setEditorScreenState(EditorScreenState.maskPreview);
          } else {
            print('❌ [seg] normalize вернул null');
          }
        } else {
          print('❌ [seg] mask или preview отсутствуют в ответе');
        }
      } else {
        print('❌ [seg] maskResponse == null или mounted == false');
      }
    } catch (e) {
      print('❌ [seg] Ошибка: $e');
    } finally {
      appState.setLoading(false);
    }
  }

  // ==========================================================================
  //  ОБРАБОТЧИК ДОБАВЛЕНИЯ ОТРИЦАТЕЛЬНЫХ ТОЧЕК
  // ==========================================================================
  Future<void> _handleAiMaskExclusionTap(Offset imagePosition) async {
    final appState = context.read<AppState>();

    if (appState.isLoading) return;

    appState.setLoading(true);

    try {
      final imageBytes = appState.capturedImage;
      if (imageBytes == null) return;

      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final int imageWidth = frame.image.width;
      final int imageHeight = frame.image.height;

      setState(() {
        _segNegativePoints.add(imagePosition);
      });

      final maskResponse = await _segmentationService.getMask(
        imageBytes: imageBytes,
        positivePoint: _segPositivePoints.first,
        negativePoints: _segNegativePoints,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );

      if (mounted && maskResponse != null) {
        final maskB64 = maskResponse['mask'];
        final previewB64 = maskResponse['preview'];

        if (maskB64 != null && previewB64 != null) {
          final maskBytes = base64Decode(maskB64);
          final previewBytes = base64Decode(previewB64);

          final normalizedMask = await compute(_normalizePngMaskToBinary, [
            maskBytes,
          ]);
          if (normalizedMask != null) {
            setState(() {
              _currentAiMask = normalizedMask;
              _currentMaskB64 = maskB64;
              _currentPreviewB64 = previewB64;
            });
            appState.setAiMask(normalizedMask);
            appState.setAiMaskPreview(previewBytes);
          }
        }
      }
    } catch (e) {
      debugPrint('Ошибка обновления маски: $e');
    } finally {
      appState.setLoading(false);
    }
  }

  // ==========================================================================
  //  AI ПЕРЕКРАСКА
  // ==========================================================================
  Future<void> _runAiRecolor() async {
    final appState = context.read<AppState>();

    if (appState.isLoading) return;
    final maskToUse = appState.confirmedAiMask ?? _currentAiMask;
    if (maskToUse == null || _segPositivePoints.isEmpty) return;

    appState.setLoading(true);
    appState.setEditorScreenState(EditorScreenState.recoloring);

    try {
      final imageBytes = appState.capturedImage;
      if (imageBytes == null) return;

      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final int imageWidth = frame.image.width;
      final int imageHeight = frame.image.height;

      final resultBytes = await _segmentationService.segmentObject(
        imageBytes: imageBytes,
        imagePosition: _segPositivePoints.first,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        material: appState.selectedMaterial,
        colorHex: appState.selectedColor.value,
        gloss: appState.glossLevel,
        strength: 1.0,
      );

      if (mounted && resultBytes != null) {
        appState.setPreviewImage(resultBytes);
        if (!appState.isPreviewMode) appState.togglePreviewMode();
        appState.addProject(resultBytes);
        appState.setEditorScreenState(EditorScreenState.result);
        if (mounted) {
          Navigator.push(
            context,
            AppTransitions.slideRoute(
              const ExportScreen(),
              direction: SlideDirection.up,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ошибка AI перекраски')));
        appState.setEditorScreenState(EditorScreenState.paramsSelect);
      }
    } catch (e) {
      debugPrint('Ошибка AI: $e');
      appState.setEditorScreenState(EditorScreenState.paramsSelect);
    } finally {
      appState.setLoading(false);
    }
  }

  void _confirmMask() {
    final appState = context.read<AppState>();
    setState(() {
      appState.setConfirmedAiMask(_currentAiMask);
      appState.setPreviewImage(null);
      appState.setIsPreviewMode(false);
      _isSegmentationModeActive = false;
      appState.setEditorScreenState(EditorScreenState.paramsSelect);
    });
  }

  void _resetMask() {
    final appState = context.read<AppState>();
    setState(() {
      _currentAiMask = null;
      _currentMaskB64 = null;
      _currentPreviewB64 = null;
      _segPositivePoints.clear();
      _segNegativePoints.clear();
      _isSegmentationModeActive = false;
      appState.setAiMask(null);
      appState.setAiMaskPreview(null);
      appState.setConfirmedAiMask(null);
      appState.setEditorScreenState(EditorScreenState.idle);
    });
  }

  // ==========================================================================
  //  ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ (БЕЗ ИЗМЕНЕНИЙ)
  // ==========================================================================
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

  Future<Map<String, dynamic>?> _analyzeSelectionBrightness({
    Uint8List? mask,
  }) async {
    final appState = context.read<AppState>();
    final imageBytes = appState.capturedImage;
    final analysisMask = mask ?? appState.selectionMask;
    if (imageBytes == null || analysisMask.isEmpty) {
      debugPrint('[BrightnessAnalysis] Нет выделенной области для анализа');
      return null;
    }
    try {
      final result = await compute(_analyzeSelectionBrightnessStatic, [
        imageBytes,
        analysisMask,
      ]);
      if (result == null) {
        debugPrint('[BrightnessAnalysis] Ошибка анализа');
      }
      return result;
    } catch (e) {
      debugPrint('[BrightnessAnalysis] Ошибка анализа: $e');
      return null;
    }
  }

  void _showColorPicker(BuildContext context) async {
    final appState = context.read<AppState>();
    final editorState = appState.editorScreenState;
    await Navigator.push(
      context,
      AppTransitions.fadeRoute(
        ColorPickerScreen(
          initialColor: appState.selectedColor,
          onColorChanged: (color) {
            appState.setSelectedColor(color);
            if (editorState != EditorScreenState.paramsSelect &&
                editorState != EditorScreenState.maskPreview) {
              _applyLiveRecoloring(context, color);
            }
          },
        ),
      ),
    );
    if (mounted && appState.isPreviewMode && appState.previewImage == null) {
      appState.togglePreviewMode();
    }
  }

  void _showGlossSlider(BuildContext context) {
    final appState = context.read<AppState>();
    double tempGloss = appState.glossLevel;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2C2C2E),
          title: const Text(
            'Уровень блеска',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tempGloss <= 0.0
                    ? 'Без блеска'
                    : tempGloss < 0.3
                        ? 'Матовый'
                        : tempGloss < 0.6
                            ? 'Полуматовый'
                            : tempGloss < 0.8
                                ? 'Полуглянцевый'
                                : 'Глянцевый',
                style: const TextStyle(color: Colors.white70),
              ),
              Slider(
                value: tempGloss,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                activeColor: const Color(0xFFFFC107),
                label: '${(tempGloss * 100).round()}%',
                onChanged: (value) {
                  setDialogState(() {
                    tempGloss = value;
                  });
                },
                onChangeEnd: (value) {
                  appState.setGlossLevel(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(color: Color(0xFFFFC107)),
              ),
            ),
          ],
        ),
      ),
    );
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
      final useOverlay =
          dominantType == 'bright' ||
          dominantType == 'medium' ||
          dominantType == 'mixed';

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
      AppTransitions.fadeRoute(const ColorPaletteScreen()),
    );
    if (!mounted) return;
    if (result != null) {
      appState.setSelectedColor(result);
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

// ============================================================================
//  ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ (БЕЗ ИЗМЕНЕНИЙ)
// ============================================================================
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

class _MaskConfirmButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MaskConfirmButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlossIndicator extends StatelessWidget {
  final double gloss;

  const _GlossIndicator({required this.gloss});

  @override
  Widget build(BuildContext context) {
    final label = gloss <= 0.0
        ? 'Без блеска'
        : gloss < 0.3
            ? 'Матовый'
            : gloss < 0.6
                ? 'Полуматовый'
                : gloss < 0.8
                    ? 'Полуглянцевый'
                    : 'Глянцевый';
    return Text(
      'Блеск: ${label} (${(gloss * 100).round()}%)',
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }
}

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

// ============================================================================
//  ISOLATE HELPER ДЛЯ ПЕРЕКРАСКИ
// ============================================================================
Uint8List _recolorIsolateFunction(_RecolorParams params) {
  if (params.useScreenFilter) {
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
