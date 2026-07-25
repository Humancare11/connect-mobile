// Section 6 — MedicalServicesSection
// Premium redesign: 2-col grid, rounded square icon containers with
// per-service soft bg, subtitle row, consistent shadows + border.
// Visually distinct from BookByService (circle icons, no subtitle)
// and ExploreSpecialties (horizontal scroll).
//
// Services are fetched from GET /api/services at runtime instead of
// being hardcoded.

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';
import '../../models/service_model.dart';
import '../../services/services_service.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _MedService {
  final String id;
  final String icon;
  final String title;
  final String subtitle;
  final num price;
  final Color accent;
  final Color bgColor;

  const _MedService({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.accent,
    required this.bgColor,
  });
}

// ── Main widget ───────────────────────────────────────────────────────────────

class MedicalServicesSection extends StatefulWidget {
  const MedicalServicesSection({super.key, this.searchQuery = ''});

  final String searchQuery;

  @override
  State<MedicalServicesSection> createState() =>
      _MedicalServicesSectionState();
}

class _MedicalServicesSectionState extends State<MedicalServicesSection> {
  final _servicesService = ServicesService();

  bool _loading = true;
  String? _error;
  List<_MedService> _services = const [];

  // Cycled per-tile accent/background pair — mirrors the original
  // hardcoded palette since the backend does not provide colors.
  static const List<Color> _accentColors = [
    Color(0xFF4CC3B3),
    Color(0xFFF5B74E),
    AppColors.catBrain,
    Color(0xFF5B9EFF),
    Color(0xFFFF7FA3),
    Color(0xFF63C06B),
  ];

  static const List<Color> _bgColors = [
    Color(0xFFEFF9F7),
    Color(0xFFFFF9EE),
    Color(0xFFF5EFFF),
    Color(0xFFEFF5FF),
    Color(0xFFFFF0F4),
    Color(0xFFEFF8EF),
  ];

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await _servicesService.fetchServices();
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.success) {
        _services = _buildServices(result.data ?? const []);
      } else {
        _error = result.message;
      }
    });
  }

  List<_MedService> _buildServices(List<ServiceModel> services) {
    final items = <_MedService>[];
    for (final service in services) {
      final index = items.length;
      items.add(
        _MedService(
          id: service.id,
          icon: service.icon,
          title: service.name,
          subtitle: service.description,
          price: service.price,
          accent: _accentColors[index % _accentColors.length],
          bgColor: _bgColors[index % _bgColors.length],
        ),
      );
    }
    return items;
  }

  List<_MedService> get _filteredServices {
    final query = _normalizeSearchText(widget.searchQuery);
    if (query.isEmpty) return _services;

    return _services.where((service) {
      return _normalizeSearchText(service.title).contains(query) ||
          _normalizeSearchText(service.subtitle).contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────────────────────
        AppSectionHeader(
          title:       'Our Medical Services',
          seeAllLabel: 'View all',
          onSeeAll:    () {},
        ),

        const SizedBox(height: AppSpacing.md),

        _buildContent(context),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (_error != null) {
      return _MessageState(
        message: _error!.isEmpty
            ? 'Unable to load medical services.'
            : _error!,
        actionLabel: 'Retry',
        onAction: _loadServices,
      );
    }

    final services = _filteredServices;

    if (services.isEmpty) {
      return _MessageState(
        message: _services.isNotEmpty && widget.searchQuery.trim().isNotEmpty
            ? 'No medical services match your search.'
            : 'No medical services available.',
      );
    }

    // ── 2-col service grid ───────────────────────────────────────────────
    return GridView.builder(
      shrinkWrap: true,
      physics:    const NeverScrollableScrollPhysics(),
      itemCount:  services.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   2,
        crossAxisSpacing: 11,
        mainAxisSpacing:  11,
        childAspectRatio: 1.95,
      ),
      itemBuilder: (context, index) {
        return _ServiceTile(item: services[index]);
      },
    );
  }
}

// ── Service tile ──────────────────────────────────────────────────────────────

class _ServiceTile extends StatelessWidget {
  final _MedService item;

  const _ServiceTile({super.key, required this.item});

  // Reuses the same "/appointment-form" → consent → "/appointment-payment"
  // → "/appointment-confirmation" flow already used for Category/Specialty/
  // Condition bookings. That flow reads its selection from generic
  // specName/specIcon/catLabel/condName/condIcon/cost keys, so mapping a
  // service onto those keys lets it go through payment, appointment
  // creation and notifications unchanged.
  void _openBookingForm(BuildContext context) {
    Navigator.pushNamed(
      context,
      '/appointment-form',
      arguments: {
        'specName': item.title,
        'specIcon': item.icon,
        'catLabel': 'Service',
        'condName': item.subtitle,
        'condIcon': '',
        'cost': item.price,
        'serviceId': item.id,
        'bookingType': 'service',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color:        Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        splashColor:  item.accent.withValues(alpha: 0.10),
        onTap:        () => _openBookingForm(context),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border:       Border.all(color: AppColors.border, width: 1.2),
            boxShadow:    AppShadows.subtle,
          ),
          child: Row(
            children: [
              // Rounded-square icon container (distinct from circle in Sec 4)
              Container(
                width:  46,
                height: 46,
                decoration: BoxDecoration(
                  color:        item.bgColor,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Center(
                  child: _ServiceIcon(icon: item.icon, color: item.accent),
                ),
              ),

              const SizedBox(width: AppSpacing.sm + 3),

              // Text column
              Expanded(
                child: Column(
                  mainAxisAlignment:  MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines:  1,
                      overflow:  TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily:    AppFonts.family,
                        fontSize:      12.5,
                        fontWeight:    FontWeight.w700,
                        color:         AppColors.textPrimary,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines:  1,
                      overflow:  TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize:   10.5,
                        fontWeight: FontWeight.w400,
                        color:      AppColors.textSecondary,
                      ),
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
}

// Backend icons arrive as a string (emoji/glyph); fall back to a generic
// icon so the tile still reads correctly when a service has none set.
class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.icon, required this.color});

  final String icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = icon.trim();
    if (value.isEmpty) {
      return Icon(Icons.medical_services_outlined, size: 22, color: color);
    }

    return Text(value, style: const TextStyle(fontSize: 20, height: 1));
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border:       Border.all(color: AppColors.border, width: 1.2),
        boxShadow:    AppShadows.subtle,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.family,
                fontSize:   12,
                fontWeight: FontWeight.w500,
                color:      AppColors.textSecondary,
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
