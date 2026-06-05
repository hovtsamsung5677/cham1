import 'package:flutter/material.dart';
import '../models/selection_tool.dart';

class ToolBarWidget extends StatelessWidget implements PreferredSizeWidget {
  final SelectionTool currentTool;
  final double brushSize;
  final Function(SelectionTool) onToolChanged;
  final Function(double) onBrushSizeChanged;
  final VoidCallback onColorPick;
  final VoidCallback onPreview;
  final VoidCallback onReset;
  final VoidCallback onSave;
  final VoidCallback onCancelPreview;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool hasSelection;
  final bool isPreviewMode;
  final Color selectedColor;

  const ToolBarWidget({
    super.key,
    required this.currentTool,
    required this.brushSize,
    required this.onToolChanged,
    required this.onBrushSizeChanged,
    required this.onColorPick,
    required this.onPreview,
    required this.onReset,
    required this.onSave,
    required this.onCancelPreview,
    this.onUndo,
    this.onRedo,
    required this.hasSelection,
    this.isPreviewMode = false,
    required this.selectedColor,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child));
      },
      child: isPreviewMode
          ? _PreviewToolbar(key: const ValueKey('preview_toolbar'), onCancelPreview: onCancelPreview, onColorPick: onColorPick, onSave: onSave)
          : _EditorToolbar(
              key: const ValueKey('editor_toolbar'),
              currentTool: currentTool,
              brushSize: brushSize,
              onToolChanged: onToolChanged,
              onBrushSizeChanged: onBrushSizeChanged,
              onColorPick: onColorPick,
              onPreview: onPreview,
              onReset: onReset,
              onSave: onSave,
              onUndo: onUndo,
              onRedo: onRedo,
              hasSelection: hasSelection,
              selectedColor: selectedColor,
            ),
    );
  }
}

class _PreviewToolbar extends StatelessWidget {
  final VoidCallback onCancelPreview;
  final VoidCallback onColorPick;
  final VoidCallback onSave;

  const _PreviewToolbar({super.key, required this.onCancelPreview, required this.onColorPick, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _PreviewActionButton(icon: Icons.edit, label: 'Редактировать', onTap: onCancelPreview),
          _PreviewActionButton(icon: Icons.color_lens, label: 'Цвет', onTap: onColorPick),
          _PreviewActionButton(icon: Icons.save, label: 'Сохранить', onTap: onSave),
        ],
      ),
    );
  }
}

