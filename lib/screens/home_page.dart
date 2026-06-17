
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const CuraApp());

class CuraApp extends StatelessWidget {
  const CuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const HomeScreen(),
    );
  }
}

// ============================================================
// COLOR TOKENS
// ============================================================
class AppColors {
  static const bg = Color(0xFFFFFFFF);
  static const bgTint = Color(0xFFF3F7FF);

  static const primary700 = Color(0xFF1E3FA8);
  static const primary600 = Color(0xFF2A52D8);
  static const primary500 = Color(0xFF4D7CF2);
  static const primary300 = Color(0xFF9CC0FF);
  static const primary100 = Color(0xFFEAF1FF);

  static const violet700 = Color(0xFF4A33B0);
  static const violet600 = Color(0xFF6A4FE0);
  static const violet400 = Color(0xFFA593F5);
  static const violet100 = Color(0xFFF1EDFF);

  static const mint500 = Color(0xFF1FCB8E);
  static const amber500 = Color(0xFFFFB020);

  static const ink900 = Color(0xFF0E1726);
  static const ink700 = Color(0xFF384154);
  static const ink500 = Color(0xFF6B7785);
  static const ink300 = Color(0xFFA7B1BD);
  static const line = Color(0xFFE9EFF6);

  static const roseBg = Color(0xFFFFE9ED);
  static const roseIcon = Color(0xFFE04766);
  static const skyBg = Color(0xFFE6F7FF);
  static const skyIcon = Color(0xFF0FA3D9);
  static const amberBg = Color(0xFFFFF3DD);
  static const amberIcon = Color(0xFFD98A00);
  static const violetBg = Color(0xFFF1EDFF);
  static const mintBg = Color(0xFFE4FAF1);
  static const mintIcon = Color(0xFF11A06B);
}

TextStyle display({double size = 16, FontWeight w = FontWeight.w700, Color c = AppColors.ink900}) =>
    GoogleFonts.outfit(fontSize: size, fontWeight: w, color: c, letterSpacing: -0.2);

TextStyle body({double size = 13, FontWeight w = FontWeight.w500, Color c = AppColors.ink700}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c);

// ============================================================
// HOME SCREEN
// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFilter = 0;
  final _filters = const ['Category', 'Speciality', 'Condition'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _buildHeader(),
              const SizedBox(height: 22),
              const SearchBar(),
              const SizedBox(height: 22),
              const BookAppointmentCard(),
              const SizedBox(height: 14),
              const AskQuestionCard(),
              const SizedBox(height: 26),
              _buildFilterChips(),
              const SizedBox(height: 26),
              const SectionHeader(title: 'Specialists'),
              const SizedBox(height: 14),
              const SpecialistsCarousel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary600, Color(0xFF5AA7FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary600.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.show_chart, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hello, Satish 👋', style: display(size: 18)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.primary500),
                  const SizedBox(width: 4),
                  Text('Bandra West, Mumbai', style: body(size: 12.5, c: AppColors.ink500)),
                ],
              ),
            ],
          ),
        ),
        _IconButtonCircle(
          icon: Icons.notifications_outlined,
          showDot: true,
          onTap: () {},
        ),
        const SizedBox(width: 12),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.violet600, Color(0xFF9C6BFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.violet600.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text('S', style: display(size: 15, c: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Row(
      children: List.generate(_filters.length, (i) {
        final selected = _selectedFilter == i;
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _FilterChip(
            label: _filters[i],
            selected: selected,
            onTap: () => setState(() => _selectedFilter = i),
          ),
        );
      }),
    );
  }
}

// ============================================================
// REUSABLE: circular icon button with notification dot
// ============================================================
class _IconButtonCircle extends StatelessWidget {
  final IconData icon;
  final bool showDot;
  final VoidCallback onTap;

