import 'package:flutter/material.dart';



// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Teleconsultation',
//       theme: ThemeData(
//         primarySwatch: Colors.teal,
//         scaffoldBackgroundColor: const Color(0xFFF6F8FB),
//       ),
//       home: const HomePage(),
//     );
//   }
// }

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Hello, Sarah 👋",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "How are you feeling today?",
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(
                      "https://i.pravatar.cc/150",
                    ),
                  )
                ],
              ),

              const SizedBox(height: 25),

              /// Search Bar
              TextField(
                decoration: InputDecoration(
                  hintText: "Search doctors, specialties...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              /// Upcoming Appointment Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.teal,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.person,
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Dr. Michael Smith",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            "Cardiologist",
                            style: TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Today • 10:30 AM",
                            style: TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.video_call,
                      color: Colors.white,
                      size: 30,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              /// Quick Actions
              const Text(
                "Quick Actions",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  actionCard(
                    Icons.video_call,
                    "Video Call",
                    Colors.blue,
                  ),
                  actionCard(
                    Icons.chat,
                    "Chat",
                    Colors.orange,
                  ),
                  actionCard(
                    Icons.medical_services,
                    "Prescription",
                    Colors.green,
                  ),
                  actionCard(
                    Icons.local_hospital,
                    "Emergency",
                    Colors.red,
                  ),
                ],
              ),

              const SizedBox(height: 30),

              /// Specialties
              const Text(
                "Specialties",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    specialtyChip("Cardiology"),
                    specialtyChip("Dermatology"),
                    specialtyChip("Neurology"),
                    specialtyChip("Pediatrics"),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              /// Top Doctors
              const Text(
                "Top Doctors",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              doctorCard(
                "Dr. Emma Wilson",
                "Dermatologist",
                "4.9",
              ),

              doctorCard(
                "Dr. John Carter",
                "Neurologist",
                "4.8",
              ),

              doctorCard(
                "Dr. Olivia Brown",
                "Pediatrician",
                "4.9",
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget actionCard(
      IconData icon,
      String title,
      Color color,
      ) {
    return Container(
      width: 75,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  static Widget specialtyChip(String title) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(title),
    );
  }

  static Widget doctorCard(
      String name,
      String specialty,
      String rating,
      ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          radius: 25,
          child: Icon(Icons.person),
        ),
        title: Text(name),
        subtitle: Text(specialty),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.star,
              color: Colors.amber,
              size: 18,
            ),
            Text(rating),
          ],
        ),
      ),
    );
  }
}