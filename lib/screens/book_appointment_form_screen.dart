import 'package:flutter/material.dart';

import '../utils/direct_upload.dart';

class AppointmentFormPage extends StatefulWidget {
  const AppointmentFormPage({super.key});

  @override
  State<AppointmentFormPage> createState() => _AppointmentFormPageState();
}

class _AppointmentFormPageState extends State<AppointmentFormPage> {
  DateTime? selectedDate;
  String? selectedTime;
  final notesCtrl = TextEditingController();

  final List<UploadCandidate> _files = [];
  bool _uploading = false;
  String? _uploadError;

  // Generated the same way as the web version: all 48 half-hour slots
  // across the full 24-hour day (12:00 AM -> 11:30 PM), not just business
  // hours.
  late final List<String> timeSlots = _generateTimeSlots();

  List<String> _generateTimeSlots() {
    final List<String> slots = [];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        final period = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        final ampm = hour < 12 ? "AM" : "PM";
        final minuteStr = minute.toString().padLeft(2, "0");
        slots.add("$period:$minuteStr $ampm");
      }
    }
    return slots;
  }

  // Consent checkboxes are no longer pre-checked by default — they are
  // force-reset to false every time the modal is opened (see
  // _validateAndOpenConsent), mirroring the updated web behavior where
  // users must explicitly re-affirm consent on every booking attempt.
  bool telehealth = false;
  bool terms = false;
  bool hipaa = false;
  bool age = false;

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    final selection = args ??
        {
          "specName": "",
          "specIcon": "",
          "catLabel": "",
          "condName": "",
          "condIcon": "",
          "cost": 0,
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
                onPressed: _uploading
                    ? null
                    : () => _validateAndOpenConsent(selection),
                child: _uploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "Preparing…",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      )
                    : Text(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _uploading ? null : _pickFiles,
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
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._files.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xfff9fafb),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    children: [
                      const Text("📄", style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.value.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              "${(entry.value.sizeBytes / 1048576).toStringAsFixed(1)} MB",
                              style: const TextStyle(
                                color: Colors.black45,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _uploading
                            ? null
                            : () => _removeFile(entry.key),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (_uploadError != null) ...[
            const SizedBox(height: 8),
            Text(
              _uploadError!,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    setState(() => _uploadError = null);
    try {
      final picked = await pickFilesForUpload();
      if (picked.isEmpty) return;

      // Both skip conditions below used to fail silently — a file over the
      // limit (or sharing a name with one already added) just never
      // appeared in the list, with nothing telling the user why their tap
      // "did nothing". Collect what got skipped and surface it the same
      // way the file-picker-open failure already does, via _uploadError.
      final skippedOversized = <String>[];
      final skippedDuplicate = <String>[];
      setState(() {
        for (final candidate in picked) {
          if (candidate.sizeBytes > 10 * 1024 * 1024) {
            skippedOversized.add(candidate.name);
            continue;
          }
          if (_files.any((f) => f.name == candidate.name)) {
            skippedDuplicate.add(candidate.name);
            continue;
          }
          _files.add(candidate);
        }
        if (skippedOversized.isNotEmpty || skippedDuplicate.isNotEmpty) {
          final parts = <String>[
            if (skippedOversized.isNotEmpty)
              '${skippedOversized.join(', ')} '
                  '${skippedOversized.length == 1 ? 'is' : 'are'} over the 10 MB limit',
            if (skippedDuplicate.isNotEmpty)
              '${skippedDuplicate.join(', ')} '
                  '${skippedDuplicate.length == 1 ? 'was' : 'were'} already added',
          ];
          _uploadError = '${parts.join('; ')}.';
        }
      });
    } catch (_) {
      setState(() => _uploadError = "Could not open the file picker.");
    }
  }

  void _removeFile(int index) => setState(() => _files.removeAt(index));

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

    // A missing/zero price here means the category, specialty, or condition
    // the user picked has no resolvable price from the backend. Block
    // before payment with an actionable message instead of letting an
    // invalid $0 charge reach Stripe/the backend, where it comes back as an
    // opaque "could not determine price" failure.
    if (_parsedCost(selection["cost"]) == null) {
      _snack(
        "We couldn't determine a valid price for this selection. Please go back and choose again.",
      );
      return;
    }

    // Force all consent checkboxes back to unchecked every time the modal
    // is opened — no pre-checked boxes, matching the updated web behavior.
    setState(() {
      telehealth = false;
      terms = false;
      hipaa = false;
      age = false;
    });

    _showConsentDialog(selection);
  }

  Future<void> _uploadAndProceed(Map<String, dynamic> selection) async {
    setState(() {
      _uploading = true;
      _uploadError = null;
    });

    try {
      final medicalReports = <Map<String, dynamic>>[];
      for (final candidate in _files) {
        final uploaded = await uploadFileDirectToS3(candidate);
        medicalReports.add({
          "key": uploaded.key,
          "name": uploaded.name,
          "type": uploaded.type,
          "size": uploaded.sizeBytes,
        });
      }

      if (!mounted) return;

      Navigator.pushNamed(
        context,
        "/appointment-payment",
        arguments: {
          ...selection,
          "date": selectedDate.toString(),
          "time": selectedTime,
          "problem": notesCtrl.text.trim(),
          "medicalReports": medicalReports,
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploadError = "Failed to upload reports. Please try again.";
      });
      _snack("Failed to upload reports. Please try again.");
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
                          _uploadAndProceed(selection);
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

  // Returns the numeric cost only if it's a real, positive price — null for
  // missing, unparseable, or zero/negative values, all of which mean the
  // selection has no valid price to charge.
  num? _parsedCost(Object? value) {
    final parsed = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
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