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
            defaultValue: 'http://139.100.226.10',
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

  Future<Uint8List?> segmentObject({
    required Uint8List imageBytes,
    required Offset imagePosition,
    required int imageWidth,
    required int imageHeight,
    int minComponentArea = 300,
    int dilateKernel = 3,
    double expandColorThreshold = 25.0,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/segment'),
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
      request.fields['point_label'] = '1';
      request.fields['min_component_area'] = minComponentArea.toString();
      request.fields['dilate_kernel'] = dilateKernel.toString();
      request.fields['expand_color_threshold'] = expandColorThreshold.toString();

      // Add timeout of 30 seconds
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timeout after 30 seconds');
        },
      );
      final response = await http.Response.fromStream(streamedResponse).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Response read timeout after 10 seconds');
        },
      );
      final responseBody = response.body;
      final jsonResponse = json.decode(responseBody);
      if (response.statusCode == 200 && jsonResponse['success'] == true) {
        final maskRle = jsonResponse['mask'];
        final mask = _rleDecode(maskRle, imageWidth, imageHeight);
        return _maskToUint8List(mask, imageWidth, imageHeight);
      } else {
        debugPrint('Ошибка сегментации: ${response.statusCode}');
        debugPrint('Response body: $responseBody');
        return null;
      }
    } catch (e) {
      debugPrint('Исключение при сегментации: $e');
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
