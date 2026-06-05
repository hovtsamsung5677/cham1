import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'lib/services/image_processing_service.dart';

void main() {
  print('=== Тест аддитивной селекции (сохранения предыдущей маски) ===\n');

  final width = 10;
  final height = 10;
  final image = img.Image(width: width, height: height);

  // Объект 1: левая половина - красный
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < 5; x++) {
      image.setPixelRgb(x, y, 200, 50, 50);
    }
  }
  // Объект 2: правая половина - зелёный
  for (int y = 0; y < height; y++) {
    for (int x = 5; x < 10; x++) {
      image.setPixelRgb(x, y, 50, 200, 50);
    }
  }

  final imageBytes = Uint8List.fromList(img.encodePng(image));

  // Первая маска: выделяем левую половину (все 50 пикселей)
  final mask1 = Uint8List(width * height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < 5; x++) {
      mask1[y * width + x] = 1;
    }
  }

  // Вторая маска: выделяем правую половину (все 50 пикселей)
  final mask2 = Uint8List(width * height);
  for (int y = 0; y < height; y++) {
    for (int x = 5; x < 10; x++) {
      mask2[y * width + x] = 1;
    }
  }

  print(
    'Объект 1: левая половина (красный), пикселей: ${mask1.where((v) => v == 1).length}',
  );
  print(
    'Объект 2: правая половина (зелёный), пикселей: ${mask2.where((v) => v == 1).length}',
  );

  // Фильтрация для объекта 1 (красный)
  final filtered1 = ImageProcessingService.filterMaskByColorTolerance(
    imageBytes: imageBytes,
    width: width,
    height: height,
    currentMask: mask1,
    avgR: 200,
    avgG: 50,
    avgB: 50,
    tolerance: 50,
  );

  // Фильтрация для объекта 2 (зелёный)
  final filtered2 = ImageProcessingService.filterMaskByColorTolerance(
    imageBytes: imageBytes,
    width: width,
    height: height,
    currentMask: mask2,
    avgR: 50,
    avgG: 200,
    avgB: 50,
    tolerance: 50,
  );

  // Аддитивное объединение (как в редакторе при повторном клике)
  final combined = Uint8List(width * height);
  for (int i = 0; i < combined.length; i++) {
    combined[i] = (filtered1[i] == 1 || filtered2[i] == 1) ? 1 : 0;
  }

  final totalSelected = combined.where((v) => v == 1).length;
  print('\nПосле двух сегментаций (аддитивный режим):');
  print('Всего выделенных пикселей: $totalSelected');

  if (totalSelected == 100) {
    print('✅ ТЕСТ ПРОЙДЕН: обе половины изображения выделены');
  } else {
    print('❌ ТЕСТ НЕ ПРОЙДЕН: ожидалось 100, получено $totalSelected');
  }
}
