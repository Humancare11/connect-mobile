// Section 3 — BookAppointmentCard (home hero)
//
// Deep-indigo gradient panel: availability pill across the top, then a two
// column body with the headline and "Get Started" action on the left and a
// calendar/stethoscope illustration on the right.
//
// "Get Started" reveals the category grid in place rather than navigating, so
// the card stays the quick path into a specialty while "View all categories"
// remains the way through to AppointmentBookingPage.
//
// Category loading/filtering/navigation is unchanged from earlier versions.

import 'package:flutter/material.dart';

import '../../config/app_design_system.dart';
import '../../models/appointment_tree_model.dart';
import '../../screens/book_appointment_screen.dart';
import '../../services/appointment_tree_service.dart';

class BookAppointmentCard extends StatefulWidget {
  const BookAppointmentCard({super.key, this.searchQuery = ''});

  final String searchQuery;

  @override
  State<BookAppointmentCard> createState() => _BookAppointmentCardState();
}

class _BookAppointmentCardState extends State<BookAppointmentCard> {
  final _treeService = AppointmentTreeService();

  bool _expanded = false;
  bool _loadingCategories = true;
  String? _categoryError;
  List<AppointmentTreeCategory> _categories = const [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });

    final result = await _treeService.fetchTree();
    if (!mounted) return;

    setState(() {
      _loadingCategories = false;
      if (result.success) {
        _categories = result.data ?? const [];
      } else {
        _categoryError = result.message;
      }
    });
  }

  bool get _hasSearch => widget.searchQuery.trim().isNotEmpty;

  List<AppointmentTreeCategory> get _filteredCategories {
    final query = _normalizeSearchText(widget.searchQuery);
    if (query.isEmpty) return _categories;

    return _categories.where((category) {
      if (_normalizeSearchText(category.label).contains(query)) return true;
      if (_normalizeSearchText(category.id).contains(query)) return true;
      return category.specialties.any((specialty) {
        if (_normalizeSearchText(specialty.name).contains(query)) return true;
        return specialty.conditions.any(
          (condition) => _normalizeSearchText(condition.name).contains(query),
        );
      });
    }).toList();
  }

  void _openAppointmentPage({String? categoryTitle}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AppointmentBookingPage(initialCategoryLabel: categoryTitle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showExpanded = _expanded || _hasSearch;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.heroFrom, AppColors.heroMid, AppColors.heroTo],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: AppShadows.elevated,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        child: Stack(
          children: [
            // Diagonal sheen. Previously two large translucent circles, which
            // at this card size left a visible curved seam across the panel
            // instead of reading as light — a gradient has no edge to show.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.04),
                      Colors.white.withValues(alpha: 0.12),
                    ],
                    stops: const [0.35, 0.72, 1.0],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pill and chevron share the full card width rather than
                  // sitting inside the left column: beside the illustration
                  // there is not enough room for the pill's copy, and it would
                  // ellipsize.
                  Row(
                    children: [
                      const Flexible(
                        child: _LivePill(
                          label: 'Available 24/7 · HIPAA Compliant',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CircleToggle(
                        expanded: showExpanded,
                        onTap: () => setState(() => _expanded = !_expanded),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Book an\nAppointment',
                              style: AppType.display(
                                size: 25,
                                weight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              'Choose a specialty to get started',
                              // Lifted off the old #B9C1EA: against the
                              // brighter gradient that value sank into the
                              // background instead of reading as secondary.
                              style: AppType.body(
                                size: 12.5,
                                color: const Color(0xFFC8D5F7),
                                height: 1.35,
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Straight through to the full booking page. The
                            // chevron above is what expands the shortlist of
                            // categories in place.
                            _GetStartedButton(
                              onTap: () => _openAppointmentPage(),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 10),

                      const _AppointmentIllustration(),
                    ],
                  ),

                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    sizeCurve: Curves.easeInOut,
                    crossFadeState: showExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: _buildExpandedContent(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          if (_loadingCategories) _loadingState(),
          if (!_loadingCategories && _categoryError != null)
            _errorState(_categoryError!),
          if (!_loadingCategories &&
              _categoryError == null &&
              _categories.isEmpty)
            _emptyState(),
          if (!_loadingCategories &&
              _categoryError == null &&
              _categories.isNotEmpty)
            _categoryGrid(),
          const SizedBox(height: 14),
          _viewAllButton(),
        ],
      ),
    );
  }

  Widget _categoryGrid() {
    final categories = _filteredCategories;
    if (categories.isEmpty) {
      return _emptyState(
        _hasSearch
            ? 'No categories match your search'
            : 'No categories available',
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        mainAxisExtent: 46,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];
        final title = category.label;

        return Material(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            splashColor: Colors.white.withValues(alpha: 0.14),
            onTap: () => _openAppointmentPage(categoryTitle: title),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    alignment: Alignment.center,
                    child: _CategoryIcon(icon: category.icon),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body(
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loadingState() {
    return const SizedBox(
      height: 46,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      ),
    );
  }

  Widget _errorState(String message) {
    return _glassPanel(
      child: Row(
        children: [
          Expanded(
            child: Text(
              message.isEmpty ? 'Unable to load categories.' : message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.body(size: 11.5, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loadCategories,
            child: Text(
              'Retry',
              style: AppType.body(
                size: 11.5,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState([String message = 'No categories available']) {
    return _glassPanel(
      child: Text(message, style: AppType.body(size: 11.5, color: Colors.white)),
    );
  }

  Widget _glassPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }

  Widget _viewAllButton() {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _openAppointmentPage(),
        child: Container(
          height: 46,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'View all categories',
                style: AppType.display(size: 13.5, color: Colors.white),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero sub-widgets ─────────────────────────────────────────────────────────

class _LivePill extends StatelessWidget {
  const _LivePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // No outline — the design relies on the translucent fill alone, and a
      // hairline border on a gradient reads as a seam rather than an edge.
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.teal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.body(
                size: 11,
                weight: FontWeight.w500,
                color: const Color(0xFFEDEFFB),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular chevron that expands the category shortlist in place. Restored
/// from the pre-redesign card: the illustration-led layout has no other
/// affordance for browsing categories without leaving the home screen.
class _CircleToggle extends StatelessWidget {
  const _CircleToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
        ),
        alignment: Alignment.center,
        child: AnimatedRotation(
          turns: expanded ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 280),
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// White pill with a filled circular arrow, as in the design. The arrow points
/// forward and does not animate — this navigates to the booking page, so it
/// must not read as an in-place disclosure the way the chevron above does.
class _GetStartedButton extends StatelessWidget {
  const _GetStartedButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Get Started',
                  style: AppType.display(
                    size: 13,
                    color: AppColors.primaryDeep,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDeep],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Calendar-and-stethoscope motif from the design, drawn rather than shipped as
/// an image asset so it stays crisp at any density and recolours with the
/// palette. The stethoscope is painted behind the calendar so its tube reads as
/// passing around it.
class _AppointmentIllustration extends StatelessWidget {
  const _AppointmentIllustration();

  static const double _size = 116;

  // Calendar geometry, shared with the badge and ring placement below so the
  // three stay aligned if the sizes are tuned.
  static const double _calWidth = 88;
  static const double _calHeight = 78;
  static const double _calTop = 16;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _StethoscopePainter()),
          ),

          // Binder rings, straddling the header's top edge so they read as
          // threaded through it rather than floating above the card.
          const Positioned(top: _calTop - 7, right: 60, child: _BinderRing()),
          const Positioned(top: _calTop - 7, right: 24, child: _BinderRing()),

          Positioned(
            top: _calTop,
            right: 0,
            child: Container(
              width: _calWidth,
              height: _calHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.heroTo.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: -6,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 17,
                    decoration: const BoxDecoration(
                      // Blue, not the indigo `accent` — that read as purple
                      // against the card and fought the rest of the palette.
                      color: Color(0xFF3D7BEE),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: List.generate(
                          12,
                          (_) => Container(
                            width: 14,
                            height: 9,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD9E4FA),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Confirmation badge, overlapping the calendar's lower-right corner.
          Positioned(
            right: 0,
            bottom: _size - (_calTop + _calHeight) - 8,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2F6BE5),
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BinderRing extends StatelessWidget {
  const _BinderRing();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFFCBD8F2),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _StethoscopePainter extends CustomPainter {
  const _StethoscopePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final tube = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.62);

    // Both ear tubes start high and to the right so they disappear behind the
    // calendar, then converge and sweep down the left side to the chest piece
    // — the tube has to look like it passes behind the card, not beside it.
    final yoke = Offset(w * 0.17, h * 0.40);
    final earLeft = Offset(w * 0.10, h * 0.08);
    final earRight = Offset(w * 0.40, h * 0.04);
    final chestPiece = Offset(w * 0.22, h * 0.76);

    canvas.drawPath(
      Path()
        ..moveTo(earLeft.dx, earLeft.dy)
        ..quadraticBezierTo(w * 0.04, h * 0.24, yoke.dx, yoke.dy),
      tube,
    );
    canvas.drawPath(
      Path()
        ..moveTo(earRight.dx, earRight.dy)
        ..quadraticBezierTo(w * 0.36, h * 0.26, yoke.dx, yoke.dy),
      tube,
    );

    canvas.drawPath(
      Path()
        ..moveTo(yoke.dx, yoke.dy)
        ..cubicTo(
          w * 0.05,
          h * 0.56,
          w * 0.06,
          h * 0.72,
          chestPiece.dx,
          chestPiece.dy,
        ),
      tube,
    );

    canvas.drawCircle(
      chestPiece,
      12,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      chestPiece,
      6.5,
      Paint()..color = const Color(0xFF3D7BEE).withValues(alpha: 0.45),
    );

    // Ear tips.
    final tip = Paint()..color = Colors.white.withValues(alpha: 0.8);
    canvas.drawCircle(earLeft, 4, tip);
    canvas.drawCircle(earRight, 4, tip);
  }

  @override
  bool shouldRepaint(_StethoscopePainter oldDelegate) => false;
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.icon});

  final String icon;

  @override
  Widget build(BuildContext context) {
    final value = icon.trim();
    if (value.isEmpty) return const SizedBox.shrink();

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return Image.network(
        value,
        width: 14,
        height: 14,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }

    return Text(
      value,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, height: 1),
    );
  }
}

String _normalizeSearchText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
