import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../utils/transitions.dart';
import 'camera_page.dart';
import 'editor_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  // ImagePicker does not need explicit dispose() — it's a lightweight wrapper
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E0A),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 1.2,
                colors: [Color(0xFF3D1F10), Color(0xFF1A0E0A)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _circleIconBtn(
                        'assets/icons/Vector.png',
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ваши проекты',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Ваши предметы для перекраски',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _circleIconBtn('assets/icons/Love.png'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Projects grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Consumer<AppState>(
                      builder: (context, appState, child) {
                        final projects = appState.sortedProjects;
                        if (projects.isEmpty) {
                          return const Center(
                            child: Text(
                              'Нет проектов',
                              style: TextStyle(color: Colors.white54),
                            ),
                          );
                        }
                        return GridView.builder(
                          itemCount: projects.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.85,
                              ),
                          itemBuilder: (context, index) {
                            final project = projects[index];
                            return GestureDetector(
                              onTap: () {
                                // Open project in editor
                                appState.setCapturedImage(project.imageBytes);
                                Navigator.push(
                                  context,
                                  AppTransitions.slideRoute(
                                    const EditorScreen(),
                                    direction: SlideDirection.left,
                                  ),
                                );
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.memory(
                                      project.imageBytes,
                                      fit: BoxFit.cover,
                                    ),
                                    // Like button
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: GestureDetector(
                                        onTap: () => appState.toggleProjectLike(
                                          project.id,
                                        ),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: project.liked
                                                ? Colors.red
                                                : Colors.black38,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(7),
                                            child: Image.asset(
                                              'assets/icons/Love.png',
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                // Bottom buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            // Set stage to camera before navigating
                            Provider.of<AppState>(
                              context,
                              listen: false,
                            ).setStage(AppStage.camera);
                            Navigator.push(
                              context,
                              AppTransitions.slideRoute(
                                const CameraPage(),
                                direction: SlideDirection.left,
                              ),
                            );
                          },
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5C518),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: const Center(
                              child: Text(
                                'Сделать фото',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _pickFromGallery,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Image.asset(
                              'assets/icons/Add_Image.png',
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();

        if (mounted) {
          // Store image in AppState and navigate to editor
          context.read<AppState>().setCapturedImage(bytes);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')),
        );
      }
    }
  }

  Widget _circleIconBtn(String asset, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: Colors.white12,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset(asset, color: Colors.white),
        ),
      ),
    );
  }
}
