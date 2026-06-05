import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../utils/transitions.dart';
import 'projects_screen.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  // Флаг удержания кнопки сравнения
  bool _isCompareHeld = false;

  @override
  Widget build(BuildContext context) {
    // Use context.select to only rebuild when these specific values change
    final capturedImage = context.select<AppState, Uint8List?>(
      (s) => s.capturedImage,
    );
    final previewImage = context.select<AppState, Uint8List?>(
      (s) => s.previewImage,
    );
    // При удержании показываем оригинал, иначе перекрашенное
    final displayImage = _isCompareHeld
        ? capturedImage
        : (previewImage ?? capturedImage);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Результат'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          GestureDetector(
            onTap: () {
              // Clear state and go to projects
              context.read<AppState>().setCapturedImage(null);
              Navigator.pushAndRemoveUntil(
                context,
                AppTransitions.fadeRoute(const ProjectsScreen()),
                (route) => false,
              );
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                color: Colors.white12,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Image.asset(
                  'assets/icons/Group_2977.png',
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: displayImage != null
                ? Center(
                    child: Image.memory(
                      displayImage,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  )
                : const Center(
                    child: Text(
                      'Нет изображения',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
          ),
          Container(
            color: const Color(0xFF1C1C1E),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Кнопка сравнения "До/После"
                _buildCompareButton(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveImage(context, displayImage),
                    icon: const Icon(Icons.download, size: 24),
                    label: const Text(
                      'Скачать',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5C518),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => _shareImage(context, displayImage),
                    icon: const Icon(Icons.share, size: 24),
                    label: const Text(
                      'Отправить',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF404040),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompareButton() {
    // Only rebuild when these specific values change
    final hasOriginal =
        context.select<AppState, Uint8List?>((s) => s.capturedImage) != null;
    final hasRecolored =
        context.select<AppState, Uint8List?>((s) => s.previewImage) != null;

    // Если нет обоих изображений, не показываем кнопку
    if (!hasOriginal || !hasRecolored) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: GestureDetector(
        // Обработка нажатия и удержания
        onTapDown: (_) => setState(() => _isCompareHeld = true),
        onTapUp: (_) => setState(() => _isCompareHeld = false),
        onTapCancel: () => setState(() => _isCompareHeld = false),
        // Также поддерживаем long press для удобства
        onLongPressStart: (_) => setState(() => _isCompareHeld = true),
        onLongPressEnd: (_) => setState(() => _isCompareHeld = false),
        child: Container(
          decoration: BoxDecoration(
            color: _isCompareHeld
                ? const Color(0xFFFFC107)
                : const Color(0xFF404040),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _isCompareHeld ? Colors.white : Colors.grey,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.compare_arrows, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                _isCompareHeld ? 'Оригинал' : 'Перекраска',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveImage(BuildContext context, Uint8List? imageBytes) async {
    if (imageBytes == null) return;

    try {
      if (Platform.isAndroid) {
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Требуется разрешение для сохранения'),
              ),
            );
          }
          return;
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'recolored_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Фото сохранено: $fileName')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    }
  }

  Future<void> _shareImage(BuildContext context, Uint8List? imageBytes) async {
    if (imageBytes == null) return;

    try {
      final directory = await getTemporaryDirectory();
      final fileName =
          'recolored_share_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Посмотри на моё перекрашенное фото!');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка отправки: $e')));
      }
    }
  }
}
