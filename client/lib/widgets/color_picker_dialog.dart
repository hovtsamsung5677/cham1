import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../utils/transitions.dart';

/// Dialog for selecting color to recolor furniture
class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final Function(Color) onColorSelected;
  final Function(Color)? onColorChanged; // Optional callback for live preview

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
    this.onColorChanged,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _selectedColor;
  final TextEditingController _hexController = TextEditingController();

  // Preset furniture colors
  static const List<Color> _presetColors = [
    // Wood tones
    Color(0xFF8B4513), // Saddle Brown
    Color(0xFFA0522D), // Sienna
    Color(0xFFCD853F), // Peru
    Color(0xFFDEB887), // Burlywood
    Color(0xFFD2691E), // Chocolate
    Color(0xFFF0BC79), // Wood
    Color(0xFF5D4037), // Dark wood
    // Metals
    Color(0xFFEBB014), // Gold
    Color(0xFFC0C0C0), // Silver
    Color(0xFFCD7F32), // Bronze
    // Modern colors
    Color(0xFF2196F3), // Blue
    Color(0xFF4CAF50), // Green
    Color(0xFFF44336), // Red
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF9C27B0), // Purple
    Color(0xFFFF5722), // Orange
    Color(0xFF00BCD4), // Cyan
    Color(0xFF607D8B), // Blue Grey
    // Whites and grays
    Color(0xFFFFFFFF), // White
    Color(0xFFF5F5F5), // White Smoke
    Color(0xFFE0E0E0), // Light Gray
    Color(0xFF9E9E9E), // Grey
    Color(0xFF424242), // Dark Grey
    Color(0xFF212121), // Charcoal
    // Modern furniture colors
    Color(0xFF1A237E), // Navy
    Color(0xFF004D40), // Teal
    Color(0xFFBF360C), // Rust
    Color(0xFF3E2723), // Espresso
    Color(0xFF263238), // Charcoal Blue
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _updateHexController();
  }

  void _updateHexController() {
    final hexStr = _selectedColor.value
        .toRadixString(16)
        .substring(2)
        .toUpperCase();
    _hexController.text = '#$hexStr';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: FadeAnimatedWidget(
        visible: true,
        duration: const Duration(milliseconds: 400),
        child: SlideAnimatedWidget(
          visible: true,
          duration: const Duration(milliseconds: 350),
          offset: const Offset(0, 0.1),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 500),
                    tween: Tween(begin: 0, end: 1),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                    child: const Text(
                      'Выберите цвет',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selected color preview - с плавной сменой
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _selectedColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: _selectedColor.withAlpha((0.4 * 255).toInt()),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _getColorName(_selectedColor),
                        style: TextStyle(
                          color: _selectedColor.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // HEX input
                  TextField(
                    controller: _hexController,
                    decoration: const InputDecoration(
                      labelText: 'HEX код',
                      border: OutlineInputBorder(),
                      prefixText: '#',
                    ),
                    onChanged: (value) {
                      if (value.length == 6) {
                        try {
                          final colorValue = int.parse('FF$value', radix: 16);
                          setState(() {
                            _selectedColor = Color(colorValue);
                          });
                          if (widget.onColorChanged != null) {
                            widget.onColorChanged!(_selectedColor);
                          }
                        } catch (e) {}
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Color wheel using flex_color_picker - с анимацией иконок
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 400),
                    tween: Tween(begin: 0, end: 1),
                    builder: (context, value, child) {
                      return Opacity(opacity: value, child: child);
                    },
                    child: ColorPicker(
                      color: _selectedColor,
                      onColorChanged: (Color color) {
                        setState(() {
                          _selectedColor = color;
                          _updateHexController();
                        });
                        if (widget.onColorChanged != null) {
                          widget.onColorChanged!(color);
                        }
                      },
                      width: 44,
                      height: 44,
                      borderRadius: 22,
                      spacing: 5,
                      runSpacing: 5,
                      wheelDiameter: 155,
                      wheelWidth: 18,
                      wheelHasBorder: true,
                      borderColor: Colors.grey.shade300,
                      showColorCode: false,
                      colorCodeHasColor: true,
                      pickersEnabled: const <ColorPickerType, bool>{
                        ColorPickerType.both: false,
                        ColorPickerType.primary: true,
                        ColorPickerType.accent: true,
                        ColorPickerType.bw: true,
                        ColorPickerType.custom: false,
                        ColorPickerType.wheel: true,
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Preset colors - с staggered анимацией
                  const Text(
                    'Готовые цвета:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: GridView.builder(
                      scrollDirection: Axis.horizontal,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: _presetColors.length,
                      itemBuilder: (context, index) {
                        final color = _presetColors[index];
                        final isSelected = color.value == _selectedColor.value;

                        return TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 200 + (index * 30)),
                          tween: Tween(begin: 0, end: 1),
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: value,
                              child: Opacity(opacity: value, child: child),
                            );
                          },
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColor = color;
                                _updateHexController();
                              });
                              if (widget.onColorChanged != null) {
                                widget.onColorChanged!(color);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.black
                                      : Colors.grey.shade300,
                                  width: isSelected ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // RGB values
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildRgbValue('R', _selectedColor.red),
                      _buildRgbValue('G', _selectedColor.green),
                      _buildRgbValue('B', _selectedColor.blue),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Action buttons - с анимацией
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 400),
                    tween: Tween(begin: 0, end: 1),
                    curve: const Interval(0.5, 1),
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, (1 - value) * 20),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(width: 8),
                        AnimatedScale(
                          scale: 1,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          child: ElevatedButton(
                            onPressed: () => widget.onColorSelected(_selectedColor),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _selectedColor,
                              foregroundColor: _selectedColor.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            child: const Text('Применить'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRgbValue(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(value.toString(), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _getColorName(Color color) {
    // Simple color naming
    if (color == const Color(0xFF8B4513)) return 'Коричневый';
    if (color == const Color(0xFFA0522D)) return 'Сиена';
    if (color == const Color(0xFFCD853F)) return 'Перу';
    if (color == const Color(0xFFEBB014)) return 'Золотой';
    if (color == const Color(0xFFC0C0C0)) return 'Серебряный';
    if (color == const Color(0xFFCD7F32)) return 'Бронза';
    if (color == const Color(0xFF2196F3)) return 'Синий';
    if (color == const Color(0xFF4CAF50)) return 'Зелёный';
    if (color == const Color(0xFFF44336)) return 'Красный';
    if (color == const Color(0xFFFFFFFF)) return 'Белый';
    if (color == const Color(0xFF212121)) return 'Тёмно-серый';

    // Calculate color name based on hue
    final hsv = HSVColor.fromColor(color);
    if (hsv.saturation < 0.1) {
      if (hsv.value > 0.8) return 'Белый';
      if (hsv.value > 0.5) return 'Светло-серый';
      return 'Серый';
    }

    final hue = hsv.hue;
    if (hue < 15 || hue >= 345) return 'Красный';
    if (hue < 45) return 'Оранжевый';
    if (hue < 75) return 'Жёлтый';
    if (hue < 150) return 'Зелёный';
    if (hue < 210) return 'Голубой';
    if (hue < 270) return 'Синий';
    if (hue < 315) return 'Фиолетовый';
    return 'Розовый';
  }
}
