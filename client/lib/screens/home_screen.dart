import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show compute, defaultTargetPlatform, TargetPlatform;
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/image_processing_service.dart';
import '../widgets/selection_canvas.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/tool_bar.dart';
import '../utils/transitions.dart';

/// Main home screen with camera and editor
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  final ImagePicker _picker = ImagePicker();
  int _currentCameraIndex = 0;

  // Selection variables
  List<Offset> _lassoPoints = [];
  List<List<int>> _polygonPoints = [];
  List<Offset> _rectanglePoints = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera([int? cameraIndex]) async {
    // Request camera permission
    PermissionStatus cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Камера требует разрешения')),
        );
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Dispose existing controller if any
        await _cameraController?.dispose();

        // Use specified index or default to 0
        final index = cameraIndex ?? _currentCameraIndex;
        if (index >= _cameras!.length) {
          _currentCameraIndex = 0;
        } else {
          _currentCameraIndex = index;
        }

        _cameraController = CameraController(
          _cameras![_currentCameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка камеры: $e')));
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) {
      // Show snackbar if no front camera available
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Переключение камеры недоступно')),
        );
      }
      return;
    }

    // Switch to the other camera
    final newIndex = (_currentCameraIndex + 1) % _cameras!.length;
    await _initializeCamera(newIndex);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    // ImagePicker не требует явного dispose — это легковесная обёртка
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      if (mounted) {
        context.read<AppState>().setCapturedImage(bytes);
        context.read<AppState>().setStage(AppStage.editor);
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    // Request storage/photos permission with Android 13+ support
    PermissionStatus status;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      status = await Permission.photos.request();
    } else {
      // Android: try photos permission first (Android 13+), fallback to storage
      try {
        status = await Permission.photos.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      } catch (e) {
        // If Permission.photos not supported (Android <13), use storage
        status = await Permission.storage.request();
      }
    }
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Требуется разрешение доступа к галерее'),
          ),
        );
      }
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();

        if (mounted) {
          context.read<AppState>().setCapturedImage(bytes);
          context.read<AppState>().setStage(AppStage.editor);
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Перекраска мебели'),
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            actions: [
              if (appState.currentStage == AppStage.editor)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    // Go back to camera to take new photo
                    appState.setStage(AppStage.camera);
                    // Clear the captured image so camera view will show fresh
                    appState.setCapturedImage(null);
                    appState.resetSelection();
                    // Re-initialize camera when going back
                    _initializeCamera();
                  },
                  tooltip: 'Вернуться к камере',
                ),
            ],
          ),
          body: _buildBody(appState),
        );
      },
    );
  }

  Widget _buildBody(AppState appState) {
    switch (appState.currentStage) {
      case AppStage.camera:
        return _buildCameraView(appState);
      case AppStage.editor:
        return _buildEditorView(appState);
      case AppStage.colorPicker:
        return _buildEditorView(appState); // Keep editor in background
    }
  }

  Widget _buildCameraView(AppState appState) {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        CameraPreview(_cameraController!),

        // Bottom controls
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Camera switch button
              IconButton(
                icon: const Icon(Icons.flip_camera_ios, size: 40),
                color: Colors.white,
                onPressed: _switchCamera,
              ),

              // Capture button
              GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              // Gallery button
              IconButton(
                icon: const Icon(Icons.photo_library, size: 40),
                color: Colors.white,
                onPressed: _pickFromGallery,
              ),
            ],
          ),
        ),

        // Instructions
        Positioned(
          top: 20,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Сделайте фото мебели, которую хотите перекрасить',
              style: TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorView(AppState appState) {
    // Show preview image if in preview mode, otherwise show original
    final imageBytes = appState.isPreviewMode && appState.previewImage != null
        ? appState.previewImage!
        : appState.capturedImage;

    if (imageBytes == null) {
      return const Center(
        child: Text('Нет изображения', style: TextStyle(color: Colors.white)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Image canvas with selection tools (hide selection UI in preview mode)
        SelectionCanvas(
          imageBytes: imageBytes,
          selectionMask: appState.isPreviewMode
              ? Uint8List(0)
              : appState.selectionMask,
          currentTool: appState.currentTool,
          brushSize: appState.brushSize,
          lassoPoints: appState.isPreviewMode ? [] : _lassoPoints,
          polygonPoints: appState.isPreviewMode ? [] : _polygonPoints,
          rectanglePoints: appState.isPreviewMode ? [] : _rectanglePoints,
          onSelectionUpdate: appState.isPreviewMode
              ? (_) {}
              : (mask) {
                  appState.setSelectionMask(mask);
                },
          onLassoPointsUpdate: (points) {
            _lassoPoints = points;
          },
          onPolygonPointsUpdate: (points) {
            _polygonPoints = points;
          },
          onRectanglePointsUpdate: (points) {
            _rectanglePoints = points;
          },
        ),

        // Bottom toolbar with tools
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ToolBarWidget(
            currentTool: appState.currentTool,
            brushSize: appState.brushSize,
            onToolChanged: (tool) {
              appState.setCurrentTool(tool);
              _lassoPoints = [];
              _polygonPoints = [];
              _rectanglePoints = [];
            },
            onBrushSizeChanged: (size) {
              appState.setBrushSize(size);
            },
            onColorPick: () => _showColorPicker(appState),
            onPreview: () => _applyRecoloring(appState),
            onReset: () {
              appState.resetSelection();
              _lassoPoints = [];
              _polygonPoints = [];
              _rectanglePoints = [];
            },
            onUndo: () => appState.undo(),
            onRedo: () => appState.redo(),
            onSave: () => Navigator.pushNamed(context, '/export'),
            onCancelPreview: () {
              appState.togglePreviewMode();
              appState.setPreviewImage(null);
            },
            hasSelection: appState.selectionMask.any((m) => m == 1),
            isPreviewMode: appState.isPreviewMode,
            selectedColor: appState.selectedColor,
          ),
        ),

        // Loading screen (same as splash screen during processing)
        if (appState.isLoading)
          FadeAnimatedWidget(
            visible: true,
            duration: const Duration(milliseconds: 200),
            child: Container(
              color: Theme.of(context).colorScheme.background,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 800),
                  tween: Tween(begin: 0.8, end: 1.0),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Opacity(opacity: value, child: child);
                  },
                  child: Image.asset(
                    'assets/logo/logotip.png',
                    width: 200,
                    height: 200,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showColorPicker(AppState appState) {
    showDialog(
      context: context,
      builder: (context) => ColorPickerDialog(
        initialColor: appState.selectedColor,
        onColorSelected: (color) {
          appState.setSelectedColor(color);
          Navigator.of(context).pop();
          // Start recoloring process
          _applyRecoloring(appState);
        },
        onColorChanged: (color) {
          // Обновляем выбранный цвет
          appState.setSelectedColor(color);
        },
      ),
    );
  }

  Future<void> _applyRecoloring(AppState appState) async {
    final imageBytes = appState.capturedImage;
    final mask = appState.selectionMask;

    if (imageBytes == null || mask.isEmpty || !mask.any((m) => m == 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала выделите область для перекраски'),
        ),
      );
      return;
    }

    appState.setLoading(true);

    try {
      // Decode image to get actual dimensions
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;

      final color = appState.selectedColor;
      final r = color.red;
      final g = color.green;
      final b = color.blue;

      // Apply recoloring using compute for performance
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
          useScreenFilter: const bool.fromEnvironment(
            'USE_SCREEN_FILTER',
            defaultValue: false,
          ),
          blendFactor: 1.0,
        ),
      );

      appState.setPreviewImage(result);
      // Only toggle preview mode if not already in preview
      if (!appState.isPreviewMode) {
        appState.togglePreviewMode();
      }

      // Navigate to export screen after recoloring completes
      if (mounted) {
        await Navigator.pushNamed(context, '/export');
      }
    } catch (e) {
      debugPrint('Recoloring error: $e');
      appState.setError('Ошибка перекраски: $e');
    } finally {
      appState.setLoading(false);
    }
  }

  static Uint8List _recolorIsolateFunction(_RecolorParams params) {
    // Check if we should use screen filter for dark pixels only
    if (params.useScreenFilter) {
      return ImageProcessingService.recolorDarkPixelsWithScreen(
        imageBytes: params.imageBytes,
        width: params.width,
        height: params.height,
        selectionMask: params.mask,
        targetRed: params.targetRed,
        targetGreen: params.targetGreen,
        targetBlue: params.targetBlue,
        blendFactor: params.blendFactor,
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

  // _saveImage removed — unused stub
}

/// Parameters for isolate computation
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
    this.blendFactor = 1.0,
  });
}
