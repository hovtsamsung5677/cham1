import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'selection_tool.dart';

/// Represents a saved project (edited photo) — immutable model
@immutable
class Project {
  final int id;
  final Uint8List imageBytes;
  final bool liked;
  final DateTime createdAt;

  Project({required this.imageBytes, this.liked = false, DateTime? createdAt})
    : id = DateTime.now().millisecondsSinceEpoch,
      createdAt = createdAt ?? DateTime.now();

  Project copyWith({Uint8List? imageBytes, bool? liked, DateTime? createdAt}) {
    return Project(
      imageBytes: imageBytes ?? this.imageBytes,
      liked: liked ?? this.liked,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageBytes': base64Encode(imageBytes),
        'liked': liked,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      imageBytes: base64Decode(json['imageBytes'] as String),
      liked: json['liked'] as bool? ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }
}

/// Application state model
class AppState extends ChangeNotifier {
  // Current stage of the application
  AppStage _currentStage = AppStage.camera;
  AppStage get currentStage => _currentStage;

  // Captured image
  Uint8List? _capturedImage;
  Uint8List? get capturedImage => _capturedImage;

  // Selection mask (1 = selected, 0 = not selected)
  Uint8List _selectionMask = Uint8List(0);
  Uint8List get selectionMask => _selectionMask;

  // Undo/Redo history for selection mask
  final List<Uint8List> _maskHistory = [];
  int _historyIndex = -1;

  // Current selection tool
  SelectionTool _currentTool = SelectionTool.brush;
  SelectionTool get currentTool => _currentTool;

  // Selected color for recoloring
  Color _selectedColor = const Color(0xFF8B4513); // Default wood brown
  Color get selectedColor => _selectedColor;

  // Selected wood texture (for tree color selection)
  String?
  _selectedWoodTexture; // 'wood1', 'wood2', 'wood3', or null for no texture
  String? get selectedWoodTexture => _selectedWoodTexture;

  void setSelectedWoodTexture(String? texture) {
    _selectedWoodTexture = texture;
    notifyListeners();
  }

  // Selected metal texture (for metal color selection)
  String?
  _selectedMetalTexture; // 'metall1', 'metall2', 'metall3', or null for no texture
  String? get selectedMetalTexture => _selectedMetalTexture;

  void setSelectedMetalTexture(String? texture) {
    _selectedMetalTexture = texture;
    notifyListeners();
  }

  // Preview mode
  bool _isPreviewMode = false;
  bool get isPreviewMode => _isPreviewMode;

  // Preview recolored image
  Uint8List? _previewImage;
  Uint8List? get previewImage => _previewImage;

  // Brush size for selection
  double _brushSize = 30.0;
  double get brushSize => _brushSize;

  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Error message
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // My palette (max 8 colors)
  final List<Color> _myPaletteColors = [];
  List<Color> get myPaletteColors => List.unmodifiable(_myPaletteColors);
  static const int maxPaletteSlots = 8;

  void addToMyPalette(Color color) {
    if (_myPaletteColors.length < maxPaletteSlots) {
      _myPaletteColors.add(color);
      notifyListeners();
    }
  }

  void removeFromMyPalette(int index) {
    if (index >= 0 && index < _myPaletteColors.length) {
      _myPaletteColors.removeAt(index);
      notifyListeners();
    }
  }

  void clearMyPalette() {
    _myPaletteColors.clear();
    notifyListeners();
  }

  // Projects history
  final List<Project> _projects = [];
  List<Project> get projects => List.unmodifiable(_projects);

