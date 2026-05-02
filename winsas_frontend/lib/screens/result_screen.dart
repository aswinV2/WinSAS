import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'home_screen.dart';

class ResultScreen extends StatelessWidget {
  final String pdfPath;
  final String originalName;
  final Color accentColor;

  const ResultScreen({
    super.key,
    required this.pdfPath,
    required this.originalName,
    required this.accentColor,
  });

  Future<double> _getFileSize() async {
    final file = File(pdfPath);
    final bytes = await file.length();
    return bytes / (1024 * 1024);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 60),
              _buildSuccessIcon(),
              const SizedBox(height: 32),
              _buildSuccessText(),
              const SizedBox(height: 40),
              _buildFilePreviewCard(),
              const Spacer(),
              _buildActions(context),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessIcon() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF30D158).withOpacity(0.15),
        border: Border.all(
          color: const Color(0xFF30D158).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: const Icon(
        Icons.check_rounded,
        color: Color(0xFF30D158),
        size: 52,
      ),
    )
        .animate()
        .scale(
      begin: const Offset(0.3, 0.3),
      end: const Offset(1, 1),
      duration: 500.ms,
      curve: Curves.elasticOut,
    )
        .fadeIn(duration: 300.ms);
  }

  Widget _buildSuccessText() {
    return Column(
      children: [
        Text(
          'Conversion\nComplete',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 42,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
            letterSpacing: -2,
          ),
        )
            .animate()
            .fadeIn(delay: 200.ms, duration: 500.ms)
            .slideY(begin: 0.2, end: 0),
        const SizedBox(height: 12),
        Text(
          'Your PDF is ready to open or share.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: const Color(0xFF8E8E93),
          ),
        ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
      ],
    );
  }

  Widget _buildFilePreviewCard() {
    return FutureBuilder<double>(
      future: _getFileSize(),
      builder: (context, snap) {
        final size = snap.data;
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2C2C2E)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF453A).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('📕', style: TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$originalName.pdf',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      size != null
                          ? '${size.toStringAsFixed(2)} MB  •  PDF Document'
                          : 'PDF Document',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.picture_as_pdf_rounded,
                  color: Color(0xFFFF453A), size: 24),
            ],
          ),
        )
            .animate()
            .fadeIn(delay: 400.ms, duration: 500.ms)
            .slideY(begin: 0.2, end: 0);
      },
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        // Open PDF
        GestureDetector(
          onTap: () => OpenFilex.open(pdfPath),
          child: Container(
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF30D158),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF30D158).withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Center(
              child: Text(
                'Open PDF',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Share
        GestureDetector(
          onTap: () => Share.shareXFiles(
            [XFile(pdfPath)],
            text: 'Converted with WinSAS',
          ),
          child: Container(
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2C2C2E)),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.share_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Share',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Convert another
        GestureDetector(
          onTap: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
          ),
          child: Container(
            width: double.infinity,
            height: 48,
            child: Center(
              child: Text(
                'Convert another file',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF8E8E93),
                ),
              ),
            ),
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(delay: 500.ms, duration: 500.ms)
        .slideY(begin: 0.3, end: 0);
  }
}