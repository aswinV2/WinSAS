import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../utils/web_download.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:pdfx/pdfx.dart';
late Uint8List _pdfBytes;        // used for saving
late Uint8List _renderBytes; // used for pdf rendering

// ─── Annotation models ───────────────────────────────────────────────────────

enum AnnotationType { text, rect, ellipse, line, freehand, image }

enum Tool { select, text, rect, ellipse, line, freehand, image }

class Annotation {
  final String id;
  AnnotationType type;
  int page;
  // Common
  double x, y;
  Color color;
  double strokeWidth;
  // Text
  String text;
  double fontSize;
  bool bold, italic;
  // Shapes
  double width, height;
  Color? fillColor;
  // Line / freehand
  double x2, y2;
  List<Offset> points;
  // Image
  String imageData; // base64
  bool selected;

  Annotation({
    required this.id,
    required this.type,
    required this.page,
    this.x = 0,
    this.y = 0,
    this.color = Colors.black,
    this.strokeWidth = 2,
    this.text = '',
    this.fontSize = 16,
    this.bold = false,
    this.italic = false,
    this.width = 100,
    this.height = 50,
    this.fillColor,
    this.x2 = 0,
    this.y2 = 0,
    this.points = const [],
    this.imageData = '',
    this.selected = false,
  });

  Map<String, dynamic> toJson(Size canvasSize) {
    // Convert pixel coords to percentage
    double px(double v) => (v / canvasSize.width) * 100;
    double py(double v) => (v / canvasSize.height) * 100;

    final base = {
      'type': type.name,
      'page': page,
      'color': _colorToHex(color),
      'stroke_width': strokeWidth,
    };

    switch (type) {
      case AnnotationType.text:
        return {
          ...base,
          'x': px(x), 'y': py(y),
          'text': text,
          'font_size': fontSize,
          'bold': bold,
          'italic': italic,
        };
      case AnnotationType.rect:
      case AnnotationType.ellipse:
        return {
          ...base,
          'x': px(x), 'y': py(y),
          'width': px(width), 'height': py(height),
          'fill_color': fillColor != null ? _colorToHex(fillColor!) : 'none',
        };
      case AnnotationType.line:
        return {
          ...base,
          'x1': px(x), 'y1': py(y),
          'x2': px(x2), 'y2': py(y2),
        };
      case AnnotationType.freehand:
        return {
          ...base,
          'points': points.map((p) => [px(p.dx), py(p.dy)]).toList(),
        };
      case AnnotationType.image:
        return {
          ...base,
          'x': px(x), 'y': py(y),
          'width': px(width), 'height': py(height),
          'data': imageData,
        };
    }
  }

  String _colorToHex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}'
          '${c.green.toRadixString(16).padLeft(2, '0')}'
          '${c.blue.toRadixString(16).padLeft(2, '0')}';
}

// ─── Edit Screen ─────────────────────────────────────────────────────────────

class EditScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final String fileName;

  const EditScreen({
    super.key,
    required this.pdfBytes,
    required this.fileName,
  });

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  static const String _baseUrl = 'http://localhost:8000';

  // PDF rendering
  ui.Image? _pageImage;
  Size _canvasSize = Size.zero;
  bool _loadingPage = true;

  // Tools & annotations
  Tool _activeTool = Tool.select;
  final List<Annotation> _annotations = [];
  Annotation? _selected;
  Annotation? _dragging;
  Offset? _dragStart;
  List<Offset> _currentFreehand = [];
  Offset? _shapeStart;
  Annotation? _preview;

  // Style state
  Color _strokeColor = Colors.black;
  Color _fillColor = Colors.transparent;
  bool _hasFill = false;
  double _strokeWidth = 2;
  double _fontSize = 18;
  bool _bold = false;
  bool _italic = false;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Two separate copies — pdfx detaches the buffer it uses for rendering
    _pdfBytes = Uint8List.fromList(widget.pdfBytes);
    _renderBytes = Uint8List.fromList(widget.pdfBytes);
    _renderPdfPage();
  }

  Future<void> _renderPdfPage() async {
    // Decode first page of PDF as image using dart:ui
    // We use the pdfx package approach — render to image
    try {
      // Use pdfx to render
      final document = await _loadPdfDocument();
      setState(() {
        _pageImage = document;
        _loadingPage = false;
      });
    } catch (e) {
      setState(() => _loadingPage = false);
    }
  }

  Future<ui.Image> _loadPdfDocument() async {
    final completer = Completer<ui.Image>();

    try {
      // Use a fresh copy every time — pdfx detaches on web
      final bytes = Uint8List.fromList(_renderBytes);
      final pdfDoc = await PdfDocument.openData(bytes);
      final page = await pdfDoc.getPage(1);
      final pageImage = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.png,
      );
      await page.close();
      await pdfDoc.close();

      final codec = await ui.instantiateImageCodec(pageImage!.bytes);
      final frame = await codec.getNextFrame();
      completer.complete(frame.image);
    } catch (e) {
      debugPrint('PDF render error: $e');
      // Fallback: blank white page
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 595, 842),
        Paint()..color = Colors.white,
      );
      final pic = recorder.endRecording();
      final img = await pic.toImage(595, 842);
      completer.complete(img);
    }

    return completer.future;
  }

  // ── Gesture handlers ────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;

    if (_activeTool == Tool.select) {
      // Find topmost annotation at this position
      final hit = _annotations.reversed.firstWhere(
            (a) => _hitTest(a, pos),
        orElse: () => Annotation(id: '', type: AnnotationType.text, page: 0),
      );
      setState(() {
        if (hit.id.isNotEmpty) {
          _selected = hit;
          _dragging = hit;
          _dragStart = pos;
          for (var a in _annotations) {
            a.selected = a.id == hit.id;
          }
        } else {
          _selected = null;
          _dragging = null;
          for (var a in _annotations) {
            a.selected = false;
          }
        }
      });
      return;
    }

    if (_activeTool == Tool.freehand) {
      setState(() => _currentFreehand = [pos]);
      return;
    }

    // Shape / line / text start
    setState(() => _shapeStart = pos);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final pos = d.localPosition;

    if (_activeTool == Tool.select && _dragging != null) {
      final delta = pos - _dragStart!;
      setState(() {
        _dragging!.x += delta.dx;
        _dragging!.y += delta.dy;
        if (_dragging!.type == AnnotationType.freehand) {
          _dragging!.points = _dragging!.points
              .map((p) => p + delta)
              .toList();
        }
        if (_dragging!.type == AnnotationType.line) {
          _dragging!.x2 += delta.dx;
          _dragging!.y2 += delta.dy;
        }
        _dragStart = pos;
      });
      return;
    }

    if (_activeTool == Tool.freehand) {
      setState(() => _currentFreehand.add(pos));
      return;
    }

    if (_shapeStart != null) {
      _updatePreview(_shapeStart!, pos);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_activeTool == Tool.select) {
      _dragging = null;
      return;
    }

    if (_activeTool == Tool.freehand && _currentFreehand.length > 1) {
      final a = Annotation(
        id: _newId(),
        type: AnnotationType.freehand,
        page: 0,
        color: _strokeColor,
        strokeWidth: _strokeWidth,
        points: List.from(_currentFreehand),
      );
      setState(() {
        _annotations.add(a);
        _currentFreehand = [];
        _preview = null;
      });
      return;
    }

    if (_shapeStart != null && _preview != null) {
      setState(() {
        _annotations.add(_preview!);
        _preview = null;
        _shapeStart = null;
      });
    }
  }

  void _onTapUp(TapUpDetails d) {
    if (_activeTool == Tool.text) {
      _showTextDialog(d.localPosition);
    }
  }

  void _updatePreview(Offset start, Offset current) {
    final dx = current.dx - start.dx;
    final dy = current.dy - start.dy;

    switch (_activeTool) {
      case Tool.rect:
        _preview = Annotation(
          id: _newId(),
          type: AnnotationType.rect,
          page: 0,
          x: dx >= 0 ? start.dx : current.dx,
          y: dy >= 0 ? start.dy : current.dy,
          width: dx.abs(),
          height: dy.abs(),
          color: _strokeColor,
          fillColor: _hasFill ? _fillColor : null,
          strokeWidth: _strokeWidth,
        );
      case Tool.ellipse:
        _preview = Annotation(
          id: _newId(),
          type: AnnotationType.ellipse,
          page: 0,
          x: dx >= 0 ? start.dx : current.dx,
          y: dy >= 0 ? start.dy : current.dy,
          width: dx.abs(),
          height: dy.abs(),
          color: _strokeColor,
          fillColor: _hasFill ? _fillColor : null,
          strokeWidth: _strokeWidth,
        );
      case Tool.line:
        _preview = Annotation(
          id: _newId(),
          type: AnnotationType.line,
          page: 0,
          x: start.dx, y: start.dy,
          x2: current.dx, y2: current.dy,
          color: _strokeColor,
          strokeWidth: _strokeWidth,
        );
      default:
        break;
    }
    setState(() {});
  }

  bool _hitTest(Annotation a, Offset pos) {
    if (a.type == AnnotationType.freehand) {
      return a.points.any((p) => (p - pos).distance < 20);
    }
    if (a.type == AnnotationType.line) {
      return _pointNearLine(pos, Offset(a.x, a.y), Offset(a.x2, a.y2));
    }
    return Rect.fromLTWH(a.x, a.y, a.width, a.height).contains(pos);
  }

  bool _pointNearLine(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final t = (ap.dx * ab.dx + ap.dy * ab.dy) /
        (ab.dx * ab.dx + ab.dy * ab.dy + 0.001);
    final closest = a + ab * t.clamp(0.0, 1.0);
    return (p - closest).distance < 12;
  }

  String _newId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
          Random().nextInt(9999).toString();

  // ── Text dialog ─────────────────────────────────────────────────────────────

  void _showTextDialog(Offset pos) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add Text',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Type here…',
            hintStyle: GoogleFonts.inter(color: const Color(0xFF8E8E93)),
            filled: true,
            fillColor: const Color(0xFF2C2C2E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: const Color(0xFF8E8E93))),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _annotations.add(Annotation(
                    id: _newId(),
                    type: AnnotationType.text,
                    page: 0,
                    x: pos.dx,
                    y: pos.dy,
                    text: controller.text.trim(),
                    color: _strokeColor,
                    fontSize: _fontSize,
                    bold: _bold,
                    italic: _italic,
                  ));
                });
              }
              Navigator.pop(context);
            },
            child: Text('Add',
                style: GoogleFonts.inter(
                    color: const Color(0xFF0A84FF),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Image picker ─────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.single.bytes ??
        (result.files.single.path != null
            ? await FilePicker.platform
            .pickFiles()
            .then((_) => null)
            : null);

    final fileBytes = result.files.single.bytes;
    if (fileBytes == null) return;

    final b64 = base64Encode(fileBytes);
    setState(() {
      _annotations.add(Annotation(
        id: _newId(),
        type: AnnotationType.image,
        page: 0,
        x: 50, y: 50,
        width: 200, height: 150,
        imageData: b64,
      ));
    });
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_annotations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No annotations to save.',
            style: GoogleFonts.inter()),
        backgroundColor: const Color(0xFFFF453A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final annotationsJson = jsonEncode(
        _annotations.map((a) => a.toJson(_canvasSize)).toList(),
      );

      final bytesCopy = Uint8List.fromList(_pdfBytes);
      final request =
      http.MultipartRequest('POST', Uri.parse('$_baseUrl/edit'));
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytesCopy,
        filename: widget.fileName,
        contentType: http_parser.MediaType('application', 'pdf'),
      ));
      request.fields['annotations'] = annotationsJson;

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final baseName =
        widget.fileName.replaceAll(RegExp(r'\.pdf$'), '');
        downloadOnWeb(response.bodyBytes, '${baseName}_edited.pdf');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('PDF saved!', style: GoogleFonts.inter()),
            backgroundColor: const Color(0xFF30D158),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ));
        }
      } else {
        _showErr('Save failed (${response.statusCode})');
      }
    } catch (e) {
      _showErr('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter()),
      backgroundColor: const Color(0xFFFF453A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _deleteSelected() {
    if (_selected == null) return;
    setState(() {
      _annotations.removeWhere((a) => a.id == _selected!.id);
      _selected = null;
    });
  }

  // ── Color picker ─────────────────────────────────────────────────────────────

  void _showColorPicker({required bool isFill}) {
    Color temp = isFill ? _fillColor : _strokeColor;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isFill ? 'Fill Color' : 'Stroke Color',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: temp,
            onColorChanged: (c) => temp = c,
            pickerAreaHeightPercent: 0.6,
            enableAlpha: false,
            displayThumbColor: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                if (isFill) {
                  _fillColor = temp;
                  _hasFill = true;
                } else {
                  _strokeColor = temp;
                  _selected?.color = temp;
                }
              });
              Navigator.pop(context);
            },
            child: Text('Done',
                style: GoogleFonts.inter(
                    color: const Color(0xFF0A84FF),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildToolbar(),
            _buildStyleBar(),
            Expanded(child: _buildCanvas()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C2E))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.fileName,
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_selected != null)
            GestureDetector(
              onTap: _deleteSelected,
              child: Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF453A).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF453A), size: 18),
              ),
            ),
          GestureDetector(
            onTap: _isSaving ? null : _save,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A84FF),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0A84FF).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: _isSaving
                  ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : Text('Save PDF',
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final tools = [
      //(Tool.select, Icons.arrow_selector_tool_rounded, 'Select'),
      (Tool.select, Icons.pan_tool_rounded, 'Select'),
      (Tool.text, Icons.text_fields_rounded, 'Text'),
      (Tool.freehand, Icons.draw_rounded, 'Draw'),
      (Tool.rect, Icons.rectangle_outlined, 'Rect'),
      (Tool.ellipse, Icons.circle_outlined, 'Ellipse'),
      (Tool.line, Icons.remove_rounded, 'Line'),
      (Tool.image, Icons.image_outlined, 'Image'),
    ];

    return Container(
      height: 52,
      color: const Color(0xFF1C1C1E),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: tools.map((t) {
          final isActive = _activeTool == t.$1;
          return GestureDetector(
            onTap: () {
              if (t.$1 == Tool.image) {
                _pickImage();
                return;
              }
              setState(() => _activeTool = t.$1);
            },
            child: AnimatedContainer(
              duration: 200.ms,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF0A84FF)
                    : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(t.$2,
                      size: 16,
                      color: isActive
                          ? Colors.white
                          : const Color(0xFF8E8E93)),
                  const SizedBox(width: 6),
                  Text(t.$3,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isActive
                              ? Colors.white
                              : const Color(0xFF8E8E93))),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStyleBar() {
    return Container(
      height: 48,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Stroke color
          GestureDetector(
            onTap: () => _showColorPicker(isFill: false),
            child: _colorDot(_strokeColor, 'Stroke'),
          ),
          const SizedBox(width: 12),
          // Fill color
          GestureDetector(
            onTap: () => _showColorPicker(isFill: true),
            child: _colorDot(_hasFill ? _fillColor : Colors.transparent,
                'Fill', _hasFill),
          ),
          const SizedBox(width: 4),
          // Clear fill
          if (_hasFill)
            GestureDetector(
              onTap: () => setState(() => _hasFill = false),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Color(0xFF8E8E93)),
            ),
          const SizedBox(width: 12),
          // Stroke width
          const Icon(Icons.line_weight_rounded,
              size: 16, color: Color(0xFF8E8E93)),
          SizedBox(
            width: 80,
            child: Slider(
              value: _strokeWidth,
              min: 1,
              max: 12,
              divisions: 11,
              activeColor: const Color(0xFF0A84FF),
              inactiveColor: const Color(0xFF2C2C2E),
              onChanged: (v) => setState(() => _strokeWidth = v),
            ),
          ),
          // Font size (text tool only)
          if (_activeTool == Tool.text) ...[
            const Icon(Icons.format_size_rounded,
                size: 16, color: Color(0xFF8E8E93)),
            SizedBox(
              width: 80,
              child: Slider(
                value: _fontSize,
                min: 8,
                max: 72,
                activeColor: const Color(0xFF0A84FF),
                inactiveColor: const Color(0xFF2C2C2E),
                onChanged: (v) => setState(() => _fontSize = v),
              ),
            ),
            // Bold
            _styleToggle(
                Icons.format_bold_rounded, _bold, () => setState(() => _bold = !_bold)),
            // Italic
            _styleToggle(Icons.format_italic_rounded, _italic,
                    () => setState(() => _italic = !_italic)),
          ],
          const Spacer(),
          // Undo
          GestureDetector(
            onTap: () {
              if (_annotations.isNotEmpty) {
                setState(() => _annotations.removeLast());
              }
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.undo_rounded,
                  size: 16, color: Color(0xFF8E8E93)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorDot(Color color, String label, [bool active = true]) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color == Colors.transparent ? null : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF48484A),
              width: 1.5,
            ),
          ),
          child: color == Colors.transparent
              ? const Icon(Icons.block_rounded,
              size: 12, color: Color(0xFF48484A))
              : null,
        ),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 9, color: const Color(0xFF8E8E93))),
      ],
    );
  }

  Widget _styleToggle(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF0A84FF).withOpacity(0.2)
              : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(
              color: const Color(0xFF0A84FF).withOpacity(0.5))
              : null,
        ),
        child: Icon(icon,
            size: 16,
            color: active
                ? const Color(0xFF0A84FF)
                : const Color(0xFF8E8E93)),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, constraints) {
      _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTapUp: _onTapUp,
        child: Container(
          color: const Color(0xFF404040),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1 / 1.414, // A4
              child: Stack(
                children: [
                  // PDF page background
                  _loadingPage
                      ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF0A84FF)))
                      : _pageImage != null
                      ? CustomPaint(
                    painter: _PdfPagePainter(_pageImage!),
                    size: Size.infinite,
                  )
                      : Container(color: Colors.white),
                  // Annotations
                  CustomPaint(
                    painter: _AnnotationPainter(
                      annotations: _annotations,
                      preview: _preview,
                      currentFreehand: _currentFreehand,
                      selectedId: _selected?.id,
                    ),
                    size: Size.infinite,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ─── Custom Painters ──────────────────────────────────────────────────────────

class _PdfPagePainter extends CustomPainter {
  final ui.Image image;
  _PdfPagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: image,
      fit: BoxFit.fill,
    );
  }

  @override
  bool shouldRepaint(_PdfPagePainter old) => old.image != image;
}

