import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

enum EditorTab {
  crop,
  filters,
  tune,
  doodle,
  textStickers,
}

enum CropAspectRatio {
  free,
  square, // 1:1
  portrait45, // 4:5
  landscape169, // 16:9
  story916, // 9:16
  classic34, // 3:4
}

enum ImageFilterPreset {
  normal,
  cyberpunk,
  velvetRose,
  goldenHour,
  emerald,
  noir,
  sepia,
  pastelSoft,
}

class DrawnStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  DrawnStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

class ImageStickerItem {
  final String id;
  final String content;
  final bool isEmoji;
  Offset position;
  final Color textColor;
  final bool hasBackground;

  ImageStickerItem({
    required this.id,
    required this.content,
    this.isEmoji = false,
    required this.position,
    this.textColor = Colors.white,
    this.hasBackground = true,
  });
}

class ImageCropEditor extends StatefulWidget {
  final File imageFile;

  const ImageCropEditor({
    super.key,
    required this.imageFile,
  });

  @override
  State<ImageCropEditor> createState() => _ImageCropEditorState();
}

class _ImageCropEditorState extends State<ImageCropEditor> with SingleTickerProviderStateMixin {
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  late File _currentFile;
  Uint8List? _imageBytes;
  bool _isLoading = true;
  bool _isProcessing = false;

  EditorTab _currentTab = EditorTab.crop;

  // 1. Crop & Rotate
  int _rotationQuarterTurns = 0; // 0, 1, 2, 3
  bool _isFlippedHorizontally = false;
  CropAspectRatio _selectedAspectRatio = CropAspectRatio.free;
  Rect _cropRect = const Rect.fromLTWH(0.04, 0.04, 0.92, 0.92);
  bool _isDraggingCrop = false;

  // 2. Filters
  ImageFilterPreset _selectedFilter = ImageFilterPreset.normal;

  // 3. Tuning Sliders
  double _brightness = 0.0; // -0.5 to 0.5
  double _contrast = 1.0; // 0.5 to 1.5
  double _saturation = 1.0; // 0.0 to 2.0
  double _warmth = 0.0; // -0.5 to 0.5

  // 4. Doodle / Brush
  final List<DrawnStroke> _strokes = [];
  DrawnStroke? _currentStroke;
  Color _brushColor = const Color(0xFFFF2D75);
  final double _brushWidth = 5.0;

  // 5. Text & Stickers
  final List<ImageStickerItem> _stickers = [];
  final TextEditingController _textStickerController = TextEditingController();

  final List<Color> _palette = const [
    Color(0xFFFF2D75), // Neon Pink
    Color(0xFF00E5FF), // Cyan
    Color(0xFF9B51E0), // Violet
    Color(0xFFFFD600), // Sunshine Yellow
    Color(0xFF00E676), // Lime Green
    Colors.white,
    Color(0xFFFF3D00), // Crimson
    Colors.black,
  ];

  final List<String> _stickerEmojis = const [
    "💖", "🔥", "💋", "👑", "✨", "🧸", "🌹", "💫", "🥂", "🕶️", "💘", "🍓", "💌", "🎉",
  ];

  @override
  void initState() {
    super.initState();
    _currentFile = widget.imageFile;
    _loadImage();
  }

