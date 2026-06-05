import 'package:flutter/material.dart';
import 'dart:math' as math;

class ColorPickerScreen extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const ColorPickerScreen({
    super.key,
    this.initialColor = const Color(0xFF9B00FF),
    required this.onColorChanged,
  });

  @override
  State<ColorPickerScreen> createState() => _ColorPickerScreenState();
}

class _ColorPickerScreenState extends State<ColorPickerScreen> {
  late double hue;
  late double saturation;
  late double brightness;

  static const double _innerRatio = 0.54;
  static const double _diamondRatio = 0.54 * 0.92;

  Color get currentColor => HSVColor.fromAHSV(1.0, hue, saturation / 100, brightness / 100).toColor();

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    hue = hsv.hue;
    saturation = hsv.saturation * 100;
    brightness = hsv.value * 100;
  }

  void _updateColor({double? newHue, double? newSaturation, double? newBrightness}) {
    final hasChanges = newHue != null || newSaturation != null || newBrightness != null;
    if (hasChanges) {
      setState(() {
        if (newHue != null) hue = newHue;
        if (newSaturation != null) saturation = newSaturation;
        if (newBrightness != null) brightness = newBrightness;
      });
      widget.onColorChanged(currentColor);
    }
  }

  void _handleTouch(Offset local, double size) {
    final cx = size / 2;
    final cy = size / 2;
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final outerR = size / 2;
    final innerR = outerR * _innerRatio;
    final diamondR = outerR * _diamondRatio;
    final half = diamondR / math.sqrt2;

    if (dist >= innerR && dist <= outerR) {
      final angle = math.atan2(dy, dx);
      _updateColor(newHue: ((angle * 180 / math.pi) + 360) % 360);
    } else if (dist < innerR) {
      final cos45 = math.cos(-math.pi / 4);
      final sin45 = math.sin(-math.pi / 4);
      final rx = dx * cos45 - dy * sin45;
      final ry = dx * sin45 + dy * cos45;
      _updateColor(
        newSaturation: ((rx / half + 1) / 2 * 100).clamp(0, 100),
        newBrightness: ((1 - (ry / half + 1) / 2) * 100).clamp(0, 100),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C2C2E),
      body: Stack(
        children: [
          const Positioned.fill(child: _ColorPickerBackground()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildColorWheel(),
                const SizedBox(height: 24),
                _buildSliders(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _IconButton(icon: Icons.close, onTap: () => Navigator.pop(context)),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: currentColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38, width: 2),
            ),
          ),
          _IconButton(icon: Icons.check, onTap: () => Navigator.pop(context, currentColor)),
        ],
      ),
    );
  }

  Widget _buildColorWheel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          LayoutBuilder(
            builder: (ctx, bc) {
              final size = bc.maxWidth;
              return GestureDetector(
                onTapDown: (d) => _handleTouch(d.localPosition, size),
                onPanUpdate: (d) => _handleTouch(d.localPosition, size),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: _ColorWheelPainter(hue: hue, saturation: saturation, brightness: brightness),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSliders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Center(
        child: SizedBox(
          width: 240,
          child: Column(
            children: [
              _AnimatedHsbRow(
                label: 'H',
                value: hue,
                max: 360,
                trackGradient: const LinearGradient(
                  colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000)],
                ),
                onChanged: (v) => _updateColor(newHue: v),
              ),
              const SizedBox(height: 10),
              _AnimatedHsbRow(
                label: 'S',
                value: saturation,
                max: 100,
                trackGradient: LinearGradient(
                  colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
                ),
                onChanged: (v) => _updateColor(newSaturation: v),
              ),
              const SizedBox(height: 10),
              _AnimatedHsbRow(
                label: 'B',
                value: brightness,
                max: 100,
                trackGradient: LinearGradient(
                  colors: [Colors.black, HSVColor.fromAHSV(1, hue, saturation / 100, 1).toColor()],
                ),
                onChanged: (v) => _updateColor(newBrightness: v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPickerBackground extends StatelessWidget {
  const _ColorPickerBackground();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white70, size: 24),
      ),
    );
  }
}

class _AnimatedHsbRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Gradient trackGradient;
  final ValueChanged<double> onChanged;

  const _AnimatedHsbRow({
    required this.label,
    required this.value,
    required this.max,
    required this.trackGradient,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 200),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, opacity, child) {
        return Opacity(opacity: opacity, child: child);
      },
      child: Row(
        children: [
          SizedBox(width: 14, child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12))),
          const SizedBox(width: 6),
          GestureDetector(onTap: () => onChanged((value - 1).clamp(0, max)), child: const Text('−', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 18))),
          const SizedBox(width: 4),
          Expanded(child: _GradientSlider(value: value, max: max, gradient: trackGradient, onChanged: onChanged)),
          const SizedBox(width: 4),
          GestureDetector(onTap: () => onChanged((value + 1).clamp(0, max)), child: const Text('+', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 18))),
          const SizedBox(width: 8),
          SizedBox(width: 32, child: Text(value.round().toString(), textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12))),
        ],
      ),
    );
  }
}

