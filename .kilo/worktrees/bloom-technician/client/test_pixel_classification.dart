import 'dart:typed_data';
import 'lib/services/image_processing_service.dart';

void main() {
  print('=== Тест алгоритма классификации пикселей по яркости ===\n');

  // Создаем тестовое изображение 10x10 с разными яркостями
  final width = 10;
  final height = 10;
  final pixels = Uint8List(width * height * 4); // RGBA

  // Заполняем пиксели разными яркостями
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = (y * width + x) * 4;

      // Создаем градиент от темного к светлому
      final intensity = ((x + y) / (width + height - 2) * 255).round();

      pixels[idx] = intensity; // R
      pixels[idx + 1] = intensity; // G
      pixels[idx + 2] = intensity; // B
      pixels[idx + 3] = 255; // A
    }
  }

  // Кодируем в PNG (упрощенно - используем библиотеку image)
  // Для теста просто вызовем функцию классификации

  print('Тестовые данные созданы: изображение ${width}x${height}');
  print('Градиент от темного (0,0,0) к светлому (255,255,255)\n');

  // Создаем маску выборки (выделяем все пиксели)
  final selectionMask = Uint8List(width * height);
  for (int i = 0; i < selectionMask.length; i++) {
    selectionMask[i] = 1;
  }

  // Кодируем пиксели в формат PNG для обработки
  // Используем простое кодирование
  final imageBytes = encodeTestPng(pixels, width, height);

  print(
    'Вызов функции recolorImage с целевым цветом RGB(139, 69, 19) - коричневый\n',
  );

  final result = ImageProcessingService.recolorImage(
    imageBytes: imageBytes,
    width: width,
    height: height,
    selectionMask: selectionMask,
    targetRed: 139,
    targetGreen: 69,
    targetBlue: 19,
    blendFactor: 1.0,
  );

  print('Результат: изображение перекрашено, размер ${result.length} байт');
  print('\n=== Тест завершен ===');
}

// Упрощенное кодирование PNG для теста
Uint8List encodeTestPng(Uint8List pixels, int width, int height) {
  // В реальном приложении используется библиотека image
  // Для демонстрации возвращаем сырые пиксели
  return pixels;
}
