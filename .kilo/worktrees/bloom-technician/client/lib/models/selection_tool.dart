/// Enum representing different selection tools for image editing
enum SelectionTool {
  /// Free-form lasso selection tool
  lasso,

  /// Brush tool for painting selection
  brush,

  /// Polygon selection tool (tap to add points)
  polygon,

  /// Interactive segmentation with grab-cut like algorithm
  interactiveSegmentation,

  /// Rectangle selection tool (draw and resize rectangle)
  rectangle,

  /// Eraser tool for removing selection
  eraser,

  /// Fill tool for filling selection
  fill,

  /// Hand tool for panning the image
  hand,
}

/// Extension to get display name and icon for each tool
extension SelectionToolExtension on SelectionTool {
  String get displayName {
    switch (this) {
      case SelectionTool.lasso:
        return 'Лассо';
      case SelectionTool.brush:
        return 'Кисть';
      case SelectionTool.polygon:
        return 'Полигон';
      case SelectionTool.interactiveSegmentation:
        return 'Сегментация';
      case SelectionTool.rectangle:
        return 'Прямоугольник';
      case SelectionTool.eraser:
        return 'Ластик';
      case SelectionTool.fill:
        return 'Заливка';
      case SelectionTool.hand:
        return 'Рука';
    }
  }

  String get iconName {
    switch (this) {
      case SelectionTool.lasso:
        return 'gesture';
      case SelectionTool.brush:
        return 'brush';
      case SelectionTool.polygon:
        return 'pentagon';
      case SelectionTool.interactiveSegmentation:
        return 'auto_fix_high';
      case SelectionTool.rectangle:
        return 'crop';
      case SelectionTool.eraser:
        return 'eraser';
      case SelectionTool.fill:
        return 'format_color_fill';
      case SelectionTool.hand:
        return 'Hand Cursor';
    }
  }
}