  const _IconButtonCircle({required this.icon, required this.onTap, this.showDot = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgTint,
      shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            children: [
              Center(child: Icon(icon, size: 19, color: AppColors.ink700)),
              if (showDot)
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF6A88),
                      border: Border.all(color: AppColors.bg, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SEARCH BAR
// ============================================================
class SearchBar extends StatelessWidget {
  const SearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.bgTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.search, size: 17, color: AppColors.primary600),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              style: body(size: 13.5, w: FontWeight.w500, c: AppColors.ink900),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search doctors, specialties, conditions',
                hintStyle: body(size: 13, w: FontWeight.w500, c: AppColors.ink300),
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary600, Color(0xFF5AA7FF)],
              ),
              boxShadow: [
                BoxShadow(color: AppColors.primary600.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.tune, size: 15, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BOOK APPOINTMENT CARD
// ============================================================
class BookAppointmentCard extends StatefulWidget {
  const BookAppointmentCard({super.key});

  @override
  State<BookAppointmentCard> createState() => _BookAppointmentCardState();
}

class _BookAppointmentCardState extends State<BookAppointmentCard> {
  bool isExpanded = false;

  final List<String> options = [
    "General",
    "Dental",
    "Cardiology",
    "Neurology",
    "Pediatrics",
    "Dermatology",
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F9D58),
                Color(0xFF34A853),
                Color(0xFF7ED957),
              ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Book Appointment",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              IconButton(
                onPressed: () {
                  setState(() {
                    isExpanded = !isExpanded;
                  });
                },
                icon: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ],
          ),
        ),

        AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: options.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // 2 cards per row
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.5,
              ),
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.green.shade200,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    options[index],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }


  Widget _glowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _PulseLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final midY = size.height * 0.55;
    final path = Path()
      ..moveTo(0, midY)
      ..lineTo(w * 0.16, midY)
      ..lineTo(w * 0.21, midY - 18)
      ..lineTo(w * 0.26, midY + 18)
      ..lineTo(w * 0.30, midY)
      ..lineTo(w * 0.34, midY)
      ..lineTo(w * 0.47, midY)
      ..lineTo(w * 0.52, midY - 16)
      ..lineTo(w * 0.56, midY + 16)
      ..lineTo(w * 0.60, midY)
      ..lineTo(w * 0.64, midY)
      ..lineTo(w * 0.78, midY)
      ..lineTo(w * 0.82, midY - 18)
      ..lineTo(w * 0.87, midY + 16)
      ..lineTo(w * 0.91, midY)
      ..lineTo(w, midY);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Small pulsing "available now" dot.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Container(
                  width: 6 + t * 14,
                  height: 6 + t * 14,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.mint500.withOpacity(0.55)),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.mint500),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// ASK A QUESTION CARD