  @override
  void dispose() {
    _textStickerController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await _currentFile.readAsBytes();
      if (mounted) {
        setState(() {
          _imageBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _rotateClockwise() {
    HapticFeedback.selectionClick();
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
      _resetCropRect();
    });
  }

  void _flipHorizontal() {
    HapticFeedback.selectionClick();
    setState(() {
      _isFlippedHorizontally = !_isFlippedHorizontally;
    });
  }

  void _resetCropRect() {
    setState(() {
      _cropRect = const Rect.fromLTWH(0.04, 0.04, 0.92, 0.92);
    });
  }

  void _setAspectRatio(CropAspectRatio ratio) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedAspectRatio = ratio;
      double aspect = 1.0;
      switch (ratio) {
        case CropAspectRatio.free:
          _resetCropRect();
          return;
        case CropAspectRatio.square:
          aspect = 1.0;
          break;
        case CropAspectRatio.portrait45:
          aspect = 4.0 / 5.0;
          break;
        case CropAspectRatio.classic34:
          aspect = 3.0 / 4.0;
          break;
        case CropAspectRatio.landscape169:
          aspect = 16.0 / 9.0;
          break;
        case CropAspectRatio.story916:
          aspect = 9.0 / 16.0;
          break;
      }

      double w = 0.88;
      double h = w / aspect;
      if (h > 0.88) {
        h = 0.88;
        w = h * aspect;
      }
      double l = (1.0 - w) / 2.0;
      double t = (1.0 - h) / 2.0;
      _cropRect = Rect.fromLTWH(l, t, w, h);
    });
  }

  ColorFilter _composeColorMatrix() {
    // 1. Base filter preset matrix
    List<double> matrix = _getFilterMatrix(_selectedFilter);

    // 2. Apply Brightness shift
    if (_brightness != 0.0) {
      final b = _brightness * 255;
      matrix = _multiplyMatrices(matrix, <double>[
        1, 0, 0, 0, b,
        0, 1, 0, 0, b,
        0, 0, 1, 0, b,
        0, 0, 0, 1, 0,
      ]);
    }

    // 3. Apply Contrast
    if (_contrast != 1.0) {
      final c = _contrast;
      final t = (1.0 - c) / 2.0 * 255;
      matrix = _multiplyMatrices(matrix, <double>[
        c, 0, 0, 0, t,
        0, c, 0, 0, t,
        0, 0, c, 0, t,
        0, 0, 0, 1, 0,
      ]);
    }

    // 4. Apply Saturation
    if (_saturation != 1.0) {
      final s = _saturation;
      const rWeight = 0.213;
      const gWeight = 0.715;
      const bWeight = 0.072;
      matrix = _multiplyMatrices(matrix, <double>[
        (1 - s) * rWeight + s, (1 - s) * gWeight, (1 - s) * bWeight, 0, 0,
        (1 - s) * rWeight, (1 - s) * gWeight + s, (1 - s) * bWeight, 0, 0,
        (1 - s) * rWeight, (1 - s) * gWeight, (1 - s) * bWeight + s, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    }

    // 5. Apply Warmth
    if (_warmth != 0.0) {
      final w = _warmth * 30;
      matrix = _multiplyMatrices(matrix, <double>[
        1, 0, 0, 0, w,
        0, 1, 0, 0, w * 0.4,
        0, 0, 1, 0, -w * 0.8,
        0, 0, 0, 1, 0,
      ]);
    }

    return ColorFilter.matrix(matrix);
  }

  List<double> _getFilterMatrix(ImageFilterPreset preset) {
    switch (preset) {
      case ImageFilterPreset.normal:
        return const <double>[
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case ImageFilterPreset.cyberpunk:
        return const <double>[
          1.35, 0, 0, 0, 15,
          0, 1.15, 0, 0, -5,
          0, 0, 1.45, 0, 25,
          0, 0, 0, 1, 0,
        ];
      case ImageFilterPreset.velvetRose:
        return const <double>[
          1.25, 0, 0, 0, 20,
          0, 0.95, 0, 0, -10,
          0, 0, 1.15, 0, 10,
          0, 0, 0, 1, 0,
        ];
      case ImageFilterPreset.goldenHour:
        return const <double>[
          1.25, 0, 0, 0, 25,
          0, 1.12, 0, 0, 15,
          0, 0, 0.82, 0, -20,
          0, 0, 0, 1, 0,
        ];
      case ImageFilterPreset.emerald:
        return const <double>[
          0.9, 0, 0, 0, -10,
          0, 1.25, 0, 0, 15,
          0, 0, 1.1, 0, 10,
          0, 0, 0, 1, 0,
        ];
      case ImageFilterPreset.noir:
        return const <double>[
          0.33, 0.59, 0.11, 0, 0,
          0.33, 0.59, 0.11, 0, 0,
          0.33, 0.59, 0.11, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case ImageFilterPreset.sepia:
        return const <double>[
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case ImageFilterPreset.pastelSoft:
        return const <double>[
          0.95, 0.1, 0.1, 0, 15,
          0.05, 0.95, 0.1, 0, 15,
          0.05, 0.1, 0.95, 0, 20,
          0, 0, 0, 1, 0,
        ];
    }
  }

  List<double> _multiplyMatrices(List<double> a, List<double> b) {
    List<double> result = List.filled(20, 0.0);
    for (int y = 0; y < 4; y++) {
      for (int x = 0; x < 5; x++) {
        double sum = 0.0;
        for (int i = 0; i < 4; i++) {
          sum += a[y * 5 + i] * b[i * 5 + x];
        }
        if (x == 4) sum += a[y * 5 + 4];
        result[y * 5 + x] = sum;
      }
    }
    return result;
  }

  void _addTextSticker() {
    _textStickerController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181824),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Add Text Caption", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: _textStickerController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Type text sticker...",
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2D75),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () {
              final text = _textStickerController.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  _stickers.add(ImageStickerItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    content: text,
                    isEmoji: false,
                    position: const Offset(100, 150),
                    textColor: _brushColor,
                    hasBackground: true,
                  ));
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text("Add", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _addEmojiSticker(String emoji) {
    HapticFeedback.selectionClick();
    setState(() {
      _stickers.add(ImageStickerItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: emoji,
        isEmoji: true,
        position: const Offset(120, 180),
      ));
    });
  }

  Future<void> _applyAndSave() async {
    if (_imageBytes == null) return;

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      // 1. Capture visual overlays (Doodles & Stickers) if present using RenderRepaintBoundary
      Uint8List? overlayBytes;
      if (_strokes.isNotEmpty || _stickers.isNotEmpty) {
        final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            overlayBytes = byteData.buffer.asUint8List();
          }
        }
      }

      final processedFile = await compute(_processImageInIsolate, _ImageProcessParams(
        rawBytes: _imageBytes!,
        rotationQuarterTurns: _rotationQuarterTurns,
        isFlippedHorizontally: _isFlippedHorizontally,
        cropRectNorm: _cropRect,
        filterPreset: _selectedFilter,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        warmth: _warmth,
        overlayPngBytes: overlayBytes,
        origPath: widget.imageFile.path,
      ));

      if (mounted) {
        Navigator.pop(context, processedFile);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving edited image: $e")),
        );
      }
    }
  }

  static Future<File> _processImageInIsolate(_ImageProcessParams params) async {
    var image = img.decodeImage(params.rawBytes);
    if (image == null) throw Exception("Unable to decode image");

    // 1. Rotate
    if (params.rotationQuarterTurns != 0) {
      image = img.copyRotate(image, angle: params.rotationQuarterTurns * 90);
    }

    // 2. Flip
    if (params.isFlippedHorizontally) {
      image = img.copyFlip(image, direction: img.FlipDirection.horizontal);
    }

    // 3. Crop
    final imgW = image.width;
    final imgH = image.height;
    int cropX = (params.cropRectNorm.left * imgW).clamp(0, imgW - 1).toInt();
    int cropY = (params.cropRectNorm.top * imgH).clamp(0, imgH - 1).toInt();
    int cropW = (params.cropRectNorm.width * imgW).clamp(1, imgW - cropX).toInt();
    int cropH = (params.cropRectNorm.height * imgH).clamp(1, imgH - cropY).toInt();

    image = img.copyCrop(image, x: cropX, y: cropY, width: cropW, height: cropH);

    // 4. Filters & Adjustments
    switch (params.filterPreset) {
      case ImageFilterPreset.noir:
        image = img.grayscale(image);
        break;
      case ImageFilterPreset.sepia:
        image = img.sepia(image);
        break;
      case ImageFilterPreset.cyberpunk:
        image = img.adjustColor(image, saturation: 1.4, contrast: 1.25);
        break;
      case ImageFilterPreset.velvetRose:
        image = img.adjustColor(image, gamma: 1.08, saturation: 1.2);
        break;
      case ImageFilterPreset.goldenHour:
        image = img.adjustColor(image, gamma: 1.15, saturation: 1.15);
        break;
      case ImageFilterPreset.emerald:
        image = img.adjustColor(image, gamma: 0.95, contrast: 1.1);
        break;
      case ImageFilterPreset.pastelSoft:
        image = img.adjustColor(image, saturation: 0.85, brightness: 1.08);
        break;
      case ImageFilterPreset.normal:
        break;
    }

    if (params.brightness != 0.0 || params.contrast != 1.0 || params.saturation != 1.0) {
      image = img.adjustColor(
        image,
        brightness: 1.0 + params.brightness,
        contrast: params.contrast,
        saturation: params.saturation,
      );
    }

    // 5. Composite Overlay Graphics (Doodles & Stickers) if provided
    if (params.overlayPngBytes != null) {
      final overlayImg = img.decodePng(params.overlayPngBytes!);
      if (overlayImg != null) {
        final resizedOverlay = img.copyResize(overlayImg, width: image.width, height: image.height);
        img.compositeImage(image, resizedOverlay);
      }
    }

    // Write to temp file
    final ext = params.origPath.endsWith('.png') ? 'png' : 'jpg';
    final tempDir = Directory.systemTemp;
    final outPath = "${tempDir.path}/pro_edited_${DateTime.now().millisecondsSinceEpoch}.$ext";
    final outFile = File(outPath);

    final encoded = ext == 'png' ? img.encodePng(image) : img.encodeJpg(image, quality: 92);
    await outFile.writeAsBytes(encoded);
    return outFile;
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF08080C);
    const rose = Color(0xFFFF2D75);
    const violet = Color(0xFF9B51E0);

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: rose))
            : Stack(
                children: [
                  Column(
                    children: [
                      // Top Action Bar
                      _buildTopActionBar(rose, violet),

                      // Canvas Viewport
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return RepaintBoundary(
                              key: _repaintBoundaryKey,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Base Transformed & Tuned Image
                                  Transform.rotate(
                                    angle: _rotationQuarterTurns * 3.1415926535897932 / 2,
                                    child: Transform.scale(
                                      scaleX: _isFlippedHorizontally ? -1 : 1,
                                      child: ColorFiltered(
                                        colorFilter: _composeColorMatrix(),
                                        child: Image.memory(
                                          _imageBytes!,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Doodles Layer
                                  _buildDoodleCanvas(),

                                  // Stickers & Text Overlay Layer
                                  ..._stickers.map((sticker) => _buildDraggableSticker(sticker)),

                                  // Crop Grid & Handles Overlay (Active in Crop Tab)
                                  if (_currentTab == EditorTab.crop)
                                    _buildCropOverlay(constraints),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      // Pro Studio Tabs & Control Panels
                      _buildBottomStudio(rose, violet),
                    ],
                  ),

                  // Processing Overlay
                  if (_isProcessing)
                    Container(
                      color: Colors.black.withValues(alpha: 0.75),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: rose),
                            SizedBox(height: 16),
                            Text(
                              "Baking Pro Edits...",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildTopActionBar(Color rose, Color violet) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
            onPressed: () => Navigator.pop(context),
          ),
          Row(
            children: [
              IconButton(
                tooltip: "Rotate 90°",
                icon: const Icon(Icons.rotate_right_rounded, color: Colors.white, size: 24),
                onPressed: _rotateClockwise,
              ),
              IconButton(
                tooltip: "Flip Horizontal",
                icon: const Icon(Icons.flip_rounded, color: Colors.white, size: 24),
                onPressed: _flipHorizontal,
              ),
              IconButton(
                tooltip: "Reset All",
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 24),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _rotationQuarterTurns = 0;
                    _isFlippedHorizontally = false;
                    _selectedAspectRatio = CropAspectRatio.free;
                    _selectedFilter = ImageFilterPreset.normal;
                    _brightness = 0.0;
                    _contrast = 1.0;
                    _saturation = 1.0;
                    _warmth = 0.0;
                    _strokes.clear();
                    _stickers.clear();
                    _resetCropRect();
                  });
                },
              ),
            ],
          ),
          // Save / Done
          GestureDetector(
            onTap: _applyAndSave,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [rose, violet]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: rose.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 4),
                  Text(
                    "Done",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoodleCanvas() {
    return GestureDetector(
      onPanStart: (details) {
        if (_currentTab != EditorTab.doodle) return;
        setState(() {
          _currentStroke = DrawnStroke(
            points: [details.localPosition],
            color: _brushColor,
            strokeWidth: _brushWidth,
          );
          _strokes.add(_currentStroke!);
        });
      },
      onPanUpdate: (details) {
        if (_currentTab != EditorTab.doodle || _currentStroke == null) return;
        setState(() {
          _currentStroke!.points.add(details.localPosition);
        });
      },
      onPanEnd: (_) {
        _currentStroke = null;
      },
      child: CustomPaint(
        painter: _DoodlePainter(strokes: _strokes),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildDraggableSticker(ImageStickerItem sticker) {
    return Positioned(
      left: sticker.position.dx,
      top: sticker.position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            sticker.position += details.delta;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: sticker.isEmoji ? 6 : 12,
            vertical: sticker.isEmoji ? 4 : 8,
          ),
          decoration: sticker.isEmoji
              ? null
              : BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: sticker.textColor, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 8),
                  ],
                ),
          child: Text(
            sticker.content,
            style: TextStyle(
              fontSize: sticker.isEmoji ? 36 : 18,
              color: sticker.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropOverlay(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;

    final leftPx = _cropRect.left * width;
    final topPx = _cropRect.top * height;
    final cropWidthPx = _cropRect.width * width;
    final cropHeightPx = _cropRect.height * height;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _CropDarkMaskPainter(
              cropRect: Rect.fromLTWH(leftPx, topPx, cropWidthPx, cropHeightPx),
              showGrid: _isDraggingCrop,
            ),
          ),
        ),
        Positioned(
          left: leftPx,
          top: topPx,
          width: cropWidthPx,
          height: cropHeightPx,
          child: GestureDetector(
            onPanStart: (_) => setState(() => _isDraggingCrop = true),
            onPanEnd: (_) => setState(() => _isDraggingCrop = false),
            onPanUpdate: (details) {
              final dxNorm = details.delta.dx / width;
              final dyNorm = details.delta.dy / height;
              setState(() {
                double newL = (_cropRect.left + dxNorm).clamp(0.0, 1.0 - _cropRect.width);
                double newT = (_cropRect.top + dyNorm).clamp(0.0, 1.0 - _cropRect.height);
                _cropRect = Rect.fromLTWH(newL, newT, _cropRect.width, _cropRect.height);
              });
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Stack(
                children: [
                  _buildCornerHandle(Alignment.topLeft),
                  _buildCornerHandle(Alignment.topRight),
                  _buildCornerHandle(Alignment.bottomLeft),
                  _buildCornerHandle(Alignment.bottomRight),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCornerHandle(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
        ),
      ),
    );
  }

  Widget _buildBottomStudio(Color rose, Color violet) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101018),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Active Tab Content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildTabPanel(rose, violet),
          ),

          // Main Studio Tabs Navigation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _tabButton(EditorTab.crop, "Crop", Icons.crop_rotate_rounded, rose),
                _tabButton(EditorTab.filters, "Filters", Icons.auto_awesome_rounded, rose),
                _tabButton(EditorTab.tune, "Tune", Icons.tune_rounded, rose),
                _tabButton(EditorTab.doodle, "Doodle", Icons.draw_rounded, rose),
                _tabButton(EditorTab.textStickers, "Stickers", Icons.sentiment_satisfied_alt_rounded, rose),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(EditorTab tab, String label, IconData icon, Color rose) {
    final isSelected = _currentTab == tab;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currentTab = tab);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? rose : Colors.white60, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? rose : Colors.white60,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPanel(Color rose, Color violet) {
    switch (_currentTab) {
      case EditorTab.crop:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _aspectRatioChip("Free", CropAspectRatio.free, rose),
              _aspectRatioChip("1:1", CropAspectRatio.square, rose),
              _aspectRatioChip("4:5", CropAspectRatio.portrait45, rose),
              _aspectRatioChip("3:4", CropAspectRatio.classic34, rose),
              _aspectRatioChip("16:9", CropAspectRatio.landscape169, rose),
              _aspectRatioChip("9:16", CropAspectRatio.story916, rose),
            ],
          ),
        );

      case EditorTab.filters:
        return Container(
          height: 90,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterThumbnail("Original", ImageFilterPreset.normal, rose),
              _filterThumbnail("Cyberpunk", ImageFilterPreset.cyberpunk, rose),
              _filterThumbnail("Velvet Rose", ImageFilterPreset.velvetRose, rose),
              _filterThumbnail("Golden Hour", ImageFilterPreset.goldenHour, rose),
              _filterThumbnail("Emerald", ImageFilterPreset.emerald, rose),
              _filterThumbnail("Noir", ImageFilterPreset.noir, rose),
              _filterThumbnail("Sepia", ImageFilterPreset.sepia, rose),
              _filterThumbnail("Pastel", ImageFilterPreset.pastelSoft, rose),
            ],
          ),
        );

      case EditorTab.tune:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sliderControl("Brightness", _brightness, -0.5, 0.5, (v) => setState(() => _brightness = v), rose),
              _sliderControl("Contrast", _contrast, 0.5, 1.5, (v) => setState(() => _contrast = v), rose),
              _sliderControl("Saturation", _saturation, 0.0, 2.0, (v) => setState(() => _saturation = v), rose),
              _sliderControl("Warmth", _warmth, -0.5, 0.5, (v) => setState(() => _warmth = v), rose),
            ],
          ),
        );

      case EditorTab.doodle:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: "Undo Stroke",
                icon: const Icon(Icons.undo_rounded, color: Colors.white),
                onPressed: () {
                  if (_strokes.isNotEmpty) {
                    setState(() => _strokes.removeLast());
                  }
                },
              ),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _palette.length,
                    itemBuilder: (ctx, i) {
                      final c = _palette[i];
                      final isSelected = _brushColor == c;
                      return GestureDetector(
                        onTap: () => setState(() => _brushColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.white24,
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );

      case EditorTab.textStickers:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.text_fields_rounded, color: Colors.white, size: 18),
                    label: const Text("Add Text", style: TextStyle(color: Colors.white, fontSize: 12)),
                    onPressed: _addTextSticker,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _stickerEmojis.length,
                        itemBuilder: (ctx, i) {
                          final em = _stickerEmojis[i];
                          return GestureDetector(
                            onTap: () => _addEmojiSticker(em),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(em, style: const TextStyle(fontSize: 26)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }

  Widget _sliderControl(String label, double value, double min, double max, ValueChanged<double> onChanged, Color rose) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: rose,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _aspectRatioChip(String label, CropAspectRatio ratio, Color rose) {
    final isSelected = _selectedAspectRatio == ratio;
    return GestureDetector(
      onTap: () => _setAspectRatio(ratio),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? rose.withValues(alpha: 0.2) : Colors.white10,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? rose : Colors.transparent, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _filterThumbnail(String label, ImageFilterPreset preset, Color rose) {
    final isSelected = _selectedFilter == preset;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = preset);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? rose : Colors.white24, width: isSelected ? 2.5 : 1),
              ),
              child: ClipOval(
                child: _imageBytes != null
                    ? ColorFiltered(
                        colorFilter: ColorFilter.matrix(_getFilterMatrix(preset)),
                        child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? rose : Colors.white70,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  final List<DrawnStroke> strokes;

  _DoodlePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (var stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length > 1) {
        final path = Path();
        path.moveTo(stroke.points[0].dx, stroke.points[0].dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      } else if (stroke.points.isNotEmpty) {
        canvas.drawCircle(stroke.points[0], stroke.strokeWidth / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DoodlePainter oldDelegate) => true;
}

class _CropDarkMaskPainter extends CustomPainter {
  final Rect cropRect;
  final bool showGrid;

  _CropDarkMaskPainter({required this.cropRect, required this.showGrid});

  @override
  void paint(Canvas canvas, Size size) {
    final paintMask = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final fullScreen = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cropArea = Path()..addRect(cropRect);
    final combined = Path.combine(PathOperation.difference, fullScreen, cropArea);

    canvas.drawPath(combined, paintMask);

    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      final stepX = cropRect.width / 3.0;
      final stepY = cropRect.height / 3.0;

      canvas.drawLine(Offset(cropRect.left + stepX, cropRect.top), Offset(cropRect.left + stepX, cropRect.bottom), gridPaint);
      canvas.drawLine(Offset(cropRect.left + 2 * stepX, cropRect.top), Offset(cropRect.left + 2 * stepX, cropRect.bottom), gridPaint);
      canvas.drawLine(Offset(cropRect.left, cropRect.top + stepY), Offset(cropRect.right, cropRect.top + stepY), gridPaint);
      canvas.drawLine(Offset(cropRect.left, cropRect.top + 2 * stepY), Offset(cropRect.right, cropRect.top + 2 * stepY), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropDarkMaskPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect || oldDelegate.showGrid != showGrid;
  }
}

class _ImageProcessParams {
  final Uint8List rawBytes;
  final int rotationQuarterTurns;
  final bool isFlippedHorizontally;
  final Rect cropRectNorm;
  final ImageFilterPreset filterPreset;
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
  final Uint8List? overlayPngBytes;
  final String origPath;

  _ImageProcessParams({
    required this.rawBytes,
    required this.rotationQuarterTurns,
    required this.isFlippedHorizontally,
    required this.cropRectNorm,
    required this.filterPreset,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.warmth,
    this.overlayPngBytes,
    required this.origPath,
  });
}
