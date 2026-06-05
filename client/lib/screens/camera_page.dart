import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/app_state.dart';
import '../utils/transitions.dart';
import 'editor_screen.dart';
import 'projects_screen.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  int _currentCameraIndex = 0;
  double _selectedZoom = 1.5;
  final List<double> _zoomLevels = [1.0, 1.5, 2, 4];
bool _isFlashOn = false;

  Future<void> _initializeCamera([int? cameraIndex]) async {
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
        await _cameraController?.dispose();

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

        // Set initial zoom level
        try {
          await _cameraController!.setZoomLevel(_selectedZoom);
        } catch (e) {
          debugPrint('Error setting initial zoom: $e');
        }

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Переключение камеры недоступно')),
        );
      }
      return;
    }

    // Отключаем вспышку перед переключением камеры
    if (_isFlashOn &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
        _isFlashOn = false;
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('Error turning off flash: $e');
      }
    }

    final newIndex = (_currentCameraIndex + 1) % _cameras!.length;
    await _initializeCamera(newIndex);
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      if (mounted) {
        // Store image in AppState
        context.read<AppState>().setCapturedImage(bytes);
        // Navigate to editor with slide transition
        Navigator.push(
          context,
          AppTransitions.slideRoute(
            const EditorScreen(),
            direction: SlideDirection.left,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  Future<void> _setZoom(double zoom) async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setZoomLevel(zoom);
      } catch (e) {
        debugPrint('Error setting zoom: $e');
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(
        _isFlashOn ? FlashMode.always : FlashMode.off,
      );
      setState(() {});
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    // Отключаем вспышку перед освобождением ресурсов
    if (_isFlashOn && _cameraController != null) {
      try {
        _cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('Error turning off flash in dispose: $e');
      }
    }
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C2C2E),
      body: Stack(
        children: [
          Positioned.fill(
            child: _isCameraInitialized && _cameraController != null
                ? CameraPreview(_cameraController!)
                : Container(color: const Color(0xFF2C2C2E)),
          ),
          Center(
            child: SizedBox(
              width: 80,
              height: 80,
              child: CustomPaint(painter: _FocusFramePainter()),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TopButton(
                    iconPath: 'assets/icons/Group_2977.png',
                    onTap: () async {
                      // Отключаем вспышку перед выходом
                      if (_isFlashOn &&
                          _cameraController != null &&
                          _cameraController!.value.isInitialized) {
                        try {
                          await _cameraController!.setFlashMode(FlashMode.off);
                          _isFlashOn = false;
                          if (mounted) setState(() {});
                        } catch (e) {
                          debugPrint('Error turning off flash: $e');
                        }
                      }
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.push(
                          context,
                          AppTransitions.fadeRoute(const ProjectsScreen()),
                        );
                      }
                    },
                  ),
                  _TopButton(
                    iconPath: 'assets/icons/Group_2976.png',
                    onTap: _toggleFlash,
                    isActive: _isFlashOn,
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: const Color(0xFF2C2C2E),
              padding: const EdgeInsets.only(bottom: 32, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ZoomSelector(
                    levels: _zoomLevels,
                    selected: _selectedZoom,
                    onSelect: (v) async {
                      setState(() => _selectedZoom = v);
                      await _setZoom(v);
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: _pickFromGallery,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Image.asset(
                              'assets/icons/Add_Image.png',
                              width: 26,
                              height: 26,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _takePicture,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF5A623),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFF5A623,
                                ).withValues(alpha: 0.45),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _switchCamera,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Image.asset(
                              'assets/icons/Rotate_Camera.png',
                              width: 26,
                              height: 26,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    PermissionStatus status;
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      status = await Permission.photos.request();
    } else {
      // Android: используем Permission.photos для Android 13+ (API 33+), иначе storage
      try {
        status = await Permission.photos.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      } catch (e) {
        // Если Permission.photos не поддерживается (Android <13), используем storage
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
      // Отключаем вспышку перед открытием галереи
      if (_isFlashOn &&
          _cameraController != null &&
          _cameraController!.value.isInitialized) {
        await _cameraController!.setFlashMode(FlashMode.off);
        _isFlashOn = false;
        if (mounted) setState(() {});
      }

      final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        debugPrint('Picked image from gallery: ${bytes.length} bytes');

        if (mounted) {
          // Store image in AppState
          context.read<AppState>().setCapturedImage(bytes);
          // Navigate to editor with slide transition
          Navigator.push(
            context,
            AppTransitions.slideRoute(
              const EditorScreen(),
              direction: SlideDirection.left,
            ),
          );
        }
      } else {
        debugPrint('No image selected from gallery');
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
}

class _TopButton extends StatelessWidget {
  final String iconPath;
  final VoidCallback? onTap;
  final bool isActive; // Новый параметр для состояния активности
  const _TopButton({
    required this.iconPath,
    this.onTap,
    this.isActive = false, // По умолчанию неактивно
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFFC107) : const Color(0xFF2A2A2A),
          shape: BoxShape.circle,
          border: isActive ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Center(
          child: Image.asset(
            iconPath,
            width: 22,
            height: 22,
            color: isActive ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ZoomSelector extends StatelessWidget {
  final List<double> levels;
  final double selected;
  final ValueChanged<double> onSelect;

  const _ZoomSelector({
    required this.levels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: levels.map((level) {
          final isSelected = level == selected;
          final label = level == level.truncateToDouble()
              ? '${level.toInt()}'
              : '$level';

          return GestureDetector(
            onTap: () => onSelect(level),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF3A3A3A)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${label}x',
                style: TextStyle(
                  color: isSelected ? const Color(0xFFF5A623) : Colors.white60,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FocusFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const cornerLen = 16.0;
    final w = size.width;
    final h = size.height;

    final paths = [
      [Offset(0, cornerLen), Offset(0, 0), Offset(cornerLen, 0)],
      [Offset(w - cornerLen, 0), Offset(w, 0), Offset(w, cornerLen)],
      [Offset(0, h - cornerLen), Offset(0, h), Offset(cornerLen, h)],
      [Offset(w - cornerLen, h), Offset(w, h), Offset(w, h - cornerLen)],
    ];

    for (final pts in paths) {
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
