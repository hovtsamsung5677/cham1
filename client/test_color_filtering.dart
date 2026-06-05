import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'lib/services/image_processing_service.dart';

void main() {
  print('=== Тест цветовой фильтрации маски ===\n');

  final width = 10;
  final height = 10;
  final image = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      if ((x == 5 && y == 5) || (x == 3 && y == 7)) {
        image.setPixelRgb(x, y, 0, 0, 255);
      } else if (x == 8 && y == 2) {
        image.setPixelRgb(x, y, 0, 255, 0);
      } else {
        image.setPixelRgb(x, y, 200, 50, 50);
      }
    }
  }

  final imageBytes = Uint8List.fromList(img.encodePng(image));
  final mask = Uint8List(width * height);
  for (int i = 0; i < mask.length; i++) {
    mask[i] = 1;
  }

  print(
    'Изображение: ${width}x${height}, выделено: ${mask.where((v) => v == 1).length} пикселей',
  );
  print(
    'Основной цвет: RGB(200,50,50), outliers: (5,5)=blue, (3,7)=blue, (8,2)=green\n',
  );

  final filteredMask = ImageProcessingService.filterMaskByColorTolerance(
    imageBytes: imageBytes,
    width: width,
    height: height,
    currentMask: mask,
    avgR: 200,
    avgG: 50,
    avgB: 50,
    tolerance: 50,
  );

  final filteredCount = filteredMask.where((v) => v == 1).length;
  print('\nРезультат: осталось $filteredCount пикселей');
  if (filteredCount == 97) {
    print('✅ ТЕСТ ПРОЙДЕН: удалено 3 outlier-пикселя');
  } else {
    print('❌ ТЕСТ НЕ ПРОЙДЕН: ожидалось 97, получено $filteredCount');
  }
}
