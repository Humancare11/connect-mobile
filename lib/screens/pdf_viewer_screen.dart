import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../config/app_design_system.dart';

/// Shows a saved PDF inside the app, for a phone with no app that can open it.
/// Read only: no printing, no sharing.
class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({
    super.key,
    required this.title,
    required this.bytes,
    required this.errorText,
  });

  /// The file name.
  final String title;
  final Uint8List bytes;

  /// Shown when the pages cannot be drawn either.
  final String errorText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: AppType.body(
            size: 16,
            weight: FontWeight.w800,
          ).copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: PdfPreview(
        build: (_) => bytes,
        useActions: false,
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        onError: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              errorText,
              textAlign: TextAlign.center,
              style: AppType.body(size: 14),
            ),
          ),
        ),
      ),
    );
  }
}
