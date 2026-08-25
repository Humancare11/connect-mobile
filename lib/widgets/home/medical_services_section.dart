// Section 6 — MedicalServicesSection
// Premium redesign: responsive grid of soft, elevated tiles.
//   • rounded-square icon container with per-service soft bg tint
//   • thin left accent rail (signature element, tied to each service colour)
//   • title wraps up to 2 lines (no subtitle) so names are never cut off
//   • trailing chevron + press-scale micro-interaction
//   • column count adapts to screen width (1 / 2 / 3)
// Backend icons (emoji/glyph strings) are kept exactly as-is.
//
// Services are fetched from GET /api/services at runtime instead of
// being hardcoded. Subtitle is still used for search, just not shown.

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';
import '../../models/service_model.dart';
import '../../services/services_service.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _MedService {
  final String id;
  final String icon;
  final String title;
  final String subtitle; // kept for search only, not displayed
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
        // Plain title only — no "View all" pill here (unlike other home
        // sections, which still use AppSectionHeader for that).
        Text(
          'Our Medical Services',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.h2,
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
        child: Center(child: CircularProgressIndicator()),
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

    return _buildGrid(context, services);
  }

  // ── Responsive service grid ──────────────────────────────────────────────
  // Column count screen width ke hisaab se: choti screen par 1 column,
  // normal phone par 2, tablet/wide par 3. Tile ki width auto-calculate hoti
  // hai taaki kabhi overflow na ho.
  Widget _buildGrid(BuildContext context, List<_MedService> services) {
    const double spacing = 10;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Previous 340 cutoff was wider than the content area on virtually
        // every phone once the page's own 22px gutter (see _Gutter in
        // home_page.dart) is subtracted from the screen width — e.g. a
        // common 360-390 logical-px phone only ever passes ~316-346 down
        // here, so it was permanently stuck at 1 column. Lowered so 2
        // columns is the normal phone case; 1 column is now reserved for
        // genuinely tiny widths (e.g. a split-screen/multi-window pane).
        int columns;
        if (maxWidth < 240) {
          columns = 1; // extremely narrow (split-screen, etc.)
        } else if (maxWidth < 620) {
          columns = 2; // normal phones
        } else {
          columns = 3; // tablets / wide screens
        }

        final totalSpacing = spacing * (columns - 1);
        final tileWidth =
            ((maxWidth - totalSpacing) / columns).floorToDouble();

        // Title 2 line tak ja sakti hai isliye tile thodi lambi rakhi hai.
        const double tileHeight = 82;

        final isOdd = services.length.isOdd;

        final tiles = <Widget>[];
        for (var i = 0; i < services.length; i++) {
          // Sirf 2-column layout me: agar count odd hai to aakhri tile poori
          // width le le, taaki neeche adhoora gap na dikhe.
          final bool fullWidth =
              columns == 2 && isOdd && i == services.length - 1;

          tiles.add(
            SizedBox(
              width: fullWidth ? maxWidth : tileWidth,
              height: tileHeight,
              child: _ServiceTile(item: services[i]),
            ),
          );
        }

        return Wrap(
          spacing:    spacing,
          runSpacing: spacing,
          children:   tiles,
        );
      },
    );
  }
}

// ── Service tile ──────────────────────────────────────────────────────────────

class _ServiceTile extends StatefulWidget {
  final _MedService item;

  const _ServiceTile({super.key, required this.item});

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _pressed = false;

  // Reuses the same "/appointment-form" → consent → "/appointment-payment"
  // → "/appointment-confirmation" flow already used for Category/Specialty/
  // Condition bookings.
  void _openBookingForm(BuildContext context) {
    final item = widget.item;
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
    final item = widget.item;

    return AnimatedScale(
      scale:    _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve:    Curves.easeOut,
      child: Material(
        color:        Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius:       BorderRadius.circular(AppRadius.md),
          splashColor:        item.accent.withOpacity(0.10),
          highlightColor:     Colors.transparent,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onTap:              () => _openBookingForm(context),
          child: Container(
            decoration: BoxDecoration(
              color:        AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border:       Border.all(color: AppColors.border, width: 1.2),
              boxShadow:    AppShadows.subtle,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left accent rail — signature element, one colour per service
                  Container(width: 3.5, color: item.accent),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
                      child: Row(
                        children: [
                          // Rounded-square icon container
                          Container(
                            width:  44,
                            height: 44,
                            decoration: BoxDecoration(
                              color:        item.bgColor,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Center(
                              child: _ServiceIcon(
                                icon:  item.icon,
                                color: item.accent,
                              ),
                            ),
                          ),

                          const SizedBox(width: AppSpacing.sm + 1),

                          // Title only — wraps up to 2 lines, vertically centered
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily:    AppFonts.family,
                                fontSize:      13,
                                fontWeight:    FontWeight.w700,
                                color:         AppColors.textPrimary,
                                letterSpacing: -0.1,
                                height:        1.2,
                              ),
                            ),
                          ),

                          const SizedBox(width: 4),

                          // Trailing chevron
                          Icon(
                            Icons.chevron_right_rounded,
                            size:  20,
                            color: AppColors.textSecondary.withOpacity(0.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

    return Text(value, style: const TextStyle(fontSize: 21, height: 1));
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