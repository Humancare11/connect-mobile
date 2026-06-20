import 'package:flutter/material.dart';

class AppointmentFormPage extends StatefulWidget {
  const AppointmentFormPage({super.key});

  @override
  State<AppointmentFormPage> createState() => _AppointmentFormPageState();
}

class _AppointmentFormPageState extends State<AppointmentFormPage> {
  DateTime? selectedDate;
  String? selectedTime;
  final notesCtrl = TextEditingController();

  final List<String> timeSlots = [
    "8:00 AM", "8:30 AM", "9:00 AM", "9:30 AM",
    "10:00 AM", "10:30 AM", "11:00 AM", "11:30 AM",
    "12:00 PM", "12:30 PM", "1:00 PM", "1:30 PM",
    "2:00 PM", "2:30 PM", "3:00 PM", "3:30 PM",
    "4:00 PM", "4:30 PM", "5:00 PM", "5:30 PM",
    "6:00 PM", "6:30 PM", "7:00 PM", "7:30 PM",
  ];

  bool telehealth = true;
  bool terms = true;
  bool hipaa = true;
  bool age = true;

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    final selection = args ??
        {
          "specName": "General Physician",
          "specIcon": "🩺",
          "catLabel": "General & Everyday Care",
          "condName": "Fever",
          "condIcon": "🌡️",
          "cost": 100,
        };

    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text("Book Appointment"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "Book an Appointment",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              "Select your preferred date and time, then proceed to payment.",
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),

            _summaryCard(selection),
            const SizedBox(height: 18),

            _progress(),

            const SizedBox(height: 18),
            _dateSection(),
            const SizedBox(height: 16),
            _timeSection(),
            const SizedBox(height: 16),
            _problemSection(),
            const SizedBox(height: 16),
            _uploadSection(),

            const SizedBox(height: 22),

            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1a3a5c),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _validateAndOpenConsent(selection),
                child: Text(
                  "Proceed to Payment — \$${selection["cost"]} →",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> selection) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Row(
        children: [
          Text(
            selection["specIcon"] ?? "🩺",
            style: const TextStyle(fontSize: 42),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selection["catLabel"] ?? "",
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selection["specName"] ?? "",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${selection["condIcon"] ?? ""} ${selection["condName"] ?? ""}",
                  style: const TextStyle(color: Colors.black87),
                ),
              ],
            ),
          ),
          Column(
            children: [
              const Text(
                "Fee",
                style: TextStyle(color: Colors.black45, fontSize: 12),
              ),
              Text(
                "\$${selection["cost"] ?? 0}",
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xff1a3a5c),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(),
      child: Row(
        children: const [
          _StepDot(text: "1", label: "Details", active: true),
          Expanded(child: Divider(thickness: 2)),
          _StepDot(text: "2", label: "Payment"),
          Expanded(child: Divider(thickness: 2)),
          _StepDot(text: "3", label: "Confirmed"),
        ],
      ),
    );
  }

  Widget _dateSection() {
    return _section(
      number: "1",
      title: "Appointment Date *",
      child: InkWell(
        onTap: _pickDate,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: _inputBox(),
          child: Text(
            selectedDate == null
                ? "Select date"
                : "${selectedDate!.day}-${selectedDate!.month}-${selectedDate!.year}",
            style: TextStyle(
              color: selectedDate == null ? Colors.black45 : Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeSection() {
    if (selectedDate == null) {
      return _section(
        number: "2",
        title: "Preferred Time Slot",
        child: const Text(
          "⚠ Select a date above to see available slots",
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
        ),
      );
    }

    return _section(
      number: "2",
      title: "Preferred Time Slot *",
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: timeSlots.map((slot) {
          final selected = selectedTime == slot;

          return ChoiceChip(
            label: Text(slot),
            selected: selected,
            onSelected: (_) {
              setState(() => selectedTime = slot);
            },
            selectedColor: const Color(0xff1a3a5c),
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.black,
              fontWeight: FontWeight.w700,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _problemSection() {
    return _section(
      number: "3",
      title: "Describe Your Problem *",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: notesCtrl,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              hintText: "Briefly describe your symptoms or reason for visit…",
              filled: true,
              fillColor: const Color(0xfff9fafb),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadSection() {
    return _section(
      number: "4",
      title: "Medical Reports",
      subtitle: "Optional — PDF, Images, Word, Excel · max 10 MB each",
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xfff9fafb),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: const Column(
          children: [
            Text("📂", style: TextStyle(fontSize: 34)),
            SizedBox(height: 8),
            Text(
              "Tap to browse files",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 4),
            Text(
              "Max 10 MB per file",
              style: TextStyle(color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String number,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: const Color(0xff1a3a5c),
                child: Text(
                  number,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  void _validateAndOpenConsent(Map<String, dynamic> selection) {
    if (selectedDate == null) {
      _snack("Please select a date.");
      return;
    }

    if (selectedTime == null) {
      _snack("Please choose a time slot.");
      return;
    }

    if (notesCtrl.text.trim().isEmpty) {
      _snack("Please describe your problem.");
      return;
    }

    _showConsentDialog(selection);
  }

  void _showConsentDialog(Map<String, dynamic> selection) {
    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allChecked = telehealth && terms && hipaa && age;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text("Patient Informed Consent"),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    const Text(
                      "By booking this appointment, you consent to receive telehealth services from licensed physicians through Humancare Connect.",
                    ),
                    const SizedBox(height: 12),
                    _checkRow("I agree to Telehealth Informed Consent",
                        telehealth, (v) {
                      setModalState(() => telehealth = v!);
                    }),
                    _checkRow("I agree to Terms & Privacy Policy", terms, (v) {
                      setModalState(() => terms = v!);
                    }),
                    _checkRow("I have read HIPAA Notice", hipaa, (v) {
                      setModalState(() => hipaa = v!);
                    }),
                    _checkRow("I am 18 years of age or older", age, (v) {
                      setModalState(() => age = v!);
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: allChecked
                      ? () {
                          Navigator.pop(context);

                          Navigator.pushNamed(
                            context,
                            "/appointment-payment",
                            arguments: {
                              ...selection,
                              "date": selectedDate.toString(),
                              "time": selectedTime,
                              "problem": notesCtrl.text.trim(),
                            },
                          );
                        }
                      : null,
                  child: const Text("Confirm & Continue →"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _checkRow(String title, bool value, Function(bool?) onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  void _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        selectedTime = null;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
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

  BoxDecoration _inputBox() {
    return BoxDecoration(
      color: const Color(0xfff9fafb),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.black12),
    );
  }
}

class _StepDot extends StatelessWidget {
  final String text;
  final String label;
  final bool active;

  const _StepDot({
    required this.text,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: active ? const Color(0xff1a3a5c) : Colors.black12,
          child: Text(
            text,
            style: TextStyle(
              color: active ? Colors.white : Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}