import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'home_screen.dart';
import 'result_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../utils/web_download.dart';
import 'package:http_parser/http_parser.dart'; // add this import at top

class ConvertScreen extends StatefulWidget {
  final ConversionType type;
  const ConvertScreen({super.key, required this.type});

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  // 🔧 Change this to your backend URL
  static const String _baseUrl = 'http://localhost:8000';

  File? _pickedFile;
  var _filePath;
  Uint8List? _pickedFileBytes;
  String? _fileName;
  double? _fileSize;
  bool _isUploading = false;
  double _progress = 0;
  String _statusText = '';

  bool get _isWordType => widget.type == ConversionType.wordToPdf;

  String get _typeLabel => _isWordType ? 'Word Document' : 'Image';
  String get _typeExt => _isWordType ? '.docx' : '.jpg / .png';
  String get _typeIcon => _isWordType ? '📄' : '🖼️';
  Color get _accentColor =>
      _isWordType ? const Color(0xFF0A84FF) : const Color(0xFF30D158);

  // Future<void> _pickFile() async {
  //   final result = await FilePicker.platform.pickFiles(
  //     type: _isWordType ? FileType.custom : FileType.image,
  //     allowedExtensions: _isWordType ? ['docx'] : null,
  //     allowMultiple: false,
  //     withData: true
  //   );
  //
  //   if (result != null && result.files.single.path != null) {
  //     final file = File(result.files.single.path!);
  //     final bytes = await file.length();
  //     setState(() {
  //       _pickedFile = file;
  //       _fileName = result.files.single.name;
  //       _fileSize = bytes / (1024 * 1024);
  //     });
  //   }
  // }

  Future<void> _pickFile() async {
    debugPrint('🟡 _pickFile called, isWeb: $kIsWeb');

    try {
      final result = await FilePicker.platform.pickFiles(
        type: _isWordType
            ? (kIsWeb ? FileType.any : FileType.custom)
            : FileType.image,
        allowedExtensions: (!kIsWeb && _isWordType) ? ['docx'] : null,
        allowMultiple: false,
        withData: kIsWeb, // Only request bytes on web
      );

      if (result == null || result.files.isEmpty) {
        debugPrint('❌ No file selected');
        return;
      }

      final file = result.files.single;
      debugPrint('🟡 file.name: ${file.name}');

      // ── Manual extension validation (especially for web) ──────────────────
      final name = file.name.toLowerCase();
      if (_isWordType && !name.endsWith('.docx')) {
        _showError('Please select a .docx file');
        return;
      }
      if (!_isWordType &&
          !name.endsWith('.jpg') &&
          !name.endsWith('.jpeg') &&
          !name.endsWith('.png') &&
          !name.endsWith('.webp')) {
        _showError('Please select an image (jpg, png, webp)');
        return;
      }

      if (kIsWeb) {
        // ── WEB: use bytes only, never touch file.path ────────────────────
        if (file.bytes == null) {
          _showError('Could not read file bytes. Try again.');
          return;
        }
        final sizeInMB = file.bytes!.length / (1024 * 1024);
        debugPrint('✅ Web file loaded: ${file.name}, ${sizeInMB.toStringAsFixed(2)} MB');
        setState(() {
          _pickedFileBytes = file.bytes!;
          _filePath = null;
          _fileName = file.name;
          _fileSize = sizeInMB;
        });
      } else {
        // ── MOBILE/DESKTOP: use path only ────────────────────────────────
        if (file.path == null) {
          _showError('Could not get file path. Try again.');
          return;
        }
        final ioFile = File(file.path!);
        final length = await ioFile.length();
        final sizeInMB = length / (1024 * 1024);
        debugPrint('✅ Mobile file loaded: ${file.name}, ${sizeInMB.toStringAsFixed(2)} MB');
        setState(() {
          _pickedFileBytes = null;
          _filePath = file.path!;
          _fileName = file.name;
          _fileSize = sizeInMB;
        });
      }
    } catch (e, stack) {
      debugPrint('❌ _pickFile error: $e');
      debugPrint(stack.toString());
      _showError('File picker error: ${e.toString()}');
    }
  }

