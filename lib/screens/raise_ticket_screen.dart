import 'package:flutter/material.dart';

import '../services/ticket_service.dart';

class RaiseTicketPage extends StatefulWidget {
  const RaiseTicketPage({super.key});

  @override
  State<RaiseTicketPage> createState() => _RaiseTicketPageState();
}

class _RaiseTicketPageState extends State<RaiseTicketPage> {
  final _ticketService = TicketService();
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();

  String category = "other";
  String filter = "all";
  String? expandedId;
  bool loading = false;
  bool loadingTickets = true;
  String ticketLoadError = "";

  final categories = const [
    {"value": "appointment", "label": "Appointment Issue"},
    {"value": "billing", "label": "Billing / Payment"},
    {"value": "technical", "label": "Technical Problem"},
    {"value": "medical", "label": "Medical Query"},
    {"value": "other", "label": "Other"},
  ];

  final List<Map<String, dynamic>> tickets = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreAndLoadTickets();
    });
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _ticketsForFilter(filter);

    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text("Help & Support"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadTickets,
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Your Tickets",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: loadingTickets ? null : _loadTickets,
                icon: const Icon(Icons.refresh),
                tooltip: "Refresh tickets",
              ),
            ],
          ),
          const SizedBox(height: 4),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filterOptions().map((option) {
              return _filterChip(option["label"]!, option["value"]!);
            }).toList(),
          ),

          const SizedBox(height: 16),

          if (loadingTickets)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (ticketLoadError.isNotEmpty && tickets.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      ticketLoadError,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadTickets,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retry"),
                    ),
                  ],
                ),
              ),
            )
          else if (displayed.isEmpty)
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
    final count = _ticketsForFilter(value).length;

    return GestureDetector(
      onTap: () => setState(() => filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xff1a3a5c) : const Color(0xfff3f4f6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          "$label  $count",
          style: TextStyle(
            color: active ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  List<Map<String, String>> _filterOptions() {
    final options = <Map<String, String>>[
      {"value": "all", "label": "All"},
      {"value": "open", "label": "Open"},
      {"value": "resolved", "label": "Resolved"},
    ];
    final known = options.map((option) => option["value"]).toSet();

    for (final ticket in tickets) {
      final status = _statusKey(ticket["status"]);
      if (known.contains(status)) continue;

      known.add(status);
      options.add({
        "value": status,
        "label": _statusLabel(status),
      });
    }

    return options;
  }

  List<Map<String, dynamic>> _ticketsForFilter(String value) {
    if (value == "all") return tickets;

    return tickets.where((ticket) {
      return _statusKey(ticket["status"]) == value;
    }).toList();
  }

  String _statusKey(dynamic value) {
    final text = value?.toString().trim().toLowerCase() ?? "";
    final normalized = text
        .replaceAll(RegExp(r"[\s-]+"), "_")
        .replaceAll(RegExp(r"_+"), "_");

    switch (normalized) {
      case "":
      case "new":
      case "opened":
        return "open";
      case "resolve":
      case "solved":
      case "closed":
      case "complete":
      case "completed":
        return "resolved";
      default:
        return normalized;
    }
  }

  String _statusLabel(dynamic value) {
    final key = _statusKey(value);
    switch (key) {
      case "open":
        return "Open";
      case "resolved":
        return "Resolved";
      case "in_progress":
        return "In Progress";
      default:
        return key
            .split("_")
            .where((part) => part.isNotEmpty)
            .map((part) {
              return "${part[0].toUpperCase()}${part.substring(1)}";
            })
            .join(" ");
    }
  }

  MaterialColor _statusColor(String status) {
    switch (_statusKey(status)) {
      case "resolved":
        return Colors.green;
      case "open":
        return Colors.orange;
      case "in_progress":
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _ticketCard(Map<String, dynamic> ticket, int index) {
    final isOpen = expandedId == ticket["_id"];
    final status = _statusKey(ticket["status"]);
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
                  if (isResolved && _hasResolution(ticket)) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "Resolution\n${_resolutionText(ticket)}",
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
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Future<void> _restoreAndLoadTickets() async {
    final cachedTickets = await _ticketService.loadCachedTickets();
    if (!mounted) return;

    if (cachedTickets.isNotEmpty) {
      setState(() {
        tickets
          ..clear()
          ..addAll(cachedTickets.map(_ticketFromResponse));
        loadingTickets = false;
        ticketLoadError = "";
      });
    }

    await _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      loadingTickets = tickets.isEmpty;
      ticketLoadError = "";
    });

    final result = await _ticketService.fetchTickets();

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        loadingTickets = false;
        ticketLoadError = tickets.isEmpty
            ? (result.message.isNotEmpty
                  ? result.message
                  : "Unable to load tickets.")
            : "";
      });
      return;
    }

    final loadedTickets = (result.data ?? const <Map<String, dynamic>>[])
        .map(_ticketFromResponse)
        .toList();

    setState(() {
      if (loadedTickets.isNotEmpty || tickets.isEmpty) {
        final mergedTickets = loadedTickets.isEmpty
            ? tickets
            : _mergeTickets(loadedTickets, tickets);
        tickets
          ..clear()
          ..addAll(mergedTickets);
      }
      loadingTickets = false;
      ticketLoadError = "";
    });

    await _saveTickets();
  }

  void _submitTicket() async {
    final title = titleCtrl.text.trim();
    final description = descCtrl.text.trim();

    if (title.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill title and description")),
      );
      return;
    }

    setState(() => loading = true);

    final result = await _ticketService.createTicket(
      title: title,
      description: description,
      category: category,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isNotEmpty
                ? result.message
                : "Unable to submit ticket. Please try again.",
          ),
        ),
      );
      return;
    }

    final ticket = result.data ?? <String, dynamic>{};
    final createdTicket = _ticketFromResponse(ticket)
      ..["status"] = "open"
      ..remove("resolution")
      ..remove("resolvedBy")
      ..remove("resolvedAt");

    setState(() {
      tickets.insert(0, createdTicket);

      titleCtrl.clear();
      descCtrl.clear();
      category = "other";
      loading = false;
      filter = "all";
    });

    await _saveTickets();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message.isNotEmpty
              ? result.message
              : "Ticket submitted successfully.",
        ),
      ),
    );
  }

  Map<String, dynamic> _ticketFromResponse(Map<String, dynamic> ticket) {
    final status = _statusFromTicket(ticket);
    final ticketCategory = ticket["category"]?.toString().trim();

    return {
      "_id":
          ticket["_id"]?.toString() ??
          ticket["id"]?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      "title": ticket["title"]?.toString() ?? titleCtrl.text.trim(),
      "description":
          ticket["description"]?.toString() ?? descCtrl.text.trim(),
      "category":
          ticketCategory?.isNotEmpty == true ? ticketCategory : category,
      "status": status,
      if ((ticket["resolution"]?.toString().trim() ?? "").isNotEmpty)
        "resolution": ticket["resolution"].toString().trim(),
      if ((ticket["resolvedBy"]?.toString().trim() ?? "").isNotEmpty)
        "resolvedBy": ticket["resolvedBy"].toString().trim(),
      if ((ticket["resolvedAt"]?.toString().trim() ?? "").isNotEmpty)
        "resolvedAt": ticket["resolvedAt"].toString().trim(),
      "createdAt": _parseDate(ticket["createdAt"]) ?? DateTime.now(),
    };
  }

  String _statusFromTicket(Map<String, dynamic> ticket) {
    final isResolved = ticket["isResolved"];
    if (isResolved is bool && isResolved) return "resolved";

    for (final value in [
      ticket["status"],
      ticket["ticketStatus"],
      ticket["state"],
    ]) {
      if (value?.toString().trim().isEmpty ?? true) continue;
      final status = _statusKey(value);
      if (status.isNotEmpty) return status;
    }

    if (_hasResolution(ticket)) return "resolved";

    return "open";
  }

  bool _hasResolution(Map<String, dynamic> ticket) {
    final resolution = ticket["resolution"]?.toString().trim() ?? "";
    final resolvedBy = ticket["resolvedBy"]?.toString().trim() ?? "";
    final resolvedAt = ticket["resolvedAt"]?.toString().trim() ?? "";

    return resolution.isNotEmpty ||
        resolvedBy.isNotEmpty ||
        resolvedAt.isNotEmpty;
  }

  String _resolutionText(Map<String, dynamic> ticket) {
    final resolution = ticket["resolution"]?.toString().trim() ?? "";
    if (resolution.isNotEmpty) return resolution;

    return "Resolved by support.";
  }

  List<Map<String, dynamic>> _mergeTickets(
    List<Map<String, dynamic>> serverTickets,
    List<Map<String, dynamic>> cachedTickets,
  ) {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addTicket(Map<String, dynamic> ticket) {
      final key = _ticketIdentity(ticket);
      if (seen.contains(key)) return;
      seen.add(key);
      merged.add(ticket);
    }

    for (final ticket in serverTickets) {
      addTicket(ticket);
    }
    for (final ticket in cachedTickets) {
      addTicket(ticket);
    }

    return merged;
  }

  String _ticketIdentity(Map<String, dynamic> ticket) {
    final id = ticket["_id"]?.toString().trim();
    if (id != null && id.isNotEmpty) return id;

    return [
      ticket["title"]?.toString().trim() ?? "",
      ticket["description"]?.toString().trim() ?? "",
      ticket["createdAt"]?.toString().trim() ?? "",
    ].join("|");
  }

  Future<void> _saveTickets() async {
    await _ticketService.saveCachedTickets(
      tickets.map(_ticketForCache).toList(),
    );
  }

  Map<String, dynamic> _ticketForCache(Map<String, dynamic> ticket) {
    return ticket.map((key, value) {
      if (value is DateTime) {
        return MapEntry(key, value.toIso8601String());
      }
      return MapEntry(key, value);
    });
  }

  String _categoryLabel(String? value) {
    final found = categories.where((c) => c["value"] == value).toList();
    return found.isEmpty ? "Other" : found.first["label"]!;
  }

  String _formatDate(dynamic date) {
    final parsed = _parseDate(date);
    if (parsed != null) {
      return "${parsed.day.toString().padLeft(2, "0")} "
          "${_month(parsed.month)} ${parsed.year}";
    }
    return "";
  }

  DateTime? _parseDate(dynamic date) {
    if (date is DateTime) return date;
    if (date is String) return DateTime.tryParse(date)?.toLocal();
    return null;
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
