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

  static const List<Color> _accentColors = [
    AppColors.catHeart,
    AppColors.catBrain,
    AppColors.catMental,
    AppColors.catWomen,
    AppColors.catChild,
    AppColors.catRespire,
    AppColors.catGenetics,
    AppColors.catBones,
  ];

  static const List<Color> _bgColors = [
    Color(0xFFEFF6FF),
    Color(0xFFF5EFFF),
    Color(0xFFEFFAF6),
    Color(0xFFFFF0F6),
    Color(0xFFFFFBEB),
    Color(0xFFF0FFF3),
    Color(0xFFEFF9FF),
  ];

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

        final index = items.length;
        items.add(
          _SpecialtyItem(
            icon: specialty.icon,
            title: _displayTitle(name),
            appointmentName: name,
            accent: _accentColors[index % _accentColors.length],
            bgColor: _bgColors[index % _bgColors.length],
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

  String _displayTitle(String value) {
    final words = value.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
    if (words.length < 2 || value.length <= 12) return value;

    final midpoint = (words.length / 2).ceil();
    return '${words.take(midpoint).join(' ')}\n${words.skip(midpoint).join(' ')}';
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
        AppSectionHeader(
          title: 'Explore Specialties',
          seeAllLabel: 'See all',
          onSeeAll: () =>
              _openAppointmentPage(context, showAllSpecialties: true),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 140, child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loadingSpecialties) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_specialtyError != null) {
      return _InlineState(
        message: _specialtyError!.isEmpty
            ? 'Unable to load specialties.'
            : _specialtyError!,
        actionLabel: 'Retry',
        onAction: _loadSpecialties,
      );
    }

    final specialties = _filteredSpecialties;

    if (specialties.isEmpty) {
      if (_specialties.isNotEmpty && widget.searchQuery.trim().isNotEmpty) {
        return const _InlineState(message: 'No specialties match your search.');
      }

      return const _InlineState(message: 'No specialties available.');
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: specialties.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final item = specialties[index];
        return _SpecialtyCard(
          item: item,
          onTap: () => _openAppointmentPage(
            context,
            specialtyName: item.appointmentName,
          ),
        );
      },
    );
  }
}

class _SpecialtyCard extends StatelessWidget {
  final _SpecialtyItem item;
  final VoidCallback onTap;

  const _SpecialtyCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        splashColor: item.accent.withValues(alpha: 0.12),
        onTap: onTap,
        child: Container(
          width: 108,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border, width: 1.2),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: item.bgColor,
                  shape: BoxShape.circle,
                ),
                child: Center(child: _SpecialtyIcon(icon: item.icon)),
              ),
              const SizedBox(height: AppSpacing.sm + 2),
              Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpecialtyIcon extends StatelessWidget {
  const _SpecialtyIcon({required this.icon});

  final String icon;

  @override
  Widget build(BuildContext context) {
    final value = icon.trim();
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      value,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, height: 1),
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
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
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
