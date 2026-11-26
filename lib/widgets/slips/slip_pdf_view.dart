import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../config/app_design_system.dart';
import 'slip_tokens.dart';

/// Builds a document's PDF and turns its pages into pictures `widthPx` wide.
typedef SlipPageRenderer =
    Future<List<ui.Image>> Function(
      Future<Uint8List> Function() buildPdf,
      double widthPx,
    );

/// A document on screen, drawn from the very PDF the Download button saves, so
/// the two can never differ. Each page fits the width; pinch or double-tap to
/// zoom; further pages are stacked below.
class SlipPdfView extends StatefulWidget {
  const SlipPdfView({
    super.key,
    required this.buildPdf,
    required this.version,
    required this.label,
  });

  final Future<Uint8List> Function() buildPdf;

  /// Changes when the document's content does: the pages are then drawn again.
  final String version;

  /// What a screen reader calls the page, e.g. "Prescription".
  final String label;

  static const String failedText = 'Could not show the document.';
  static const String retryText = 'Retry';

  static const double maxZoom = 4;
  static const double doubleTapZoom = 2.5;

  /// Tests replace this: drawing PDF pages needs the phone.
  @visibleForTesting
  static SlipPageRenderer renderPages = renderWithPhone;

  /// Draws the pages with the phone's own PDF engine (`printing`).
  static Future<List<ui.Image>> renderWithPhone(
    Future<Uint8List> Function() buildPdf,
    double widthPx,
  ) async {
    final bytes = await buildPdf();
    final pages = <ui.Image>[];
    try {
      final dpi = widthPx / PdfPageFormat.a4.width * 72;
      await for (final page
          in Printing.raster(
            bytes,
            dpi: dpi,
          ).timeout(const Duration(seconds: 30))) {
        pages.add(await page.toImage());
      }
      if (pages.isEmpty) throw StateError('The PDF has no pages.');
      return pages;
    } catch (_) {
      for (final page in pages) {
        page.dispose();
      }
      rethrow;
    }
  }

  @override
  State<SlipPdfView> createState() => _SlipPdfViewState();
}

class _SlipPdfViewState extends State<SlipPdfView>
    with AutomaticKeepAliveClientMixin {
  List<ui.Image>? _pages;
  bool _failed = false;
  int _request = 0;
  double? _widthPx;

  // Not drawn again just because the list scrolled it out of sight.
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_widthPx != null) return;
    // Sharper than the screen, so that zooming stays readable, but bounded:
    // an A4 page 2000 px wide already takes about 22 MB.
    final screen = MediaQuery.sizeOf(context).shortestSide;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    _widthPx = (screen * ratio * 1.5).clamp(1200, 2000).toDouble();
    _render();
  }

  @override
  void didUpdateWidget(SlipPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The old pages stay on screen until the new ones are ready.
    if (oldWidget.version != widget.version) _render();
  }

  @override
  void dispose() {
    _disposePages(_pages);
    super.dispose();
  }

  static void _disposePages(List<ui.Image>? pages) {
    for (final page in pages ?? const <ui.Image>[]) {
      page.dispose();
    }
  }

  Future<void> _render() async {
    final request = ++_request;
    if (_failed) setState(() => _failed = false);
    try {
      final pages = await SlipPdfView.renderPages(widget.buildPdf, _widthPx!);
      if (!mounted || request != _request) {
        _disposePages(pages);
        return;
      }
      final old = _pages;
      setState(() => _pages = pages);
      // After the frame that stops showing them.
      WidgetsBinding.instance.addPostFrameCallback((_) => _disposePages(old));
    } catch (error) {
      debugPrint('SlipPdfView: $error');
      if (!mounted || request != _request) return;
      final old = _pages;
      setState(() {
        _pages = null;
        _failed = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _disposePages(old));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final padding = MediaQuery.sizeOf(context).width <= 420 ? 8.0 : 12.0;
    final pages = _pages;

    return Container(
      decoration: const BoxDecoration(
        color: SlipColors.wrap,
        border: Border(top: BorderSide(color: SlipColors.wrapLine)),
      ),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_failed)
            _failure()
          else if (pages == null)
            const AspectRatio(
              aspectRatio: 210 / 297,
              child: ColoredBox(
                color: Colors.white,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            )
          else
            for (var i = 0; i < pages.length; i++) ...[
              if (i > 0) SizedBox(height: padding),
              _ZoomablePage(
                key: ValueKey('slip page ${i + 1}'),
                image: pages[i],
                label: '${widget.label}, page ${i + 1} of ${pages.length}',
              ),
            ],
        ],
      ),
    );
  }

  Widget _failure() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Text(
            SlipPdfView.failedText,
            textAlign: TextAlign.center,
            style: AppType.body(size: 13),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _render,
            child: const Text(SlipPdfView.retryText),
          ),
        ],
      ),
    );
  }
}

/// One page. Dragging with one finger scrolls the screen as usual until the
/// page is zoomed; then it moves around inside the page.
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({super.key, required this.image, required this.label});

  final ui.Image image;
  final String label;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final _transform = TransformationController();
  final Set<int> _fingers = {};
  Offset _tapped = Offset.zero;
  bool _zoomed = false;
  bool _pinching = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _finger(int pointer, {required bool down}) {
    down ? _fingers.add(pointer) : _fingers.remove(pointer);
    final pinching = math.max(0, _fingers.length) > 1;
    if (pinching != _pinching) setState(() => _pinching = pinching);
  }

  void _toggleZoom() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    const scale = SlipPdfView.doubleTapZoom;
    // The tapped point stays under the finger.
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        -_tapped.dx * (scale - 1),
        -_tapped.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Semantics(
      image: true,
      label: widget.label,
      child: AspectRatio(
        aspectRatio: widget.image.width / widget.image.height,
        child: Listener(
          onPointerDown: (e) => _finger(e.pointer, down: true),
          onPointerUp: (e) => _finger(e.pointer, down: false),
          onPointerCancel: (e) => _finger(e.pointer, down: false),
          child: GestureDetector(
            onDoubleTapDown: (details) => _tapped = details.localPosition,
            onDoubleTap: _toggleZoom,
            // While zoomed or pinching, the page must win the drag before the
            // list around it does: a smaller touch slop makes it decide first.
            child: MediaQuery(
              data: _zoomed || _pinching
                  ? media.copyWith(
                      gestureSettings: const DeviceGestureSettings(
                        touchSlop: 4,
                      ),
                    )
                  : media,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: SlipPdfView.maxZoom,
                panEnabled: _zoomed,
                // The PDF paints no background of its own.
                child: ColoredBox(
                  color: Colors.white,
                  child: RawImage(
                    image: widget.image,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