  Future<void> _convert() async {
    // Guard: ensure we actually have file data for the current platform
    if (kIsWeb && _pickedFileBytes == null) return;
    if (!kIsWeb && _filePath == null) return;

    setState(() {
      _isUploading = true;
      _progress = 0;
      _statusText = 'Preparing file…';
    });

    try {
      final uri = Uri.parse('$_baseUrl/convert');
      final request = http.MultipartRequest('POST', uri);

      if (kIsWeb) {
        // Detect correct MIME type from filename
        String mimeType;
        String subtype;
        final name = _fileName!.toLowerCase();
        if (name.endsWith('.docx')) {
          mimeType = 'application';
          subtype = 'vnd.openxmlformats-officedocument.wordprocessingml.document';
        } else if (name.endsWith('.png')) {
          mimeType = 'image';
          subtype = 'png';
        } else if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
          mimeType = 'image';
          subtype = 'jpeg';
        } else if (name.endsWith('.webp')) {
          mimeType = 'image';
          subtype = 'webp';
        } else {
          mimeType = 'application';
          subtype = 'octet-stream';
        }

        request.files.add(http.MultipartFile.fromBytes(
          'file',
          _pickedFileBytes!,
          filename: _fileName!,
          contentType: MediaType(mimeType, subtype),
        ));
      }

      setState(() { _progress = 0.15; _statusText = 'Uploading…'; });
      final streamed = await request.send();
      setState(() { _progress = 0.55; _statusText = 'Converting…'; });
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        setState(() { _progress = 0.85; _statusText = 'Saving PDF…'; });

        final baseName = _fileName!.replaceAll(
            RegExp(r'\.(docx|jpg|jpeg|png|webp)$', caseSensitive: false), '');

        if (kIsWeb) {
          downloadOnWeb(response.bodyBytes, '$baseName.pdf');
          setState(() { _progress = 1.0; _statusText = 'Done!'; });
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            setState(() { _isUploading = false; _progress = 0; });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('PDF downloaded! Check your Downloads folder.',
                  style: GoogleFonts.inter()),
              backgroundColor: const Color(0xFF30D158),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ));
          }
        } else {
          final dir = await getApplicationDocumentsDirectory();
          final outFile = File('${dir.path}/$baseName.pdf');
          await outFile.writeAsBytes(response.bodyBytes);
          setState(() { _progress = 1.0; _statusText = 'Done!'; });
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            Navigator.pushReplacement(context, PageRouteBuilder(
              pageBuilder: (_, anim, __) => ResultScreen(
                pdfPath: outFile.path,
                originalName: baseName,
                accentColor: _accentColor,
              ),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 350),
            ));
          }
        }
      } else {
        _showError('Conversion failed (${response.statusCode})');
      }
    } catch (e) {
      _showError('Network error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _downloadOnWeb(Uint8List bytes, String filename) {
    // ignore: avoid_web_libraries_in_flutter

    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _showError(String msg) {
    setState(() {
      _isUploading = false;
      _statusText = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter()),
        backgroundColor: const Color(0xFFFF453A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(),
                  const SizedBox(height: 32),
                  _buildTitle(),
                  const SizedBox(height: 36),
                  _buildDropZone(),
                  const SizedBox(height: 24),
                  if (_fileName != null) _buildFileCard(),
                  const Spacer(),
                  if (_isUploading) _buildProgress(),
                  const SizedBox(height: 16),
                  _buildConvertButton(),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accentColor.withOpacity(0.3)),
            ),
            child: Text(
              _typeLabel,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _accentColor,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select your\n$_typeLabel',
            style: GoogleFonts.inter(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
              letterSpacing: -1.8,
            ),
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.2, end: 0),
          const SizedBox(height: 8),
          Text(
            'Supports $_typeExt',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: const Color(0xFF8E8E93),
            ),
          ).animate().fadeIn(delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildDropZone() {
    final hasFile = kIsWeb ? _pickedFileBytes != null : _filePath != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _isUploading ? null : _pickFile,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: hasFile
                  ? _accentColor.withOpacity(0.6)
                  : const Color(0xFF2C2C2E),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(_typeIcon, style: const TextStyle(fontSize: 30)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                hasFile ? 'Tap to change file' : 'Tap to browse',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasFile
                    ? _fileName!
                    : 'Choose a $_typeLabel from your device',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF8E8E93),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildFileCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _accentColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accentColor.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.insert_drive_file_rounded,
                  color: Colors.white70, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fileName!,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_fileSize!.toStringAsFixed(2)} MB',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.check_circle_rounded, color: _accentColor, size: 22),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _statusText,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              Text(
                '${(_progress * 100).toInt()}%',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 5,
              backgroundColor: const Color(0xFF2C2C2E),
              valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ).animate().fadeIn(duration: 300.ms),
    );
  }

  Widget _buildConvertButton() {
    final canConvert = !_isUploading &&
        (kIsWeb ? _pickedFileBytes != null : _filePath != null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: canConvert ? _convert : null,
        child: AnimatedContainer(
          duration: 300.ms,
          width: double.infinity,
          height: 58,
          decoration: BoxDecoration(
            gradient: canConvert
                ? LinearGradient(
              colors: _isWordType
                  ? [const Color(0xFF0A84FF), const Color(0xFF0055CC)]
                  : [const Color(0xFF30D158), const Color(0xFF1A7A35)],
            )
                : null,
            color: canConvert ? null : const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
            boxShadow: canConvert
                ? [
              BoxShadow(
                color: _accentColor.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              )
            ]
                : [],
          ),
          child: Center(
            child: _isUploading
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            )
                : Text(
              canConvert ? 'Convert to PDF' : 'Select a file first',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: canConvert ? Colors.white : const Color(0xFF48484A),
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3, end: 0);
  }
}