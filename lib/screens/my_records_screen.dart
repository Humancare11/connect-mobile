import 'package:flutter/material.dart';

class MyRecordsPage extends StatefulWidget {
  const MyRecordsPage({super.key});

  @override
  State<MyRecordsPage> createState() => _MyRecordsPageState();
}

class _MyRecordsPageState extends State<MyRecordsPage> {
  String activeTab = "prescriptions";
  String? expandedId;
  bool loading = false;

  final prescriptions = [
    {
      "_id": "rx1",
      "diagnosis": "Fever and Cold",
      "doctorName": "Dr. Amit Sharma",
      "createdAt": DateTime.now(),
      "appointmentDate": DateTime.now().subtract(const Duration(days: 1)),
    },
    {
      "_id": "rx2",
      "diagnosis": "Migraine Headache",
      "doctorName": "Dr. Priya Mehta",
      "createdAt": DateTime.now().subtract(const Duration(days: 4)),
      "appointmentDate": DateTime.now().subtract(const Duration(days: 5)),
    },
  ];

  final certificates = [
    {
      "_id": "cert1",
      "diagnosis": "Medical Rest Certificate",
      "doctorName": "Dr. Amit Sharma",
      "issuedDate": DateTime.now().subtract(const Duration(days: 2)),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text("My Medical Records"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _header(),
            const SizedBox(height: 16),
            _summaryCards(),
            const SizedBox(height: 16),
            _tabs(),
            const SizedBox(height: 18),

            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (activeTab == "prescriptions")
              _prescriptionList()
            else
              _certificateList(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Humancare Connect",
          style: TextStyle(
            color: Color(0xff1a3a5c),
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 6),
        Text(
          "My Medical Records",
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 6),
        Text(
          "Prescriptions and certificates from your consultations",
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _summaryCards() {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            icon: "💊",
            count: prescriptions.length,
            label: "Prescriptions",
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            icon: "📄",
            count: certificates.length,
            label: "Certificates",
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String icon,
    required int count,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$count",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _tabButton(
            keyName: "prescriptions",
            label: "💊 Prescriptions",
            count: prescriptions.length,
          ),
          _tabButton(
            keyName: "certificates",
            label: "📄 Certificates",
            count: certificates.length,
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String keyName,
    required String label,
    required int count,
  }) {
    final active = activeTab == keyName;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            activeTab = keyName;
            expandedId = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? const Color(0xff1a3a5c) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              "$label  $count",
              style: TextStyle(
                color: active ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _prescriptionList() {
    if (prescriptions.isEmpty) {
      return _empty(
        icon: "💊",
        title: "No prescriptions yet",
        msg:
            "Prescriptions from your doctors will appear here after a completed consultation.",
      );
    }

    return Column(
      children: prescriptions.map((rx) {
        return _recordCard(
          id: rx["_id"].toString(),
          icon: "💊",
          title: rx["diagnosis"].toString(),
          subtitle:
              "${rx["doctorName"]} · ${_formatDate(rx["createdAt"])} · Appt: ${_formatDate(rx["appointmentDate"])}",
          details: _prescriptionDetails(rx),
        );
      }).toList(),
    );
  }

  Widget _certificateList() {
    if (certificates.isEmpty) {
      return _empty(
        icon: "📄",
        title: "No certificates yet",
        msg: "Medical certificates issued by your doctors will appear here.",
      );
    }

    return Column(
      children: certificates.map((cert) {
        return _recordCard(
          id: cert["_id"].toString(),
          icon: "📄",
          title: cert["diagnosis"].toString(),
          subtitle:
              "${cert["doctorName"]} · Issued: ${_formatDate(cert["issuedDate"])}",
          details: _certificateDetails(cert),
        );
      }).toList(),
    );
  }

  Widget _recordCard({
    required String id,
    required String icon,
    required String title,
    required String subtitle,
    required Widget details,
  }) {
    final open = expandedId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _box(),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              setState(() {
                expandedId = open ? null : id;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("PDF download clicked")),
                      );
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text("PDF"),
                  ),
                  Icon(open
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: details,
            ),
        ],
      ),
    );
  }

  Widget _prescriptionDetails(Map<String, dynamic> rx) {
    return _slipBox(
      title: "Prescription Slip",
      children: [
        _row("Diagnosis", rx["diagnosis"]),
        _row("Doctor", rx["doctorName"]),
        _row("Date", _formatDate(rx["createdAt"])),
        const Divider(),
        const Text(
          "Medicines / Instructions will show here from API data.",
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _certificateDetails(Map<String, dynamic> cert) {
    return _slipBox(
      title: "Medical Certificate",
      children: [
        _row("Diagnosis", cert["diagnosis"]),
        _row("Doctor", cert["doctorName"]),
        _row("Issued Date", _formatDate(cert["issuedDate"])),
        const Divider(),
        const Text(
          "Certificate content will show here from API data.",
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _slipBox({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfff9fafb),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? "—",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty({
    required String icon,
    required String title,
    required String msg,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: _box(),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 46)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return "—";

    DateTime? d;
    if (date is DateTime) d = date;
    if (date is String) d = DateTime.tryParse(date);

    if (d == null) return date.toString();

    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];

    return "${d.day.toString().padLeft(2, "0")} ${months[d.month - 1]} ${d.year}";
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}