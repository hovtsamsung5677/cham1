import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';

class ColorPaletteScreen extends StatefulWidget {
  const ColorPaletteScreen({super.key});

  @override
  State<ColorPaletteScreen> createState() => _ColorPaletteScreenState();
}

class _ColorPaletteScreenState extends State<ColorPaletteScreen> {
  // Texture filters
  final List<String> textureFilters = ['Без текстуры', 'Дерево', 'Металл'];
  String selectedTexture = 'Без текстуры';

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
      case 'Дерево':
        return woodColors;
      case 'Металл':
        return metalTintColors;
      case 'Без текстуры':
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
                    _buildMyPaletteSection(),
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

  Widget _buildMyPaletteSection() {
    final appState = Provider.of<AppState>(context);
    final myPaletteColors = appState.myPaletteColors;
    final emptySlots = AppState.maxPaletteSlots - myPaletteColors.length;
    final showEmptySlots = emptySlots > 0 ? emptySlots.clamp(0, 3) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/icons/Love.png',
                  width: 20,
                  height: 20,
                  color: Colors.white,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.favorite, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Моя палитра',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  appState.clearMyPalette();
                });
              },
              child: const Text(
                'Удалить все',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Palette grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Filled color slots
            ...myPaletteColors.asMap().entries.map((entry) {
              final index = entry.key;
              final color = entry.value;
              return _buildMyPaletteColorTile(color, index);
            }),
            // Empty slots with + button
            ...List.generate(showEmptySlots, (i) => _buildEmptyPaletteSlot()),
          ],
        ),
      ],
    );
  }

  Widget _buildMyPaletteColorTile(Color color, int index) {
    return GestureDetector(
      onTap: () {
        // Delete from my palette
        Provider.of<AppState>(
          context,
          listen: false,
        ).removeFromMyPalette(index);
      },
      child: Container(
        width: 72,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF0A84FF),
            width: index == 0 ? 2.5 : 0,
          ),
        ),
        child: index == 0
            ? const Center(
                child: Icon(
                  Icons.delete_outline,
                  color: Colors.white,
                  size: 22,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildEmptyPaletteSlot() {
    return Container(
      width: 72,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.add, color: Colors.white54, size: 24),
      ),
    );
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
        // Texture filter chips
        Row(
          children: textureFilters.map((filter) {
            final isSelected = selectedTexture == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    selectedTexture = filter;
                    selectedPaletteIndex = null; // reset selection
                  });
                  // Reset wood texture when switching away from 'Дерево'
                  if (filter != 'Дерево') {
                    context.read<AppState>().setSelectedWoodTexture(null);
                  }
                  // Reset metal texture when switching away from 'Металл'
                  if (filter != 'Металл') {
                    context.read<AppState>().setSelectedMetalTexture(null);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF636366)
                        : const Color(0xFF3A3A3C),
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? Border.all(color: Colors.white24, width: 1)
                        : null,
                  ),
                  child: Text(
                    filter,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        // Color grid
        _buildColorGrid(),
        // Texture selector for wood
        if (selectedTexture == 'Дерево') _buildTextureSelector(),
        // Texture selector for metal
        if (selectedTexture == 'Металл') _buildMetalTextureSelector(),
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
        // Texture options: "Без текстуры" + wood1, wood2, wood3
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
        if (selectedTexture == 'Металл') {
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedPaletteIndex = index;
              });
              Provider.of<AppState>(
                context,
                listen: false,
              ).addToMyPalette(color);
            },
            child: _buildMetalTile(index, isSelected),
          );
        } else {
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedPaletteIndex = index;
              });
              Provider.of<AppState>(
                context,
                listen: false,
              ).addToMyPalette(color);
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