  List<Project> get sortedProjects {
    final sorted = List<Project>.from(_projects);
    sorted.sort((a, b) {
      if (a.liked && !b.liked) return -1;
      if (!a.liked && b.liked) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return List.unmodifiable(sorted);
  }

  Future<void> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final projectsJson = prefs.getStringList('projects') ?? [];
    _projects.clear();
    for (final jsonStr in projectsJson) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _projects.add(Project.fromJson(json));
      } catch (e) {
        debugPrint('Failed to load project: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final projectsJson = _projects.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList('projects', projectsJson);
  }

  void addProject(Uint8List imageBytes) {
    _projects.insert(0, Project(imageBytes: imageBytes));
    _saveProjects();
    notifyListeners();
  }

  void deleteProject(int projectId) {
    _projects.removeWhere((p) => p.id == projectId);
    _saveProjects();
    notifyListeners();
  }

  void toggleProjectLike(int projectId) {
    final index = _projects.indexWhere((p) => p.id == projectId);
    if (index == -1) return;
    _projects[index] = _projects[index].copyWith(
      liked: !_projects[index].liked,
    );
    _saveProjects();
    notifyListeners();
  }

  /// Update stage
  void setStage(AppStage stage) {
    _currentStage = stage;
    notifyListeners();
  }

  /// Set captured image
  void setCapturedImage(Uint8List? image) {
    _capturedImage = image;
    _selectionMask = Uint8List(0);
    _previewImage = null;
    _isPreviewMode = false;
    // Reset history and save initial empty state
    _maskHistory.clear();
    _historyIndex = -1;
    if (image != null) {
      // Save initial empty mask so we can undo the first action
      _saveToHistory(Uint8List(0));
    }
    notifyListeners();
  }

  /// Set selection mask
  void setSelectionMask(Uint8List mask) {
    // Always save new state to history (mask changes on every brush stroke)
    _selectionMask = mask;
    _previewImage = null;
    _saveToHistory(mask);
    notifyListeners();

    // Логируем базовую статистику выделения
    final selectedCount = mask.where((p) => p == 1).length;
    // ignore: avoid_print
    if (selectedCount > 0) {
      print('[Selection] Маска обновлена: выделено $selectedCount пикселей');
      // ignore: avoid_print
      print(
        '  (Для классификации по яркости нажмите "Превью" или завершите выделение)',
      );
    }
  }

  /// Save current mask to history
  void _saveToHistory(Uint8List mask) {
    // Remove any redo states
    if (_historyIndex < _maskHistory.length - 1) {
      _maskHistory.removeRange(_historyIndex + 1, _maskHistory.length);
    }
    // Add new state (make a copy only if mask is non-empty)
    if (mask.isNotEmpty) {
      _maskHistory.add(Uint8List.fromList(mask));
    } else {
      _maskHistory.add(Uint8List(0));
    }
    _historyIndex = _maskHistory.length - 1;
    // Limit history size to prevent memory bloat
    const maxHistory = 30;
    while (_maskHistory.length > maxHistory) {
      _maskHistory.removeAt(0);
      _historyIndex--;
    }
  }

  /// Undo last selection change
  bool canUndo() => _historyIndex > 0;

  void undo() {
    if (canUndo()) {
      _historyIndex--;
      _selectionMask = Uint8List.fromList(_maskHistory[_historyIndex]);
      _previewImage = null;
      notifyListeners();
    }
  }

  /// Redo last undone change
  bool canRedo() => _historyIndex < _maskHistory.length - 1;

  void redo() {
    if (canRedo()) {
      _historyIndex++;
      _selectionMask = Uint8List.fromList(_maskHistory[_historyIndex]);
      _previewImage = null;
      notifyListeners();
    }
  }

  /// Set current tool
  void setCurrentTool(SelectionTool tool) {
    _currentTool = tool;
    notifyListeners();
  }

  /// Set selected color
  void setSelectedColor(Color color) {
    _selectedColor = color;
    _previewImage = null;
    notifyListeners();
  }

  /// Toggle preview mode
  void togglePreviewMode() {
    _isPreviewMode = !_isPreviewMode;
    notifyListeners();
  }

  /// Set preview image
  void setPreviewImage(Uint8List? image) {
    _previewImage = image;
    notifyListeners();
  }

  /// Set brush size
  void setBrushSize(double size) {
    _brushSize = size;
    notifyListeners();
  }

  /// Set loading state
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error message
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset selection
  void resetSelection() {
    setSelectionMask(Uint8List(0));
  }

  /// Clear all (reset to beginning)
  void clearAll() {
    _capturedImage = null;
    _selectionMask = Uint8List(0);
    _previewImage = null;
    _currentStage = AppStage.camera;
    _isPreviewMode = false;
    notifyListeners();
  }
}

/// Application stages
enum AppStage {
  /// Camera capture stage
  camera,

  /// Image editor stage
  editor,

  /// Color picker stage
  colorPicker,
}