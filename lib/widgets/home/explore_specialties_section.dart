// Section 5 — ExploreSpecialtiesSection
//
// Horizontally scrolling row of narrow specialty tiles. The row deliberately
// bleeds past the page gutter (the header is padded, the list is not) so cards
// run to the screen edge and read as scrollable; the list applies the gutter as
// its own leading/trailing padding to keep the first and last card aligned with
// everything else.

import 'package:flutter/material.dart';

import '../../config/app_design_system.dart';
import '../../models/appointment_tree_model.dart';
import '../../screens/book_appointment_screen.dart';
import '../../services/appointment_tree_service.dart';

class _SpecialtyItem {
  final String icon;
  final String title;
  final String appointmentName;
  final Color accent;
  final Color bgColor;

  const _SpecialtyItem({
    required this.icon,
    required this.title,
    required this.appointmentName,
    required this.accent,
    required this.bgColor,
  });
}

class ExploreSpecialtiesSection extends StatefulWidget {
  const ExploreSpecialtiesSection({super.key, this.searchQuery = ''});

  final String searchQuery;

  @override
  State<ExploreSpecialtiesSection> createState() =>
      _ExploreSpecialtiesSectionState();
}

class _ExploreSpecialtiesSectionState extends State<ExploreSpecialtiesSection> {
  final _treeService = AppointmentTreeService();

  bool _loadingSpecialties = true;
  String? _specialtyError;
  List<_SpecialtyItem> _specialties = const [];

  @override
  void initState() {
    super.initState();
    _loadSpecialties();
  }

  Future<void> _loadSpecialties() async {
    setState(() {
      _loadingSpecialties = true;
      _specialtyError = null;
    });

    final result = await _treeService.fetchTree();
    if (!mounted) return;

    setState(() {
      _loadingSpecialties = false;
      if (result.success) {
        _specialties = _buildSpecialties(result.data ?? const []);
      } else {
        _specialtyError = result.message;
      }
    });
  }

  List<_SpecialtyItem> _buildSpecialties(
    List<AppointmentTreeCategory> categories,
  ) {
    final items = <_SpecialtyItem>[];
    for (final category in categories) {
      for (final specialty in category.specialties) {
        final name = specialty.name.trim();
        if (name.isEmpty) continue;

        // Accent/tint are cycled positionally and always taken from the same
        // index, so an icon tile's background and its ink stay a matched pair.
        final index = items.length % AppColors.accentInks.length;
        items.add(
          _SpecialtyItem(
            icon: specialty.icon,
            title: name,
            appointmentName: name,
            accent: AppColors.accentInks[index],
            bgColor: AppColors.accentTints[index],
          ),
        );
      }
    }
    return items;
  }

  List<_SpecialtyItem> get _filteredSpecialties {
    final query = _normalizeSearchText(widget.searchQuery);
    if (query.isEmpty) return _specialties;

    return _specialties.where((item) {
      return _normalizeSearchText(item.title).contains(query) ||
          _normalizeSearchText(item.appointmentName).contains(query);
    }).toList();
  }

  void _openAppointmentPage(
    BuildContext context, {
    String? specialtyName,
    bool showAllSpecialties = false,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentBookingPage(
          initialSpecialtyName: specialtyName,
          initialTab: showAllSpecialties ? "spec" : "cat",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: AppSectionHeader(
            title: 'Explore specialties',
            seeAllLabel: 'See all',
            onSeeAll: () =>
                _openAppointmentPage(context, showAllSpecialties: true),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 124, child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loadingSpecialties) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (_specialtyError != null) {
      return _gutter(
        _InlineState(
          message: _specialtyError!.isEmpty
              ? 'Unable to load specialties.'
              : _specialtyError!,
          actionLabel: 'Retry',
          onAction: _loadSpecialties,
        ),
      );
    }

    final specialties = _filteredSpecialties;

    if (specialties.isEmpty) {
      final searched =
          _specialties.isNotEmpty && widget.searchQuery.trim().isNotEmpty;
      return _gutter(
        _InlineState(
          message: searched
              ? 'No specialties match your search.'
              : 'No specialties available.',
        ),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      itemCount: specialties.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final item = specialties[index];
        return _SpecialtyCard(
          item: item,
          onTap: () =>
              _openAppointmentPage(context, specialtyName: item.appointmentName),
        );
      },
    );
  }

  Widget _gutter(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
    child: child,
  );
}

class _SpecialtyCard extends StatelessWidget {
  final _SpecialtyItem item;
  final VoidCallback onTap;

  const _SpecialtyCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
        splashColor: item.accent.withValues(alpha: 0.12),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: item.bgColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: _SpecialtyIcon(icon: item.icon, color: item.accent),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.body(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Specialty icons arrive from the backend as a string (usually an emoji).
/// Falls back to a neutral glyph tinted with the tile's accent so an entry
/// with no icon still fills its tile instead of leaving a blank square.
class _SpecialtyIcon extends StatelessWidget {
  const _SpecialtyIcon({required this.icon, required this.color});

  final String icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = icon.trim();
    if (value.isEmpty) {
      return Icon(Icons.local_hospital_outlined, size: 22, color: color);
    }

    return Text(
      value,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, height: 1),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.subtle,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.body(size: 12),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

String _normalizeSearchText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