class _AnnotationPainter extends CustomPainter {
  final List<Annotation> annotations;
  final Annotation? preview;
  final List<Offset> currentFreehand;
  final String? selectedId;

  _AnnotationPainter({
    required this.annotations,
    this.preview,
    required this.currentFreehand,
    this.selectedId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in [...annotations, if (preview != null) preview!]) {
      _drawAnnotation(canvas, a, size);
    }

    // Live freehand
    if (currentFreehand.length > 1) {
      final paint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(currentFreehand[0].dx, currentFreehand[0].dy);
      for (final p in currentFreehand.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawAnnotation(Canvas canvas, Annotation a, Size size) {
    final strokePaint = Paint()
      ..color = a.color
      ..strokeWidth = a.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = a.fillColor ?? Colors.transparent
      ..style = PaintingStyle.fill;

    // Selection highlight
    if (a.id == selectedId) {
      final selPaint = Paint()
        ..color = const Color(0xFF0A84FF).withOpacity(0.3)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final bounds = _getBounds(a);
      if (bounds != null) {
        canvas.drawRect(
          bounds.inflate(6),
          selPaint,
        );
      }
    }

    switch (a.type) {
      case AnnotationType.text:
        final tp = TextPainter(
          text: TextSpan(
            text: a.text,
            style: TextStyle(
              color: a.color,
              fontSize: a.fontSize,
              fontWeight: a.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: a.italic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(a.x, a.y));

      case AnnotationType.rect:
        final rect = Rect.fromLTWH(a.x, a.y, a.width, a.height);
        if (a.fillColor != null) canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);

      case AnnotationType.ellipse:
        final rect = Rect.fromLTWH(a.x, a.y, a.width, a.height);
        if (a.fillColor != null) canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, strokePaint);

      case AnnotationType.line:
        canvas.drawLine(Offset(a.x, a.y), Offset(a.x2, a.y2), strokePaint);

      case AnnotationType.freehand:
        if (a.points.length < 2) return;
        final path = Path()..moveTo(a.points[0].dx, a.points[0].dy);
        for (final p in a.points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, strokePaint);

      case AnnotationType.image:
      // Images drawn separately (async)
        break;
    }
  }

  Rect? _getBounds(Annotation a) {
    switch (a.type) {
      case AnnotationType.text:
      case AnnotationType.rect:
      case AnnotationType.ellipse:
      case AnnotationType.image:
        return Rect.fromLTWH(a.x, a.y, a.width, a.height);
      case AnnotationType.line:
        return Rect.fromPoints(Offset(a.x, a.y), Offset(a.x2, a.y2));
      case AnnotationType.freehand:
        if (a.points.isEmpty) return null;
        final xs = a.points.map((p) => p.dx);
        final ys = a.points.map((p) => p.dy);
        return Rect.fromLTRB(xs.reduce(min), ys.reduce(min),
            xs.reduce(max), ys.reduce(max));
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter old) => true;
}