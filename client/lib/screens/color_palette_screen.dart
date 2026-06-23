import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';

class ColorPaletteScreen extends StatefulWidget {
  const ColorPaletteScreen({super.key});

  @override
  State<ColorPaletteScreen> createState() => _ColorPaletteScreenState();
}

class _ColorPaletteScreenState extends State<ColorPaletteScreen> {
  final List<String> materials = ['wood', 'metal', 'plastic', 'fabric'];
  String selectedMaterial = 'wood';
  String selectedTexture = 'wood';
  
  final Map<String, String> materialLabels = {
    'wood': 'Дерево',
    'metal': 'Металл',
    'plastic': 'Пластик', 
    'fabric': 'Ткань',
  };

  // Wood texture options
  final List<String> woodTextureFiles = ['wood1', 'wood2', 'wood3'];

  // Metal texture options
  final List<String> metalTextureFiles = ['metall1', 'metall2', 'metall3'];

  // Solid colors (no texture)
  final List<Color> solidColors = [
    const Color(0xFF8B4513), // brown
    const Color(0xFFE040FB), // purple
    const Color(0xFF2196F3), // blue
    const Color(0xFF00BCD4), // cyan
    const Color(0xFF4CAF50), // green
    const Color(0xFFF44336), // red
    const Color(0xFF9C27B0), // purple
    const Color(0xFFCDDC39), // lime
    const Color(0xFFFFEB3B), // yellow
    const Color(0xFFFF9800), // orange
    const Color(0xFF795548), // brown
    const Color(0xFF607D8B), // blue grey
  ];

  final List<Color> plasticColors = [
    const Color(0xFFE53935),
    const Color(0xFFFB8C00),
    const Color(0xFFFDD835),
    const Color(0xFF43A047),
    const Color(0xFF00ACC1),
    const Color(0xFF1E88E5),
    const Color(0xFF5E35B1),
    const Color(0xFF8E24AA),
    const Color(0xFFD81B60),
    const Color(0xFF6D4C41),
    const Color(0xFFF5F5F5),
    const Color(0xFF212121),
  ];

  final List<Color> fabricColors = [
    const Color(0xFF8D6E63),
    const Color(0xFFA1887F),
    const Color(0xFFBCAAA4),
    const Color(0xFFD7CCC8),
    const Color(0xFF37474F),
    const Color(0xFF546E7A),
    const Color(0xFF455A64),
    const Color(0xFF607D8B),
    const Color(0xFF795548),
    const Color(0xFF4E342E),
    const Color(0xFF263238),
    const Color(0xFFECEFF1),
  ];

  // Wood colors (browns)
  final List<Color> woodColors = [
    const Color(0xFF8B4513), // saddle brown
    const Color(0xFFA0522D), // sienna
    const Color(0xFFD2691E), // chocolate
    const Color(0xFFBC8F8F), // rosy brown
    const Color(0xFFCD853F), // peru
    const Color(0xFFDEB887), // burlywood
    const Color(0xFFF4A460), // sandy brown
    const Color(0xFFD2B48C), // tan
  ];

  // Metal tint colors (using texture image) - realistic metal colors
  final List<Color> metalTintColors = [
    const Color(0xFFEBB014), // gold - golden
    const Color(0xFFC0C0C0), // silver - silver
    const Color(0xFF984D25), // bronze - bronze
  ];

  // Selected index in the current color grid
  int? selectedPaletteIndex;