class _GradientSlider extends StatelessWidget {
  final double value;
  final double max;
  final Gradient gradient;
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.value,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, bc) {
        return GestureDetector(
          onHorizontalDragUpdate: (d) => onChanged((value + d.delta.dx / bc.maxWidth * max).clamp(0.0, max)),
          onTapDown: (d) => onChanged((d.localPosition.dx / bc.maxWidth * max).clamp(0.0, max)),
          child: SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(3)),
                ),
                Positioned(
                  left: (value / max * bc.maxWidth - 11).clamp(0.0, bc.maxWidth - 22),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 150),
                    tween: Tween(begin: 0.8, end: 1.0),
                    curve: Curves.easeOut,
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))],
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
  }
}

class _ColorWheelPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double brightness;

  const _ColorWheelPainter({required this.hue, required this.saturation, required this.brightness});

@override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final outerR = size.width / 2;
    final innerR = outerR * 0.54;

    final paint = Paint()..style = PaintingStyle.fill;
    for (int deg = 0; deg < 360; deg++) {
      final rad = deg * math.pi / 180;
      final start = rad;
      final end = (deg + 1) * math.pi / 180;
      final color = HSVColor.fromAHSV(1.0, deg.toDouble(), 1.0, 1.0).toColor();
      paint.color = color;

      final path = Path()
        ..arcTo(Rect.fromCircle(center: center, radius: outerR), start, end - start, false)
        ..arcTo(Rect.fromCircle(center: center, radius: innerR), end, start - end, false)
        ..close();
      canvas.drawPath(path, paint);
    }

    final diamondR = innerR * 0.92;
    final half = diamondR / math.sqrt2;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(math.pi / 4);
    final rect = Rect.fromCenter(center: Offset.zero, width: half * 2, height: half * 2);
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [Colors.white, hueColor]).createShader(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]).createShader(rect)
        ..blendMode = BlendMode.multiply,
    );
    canvas.restore();

    final normS = saturation / 100;
    final normB = brightness / 100;
    final sqX = (normS - 0.5) * half * 2;
    final sqY = (0.5 - normB) * half * 2;
    final cos45 = math.cos(math.pi / 4);
    final sin45 = math.sin(math.pi / 4);
    final dotX = cx + sqX * cos45 - sqY * sin45;
    final dotY = cy + sqX * sin45 + sqY * cos45;

    canvas.drawCircle(Offset(dotX, dotY), 11, Paint()..color = Colors.black38..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset(dotX, dotY), 9, Paint()..color = HSVColor.fromAHSV(1, hue, normS, normB).toColor());
    canvas.drawCircle(Offset(dotX, dotY), 9, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);

    final ringMid = (outerR + innerR) / 2;
    final hueAngle = hue * math.pi / 180;
    final hueX = cx + ringMid * math.cos(hueAngle);
    final hueY = cy + ringMid * math.sin(hueAngle);

    canvas.drawCircle(Offset(hueX, hueY), (outerR - innerR) / 2 + 2, Paint()..color = Colors.black38..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(Offset(hueX, hueY), (outerR - innerR) / 2, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_ColorWheelPainter old) => old.hue != hue || old.saturation != saturation || old.brightness != brightness;
}