// ============================================================
class AskQuestionCard extends StatelessWidget {
  const AskQuestionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF4A33B0), Color(0xFF6A4FE0), Color(0xFF9C8CFF)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF4A33B0).withOpacity(0.28), blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.16),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ask a Question', style: display(size: 16, c: Colors.white)),
                const SizedBox(height: 2),
                Text('Get answers from experts',
                    style: body(size: 12, w: FontWeight.w500, c: Colors.white.withOpacity(0.82))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.28)),
                  ),
                  child: Text('Avg. reply in 10 mins', style: body(size: 10.5, w: FontWeight.w600, c: Colors.white)),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {},
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_forward, size: 15, color: AppColors.violet700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FILTER CHIP
// ============================================================
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? null : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Colors.transparent : AppColors.line),
            gradient: selected
                ? const LinearGradient(colors: [AppColors.primary600, Color(0xFF5AA7FF)])
                : null,
            boxShadow: [
              BoxShadow(
                color: selected ? AppColors.primary600.withOpacity(0.28) : Colors.black.withOpacity(0.04),
                blurRadius: selected ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: body(size: 12.5, w: FontWeight.w600, c: selected ? Colors.white : AppColors.ink700)),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: selected ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.keyboard_arrow_down, size: 14, color: selected ? Colors.white : AppColors.ink700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SECTION HEADER ("Specialists" / see all)
// ============================================================
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const SectionHeader({super.key, required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: display(size: 16.5)),
        InkWell(
          onTap: onSeeAll,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('See all', style: body(size: 12, w: FontWeight.w600, c: AppColors.primary600)),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward, size: 11, color: AppColors.primary600),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SPECIALISTS CAROUSEL
// ============================================================
class _Specialist {
  final String label;
  final String iconType;
  final Color bg;
  final Color iconColor;

  const _Specialist(this.label, this.iconType, this.bg, this.iconColor);
}

class SpecialistsCarousel extends StatelessWidget {
  const SpecialistsCarousel({super.key});

  static const _items = [
    _Specialist('Cardiology', 'heart', AppColors.roseBg, AppColors.roseIcon),
    _Specialist('Dental', 'tooth', AppColors.skyBg, AppColors.skyIcon),
    _Specialist('Skin', 'drop', AppColors.amberBg, AppColors.amberIcon),
    _Specialist('Eye', 'eye', AppColors.violetBg, AppColors.violet600),
    _Specialist('General\nPhysician', 'stethoscope', AppColors.mintBg, AppColors.mintIcon),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final item = _items[i];
          return SizedBox(
            width: 74,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.bg,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 14, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _SpecialistIconPainter(type: item.iconType, color: item.iconColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: body(size: 11.5, w: FontWeight.w600, c: AppColors.ink700).copyWith(height: 1.15),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SpecialistIconPainter extends CustomPainter {
  final String type;
  final Color color;

  _SpecialistIconPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final dx = (size.width - s) / 2;
    final dy = (size.height - s) / 2;
    canvas.translate(dx, dy);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    switch (type) {
      case 'heart':
        final p = Path()
          ..moveTo(s * 0.08, s * 0.5)
          ..lineTo(s * 0.28, s * 0.5)
          ..lineTo(s * 0.36, s * 0.25)
          ..lineTo(s * 0.50, s * 0.82)
          ..lineTo(s * 0.62, s * 0.40)
          ..lineTo(s * 0.70, s * 0.5)
          ..lineTo(s * 0.92, s * 0.5);
        canvas.drawPath(p, stroke);
        break;

      case 'tooth':
        final p = Path()
          ..moveTo(s * 0.5, s * 0.10)
          ..quadraticBezierTo(s * 0.84, s * 0.10, s * 0.80, s * 0.42)
          ..quadraticBezierTo(s * 0.78, s * 0.55, s * 0.66, s * 0.58)
          ..quadraticBezierTo(s * 0.60, s * 0.60, s * 0.57, s * 0.78)
          ..quadraticBezierTo(s * 0.54, s * 0.90, s * 0.50, s * 0.90)
          ..quadraticBezierTo(s * 0.46, s * 0.90, s * 0.43, s * 0.78)
          ..quadraticBezierTo(s * 0.40, s * 0.60, s * 0.34, s * 0.58)
          ..quadraticBezierTo(s * 0.22, s * 0.55, s * 0.20, s * 0.42)
          ..quadraticBezierTo(s * 0.16, s * 0.10, s * 0.5, s * 0.10)
          ..close();
        canvas.drawPath(p, stroke);
        break;

      case 'drop':
        final p = Path()
          ..moveTo(s * 0.5, s * 0.08)
          ..cubicTo(s * 0.78, s * 0.42, s * 0.85, s * 0.62, s * 0.85, s * 0.70)
          ..cubicTo(s * 0.85, s * 0.86, s * 0.70, s * 0.95, s * 0.5, s * 0.95)
          ..cubicTo(s * 0.30, s * 0.95, s * 0.15, s * 0.86, s * 0.15, s * 0.70)
          ..cubicTo(s * 0.15, s * 0.62, s * 0.22, s * 0.42, s * 0.5, s * 0.08)
          ..close();
        canvas.drawPath(p, stroke);
        break;

      case 'eye':
        final p = Path()
          ..moveTo(s * 0.06, s * 0.5)
          ..quadraticBezierTo(s * 0.5, s * 0.14, s * 0.94, s * 0.5)
          ..quadraticBezierTo(s * 0.5, s * 0.86, s * 0.06, s * 0.5)
          ..close();
        canvas.drawPath(p, stroke);
        canvas.drawCircle(Offset(s * 0.5, s * 0.5), s * 0.12, stroke);
        break;

      case 'stethoscope':
        final tube = Path()
          ..moveTo(s * 0.32, s * 0.10)
          ..lineTo(s * 0.32, s * 0.38)
          ..cubicTo(s * 0.32, s * 0.56, s * 0.42, s * 0.60, s * 0.50, s * 0.60)
          ..cubicTo(s * 0.58, s * 0.60, s * 0.68, s * 0.56, s * 0.68, s * 0.38)
          ..lineTo(s * 0.68, s * 0.10);
        canvas.drawPath(tube, stroke);
        canvas.drawLine(Offset(s * 0.5, s * 0.60), Offset(s * 0.5, s * 0.72), stroke);
        canvas.drawCircle(Offset(s * 0.5, s * 0.82), s * 0.10, stroke);
        canvas.drawCircle(Offset(s * 0.32, s * 0.09), s * 0.045, fill);
        canvas.drawCircle(Offset(s * 0.68, s * 0.09), s * 0.045, fill);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SpecialistIconPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.color != color;
}