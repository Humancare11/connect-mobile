import 'package:flutter/material.dart';

class RaiseTicketPage extends StatefulWidget {
  const RaiseTicketPage({super.key});

  @override
  State<RaiseTicketPage> createState() => _RaiseTicketPageState();
}

class _RaiseTicketPageState extends State<RaiseTicketPage> {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();

  String category = "other";
  String filter = "all";
  String? expandedId;
  bool loading = false;

  final categories = const [
    {"value": "appointment", "label": "Appointment Issue"},
    {"value": "billing", "label": "Billing / Payment"},
    {"value": "technical", "label": "Technical Problem"},
    {"value": "medical", "label": "Medical Query"},
    {"value": "other", "label": "Other"},
  ];

  final List<Map<String, dynamic>> tickets = [
    {
      "_id": "1",
      "title": "Unable to join video call",
      "description": "Doctor video call link is not opening.",
      "category": "technical",
      "status": "open",
      "createdAt": DateTime.now(),
    },
    {
      "_id": "2",
      "title": "Payment deducted twice",
      "description": "Amount deducted two times during appointment booking.",
      "category": "billing",
      "status": "resolved",
      "resolution": "Refund has been processed successfully.",
      "createdAt": DateTime.now().subtract(const Duration(days: 2)),
    },
  ];

  @override
  Widget build(BuildContext context) {
    final displayed = filter == "all"
        ? tickets
        : tickets.where((t) => t["status"] == filter).toList();

    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text("Help & Support"),
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
            _newTicketForm(),
            const SizedBox(height: 18),
            _ticketList(displayed),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Support", style: TextStyle(color: Colors.blue)),
              SizedBox(height: 4),
              Text(
                "Help & Support",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4),
              Text(
                "Submit an issue or track your existing support requests.",
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _box(),
          child: Column(
            children: [
              Text(
                "${tickets.length}",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                "Total tickets",
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _newTicketForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              CircleAvatar(
                backgroundColor: Color(0xffeef4fb),
                child: Icon(Icons.edit, color: Color(0xff1a3a5c)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "New Ticket",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      "Describe your issue clearly for faster resolution.",
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          const Text("Category", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: category,
            items: categories.map((c) {
              return DropdownMenuItem<String>(
                value: c["value"],
                child: Text(c["label"]!),
              );
            }).toList(),
            onChanged: (v) => setState(() => category = v ?? "other"),
            decoration: _inputDecoration(),
          ),

          const SizedBox(height: 14),

          const Text("Title *", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: titleCtrl,
            maxLength: 120,
            decoration: _inputDecoration(
              hint: "e.g. Unable to join video call",
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            "Description *",
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: descCtrl,
            maxLines: 5,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: _inputDecoration(
              hint:
                  "Please describe your issue in detail — what happened, when, and any steps you already tried.",
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: loading ? null : _submitTicket,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(loading ? "Submitting..." : "Submit Ticket"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff1a3a5c),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfffffbeb),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              "💡 Tips for faster support\n"
              "• Include error messages or screenshots if possible\n"
              "• Mention the feature or page where you faced the issue\n"
              "• Describe steps that led to the problem",
              style: TextStyle(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticketList(List<Map<String, dynamic>> displayed) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Your Tickets",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              _filterChip("All", "all"),
              _filterChip("Open", "open"),
              _filterChip("Resolved", "resolved"),
            ],
          ),

          const SizedBox(height: 16),

          if (displayed.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text("No tickets found."),
              ),
            )
          else
            ...displayed.asMap().entries.map((entry) {
              final index = entry.key;
              final ticket = entry.value;
              return _ticketCard(ticket, index);
            }),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final active = filter == value;
    final count = value == "all"
        ? tickets.length
        : tickets.where((t) => t["status"] == value).length;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => filter = value),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xff1a3a5c) : const Color(0xfff3f4f6),
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

  Widget _ticketCard(Map<String, dynamic> ticket, int index) {
    final isOpen = expandedId == ticket["_id"];
    final status = ticket["status"] ?? "open";
    final isResolved = status == "resolved";
    final catLabel = _categoryLabel(ticket["category"]);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xfff9fafb),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOpen ? const Color(0xff1a3a5c) : Colors.black12,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                expandedId = isOpen ? null : ticket["_id"];
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Text(
                    "#${(index + 1).toString().padLeft(3, "0")}",
                    style: const TextStyle(
                      color: Colors.black45,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket["title"],
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "$catLabel · ${_formatDate(ticket["createdAt"])}",
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(status),
                  Icon(
                    isOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
            ),
          ),

          if (isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const Text(
                    "Description",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(ticket["description"] ?? ""),
                  if (isResolved && ticket["resolution"] != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "✅ Resolution\n${ticket["resolution"]}",
                        style: TextStyle(color: Colors.green.shade800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final resolved = status == "resolved";

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: resolved ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        resolved ? "Resolved" : "Open",
        style: TextStyle(
          color: resolved ? Colors.green.shade700 : Colors.orange.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _submitTicket() async {
    if (titleCtrl.text.trim().isEmpty || descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill title and description")),
      );
      return;
    }

    setState(() => loading = true);

    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      tickets.insert(0, {
        "_id": DateTime.now().millisecondsSinceEpoch.toString(),
        "title": titleCtrl.text.trim(),
        "description": descCtrl.text.trim(),
        "category": category,
        "status": "open",
        "createdAt": DateTime.now(),
      });

      titleCtrl.clear();
      descCtrl.clear();
      category = "other";
      loading = false;
      filter = "all";
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Ticket submitted successfully!")),
    );
  }

  String _categoryLabel(String? value) {
    final found = categories.where((c) => c["value"] == value).toList();
    return found.isEmpty ? "Other" : found.first["label"]!;
  }

  String _formatDate(dynamic date) {
    if (date is DateTime) {
      return "${date.day.toString().padLeft(2, "0")} "
          "${_month(date.month)} ${date.year}";
    }
    return "";
  }

  String _month(int m) {
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return months[m - 1];
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xfff9fafb),
      counterText: "",
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
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
}