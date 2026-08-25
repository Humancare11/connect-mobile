// Section 3 — BookAppointmentCard (home hero)
//
// Deep-indigo gradient panel: availability pill across the top, then a two
// column body with the headline and "Get Started" action on the left and a
// calendar image illustration on the right.
//
// "Get Started" reveals the category grid in place rather than navigating, so
// the card stays the quick path into a specialty while "View all categories"
// remains the way through to AppointmentBookingPage.

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

    // Screen width nikaal ke illustration ki size decide karte hain, taaki
    // choti screens par woh chhoti ho aur badi screens par thodi badi. Sized
    // larger than before for visual balance against the headline — safe to
    // do because the title below is wrapped in a FittedBox that shrinks to
    // whatever width remains rather than wrapping mid-word.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final illustrationSize = (screenWidth * 0.36).clamp(120.0, 168.0);

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: _LiveStatus(
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
                            // FittedBox (scaleDown only) rather than a bare
                            // Text: the explicit line break keeps "Book an"
                            // and "Appointment" on their own lines as two
                            // whole words, and scaling the block down to fit
                            // whatever width the illustration leaves means
                            // "Appointment" is never forced to wrap
                            // mid-word (e.g. a lone trailing "t") on narrow
                            // screens — it never grows past its natural
                            // size on wide ones either.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Book an\nAppointment',
                                style: AppType.display(
                                  size: 25,
                                  weight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              'Choose a specialty to get started',
                              style: AppType.body(
                                size: 12.5,
                                color: const Color(0xFFC8D5F7),
                                height: 1.35,
                              ),
                            ),

                            const SizedBox(height: 18),

                            _GetStartedButton(
                              onTap: () => _openAppointmentPage(),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 10),

                      // Right-side illustration (ab image asset).
                      _AppointmentIllustration(size: illustrationSize),
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
      child: Text(
        message,
        style: AppType.body(size: 11.5, color: Colors.white),
      ),
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

/// Availability line: a live dot and the label, with no chip behind it.
class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
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
              size: 11.5,
              weight: FontWeight.w600,
              color: const Color(0xFFEDEFFB),
            ),
          ),
        ),
      ],
    );
  }
}

/// Circular chevron that expands the category shortlist in place.
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

/// White pill with a filled circular arrow.
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

/// Right-side illustration. Ab ye drawn calendar/stethoscope ki jagah ek
/// image asset (calende.png) dikhata hai. Size parent se aata hai taaki card
/// alag-alag screen widths par responsive rahe.
class _AppointmentIllustration extends StatelessWidget {
  const _AppointmentIllustration({this.size = 116});

  final double size;

  @override
  Widget build(BuildContext context) {
    // The source PNG is a 6250x6250 (~19.5 MB) image. Without cacheWidth/
    // cacheHeight, Image.asset decodes it at full resolution before scaling
    // down for display — allocating ~150 MB of raw bitmap for a ~140x140
    // box. That decode fails on real devices, and errorBuilder below was
    // silently swallowing the failure, so nothing ever rendered. Passing a
    // physical-pixel cache size makes Flutter downsample during decode.
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = (size * devicePixelRatio).round();

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/calender.png',
        fit: BoxFit.contain,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        // Agar image load na ho paye to layout na toote:
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
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
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