class _PreviewActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PreviewActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 200),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(scale: Curves.easeOut.transform(value), child: child);
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  final SelectionTool currentTool;
  final double brushSize;
  final Function(SelectionTool) onToolChanged;
  final Function(double) onBrushSizeChanged;
  final VoidCallback onColorPick;
  final VoidCallback onPreview;
  final VoidCallback onReset;
  final VoidCallback onSave;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool hasSelection;
  final Color selectedColor;

  const _EditorToolbar({
    super.key,
    required this.currentTool,
    required this.brushSize,
    required this.onToolChanged,
    required this.onBrushSizeChanged,
    required this.onColorPick,
    required this.onPreview,
    required this.onReset,
    required this.onSave,
    this.onUndo,
    this.onRedo,
    required this.hasSelection,
    required this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolButtonRow(
            currentTool: currentTool,
            onToolChanged: onToolChanged,
          ),
          const SizedBox(height: 12),
          BrushSizeSlider(
            currentTool: currentTool,
            brushSize: brushSize,
            onBrushSizeChanged: onBrushSizeChanged,
          ),
          _ActionButtonsRow(
            onUndo: onUndo,
            onRedo: onRedo,
            onColorPick: onColorPick,
            selectedColor: selectedColor,
            onPreview: onPreview,
            hasSelection: hasSelection,
            onReset: onReset,
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}

class _ToolButtonRow extends StatelessWidget {
  final SelectionTool currentTool;
  final Function(SelectionTool) onToolChanged;

  const _ToolButtonRow({required this.currentTool, required this.onToolChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _AnimatedToolButton(
          tool: SelectionTool.interactiveSegmentation,
          icon: Icons.auto_fix_high,
          isSelected: currentTool == SelectionTool.interactiveSegmentation,
          onTap: () => onToolChanged(SelectionTool.interactiveSegmentation),
        ),
        _AnimatedToolButton(
          tool: SelectionTool.rectangle,
          icon: Icons.crop,
          isSelected: currentTool == SelectionTool.rectangle,
          onTap: () => onToolChanged(SelectionTool.rectangle),
        ),
        _AnimatedToolButton(
          tool: SelectionTool.brush,
          icon: Icons.brush,
          isSelected: currentTool == SelectionTool.brush,
          onTap: () => onToolChanged(SelectionTool.brush),
        ),
        _AnimatedToolButton(
          tool: SelectionTool.eraser,
          icon: Icons.cleaning_services,
          isSelected: currentTool == SelectionTool.eraser,
          onTap: () => onToolChanged(SelectionTool.eraser),
        ),
        _AnimatedToolButton(
          tool: SelectionTool.fill,
          icon: Icons.format_color_fill,
          isSelected: currentTool == SelectionTool.fill,
          onTap: () => onToolChanged(SelectionTool.fill),
        ),
      ],
    );
  }
}

class _AnimatedToolButton extends StatelessWidget {
  final SelectionTool tool;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedToolButton({
    required this.tool,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 200),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.all(isSelected ? 12 : 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(isSelected ? 12 : 8),
            border: Border.all(color: isSelected ? Colors.blue : Colors.white24),
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.white : Colors.white70,
            size: isSelected ? 28 : 24,
          ),
        ),
      ),
    );
  }
}

class _ActionButtonsRow extends StatelessWidget {
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onColorPick;
  final Color selectedColor;
  final VoidCallback onPreview;
  final bool hasSelection;
  final VoidCallback onReset;
  final VoidCallback onSave;

  const _ActionButtonsRow({
    required this.onUndo,
    required this.onRedo,
    required this.onColorPick,
    required this.selectedColor,
    required this.onPreview,
    required this.hasSelection,
    required this.onReset,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 350),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 30),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _AnimatedActionButton(
            icon: Icons.undo,
            label: 'Отмена',
            onTap: onUndo,
            enabled: onUndo != null,
          ),
          _AnimatedActionButton(
            icon: Icons.redo,
            label: 'Повтор',
            onTap: onRedo,
            enabled: onRedo != null,
          ),
          GestureDetector(
            onTap: onColorPick,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Цвет', style: TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ),
          ),
          _AnimatedActionButton(
            icon: Icons.preview,
            label: 'Превью',
            onTap: hasSelection ? onPreview : null,
            enabled: hasSelection,
          ),
          _AnimatedActionButton(
            icon: Icons.refresh,
            label: 'Сброс',
            onTap: hasSelection ? onReset : null,
            enabled: hasSelection,
          ),
          _AnimatedActionButton(
            icon: Icons.save,
            label: 'Сохранить',
            onTap: hasSelection ? onSave : null,
            enabled: hasSelection,
          ),
        ],
      ),
    );
  }
}

class _AnimatedActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  const _AnimatedActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 1.0,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: enabled ? Colors.white : Colors.white38, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: enabled ? Colors.white70 : Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BrushSizeSlider extends StatelessWidget {
  final SelectionTool currentTool;
  final double brushSize;
  final Function(double) onBrushSizeChanged;

  const BrushSizeSlider({
    super.key,
    required this.currentTool,
    required this.brushSize,
    required this.onBrushSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (currentTool != SelectionTool.brush && currentTool != SelectionTool.eraser) {
      return const SizedBox.shrink();
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Размер кисти:', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: brushSize,
                  min: 10,
                  max: 100,
                  activeColor: Colors.blue,
                  inactiveColor: Colors.white24,
                  onChanged: onBrushSizeChanged,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Text(
                  '${brushSize.round()}',
                  key: ValueKey(brushSize.round()),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}