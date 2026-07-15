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

  static const List<Color> _categoryColors = [
    Color(0xFFFF6B81),
    Color(0xFFB18CFF),
    Color(0xFF7AD7F0),
    Color(0xFFFFC371),
    Color(0xFFB0C4FF),
    Color(0xFF6FE3C5),
    Color(0xFFFF9ECF),
    Color(0xFFA0F0A8),
  ];

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

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryMid, AppColors.accent],
            stops: [0.0, 0.45, 1.0],
          ),
          boxShadow: AppShadows.elevated,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Stack(
            children: [
              Positioned(
                top: -35,
                right: -25,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Positioned(
                top: 60,
                right: 40,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: 10,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              const Text(
                                'Available 24/7 · HIPAA Compliant',
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: AnimatedRotation(
                              turns: showExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 280),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Book an Appointment',
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Choose a specialty to get started',
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      sizeCurve: Curves.easeInOut,
                      crossFadeState: showExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: _buildExpandedContent(),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          const SizedBox(height: 16),
          _viewAllButton(),
        ],
      ),
    );
  }

  Widget _categoryGrid() {
    final categories = _filteredCategories;
    if (categories.isEmpty) {
      return _emptyState(
        _hasSearch ? 'No categories match your search' : 'No categories available',
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 4.0,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];
        final accent = _categoryColors[index % _categoryColors.length];
        final title = category.label;

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            splashColor: accent.withValues(alpha: 0.18),
            onTap: () => _openAppointmentPage(categoryTitle: title),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: _CategoryIcon(icon: category.icon),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.family,
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message.isEmpty ? 'Unable to load categories.' : message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.family,
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loadCategories,
            child: const Text(
              'Retry',
              style: TextStyle(
                fontFamily: AppFonts.family,
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState([String message = 'No categories available']) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: AppFonts.family,
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _viewAllButton() {
    return GestureDetector(
      onTap: () => _openAppointmentPage(),
      child: Container(
        height: 46,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'View all categories',
              style: TextStyle(
                fontFamily: AppFonts.family,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
          ],
        ),
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
        width: 13,
        height: 13,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }

    return Text(
      value,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, height: 1),
    );
  }
}

String _normalizeSearchText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
