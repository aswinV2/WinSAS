import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'convert_screen.dart';
import 'package:flutter/foundation.dart';
import 'edit_screen.dart';
import 'package:file_picker/file_picker.dart';

enum ConversionType { wordToPdf, imageToPdf }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  ConversionType? _selected = ConversionType.wordToPdf;

  final _cards = [
    {
      'type': ConversionType.wordToPdf,
      'icon': '📄',
      'title': 'Word → PDF',
      'subtitle': 'Convert .docx files\nwith full formatting',
      'gradient': [Color(0xFF0A84FF), Color(0xFF0055CC)],
    },
    {
      'type': ConversionType.imageToPdf,
      'icon': '🖼️',
      'title': 'Image → PDF',
      'subtitle': 'JPG, PNG & WebP\nto crisp PDF pages',
      'gradient': [Color(0xFF30D158), Color(0xFF1A7A35)],
    },
    {
      'type': null, // special — opens file picker for PDF
      'icon': '✏️',
      'title': 'Edit PDF',
      'subtitle': 'Annotate, draw\nand add text',
      'gradient': [Color(0xFFFF9F0A), Color(0xFFBF5600)],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(          // ← wraps everything
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(            // ← makes Spacer work inside scroll
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 40),
                  _buildHeroText(),
                  const SizedBox(height: 48),
                  _buildCards(),
                  const Spacer(),             // ← still works thanks to IntrinsicHeight
                  _buildCTA(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Text(
            'WinSAS',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Free',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF30D158),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2, end: 0);
  }

  Widget _buildHeroText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome to WINSAS.\nConvert.\nAnywhere.',
            style: GoogleFonts.inter(
              fontSize: 52,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.05,
              letterSpacing: -2.5,
            ),
          )
              .animate()
              .fadeIn(delay: 100.ms, duration: 600.ms)
              .slideY(begin: 0.3, end: 0),
          const SizedBox(height: 14),
          Text(
            'Turn Word docs and images into\nperfect PDFs in seconds.',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF8E8E93),
              height: 1.5,
              letterSpacing: -0.2,
            ),
          )
              .animate()
              .fadeIn(delay: 200.ms, duration: 600.ms)
              .slideY(begin: 0.3, end: 0),
        ],
      ),
    );
  }

  Widget _buildCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _cards.asMap().entries.map((entry) {
          final i = entry.key;
          final card = entry.value;
          final type = card['type'] as ConversionType?;
          final isSelected = _selectedIndex == i;
          final gradient = card['gradient'] as List<Color>;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedIndex = i;
                _selected = card['type'] as ConversionType?;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  )
                      : null,
                  color: isSelected ? null : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : const Color(0xFF2C2C2E),
                    width: 1,
                  ),
                  boxShadow: isSelected
                      ? [
                    BoxShadow(
                      color: gradient[0].withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    )
                  ]
                      : [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card['icon'] as String,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      card['title'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card['subtitle'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: isSelected
                            ? Colors.white.withOpacity(0.75)
                            : const Color(0xFF8E8E93),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedContainer(
                      duration: 280.ms,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF2C2C2E),
                      ),
                      child: isSelected
                          ? Icon(Icons.check_rounded,
                          size: 14,
                          color: gradient[0])
                          : null,
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: (300 + i * 100).ms, duration: 500.ms)
                  .slideY(begin: 0.3, end: 0),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCTA() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: GestureDetector(
        onTap: () async {
          if (_selectedIndex == 2) {
            // Edit PDF flow
            final result = await FilePicker.platform.pickFiles(
              type: kIsWeb ? FileType.any : FileType.custom,
              allowedExtensions: kIsWeb ? null : ['pdf'],
              withData: true,
            );
            if (result == null || result.files.isEmpty) return;
            final name = result.files.single.name;
            if (!name.toLowerCase().endsWith('.pdf')) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Please select a PDF file', style: GoogleFonts.inter()),
                backgroundColor: const Color(0xFFFF453A),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ));
              return;
            }
            final bytes = result.files.single.bytes!;
            if (!context.mounted) return;
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, anim, __) =>
                    EditScreen(pdfBytes: bytes, fileName: name),
                transitionsBuilder: (_, anim, __, child) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
                transitionDuration: const Duration(milliseconds: 400),
              ),
            );
          } else {
            if (_selected == null) return;
            // Convert flow
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, anim, __) => ConvertScreen(type: _selected!),
                transitionsBuilder: (_, anim, __, child) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
                transitionDuration: const Duration(milliseconds: 400),
              ),
            );
          }
        },
        child: Container(
          width: double.infinity,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFF0A84FF),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A84FF).withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Get Started',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 500.ms, duration: 500.ms)
        .slideY(begin: 0.4, end: 0);
  }
}