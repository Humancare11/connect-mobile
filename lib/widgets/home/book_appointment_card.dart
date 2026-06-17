import 'package:flutter/material.dart';

class BookAppointmentCard extends StatefulWidget {
  const BookAppointmentCard({super.key});

  @override
  State<BookAppointmentCard> createState() =>
      _BookAppointmentCardState();
}

class _BookAppointmentCardState
    extends State<BookAppointmentCard> {
  bool expanded = false;

  final List<Map<String, dynamic>> categories = [
    {
      "icon": Icons.favorite_border,
      "title": "Heart & Vascular"
    },
    {
      "icon": Icons.psychology_outlined,
      "title": "Brain & Nerves"
    },
    {
      "icon": Icons.self_improvement,
      "title": "Mental Wellness"
    },
    {
      "icon": Icons.child_friendly_outlined,
      "title": "Child Health"
    },
    {
      "icon": Icons.accessibility_new,
      "title": "Bones & Joints"
    },
    {
      "icon": Icons.air,
      "title": "Respiratory"
    },
    {
      "icon": Icons.female,
      "title": "Women's Health"
    },
    {
      "icon": Icons.science_outlined,
      "title": "Genetics & Labs"
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xff244A7A),
            Color(0xff0C8F8B),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          /// badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.18),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 3,
                  backgroundColor: Color(0xff59F68B),
                ),
                SizedBox(width: 8),
                Text(
                  "Available 24/7 • HIPAA Compliant",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              const Expanded(
                child: Text(
                  "Book an Appointment",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              IconButton(
                onPressed: () {
                  setState(() {
                    expanded = !expanded;
                  });
                },
               icon: AnimatedRotation(
  turns: expanded ? 0.5 : 0,
  duration: const Duration(milliseconds: 250),
  child: const Icon(
    Icons.keyboard_arrow_down,
    color: Colors.white,
  ),
),
              )
            ],
          ),

          const SizedBox(height: 4),

          const Text(
            "Choose a category to get started",
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
AnimatedSwitcher(
  duration: const Duration(milliseconds: 250),
  transitionBuilder: (child, animation) {
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  },
  child: expanded
      ? Padding(
          key: const ValueKey("expanded"),
          padding: const EdgeInsets.only(top: 18),
          child: Column(
  children: [

    GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3.4,
      ),
      itemBuilder: (context, index) {
        final item = categories[index];

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              Icon(
                item["icon"],
                color: Colors.white,
                size: 17,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item["title"],
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),

    const SizedBox(height: 18),

    const Center(
      child: Text(
        "View all categories →",
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  ],
),
        )
      : const SizedBox(
          key: ValueKey("collapsed"),
        ),
),
        ],
      ),
    );
  }
}