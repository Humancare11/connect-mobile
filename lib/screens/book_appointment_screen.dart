import 'package:flutter/material.dart';
import 'book_appointment_form_screen.dart';
class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() =>
      _BookAppointmentScreenState();
}

class _BookAppointmentScreenState
    extends State<BookAppointmentScreen> {
  int selectedTab = 0;
String? selectedCategory;
String? selectedSpecialty;
  final TextEditingController searchController =
      TextEditingController();
final List<Map<String, dynamic>> categories = [
  {
    "title": "General & Everyday Care",
    "icon": "🩺",
    "specialties": [
      {
        "title": "General Physician",
        "icon": "👨‍⚕️",
        "conditions": [
          "Fever",
          "Cold & Flu",
          "Headache",
        ]
      },
      {
        "title": "Internal Medicine",
        "icon": "🏥",
        "conditions": [
          "Diabetes",
          "Blood Pressure",
        ]
      }
    ]
  },
  {
    "title": "Mental Health",
    "icon": "🧠",
    "specialties": [
      {
        "title": "Psychiatrist",
        "icon": "🧠",
        "conditions": [
          "Depression",
          "Anxiety",
          "Stress",
        ]
      }
    ]
  }
];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF7F9FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          "Book Appointment",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),

      body: SafeArea(
        child: Column(
          children: [

            /// Hero Section
            _buildHeroSection(),

            /// Search
            _buildSearchBar(),

            /// Tabs
            _buildTabs(),

            /// Content
            Expanded(
              child: Builder(
                builder: (context) {
                  switch (selectedTab) {
                    case 0:
                      return _buildCategories();

                    case 1:
                      return _buildSpecialties();

                    case 2:
                      return _buildConditions();

                    default:
                      return const SizedBox();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  //==========================
  // Hero
  //==========================

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: const Column(
        children: [
          Text(
            "Find the right online\ndoctor for your needs.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              height: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          Text(
            "Book an online doctor appointment\nin minutes.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  //==========================
  // Search
  //==========================

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: searchController,
    onChanged: (_) {
      setState(() {});
    },
        decoration: InputDecoration(
          hintText: "Search...",
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  //==========================
  // Tabs
  //==========================

Widget _buildTabs() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Expanded(
          child: _tabButton(
            "Categories",
            0,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tabButton(
            "Specialties",
            1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tabButton(
            "Conditions",
            2,
          ),
        ),
      ],
    ),
  );
}

  Widget _tabButton(
    String title,
    int index,
  ) {
    final selected = selectedTab == index;

    return GestureDetector(
  onTap: () {
    setState(() {
      selectedTab = index;

      if (index == 0) {
  selectedCategory = null;
  selectedSpecialty = null;
}

if (index == 1) {
  selectedCategory = null;
  selectedSpecialty = null;
}

if (index == 2) {
  selectedSpecialty = null;
}
    });
  },
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: selected ? Colors.blue : Colors.white,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Center(
      child: Text(
        title,
        style: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  ),
);

  }

  Widget _buildEmptyState(String message) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.search_off,
          size: 60,
          color: Colors.grey,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "Try a different search keyword.",
          style: TextStyle(color: Colors.grey),
        ),
      ],
    ),
  );
}

  //==========================
  // Categories
  //==========================

Widget _buildCategories() {
  // STEP 1 - Show Categories
  if (selectedCategory == null) {
    if (filteredCategories.isEmpty) {
      return _buildEmptyState("No categories found");
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredCategories.length,
      itemBuilder: (context, index) {
        final item = filteredCategories[index];

        return Card(
          child: ListTile(
            leading: Text(item["icon"]!,
                style: const TextStyle(fontSize: 28)),
            title: Text(item["title"]!),
            trailing: const Icon(Icons.arrow_forward_ios),
onTap: () {
  setState(() {
    selectedCategory = item["title"] as String;
    selectedTab = 1;
  });
},
          ),
        );
      },
    );
  }

  // STEP 2 - Show Specialties of selected category
final category = categories.firstWhere(
  (e) => e["title"] == selectedCategory,
);

final List specialties =
    category["specialties"] as List;

return ListView.builder(
  padding: const EdgeInsets.all(16),
  itemCount: specialties.length,
  itemBuilder: (context, index) {
    final item =
        specialties[index] as Map<String, dynamic>;

    return Card(
      child: ListTile(
        leading: Text(
          item["icon"],
          style: const TextStyle(fontSize: 28),
        ),
        title: Text(item["title"]),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          setState(() {
            selectedSpecialty = item["title"];
            selectedTab = 2;
          });
        },
      ),
    );
  },
);

}
  //==========================
  // Specialties
  //==========================
Widget _buildSpecialties() {
  List<Map<String, dynamic>> specialties = [];

  if (selectedCategory == null) {
    // Show ALL specialties
    for (var category in categories) {
      specialties.addAll(
        (category["specialties"] as List)
            .cast<Map<String, dynamic>>(),
      );
    }
  } else {
    // Show selected category specialties
    final category = categories.firstWhere(
      (e) => e["title"] == selectedCategory,
    );

    specialties = (category["specialties"] as List)
        .cast<Map<String, dynamic>>();
  }

  // Search
  specialties = specialties.where((item) {
    return (item["title"] as String)
        .toLowerCase()
        .contains(searchController.text.toLowerCase());
  }).toList();

  if (specialties.isEmpty) {
    return _buildEmptyState("No specialties found");
  }

  return ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: specialties.length,
    itemBuilder: (context, index) {
      final item = specialties[index];

      return Card(
        child: ListTile(
          leading: Text(
            item["icon"],
            style: const TextStyle(fontSize: 28),
          ),
          title: Text(item["title"]),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            setState(() {
              selectedSpecialty = item["title"];
              selectedTab = 2;
            });
          },
        ),
      );
    },
  );
}
  //==========================
  // Conditions
  //==========================

Widget _buildConditions() {
  List<String> conditions = [];

  if (selectedSpecialty == null) {
    // Show ALL conditions
    for (var category in categories) {
      final specialties =
          category["specialties"] as List;

      for (var specialty in specialties) {
        conditions.addAll(
          (specialty["conditions"] as List)
              .cast<String>(),
        );
      }
    }
  } else {
    // Show selected specialty conditions
    for (var category in categories) {
      final specialties =
          category["specialties"] as List;

      for (var specialty in specialties) {
        if (specialty["title"] ==
            selectedSpecialty) {
          conditions = (specialty["conditions"]
                  as List)
              .cast<String>();
        }
      }
    }
  }

  // Search
  conditions = conditions.where((condition) {
    return condition
        .toLowerCase()
        .contains(searchController.text.toLowerCase());
  }).toList();

  if (conditions.isEmpty) {
    return _buildEmptyState("No conditions found");
  }

  return ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: conditions.length,
    itemBuilder: (context, index) {
      final condition = conditions[index];

      return Card(
        child: ListTile(
          title: Text(condition),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const BookAppointmentFormScreen(),
              ),
            );
          },
        ),
      );
    },
  );
}
List<Map<String, dynamic>> get filteredCategories {
  return categories.where((item) {
    return (item["title"] as String)
        .toLowerCase()
        .contains(searchController.text.toLowerCase());
  }).toList();
}

@override
void dispose() {
  searchController.dispose();
  super.dispose();
}
}