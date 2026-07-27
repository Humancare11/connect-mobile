// Section 6 — MedicalServicesSection
//
// Two-column grid of service tiles, stacked (icon above text) rather than the
// side-by-side row used by the specialty strip, so the two sections stay
// visually distinct while sharing the same card treatment.
//
// Services are fetched from GET /api/services at runtime instead of being
// hardcoded.

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
  State<MedicalServicesSection> createState() => _MedicalServicesSectionState();
}

class _MedicalServicesSectionState extends State<MedicalServicesSection> {
  final _servicesService = ServicesService();

  bool _loading = true;
  String? _error;
  List<_MedService> _services = const [];

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
      // Same paired accent/tint cycling as the specialty strip — the backend
      // does not send colors, so position decides the hue.
      final index = items.length % AppColors.accentInks.length;
      items.add(
        _MedService(
          id: service.id,
          icon: service.icon,
          title: service.name,
          subtitle: service.description,
          price: service.price,
          accent: AppColors.accentInks[index],
          bgColor: AppColors.accentTints[index],
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
        AppSectionHeader(
          title: 'Medical services',
          seeAllLabel: 'View all',
          onSeeAll: () {},
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
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return _MessageState(
        message: _error!.isEmpty ? 'Unable to load medical services.' : _error!,
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

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: services.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        // A fixed pixel height, not childAspectRatio: the ratio derives height
        // from the column width, so on a narrower phone the tile got shorter
        // exactly when the wrapping description needed it to be taller, and
        // the content overflowed. This height covers padding(14×2) +
        // icon(44) + title + a two-line description plus breathing room, and
        // scales with the user's text size so large-font settings do not clip.
        mainAxisExtent: 148 * _textScale(context),
      ),
      itemBuilder: (context, index) => _ServiceTile(item: services[index]),
    );
  }

  /// Clamped so an extreme accessibility text size grows the tile enough to
  /// stay readable without pushing a two-column grid to absurd heights.
  double _textScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
}

// ── Service tile ──────────────────────────────────────────────────────────────

class _ServiceTile extends StatelessWidget {
  final _MedService item;

  const _ServiceTile({required this.item});

  bool get _hasDistinctSubtitle {
    final subtitle = _normalizeSearchText(item.subtitle);
    return subtitle.isNotEmpty &&
        subtitle != _normalizeSearchText(item.title);
  }

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
    return AppCard(
      onTap: () => _openBookingForm(context),
      radius: AppRadius.field,
      padding: const EdgeInsets.all(14),
      bordered: false,
      splashColor: item.accent.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.bgColor,
              borderRadius: BorderRadius.circular(AppRadius.md - 2),
            ),
            alignment: Alignment.center,
            child: _ServiceIcon(
              icon: item.icon,
              name: item.title,
              color: item.accent,
            ),
          ),

          // Text block sits against the bottom edge with the icon pinned to
          // the top, so tiles line up along both edges regardless of whether a
          // description runs to one line or two.
          const Spacer(),

          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.display(size: 14, letterSpacing: -0.1, height: 1.25),
          ),

          // Several services come back with `description` set to the same
          // string as `name`, which rendered the title twice in two different
          // colours. Show the description only when it actually adds something.
          if (_hasDistinctSubtitle) ...[
            const SizedBox(height: 3),
            Flexible(
              child: Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                // Accent rather than neutral grey — it is what ties the copy
                // back to the icon above it.
                style: AppType.body(
                  size: 12,
                  weight: FontWeight.w500,
                  color: item.accent,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// The backend's `icon` field is only sometimes a real glyph — in practice it
// often holds a stray letter, which rendered as a bare "t" or "F" sitting in
// the tile. So a value is only drawn as text when it actually contains a
// pictographic rune; anything else falls back to a line icon derived from the
// service name, which is both meaningful and consistent with the rest of the
// page.
class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({
    required this.icon,
    required this.name,
    required this.color,
  });

  final String icon;
  final String name;
  final Color color;

  /// True for emoji and misc-symbol ranges, false for ASCII letters/digits.
  static bool _isGlyph(String value) =>
      value.runes.any((rune) => rune > 0x2100);

  static IconData _iconForName(String name) {
    final value = name.toLowerCase();

    // Ordered most specific first — "general consultation" must not be caught
    // by a broader "care" rule.
    const rules = <List<String>, IconData>{
      ['fly', 'travel', 'flight']: Icons.flight_takeoff_rounded,
      ['note', 'record', 'report', 'summary']: Icons.description_outlined,
      ['consult', 'talk', 'chat', 'advice']: Icons.chat_bubble_outline_rounded,
      ['prescription', 'medicine', 'medication']: Icons.medication_outlined,
      ['test', 'lab', 'screen', 'diagnos']: Icons.biotech_outlined,
      ['mental', 'therapy', 'counsel']: Icons.psychology_outlined,
      ['vaccin', 'immun']: Icons.vaccines_outlined,
      ['chronic', 'ongoing', 'follow']: Icons.autorenew_rounded,
      ['care', 'health', 'wellness']: Icons.favorite_border_rounded,
    };

    for (final entry in rules.entries) {
      if (entry.key.any(value.contains)) return entry.value;
    }
    return Icons.medical_services_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final value = icon.trim();
    if (value.isNotEmpty && _isGlyph(value)) {
      return Text(value, style: const TextStyle(fontSize: 20, height: 1));
    }

    return Icon(_iconForName(name), size: 21, color: color);
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
