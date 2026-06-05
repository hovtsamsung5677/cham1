import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Service for realistic image recoloring using HSV color space
/// This algorithm preserves texture, shadows, highlights, and material factors
class ImageProcessingService {
  /// Thresholds for brightness classification (public for analysis)
  static const double darkThreshold =
      0.35; // Value below this is considered dark
  static const double brightThreshold =
      0.75; // Value above this is considered bright

  /// Recolor ONLY dark pixels using SCREEN blend mode
  /// This method applies screen filter exclusively to dark areas (<35% brightness)
  /// while leaving bright and medium pixels unchanged
  ///
  /// Screen blend formula: 1 - (1 - base) * (1 - target)
  /// Makes dark objects brighter and colored, ideal for dark furniture, etc.
  static Uint8List recolorDarkPixelsWithScreen({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List selectionMask, // 1 for selected, 0 for not selected
    required int targetRed,
    required int targetGreen,
    required int targetBlue,
    double blendFactor = 1.0,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    if (selectionMask.length != image.width * image.height) {
      return imageBytes;
    }

    int darkRecoloredCount = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final index = y * image.width + x;

        if (selectionMask[index] == 1) {
          final pixel = image.getPixel(x, y);
          final originalR = pixel.r.toInt();
          final originalG = pixel.g.toInt();
          final originalB = pixel.b.toInt();

          // Calculate brightness (value) using HSV conversion
          final originalHsv = _rgbToHsv(originalR, originalG, originalB);
          final value = originalHsv[2]; // 0.0 to 1.0

          // Only recolor DARK pixels with screen filter
          if (value < darkThreshold) {
            final newR = _recolorDarkPixelWithScreen(
              originalR,
              targetRed,
              originalR,
              blendFactor,
            );
            final newG = _recolorDarkPixelWithScreen(
              originalG,
              targetGreen,
              originalG,
              blendFactor,
            );
            final newB = _recolorDarkPixelWithScreen(
              originalB,
              targetBlue,
              originalB,
              blendFactor,
            );

            image.setPixelRgb(
              x,
              y,
              newR.clamp(0, 255),
              newG.clamp(0, 255),
              newB.clamp(0, 255),
            );
            darkRecoloredCount++;
          }
        }
      }
    }

