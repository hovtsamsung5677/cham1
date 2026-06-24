import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class SegmentationService {
  final String serverUrl;
  final http.Client _client;

  SegmentationService({String? serverUrl, http.Client? client})
    : serverUrl =
          serverUrl ??
          const String.fromEnvironment(
            'SERVER_URL',
            defaultValue: 'http://212.41.29.205:8001',
          ),
      _client = client ?? http.Client();

  Future<bool> isServerAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse('$serverUrl/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>?> getMask({
    required Uint8List imageBytes,
    required Offset positivePoint,
    required List<Offset>? negativePoints,
    required int imageWidth,
    required int imageHeight,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${serverUrl}/get-mask'),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
      request.fields['point_x'] = positivePoint.dx.round().toString();
      request.fields['point_y'] = positivePoint.dy.round().toString();

      if (negativePoints != null && negativePoints.isNotEmpty) {
        final negX = negativePoints
            .map((p) => p.dx.round().toString())
            .join(',');
        final negY = negativePoints
            .map((p) => p.dy.round().toString())
            .join(',');
        request.fields['negative_point_x'] = negX;
        request.fields['negative_point_y'] = negY;
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint(
        'Mask response: status=${response.statusCode}, bytes=${response.bodyBytes.length}',
      );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final json = jsonDecode(response.body);
        return {
          'mask': json['mask'] as String,
          'preview': json['preview'] as String,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Mask error: $e');
      return null;
    }
  }

  Future<Uint8List?> segmentObject({
    required Uint8List imageBytes,
    required Offset imagePosition,
    required int imageWidth,
    required int imageHeight,
    required String material,
    required int colorHex,
    double gloss = -1.0,
    double strength = 1.0,
  }) async {
    try {
      final int rgbValue = colorHex & 0xFFFFFF;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/ai-recolor'),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
      request.fields['point_x'] = imagePosition.dx.round().toString();
      request.fields['point_y'] = imagePosition.dy.round().toString();
      request.fields['material'] = material;
      request.fields['color_hex'] =
          '0x${rgbValue.toRadixString(16).padLeft(6, '0')}';
      request.fields['strength'] = strength.toString();
      request.fields['gloss'] = gloss.toString();

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint(
        'AI recolor response: status=${response.statusCode}, bytes=${response.bodyBytes.length}',
      );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return Uint8List.fromList(response.bodyBytes);
      }
      debugPrint(
        'AI recolor empty/invalid response: status=${response.statusCode}',
      );
      return null;
    } catch (e) {
      debugPrint('AI recolor error: $e');
      return null;
    }
  }

  List<List<int>> _rleDecode(Map<String, dynamic> rle, int width, int height) {
    final List<int> counts = List<int>.from(rle['counts']);
    final List<List<int>> mask = List.generate(
      height,
      (y) => List.filled(width, 0),
    );
    int idx = 0;
    int val = 0;
    for (final int count in counts) {
      final int end = idx + count;
      if (end > width * height) break;
      final int startRow = idx ~/ width;
      final int endRow = (end - 1) ~/ width;
      for (int y = startRow; y <= endRow; y++) {
        final int startCol = (y == startRow) ? idx % width : 0;
        final int endCol = (y == endRow) ? (end - 1) % width : width - 1;
        for (int x = startCol; x <= endCol; x++) {
          if (y < height && x < width) {
            mask[y][x] = val;
          }
        }
      }
      idx = end;
      val = 1 - val;
    }
    return mask;
  }

  Uint8List _maskToUint8List(List<List<int>> mask, int width, int height) {
    final Uint8List bytes = Uint8List(width * height);
    int i = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        bytes[i++] = mask[y][x] == 1 ? 1 : 0;
      }
    }
    return bytes;
  }

  void dispose() {
    _client.close();
  }
}