  List<Color> get _currentColors {
    switch (selectedTexture) {
      case 'wood':
        return woodColors;
      case 'metal':
        return metalTintColors;
      case 'plastic':
        return plasticColors;
      case 'fabric':
        return fabricColors;
      default:
        return solidColors;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildMaterialSection(),
                    const SizedBox(height: 24),
                    _buildColorTextureSection(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back arrow
          GestureDetector(
            onTap: () => Navigator.pop(context), // cancel without selection
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          ),
          // Grid icon (decorative)
          Image.asset(
            'assets/icons/Squared_Menu.png',
            width: 28,
            height: 28,
            color: Colors.white,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.grid_view, color: Colors.white, size: 28),
          ),
          // Checkmark
          GestureDetector(
            onTap: selectedPaletteIndex != null
                ? () {
                    final color = _currentColors[selectedPaletteIndex!];
                    Navigator.pop(context, color);
                  }
                : null,
            child: Icon(
              Icons.check,
              color: selectedPaletteIndex != null
                  ? Colors.white
                  : Colors.white38,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.category_outlined, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Материал',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: materials.map((material) {
            final isSelected = selectedMaterial == material;
            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedMaterial = material;
                  selectedTexture = material;
                  selectedPaletteIndex = null;
                });

                context.read<AppState>().setSelectedMaterial(material);
                
                if (material != 'wood') {
                  context.read<AppState>().setSelectedWoodTexture(null);
                }
                if (material != 'metal') {
                  context.read<AppState>().setSelectedMetalTexture(null);
                }
              },
              child: Container(
                width: 112,
                height: 52,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF0A84FF)
                      : const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white12,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _materialIcon(material),
                      color: isSelected ? Colors.white : Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _materialLabel(material),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  IconData _materialIcon(String material) {
    switch (material) {
      case 'wood':
        return Icons.table_chart;
      case 'metal':
        return Icons.auto_awesome_mosaic;
      case 'plastic':
        return Icons.opacity_outlined;
      case 'fabric':
        return Icons.grid_view;
      default:
        return Icons.category_outlined;
    }
  }
  
  String _materialLabel(String material) {
    return materialLabels[material] ?? material;
  }

  Widget _buildColorTextureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            const Icon(Icons.palette_outlined, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Палитра цветов и текстур',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildColorGrid(),
        // Texture selector for wood
        if (selectedTexture == 'wood') _buildTextureSelector(),
        // Texture selector for metal
        if (selectedTexture == 'metal') _buildMetalTextureSelector(),
      ],
    );
  }

  Widget _buildTextureSelector() {
    final appState = Provider.of<AppState>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.texture, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Текстура дерева',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Wood texture options
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // No texture option
            GestureDetector(
              onTap: () {
                setState(() {});
                appState.setSelectedWoodTexture(null);
              },
              child: Consumer<AppState>(
                builder: (context, appState, _) {
                  final isSelected = appState.selectedWoodTexture == null;
                  return Container(
                    width: 110,
                    height: 75,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Нет',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Wood texture options
            ...woodTextureFiles.asMap().entries.map((entry) {
              final index = entry.key;
              final textureFile = entry.value;
              return _buildTextureTile(textureFile, index);
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildTextureTile(String textureFile, int index) {
    final appState = Provider.of<AppState>(context);
    final isSelected = appState.selectedWoodTexture == textureFile;
    return GestureDetector(
      onTap: () {
        setState(() {});
        appState.setSelectedWoodTexture(textureFile);
      },
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          final color = appState.selectedColor;
          return Container(
            width: 110,
            height: 75,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(color, BlendMode.modulate),
              child: Image.asset(
                'assets/textures/$textureFile.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: color);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  // Metal texture selector (similar to wood)
  Widget _buildMetalTextureSelector() {
    final appState = Provider.of<AppState>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.texture, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Текстура металла',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // No texture option
            GestureDetector(
              onTap: () {
                setState(() {});
                appState.setSelectedMetalTexture(null);
              },
              child: Consumer<AppState>(
                builder: (context, appState, _) {
                  final isSelected = appState.selectedMetalTexture == null;
                  return Container(
                    width: 110,
                    height: 75,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Нет',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Metal texture options
            ...metalTextureFiles.asMap().entries.map((entry) {
              final index = entry.key;
              final textureFile = entry.value;
              return _buildMetalTextureTile(textureFile, index);
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildMetalTextureTile(String textureFile, int index) {
    final appState = Provider.of<AppState>(context);
    final isSelected = appState.selectedMetalTexture == textureFile;
    return GestureDetector(
      onTap: () {
        setState(() {});
        appState.setSelectedMetalTexture(textureFile);
      },
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          final color = appState.selectedColor;
          return Container(
            width: 110,
            height: 75,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(color, BlendMode.modulate),
              child: Image.asset(
                'assets/textures/$textureFile.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: color);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorGrid() {
    final colors = _currentColors;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.4,
      ),
      itemCount: colors.length,
      itemBuilder: (context, index) {
        final isSelected = selectedPaletteIndex == index;
        final color = colors[index];
        if (selectedTexture == 'metal') {
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedPaletteIndex = index;
              });
            },
            child: _buildMetalTile(index, isSelected),
          );
        } else {
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedPaletteIndex = index;
              });
            },
            child: _buildColorTile(color, isSelected),
          );
        }
      },
    );
  }

  Widget _buildColorTile(Color color, bool isSelected) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        if (isSelected)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: const Center(
                child: Icon(Icons.check, color: Colors.white, size: 20),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMetalTile(int metalIndex, bool isSelected) {
    final tintColor = metalTintColors[metalIndex];
    String imagePath;
    switch (metalIndex) {
      case 0: // gold
        imagePath = 'assets/metall/Rectangle 863.png';
        break;
      case 1: // silver
        imagePath = 'assets/metall/Rectangle 864.png';
        break;
      case 2: // bronze
        imagePath = 'assets/metall/Rectangle 865.png';
        break;
      default:
        imagePath = 'assets/textures/metal_texture.png';
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            imagePath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to solid color if image fails to load
              return Container(color: tintColor);
            },
          ),
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: const Center(
                child: Icon(Icons.check, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}