    print('\n=== SCREEN FILTER RECOLOR (Dark Pixels Only) ===');
    print('Target color: RGB($targetRed,$targetGreen,$targetBlue)');
    print('Dark pixels recolored: $darkRecoloredCount');
    print('==========================================\n');

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Recolor pixels in the given selection mask with the target color
  /// Uses different algorithms for dark and bright pixels to preserve realism
  static Uint8List recolorImage({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List selectionMask, // 1 for selected, 0 for not selected
    required int targetRed,
    required int targetGreen,
    required int targetBlue,
    double blendFactor = 1.0,
    Uint8List? woodTextureBytes, // optional wood texture
  }) {
    // Decode the original image
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    // Ensure selection mask matches image size
    if (selectionMask.length != image.width * image.height) {
      return imageBytes;
    }

    // Load and process wood texture if provided
    img.Image? textureImg;
    if (woodTextureBytes != null) {
      final decodedTexture = img.decodeImage(woodTextureBytes);
      if (decodedTexture != null) {
        // Resize texture to match image dimensions
        textureImg = img.copyResize(
          decodedTexture,
          width: width,
          height: height,
        );
      }
    }

    // Pre-calculate target HSV for texture blending
    List<double>? targetHsv;
    if (textureImg != null) {
      targetHsv = _rgbToHsv(targetRed, targetGreen, targetBlue);
    }

    // Statistics for logging
    int darkCount = 0;
    int brightCount = 0;
    int midCount = 0;

    // Process each pixel in the selection
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final index = y * image.width + x;

        if (selectionMask[index] == 1) {
          final pixel = image.getPixel(x, y);
          final originalR = pixel.r.toInt();
          final originalG = pixel.g.toInt();
          final originalB = pixel.b.toInt();

          // Calculate brightness (value) using HSV conversion
          final originalHsv = _rgbToHsv(originalR, originalG, originalB);
          final value = originalHsv[2]; // 0.0 to 1.0

          // Classify pixel brightness
          final isDark = value < darkThreshold;
          final isBright = value > brightThreshold;

          // Log classification for sample pixels (every 1000th pixel to avoid spam)
          if ((x + y * width) % 1000 == 0) {
            _logPixelClassification(
              x,
              y,
              originalR,
              originalG,
              originalB,
              value,
              isDark,
              isBright,
            );
          }

          // Count statistics
          if (isDark)
            darkCount++;
          else if (isBright)
            brightCount++;
          else
            midCount++;

          // Base colorization: use original image luminance to preserve object's shape/shadows
          final gray =
              (0.299 * originalR + 0.587 * originalG + 0.114 * originalB)
                  .round();

          // Apply different blending strategies based on brightness
          int finalR, finalG, finalB;

          if (isDark) {
            // === DARK PIXELS STRATEGY ===
            // Using SCREEN blend mode to brighten dark objects while adding color
            // Screen: 1 - (1 - base) * (1 - target) - adds light to dark areas
            finalR = _recolorDarkPixelWithScreen(
              originalR,
              targetRed,
              gray,
              blendFactor,
            );
            finalG = _recolorDarkPixelWithScreen(
              originalG,
              targetGreen,
              gray,
              blendFactor,
            );
            finalB = _recolorDarkPixelWithScreen(
              originalB,
              targetBlue,
              gray,
              blendFactor,
            );
          } else if (isBright) {
            // === BRIGHT PIXELS STRATEGY ===
            // For bright areas: use overlay blend mode to add color while preserving highlights
            // Bright areas reflect light, so we use overlay for natural look
            finalR = _recolorWithOverlay(originalR, targetRed, blendFactor);
            finalG = _recolorWithOverlay(originalG, targetGreen, blendFactor);
            finalB = _recolorWithOverlay(originalB, targetBlue, blendFactor);
          } else {
            // === MEDIUM BRIGHTNESS - Standard approach ===
            var blendedR = (gray * targetRed) ~/ 255;
            var blendedG = (gray * targetGreen) ~/ 255;
            var blendedB = (gray * targetBlue) ~/ 255;
            if (blendFactor < 1.0) {
              finalR =
                  originalR + ((blendedR - originalR) * blendFactor).round();
              finalG =
                  originalG + ((blendedG - originalG) * blendFactor).round();
              finalB =
                  originalB + ((blendedB - originalB) * blendFactor).round();
            } else {
              finalR = blendedR;
              finalG = blendedG;
              finalB = blendedB;
            }
          }

          // Apply texture overlay if provided
          if (textureImg != null) {
            final texPixel = textureImg.getPixel(x, y);
            final texR = texPixel.r.toInt();
            final texG = texPixel.g.toInt();
            final texB = texPixel.b.toInt();
            final texLum = (0.299 * texR + 0.587 * texG + 0.114 * texB) / 255.0;

            double baseR = finalR / 255.0;
            double baseG = finalG / 255.0;
            double baseB = finalB / 255.0;

            double overlay(double base, double blend) {
              if (base < 0.5)
                return 2 * base * blend;
              else
                return 1 - 2 * (1 - base) * (1 - blend);
            }

            final resultR = (overlay(baseR, texLum) * 255).round().clamp(
              0,
              255,
            );
            final resultG = (overlay(baseG, texLum) * 255).round().clamp(
              0,
              255,
            );
            final resultB = (overlay(baseB, texLum) * 255).round().clamp(
              0,
              255,
            );

            image.setPixelRgb(x, y, resultR, resultG, resultB);
          } else {
            image.setPixelRgb(
              x,
              y,
              finalR.clamp(0, 255),
              finalG.clamp(0, 255),
              finalB.clamp(0, 255),
            );
          }
        }
      }
    }

    // Log summary statistics
    _logRecolorSummary(
      darkCount,
      brightCount,
      midCount,
      targetRed,
      targetGreen,
      targetBlue,
    );

    // Encode back to bytes
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Recolor ALL selected pixels using SCREEN blend mode
  /// Applies screen filter to entire selection, preserving texture
  static Uint8List recolorAllWithScreen({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List selectionMask,
    required int targetRed,
    required int targetGreen,
    required int targetBlue,
    double blendFactor = 1.0,
    Uint8List? woodTextureBytes,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    if (selectionMask.length != image.width * image.height) {
      return imageBytes;
    }

    // Load and process wood texture if provided
    img.Image? textureImg;
    if (woodTextureBytes != null) {
      final decodedTexture = img.decodeImage(woodTextureBytes);
      if (decodedTexture != null) {
        textureImg = img.copyResize(
          decodedTexture,
          width: width,
          height: height,
        );
      }
    }

    int recoloredCount = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final index = y * image.width + x;

        if (selectionMask[index] == 1) {
          final pixel = image.getPixel(x, y);
          final originalR = pixel.r.toInt();
          final originalG = pixel.g.toInt();
          final originalB = pixel.b.toInt();

          // Compute luma (Y) for proper screen blend scaling
          // Y = 0.2126*R + 0.7152*G + 0.0722*B (0-255)
          final gray =
              (0.2126 * originalR + 0.7152 * originalG + 0.0722 * originalB)
                  .round();

          // Apply SCREEN blend mode to all selected pixels
          final newR = _recolorDarkPixelWithScreen(
            originalR,
            targetRed,
            gray,
            blendFactor,
          );
          final newG = _recolorDarkPixelWithScreen(
            originalG,
            targetGreen,
            gray,
            blendFactor,
          );
          final newB = _recolorDarkPixelWithScreen(
            originalB,
            targetBlue,
            gray,
            blendFactor,
          );

          // Apply texture overlay if provided
          if (textureImg != null) {
            final texPixel = textureImg.getPixel(x, y);
            final texR = texPixel.r.toInt();
            final texG = texPixel.g.toInt();
            final texB = texPixel.b.toInt();
            final texLum = (0.299 * texR + 0.587 * texG + 0.114 * texB) / 255.0;

            double baseR = newR / 255.0;
            double baseG = newG / 255.0;
            double baseB = newB / 255.0;

            double overlay(double base, double blend) {
              if (base < 0.5)
                return 2 * base * blend;
              else
                return 1 - 2 * (1 - base) * (1 - blend);
            }

            final resultR = (overlay(baseR, texLum) * 255).round().clamp(
              0,
              255,
            );
            final resultG = (overlay(baseG, texLum) * 255).round().clamp(
              0,
              255,
            );
            final resultB = (overlay(baseB, texLum) * 255).round().clamp(
              0,
              255,
            );

            image.setPixelRgb(x, y, resultR, resultG, resultB);
          } else {
            image.setPixelRgb(
              x,
              y,
              newR.clamp(0, 255),
              newG.clamp(0, 255),
              newB.clamp(0, 255),
            );
          }
          recoloredCount++;
        }
      }
    }

    print('\n=== SCREEN FILTER RECOLOR (All Pixels) ===');
    print('Target color: RGB($targetRed,$targetGreen,$targetBlue)');
    print('Pixels recolored: $recoloredCount');
    print('==========================================\n');

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Recolor ALL selected pixels using OVERLAY blend mode
  /// Applies overlay filter to entire selection, preserving texture and highlights
  static Uint8List recolorAllWithOverlay({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List selectionMask,
    required int targetRed,
    required int targetGreen,
    required int targetBlue,
    double blendFactor = 1.0,
    Uint8List? woodTextureBytes,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    if (selectionMask.length != image.width * image.height) {
      return imageBytes;
    }

    // Load and process wood texture if provided
    img.Image? textureImg;
    if (woodTextureBytes != null) {
      final decodedTexture = img.decodeImage(woodTextureBytes);
      if (decodedTexture != null) {
        textureImg = img.copyResize(
          decodedTexture,
          width: width,
          height: height,
        );
      }
    }

    int recoloredCount = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final index = y * image.width + x;

        if (selectionMask[index] == 1) {
          final pixel = image.getPixel(x, y);
          final originalR = pixel.r.toInt();
          final originalG = pixel.g.toInt();
          final originalB = pixel.b.toInt();

          // Calculate brightness for adaptive overlay
          final originalHsv = _rgbToHsv(originalR, originalG, originalB);
          final value = originalHsv[2];

          // Apply OVERLAY blend mode to all selected pixels
          // Overlay: base < 0.5 ? 2*base*blend : 1 - 2*(1-base)*(1-blend)
          final newR = _recolorWithOverlay(originalR, targetRed, blendFactor);
          final newG = _recolorWithOverlay(originalG, targetGreen, blendFactor);
          final newB = _recolorWithOverlay(originalB, targetBlue, blendFactor);

          // Apply texture overlay if provided
          if (textureImg != null) {
            final texPixel = textureImg.getPixel(x, y);
            final texR = texPixel.r.toInt();
            final texG = texPixel.g.toInt();
            final texB = texPixel.b.toInt();
            final texLum = (0.299 * texR + 0.587 * texG + 0.114 * texB) / 255.0;

            double baseR = newR / 255.0;
            double baseG = newG / 255.0;
            double baseB = newB / 255.0;

            double overlayDouble(double base, double blend) {
              if (base < 0.5)
                return 2 * base * blend;
              else
                return 1 - 2 * (1 - base) * (1 - blend);
            }

            final resultR = (overlayDouble(baseR, texLum) * 255).round().clamp(
              0,
              255,
            );
            final resultG = (overlayDouble(baseG, texLum) * 255).round().clamp(
              0,
              255,
            );
            final resultB = (overlayDouble(baseB, texLum) * 255).round().clamp(
              0,
              255,
            );

            image.setPixelRgb(x, y, resultR, resultG, resultB);
          } else {
            image.setPixelRgb(
              x,
              y,
              newR.clamp(0, 255),
              newG.clamp(0, 255),
              newB.clamp(0, 255),
            );
          }
          recoloredCount++;
        }
      }
    }

    print('\n=== OVERLAY RECOLOR (All Pixels) ===');
    print('Target color: RGB($targetRed,$targetGreen,$targetBlue)');
    print('Pixels recolored: $recoloredCount');
    print('====================================\n');

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Recoloring strategy for dark pixels using SCREEN blend mode (INTEGER OPTIMIZED)
  /// Screen formula: base + target - (base * target) / 255
  /// Makes dark pixels brighter by adding light
  /// Ideal for dark objects that should become colored but not stay dark
  /// Uses luma (gray) to preserve texture: darker areas get less color
  static int _recolorDarkPixelWithScreen(
    int original,
    int target,
    int gray,
    double blendFactor,
  ) {
    // Integer screen blend: result = o + t - (o*t)/255
    var result = original + target - (original * target) ~/ 255;

    // Scale by luminance factor: darker pixels (low gray) get less color
    // This preserves shadows and texture structure
    // luminanceFactor: 0.3 для чёрного (gray=0), 1.0 для белого (gray=255)
    final luminanceFactor = 0.3 + 0.7 * (gray / 255.0);
    result = (result * luminanceFactor).round();

    // Apply blend factor to control intensity
    result = original + ((result - original) * blendFactor).round();

    return result.clamp(0, 255);
  }

  /// Recolor pixel using OVERLAY blend mode (INTEGER OPTIMIZED)
  /// Overlay formula: base < 128 ? (2*base*target)/255 : 2*base+2*target - (2*base*target)/255 - 255
  static int _recolorWithOverlay(int original, int target, double blendFactor) {
    int result;
    if (original < 128) {
      // 2 * base * target
      result = (2 * original * target) ~/ 255;
    } else {
      // 1 - 2*(1-base)*(1-target) in integer form
      result = 2 * original + 2 * target - (2 * original * target) ~/ 255 - 255;
    }

    // Apply blend factor
    result = original + ((result - original) * blendFactor).round();
    return result.clamp(0, 255);
  }

  /// Log pixel classification for debugging
  static void _logPixelClassification(
    int x,
    int y,
    int r,
    int g,
    int b,
    double value,
    bool isDark,
    bool isBright,
  ) {
    final colorName = _getColorName(r, g, b);
    final brightness = isDark ? 'ТЁМНЫЙ' : (isBright ? 'ЯРКИЙ' : 'СРЕДНИЙ');
    print(
      '[PixelClassify] x=$x y=$y RGB=($r,$g,$b) Value=${(value * 100).toInt()}% [$brightness] $colorName',
    );
  }

  /// Log summary statistics after recoloring
  static void _logRecolorSummary(
    int darkCount,
    int brightCount,
    int midCount,
    int r,
    int g,
    int b,
  ) {
    final total = darkCount + brightCount + midCount;
    if (total == 0) return;

    final darkPct = (darkCount * 100 / total).toInt();
    final brightPct = (brightCount * 100 / total).toInt();
    final midPct = (midCount * 100 / total).toInt();

    print('\n=== RECOLOR SUMMARY ===');
    print('Target color: RGB($r,$g,$b)');
    print('Total selected pixels: $total');
    print(
      'Dark pixels (<35% brightness): $darkCount ($darkPct%) -> dark strategy',
    );
    print(
      'Bright pixels (>75% brightness): $brightCount ($brightPct%) -> overlay strategy',
    );
    print('Medium pixels: $midCount ($midPct%) -> standard blend');
    print('========================\n');
  }

  /// Simple color name for logging
  static String _getColorName(int r, int g, int b) {
    if (r < 50 && g < 50 && b < 50) return '(black)';
    if (r > 200 && g > 200 && b > 200) return '(white)';
    if (r > g && r > b) return '(reddish)';
    if (g > r && g > b) return '(greenish)';
    if (b > r && b > g) return '(bluish)';
    if (r > 150 && g > 150 && b < 100) return '(yellowish)';
    if (r > 150 && b > 150 && g < 100) return '(magenta)';
    if (g > 150 && b > 150 && r < 100) return '(cyan)';
    return '';
  }

  /// Recolor with texture preservation algorithm
  /// Uses HSV color space to preserve value (brightness) and saturation
  /// while blending the hue
  static List<double> _recolorWithTexturePreservation({
    required List<double> originalHsv,
    required List<double> targetHsv,
    required double blendFactor,
  }) {
    // Original HSV: [hue (0-360), saturation (0-1), value (0-1)]
    // Target HSV: [hue (0-360), saturation (0-1), value (0-1)]

    final origH = originalHsv[0];
    final origS = originalHsv[1];
    final origV = originalHsv[2];

    final targetH = targetHsv[0];
    final targetS = targetHsv[1];
    final targetV = targetHsv[2];

    // Calculate local contrast preservation factor
    // This helps maintain the local contrast and details
    final localContrast = _calculateLocalContrast(origS, origV);

    // Blend hue with angular interpolation
    final blendedHue = _angularInterpolate(origH, targetH, blendFactor);

    // Preserve saturation but adjust to maintain natural look
    // For lighter colors, reduce saturation slightly
    // For darker colors, increase saturation
    final adjustedSaturation = _adjustSaturationForRealism(
      origS,
      targetS,
      origV,
      localContrast,
      blendFactor,
    );

    // Blend value with blendFactor to preserve local contrast
    final preservedValue = origV + (targetV - origV) * blendFactor;

    return [blendedHue, adjustedSaturation, preservedValue];
  }

  /// Angular interpolation for hue values (handles wraparound at 0/360)
  static double _angularInterpolate(double from, double to, double t) {
    // Calculate the shortest path around the color wheel
    double diff = to - from;

    // Normalize to -180 to 180
    if (diff > 180) {
      diff -= 360;
    } else if (diff < -180) {
      diff += 360;
    }

    double result = from + diff * t;

    // Normalize to 0-360
    if (result < 0) {
      result += 360;
    } else if (result >= 360) {
      result -= 360;
    }

    return result;
  }

  /// Adjust saturation to maintain realistic appearance
  static double _adjustSaturationForRealism(
    double originalSaturation,
    double targetSaturation,
    double value,
    double localContrast,
    double blendFactor,
  ) {
    // For very dark or very light areas, reduce saturation changes
    // to prevent unnatural colors
    final valueFactor = value < 0.15 || value > 0.9 ? 0.3 : 1.0;

    // Blend saturation while preserving local contrast
    final blended =
        originalSaturation +
        (targetSaturation - originalSaturation) * blendFactor * valueFactor;

    // Apply local contrast preservation
    return blended * (1 - localContrast * 0.3);
  }

  /// Calculate local contrast factor from saturation and value
  static double _calculateLocalContrast(double saturation, double value) {
    // High saturation and mid-range value = high local contrast
    // This helps preserve details in textured areas
    return saturation * (1 - (value - 0.5).abs() * 2).clamp(0.0, 1.0);
  }

  /// Convert RGB to HSV
  /// Returns [hue (0-360), saturation (0-1), value (0-1)]
  static List<double> rgbToHsv(int r, int g, int b) {
    return _rgbToHsv(r, g, b);
  }

  /// Convert RGB to HSV (internal)
  /// Returns [hue (0-360), saturation (0-1), value (0-1)]
  static List<double> _rgbToHsv(int r, int g, int b) {
    final rNorm = r / 255.0;
    final gNorm = g / 255.0;
    final bNorm = b / 255.0;

    final max = math.max(rNorm, math.max(gNorm, bNorm));
    final min = math.min(rNorm, math.min(gNorm, bNorm));
    final diff = max - min;

    // Value
    final value = max;

    // Saturation
    final saturation = max == 0 ? 0.0 : diff / max;

    // Hue
    double hue = 0;
    if (diff != 0) {
      if (max == rNorm) {
        hue = 60 * (((gNorm - bNorm) / diff) % 6);
      } else if (max == gNorm) {
        hue = 60 * ((bNorm - rNorm) / diff + 2);
      } else {
        hue = 60 * ((rNorm - gNorm) / diff + 4);
      }
    }
    if (hue < 0) hue += 360;

    return [hue, saturation, value];
  }

  /// Convert HSV to RGB
  /// Takes [hue (0-360), saturation (0-1), value (0-1)]
  static List<int> _hsvToRgb(double h, double s, double v) {
    final c = v * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = v - c;

    double rPrime, gPrime, bPrime;

    if (h < 60) {
      rPrime = c;
      gPrime = x;
      bPrime = 0;
    } else if (h < 120) {
      rPrime = x;
      gPrime = c;
      bPrime = 0;
    } else if (h < 180) {
      rPrime = 0;
      gPrime = c;
      bPrime = x;
    } else if (h < 240) {
      rPrime = 0;
      gPrime = x;
      bPrime = c;
    } else if (h < 300) {
      rPrime = x;
      gPrime = 0;
      bPrime = c;
    } else {
      rPrime = c;
      gPrime = 0;
      bPrime = x;
    }

    return [
      ((rPrime + m) * 255).round().clamp(0, 255),
      ((gPrime + m) * 255).round().clamp(0, 255),
      ((bPrime + m) * 255).round().clamp(0, 255),
    ];
  }

  /// Create a selection mask from a list of points (polygon)
  static Uint8List createPolygonMask({
    required int width,
    required int height,
    required List<List<int>> polygonPoints,
  }) {
    final mask = Uint8List(width * height);

    if (polygonPoints.length < 3) return mask;

    // Build edge list (non-horizontal edges)
    List<_PolygonEdge> edges = [];
    for (int i = 0; i < polygonPoints.length; i++) {
      int j = (i + 1) % polygonPoints.length;
      int x1 = polygonPoints[i][0];
      int y1 = polygonPoints[i][1];
      int x2 = polygonPoints[j][0];
      int y2 = polygonPoints[j][1];

      if (y1 == y2) continue; // skip horizontal edges

      if (y1 < y2) {
        edges.add(
          _PolygonEdge(y1, y2, x1.toDouble(), (x2 - x1) / (y2 - y1).toDouble()),
        );
      } else {
        edges.add(
          _PolygonEdge(y2, y1, x2.toDouble(), (x1 - x2) / (y1 - y2).toDouble()),
        );
      }
    }

    // Scanline fill (using pixel centers at y+0.5)
    for (int y = 0; y < height; y++) {
      double scanY = y + 0.5;
      List<double> intersections = [];

      for (var edge in edges) {
        if (scanY > edge.ymin && scanY <= edge.ymax) {
          double x = edge.xAtYmin + (scanY - edge.ymin) * edge.dxdy;
          intersections.add(x);
        }
      }

      intersections.sort();

      // Fill between pairs (even-odd rule)
      for (int i = 0; i < intersections.length; i += 2) {
        if (i + 1 < intersections.length) {
          int startX = intersections[i].ceil();
          int endX = intersections[i + 1].floor();
          if (startX > endX) continue;
          for (int x = startX; x <= endX; x++) {
            if (x >= 0 && x < width) {
              mask[y * width + x] = 1;
            }
          }
        }
      }
    }

    return mask;
  }

  /// Create a circular brush selection mask
  static Uint8List createBrushMask({
    required int width,
    required int height,
    required int centerX,
    required int centerY,
    required int radius,
  }) {
    final mask = Uint8List(width * height);
    final radiusSq = radius * radius;

    int startX = math.max(0, centerX - radius);
    int endX = math.min(width - 1, centerX + radius);
    int startY = math.max(0, centerY - radius);
    int endY = math.min(height - 1, centerY + radius);

    for (int y = startY; y <= endY; y++) {
      for (int x = startX; x <= endX; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        if (dx * dx + dy * dy <= radiusSq) {
          mask[y * width + x] = 1;
        }
      }
    }

    return mask;
  }

  /// Create a lasso selection mask from a path of points
  static Uint8List createLassoMask({
    required int width,
    required int height,
    required List<List<int>> lassoPath,
    required int strokeWidth,
  }) {
    final mask = Uint8List(width * height);

    if (lassoPath.length < 2) return mask;

    // Draw thick line through path points
    for (int i = 0; i < lassoPath.length - 1; i++) {
      final p1 = lassoPath[i];
      final p2 = lassoPath[i + 1];

      _drawThickLine(
        mask: mask,
        width: width,
        x0: p1[0],
        y0: p1[1],
        x1: p2[0],
        y1: p2[1],
        thickness: strokeWidth,
      );
    }

    return mask;
  }

  /// Draw a thick line between two points
  static void _drawThickLine({
    required Uint8List mask,
    required int width,
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required int thickness,
  }) {
    final radius = thickness ~/ 2;
    final radiusSq = radius * radius;

    final minX = math.max(0, math.min(x0, x1) - radius);
    final maxX = math.min(width - 1, math.max(x0, x1) + radius);
    final minY = math.max(0, math.min(y0, y1) - radius);
    final maxY = math.min(mask.length ~/ width - 1, math.max(y0, y1) + radius);

    // Get line equation
    final dx = x1 - x0;
    final dy = y1 - y0;
    final lenSq = dx * dx + dy * dy;

    if (lenSq == 0) {
      // Single point
      for (int y = minY; y <= maxY; y++) {
        for (int x = minX; x <= maxX; x++) {
          final dSq = (x - x0) * (x - x0) + (y - y0) * (y - y0);
          if (dSq <= radiusSq) {
            mask[y * width + x] = 1;
          }
        }
      }
      return;
    }

    // Draw line segment
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        // Calculate distance to line
        final t = ((x - x0) * dx + (y - y0) * dy) / lenSq;
        final tClamped = t.clamp(0.0, 1.0);
        final projX = x0 + tClamped * dx;
        final projY = y0 + tClamped * dy;
        final dSq = (x - projX) * (x - projX) + (y - projY) * (y - projY);

        if (dSq <= radiusSq) {
          mask[y * width + x] = 1;
        }
      }
    }
  }

  /// Apply simple GrabCut-like segmentation
  /// This is a simplified version that uses color similarity
  static Uint8List applyGrabCutSegmentation({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List
    initialMask, // 0 = background, 1 = foreground, 2 = probable foreground
    required int iterations,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return initialMask;

    var mask = Uint8List.fromList(initialMask);

    for (int iter = 0; iter < iterations; iter++) {
      final newMask = Uint8List.fromList(mask);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final idx = y * width + x;
          if (mask[idx] == 0 || mask[idx] == 2) {
            // Check if this pixel is similar to foreground
            final similarity = _calculateForegroundSimilarity(
              image: image,
              mask: mask,
              width: width,
              height: height,
              x: x,
              y: y,
            );

            if (similarity > 0.5) {
              newMask[idx] = 1;
            }
          }
        }
      }

      mask = newMask;
    }

    return mask;
  }

  /// Calculate similarity to foreground pixels
  static double _calculateForegroundSimilarity({
    required img.Image image,
    required Uint8List mask,
    required int width,
    required int height,
    required int x,
    required int y,
  }) {
    // Calculate average color of foreground and background
    double foreR = 0, foreG = 0, foreB = 0;
    double backR = 0, backG = 0, backB = 0;
    int foreCount = 0, backCount = 0;

    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
          final idx = ny * width + nx;
          final pixel = image.getPixel(nx, ny);

          if (mask[idx] == 1) {
            foreR += pixel.r;
            foreG += pixel.g;
            foreB += pixel.b;
            foreCount++;
          } else if (mask[idx] == 0) {
            backR += pixel.r;
            backG += pixel.g;
            backB += pixel.b;
            backCount++;
          }
        }
      }
    }

    if (foreCount == 0 || backCount == 0) return 0.5;

    foreR /= foreCount;
    foreG /= foreCount;
    foreB /= foreCount;
    backR /= backCount;
    backG /= backCount;
    backB /= backCount;

    final pixel = image.getPixel(x, y);
    final distToFore = _colorDistance(
      pixel.r.toDouble(),
      pixel.g.toDouble(),
      pixel.b.toDouble(),
      foreR,
      foreG,
      foreB,
    );
    final distToBack = _colorDistance(
      pixel.r.toDouble(),
      pixel.g.toDouble(),
      pixel.b.toDouble(),
      backR,
      backG,
      backB,
    );

    return distToFore / (distToFore + distToBack + 0.001);
  }

  /// Calculate Euclidean color distance
  static double _colorDistance(
    double r1,
    double g1,
    double b1,
    double r2,
    double g2,
    double b2,
  ) {
    final dr = r1 - r2;
    final dg = g1 - g2;
    final db = b1 - b2;
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  /// Expand selection to nearby similar colors
  static Uint8List expandSelectionWithTolerance({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List currentMask,
    required double tolerance,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return currentMask;

    final newMask = Uint8List.fromList(currentMask);
    final maskWidth = width;
    final maskHeight = height;

    for (int y = 0; y < maskHeight; y++) {
      for (int x = 0; x < maskWidth; x++) {
        final idx = y * maskWidth + x;

        // Skip already selected pixels
        if (currentMask[idx] == 1) continue;

        // Check neighbors
        final pixel = image.getPixel(x, y);

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;

            final nx = x + dx;
            final ny = y + dy;

            if (nx >= 0 && nx < maskWidth && ny >= 0 && ny < maskHeight) {
              final nIdx = ny * maskWidth + nx;

              if (currentMask[nIdx] == 1) {
                // Check color similarity
                final nPixel = image.getPixel(nx, ny);
                final dist = _colorDistance(
                  pixel.r.toDouble(),
                  pixel.g.toDouble(),
                  pixel.b.toDouble(),
                  nPixel.r.toDouble(),
                  nPixel.g.toDouble(),
                  nPixel.b.toDouble(),
                );

                if (dist < tolerance * 255) {
                  newMask[idx] = 1;
                  break;
                }
              }
            }
          }
          if (newMask[idx] == 1) break;
        }
      }
    }

    return newMask;
  }

  /// Compute exterior mask using flood fill from edges (excluding boundary)
  /// Returns a mask where 1 = exterior (reachable from image edges), 0 = interior/unknown
  static Uint8List computeExteriorMask({
    required Uint8List boundaryMask,
    required int width,
    required int height,
  }) {
    final exterior = Uint8List(width * height);
    final queue = <int>[];

    void tryAdd(int x, int y) {
      if (x < 0 || x >= width || y < 0 || y >= height) return;
      final idx = y * width + x;
      if (boundaryMask[idx] == 0 && exterior[idx] == 0) {
        exterior[idx] = 1;
        queue.add(idx);
      }
    }

    // Add edge pixels
    for (int x = 0; x < width; x++) {
      tryAdd(x, 0);
      tryAdd(x, height - 1);
    }
    for (int y = 1; y < height - 1; y++) {
      tryAdd(0, y);
      tryAdd(width - 1, y);
    }

    // BFS flood fill
    while (queue.isNotEmpty) {
      final idx = queue.removeAt(0);
      int x = idx % width;
      int y = idx ~/ width;
      tryAdd(x - 1, y);
      tryAdd(x + 1, y);
      tryAdd(x, y - 1);
      tryAdd(x, y + 1);
    }

    return exterior;
  }

  /// Filter selection mask to keep only pixels similar to the average color
  /// Pixels that are too far from the average color are removed from the mask
  /// Uses Euclidean distance in RGB space with performance optimizations
  ///
  /// [imageBytes] - original image
  /// [width] - image width
  /// [height] - image height
  /// [currentMask] - binary mask (1 = selected, 0 = not selected)
  /// [avgR], [avgG], [avgB] - average color of the selected region
  /// [tolerance] - maximum color distance (0-255 scale, default 80 for speed)
  ///
  /// Returns filtered mask where pixels with color distance > tolerance are set to 0
  /// OPTIMIZATION: Uses squared distance (no sqrt) and processes all pixels.
  /// Fast enough for typical mask sizes on modern devices.
  static Uint8List filterMaskByColorTolerance({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List currentMask,
    required int avgR,
    required int avgG,
    required int avgB,
    required int tolerance,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return currentMask;

    if (currentMask.length != width * height) {
      return currentMask;
    }

    final filteredMask = Uint8List.fromList(currentMask);
    int removedCount = 0;
    int totalSelected = 0;

    // Precompute tolerance squared for fast comparison
    final toleranceSq = tolerance * tolerance;

    // Process all pixels (optimized with squared distance, no sqrt)
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;

        if (currentMask[idx] == 1) {
          totalSelected++;
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();

          // Squared Euclidean distance (avoid sqrt for performance)
          final dr = r - avgR;
          final dg = g - avgG;
          final db = b - avgB;
          final distanceSq = dr * dr + dg * dg + db * db;

          if (distanceSq > toleranceSq) {
            filteredMask[idx] = 0;
            removedCount++;
          }
        }
      }
    }

    print('\n=== COLOR FILTERING ===');
    print('Average color: RGB($avgR,$avgG,$avgB)');
    print('Tolerance: $tolerance');
    print('Total selected: $totalSelected');
    print('Pixels removed: $removedCount');
    print('Remaining: ${totalSelected - removedCount}');
    print('========================\n');

    return filteredMask;
  }

  /// Filter mask by hue similarity only — keeps блики since they share the same hue
  /// Removes pixels with very different hue (handles door knobs, other objects)
  static Uint8List filterMaskByHueSimilarity({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List currentMask,
    required int avgR,
    required int avgG,
    required int avgB,
    required int hueTolerance,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return currentMask;

    if (currentMask.length != width * height) {
      return currentMask;
    }

    final filteredMask = Uint8List.fromList(currentMask);
    final originalHsv = _rgbToHsv(avgR, avgG, avgB);
    final targetHue = originalHsv[0];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;

        if (currentMask[idx] == 1) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();
          final pixelHsv = _rgbToHsv(r, g, b);
          final hueDiff = (pixelHsv[0] - targetHue).abs();

          // Remove pixels with very different hue (more than 30 degrees)
          if (hueDiff > hueTolerance && hueDiff < 360 - hueTolerance) {
            filteredMask[idx] = 0;
          }
        }
      }
    }

    return filteredMask;
  }

  /// Recolor ALL selected pixels using OVERLAY blend applied to grayscale
  /// For bright/medium objects: first convert to grayscale (preserves texture),
  /// then apply overlay blend with target color.
  static Uint8List recolorBrightWithOverlayFromGrayscale({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required Uint8List selectionMask,
    required int targetRed,
    required int targetGreen,
    required int targetBlue,
    double blendFactor = 1.0,
    Uint8List? woodTextureBytes,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    if (selectionMask.length != image.width * image.height) {
      return imageBytes;
    }

    img.Image? textureImg;
    if (woodTextureBytes != null) {
      final decodedTexture = img.decodeImage(woodTextureBytes);
      if (decodedTexture != null) {
        textureImg = img.copyResize(
          decodedTexture,
          width: width,
          height: height,
        );
      }
    }

    int recoloredCount = 0;

    // Pre-calculate target HSV for color blend mode
    final targetHsv = _rgbToHsv(targetRed, targetGreen, targetBlue);
    final targetH = targetHsv[0];
    final targetS = targetHsv[1];

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final index = y * image.width + x;

        if (selectionMask[index] == 1) {
          final pixel = image.getPixel(x, y);
          final originalR = pixel.r.toInt();
          final originalG = pixel.g.toInt();
          final originalB = pixel.b.toInt();

          final gray =
              (0.2126 * originalR + 0.7152 * originalG + 0.0722 * originalB)
                  .round();

          // Color blend mode: preserve luminance (gray) and apply target's hue/saturation
          // This ensures texture preservation and more saturated colors on bright areas
          final value = gray / 255.0;
          List<int> blendedRgb = _hsvToRgb(targetH, targetS, value);
          int newR = blendedRgb[0];
          int newG = blendedRgb[1];
          int newB = blendedRgb[2];

          newR = (originalR + ((newR - originalR) * blendFactor).round()).clamp(
            0,
            255,
          );
          newG = (originalG + ((newG - originalG) * blendFactor).round()).clamp(
            0,
            255,
          );
          newB = (originalB + ((newB - originalB) * blendFactor).round()).clamp(
            0,
            255,
          );

          if (textureImg != null) {
            final texPixel = textureImg.getPixel(x, y);
            final texR = texPixel.r.toInt();
            final texG = texPixel.g.toInt();
            final texB = texPixel.b.toInt();
            final texLum = (0.299 * texR + 0.587 * texG + 0.114 * texB) / 255.0;

            double baseR = newR / 255.0;
            double baseG = newG / 255.0;
            double baseB = newB / 255.0;

            double overlay(double base, double blend) {
              if (base < 0.5)
                return 2 * base * blend;
              else
                return 1 - 2 * (1 - base) * (1 - blend);
            }

            final resultR = (overlay(baseR, texLum) * 255).round().clamp(
              0,
              255,
            );
            final resultG = (overlay(baseG, texLum) * 255).round().clamp(
              0,
              255,
            );
            final resultB = (overlay(baseB, texLum) * 255).round().clamp(
              0,
              255,
            );

            image.setPixelRgb(x, y, resultR, resultG, resultB);
          } else {
            image.setPixelRgb(x, y, newR, newG, newB);
          }
          recoloredCount++;
        }
      }
    }

    print('\n=== OVERLAY FROM GRAYSCALE RECOLOR (Bright/Medium) ===');
    print('Target color: RGB($targetRed,$targetGreen,$targetBlue)');
    print('Pixels recolored: $recoloredCount');
    print('===================================================\n');

    return Uint8List.fromList(img.encodePng(image));
  }
}

/// Helper class for polygon scanline fill
class _PolygonEdge {
  final int ymin, ymax;
  final double xAtYmin;
  final double dxdy;

  _PolygonEdge(this.ymin, this.ymax, this.xAtYmin, this.dxdy);
}
