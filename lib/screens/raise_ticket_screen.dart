import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import '../services/socket_service.dart';
import '../services/ticket_service.dart';
import '../services/token_storage_service.dart';
import '../widgets/ticket_thread_view.dart';

class RaiseTicketPage extends StatefulWidget {
  const RaiseTicketPage({
    super.key,
    this.ticketService,
    this.enableRealtime = true,
  });

  /// Injectable for tests; defaults to the real service.
  final TicketService? ticketService;

  /// Refresh the list on socket `ticket-updated` / `ticket-created`.
  final bool enableRealtime;

  @override
  State<RaiseTicketPage> createState() => _RaiseTicketPageState();
}

class _RaiseTicketPageState extends State<RaiseTicketPage> {
  late final TicketService _ticketService =
      widget.ticketService ?? TicketService();
  Timer? _realtimeTimer;
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();

  String category = "other";
  String filter = "all";
  String? expandedId;
  bool loading = false;
  bool loadingTickets = true;
  String ticketLoadError = "";

  // Scaffold tint — swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);

  // Semantic status colours — reused across the app's status chips
  // (amber/green/blue), kept distinct from the brand colour on purpose.
  static const Color _statusOpen = Color(0xFFF5B74E);
  static const Color _statusResolved = Color(0xFF63C06B);
  static const Color _statusInProgress = Color(0xFF5B9EFF);
  static const Color _statusNeutral = Color(0xFF8A94A6);

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
    if (widget.enableRealtime) _connectRealtime();
  }

  // Support replies and closures arrive over the socket (events sent to the
  // patient's room); refresh the list when one does.
  void _connectRealtime() {
    final socket = SocketService.instance;
    socket.on('connect', _onSocketConnected);
    socket.on('ticket-updated', _onTicketEvent);
    socket.on('ticket-created', _onTicketEvent);

    if (socket.connected) {
      _joinPatientRoom();
    } else {
      socket.connect();
    }
  }

  void _disconnectRealtime() {
    final socket = SocketService.instance;
    socket.off('connect', _onSocketConnected);
    socket.off('ticket-updated', _onTicketEvent);
    socket.off('ticket-created', _onTicketEvent);
  }

  void _onSocketConnected(dynamic _) {
    _joinPatientRoom();
    _queueRealtimeRefresh();
  }

  void _onTicketEvent(dynamic _) => _queueRealtimeRefresh();

  void _queueRealtimeRefresh() {
    _realtimeTimer?.cancel();
    _realtimeTimer = Timer(const Duration(milliseconds: 300), () {
      _realtimeTimer = null;
      if (mounted) _loadTickets();
    });
  }

  Future<void> _joinPatientRoom() async {
    final profile = await const TokenStorageService().getUserProfile();
    final userId = (profile['userId'] ?? '').trim();
    if (userId.isEmpty || !SocketService.instance.connected) return;

    SocketService.instance.emit('user-online', {
      'userId': userId,
      'role': 'user',
    });
  }

  @override
  void dispose() {
    _realtimeTimer?.cancel();
    if (widget.enableRealtime) _disconnectRealtime();
    titleCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _ticketsForFilter(filter);

    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: const Text("Help & Support"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadTickets,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Support",
                style: AppType.body(size: 13, weight: FontWeight.w700)
                    .copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: 4),
              Text(
                "Help & Support",
                style: AppType.display(size: 23, height: 1.1),
              ),
              const SizedBox(height: 4),
              Text(
                "Submit an issue or track your existing support requests.",
                style: AppType.body(size: 13)
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _box(),
          child: Column(
            children: [
              Text("${tickets.length}", style: AppType.display(size: 22)),
              Text(
                "Total tickets",
                style: AppType.body(size: 11)
                    .copyWith(color: AppColors.textSecondary),
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
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                child: const Icon(Icons.edit, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("New Ticket", style: AppType.display(size: 18)),
                    Text(
                      "Describe your issue clearly for faster resolution.",
                      style: AppType.body(size: 13)
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Text("Category",
              style: AppType.body(size: 13, weight: FontWeight.w800)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: category,
            style: AppType.body(size: 14)
                .copyWith(color: AppColors.textPrimary),
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

          Text("Title *",
              style: AppType.body(size: 13, weight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: titleCtrl,
            maxLength: 120,
            style: AppType.body(size: 14)
                .copyWith(color: AppColors.textPrimary),
            decoration: _inputDecoration(
              hint: "e.g. Unable to join video call",
            ),
          ),

          const SizedBox(height: 8),

          Text(
            "Description *",
            style: AppType.body(size: 13, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: descCtrl,
            maxLines: 5,
            maxLength: 500,
            style: AppType.body(size: 14)
                .copyWith(color: AppColors.textPrimary),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(loading ? "Submitting..." : "Submit Ticket"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Text(
              "💡 Tips for faster support\n"
              "• Include error messages or screenshots if possible\n"
              "• Mention the feature or page where you faced the issue\n"
              "• Describe steps that led to the problem",
              style: AppType.body(size: 13, height: 1.5)
                  .copyWith(color: const Color(0xFF92400E)),
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
              Expanded(
                child: Text(
                  "Your Tickets",
                  style: AppType.display(size: 18),
                ),
              ),
              IconButton(
                onPressed: loadingTickets ? null : _loadTickets,
                icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
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
                child: CircularProgressIndicator(color: AppColors.primary),
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
                      style: AppType.body(size: 13)
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadTickets,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retry"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (displayed.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "No tickets found.",
                  style: AppType.body(size: 13)
                      .copyWith(color: AppColors.textSecondary),
                ),
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
          color: active ? AppColors.primary : AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          "$label  $count",
          style: AppType.body(size: 12, weight: FontWeight.w800).copyWith(
            color: active ? Colors.white : AppColors.textPrimary,
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

  Color _statusColor(String status) {
    switch (_statusKey(status)) {
      case "resolved":
        return _statusResolved;
      case "open":
        return _statusOpen;
      case "in_progress":
        return _statusInProgress;
      default:
        return _statusNeutral;
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isOpen ? AppColors.primary : AppColors.border,
          width: isOpen ? 1.6 : 1.2,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
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
                    style: AppType.body(size: 13, weight: FontWeight.w900)
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket["title"],
                          style: AppType.body(size: 14, weight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if ((ticket["ref"]?.toString() ?? "").isNotEmpty)
                              ticket["ref"].toString(),
                            catLabel,
                            _formatDate(ticket["createdAt"]),
                          ].join(" · "),
                          style: AppType.body(size: 12)
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (_hasNewReply(ticket)) _newReplyChip(),
                  _statusBadge(status),
                  Icon(
                    isOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
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
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 6),
                  TicketThreadView(
                    key: ValueKey("thread-${ticket["_id"]}"),
                    messages: _messagesOf(ticket),
                    closed: isResolved,
                    closedAt: _parseDate(ticket["closedAt"]),
                    onSend: (text) => _sendReply(ticket, text),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<TicketMessage> _messagesOf(Map<String, dynamic> ticket) {
    return TicketMessage.listFrom(
      ticket["messages"],
      fallbackText: ticket["description"]?.toString() ?? "",
      fallbackAt: ticket["createdAt"],
    );
  }

  // Open ticket whose latest message is from support (the user hasn't
  // answered yet) — same "New reply" cue as the web.
  bool _hasNewReply(Map<String, dynamic> ticket) {
    if (_statusKey(ticket["status"]) == "resolved") return false;
    final messages = _messagesOf(ticket);
    return messages.isNotEmpty && !messages.last.isMine;
  }

  Widget _newReplyChip() {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        "New reply",
        style: AppType.body(size: 10.5, weight: FontWeight.w900)
            .copyWith(color: AppColors.primary),
      ),
    );
  }

  /// Sends a reply on [ticket]. Returns `null` on success, otherwise the
  /// message to show under the reply box.
  Future<String?> _sendReply(Map<String, dynamic> ticket, String text) async {
    final id = ticket["_id"]?.toString() ?? "";
    final result = await _ticketService.replyToTicket(ticketId: id, text: text);
    if (!mounted) return null;

    if (result.success && (result.data?.isNotEmpty ?? false)) {
      setState(() => _replaceTicket(_ticketFromResponse(result.data!)));
      await _saveTickets();
      return null;
    }

    if (result.statusCode == 409) {
      // Support closed it while the box was open: show the closed state
      // instead of a dead reply box, and pick up the final conversation.
      setState(() {
        final index = tickets.indexWhere((t) => t["_id"] == id);
        if (index != -1) {
          tickets[index] = {
            ...tickets[index],
            "status": "resolved",
            "closedAt": tickets[index]["closedAt"] ??
                DateTime.now().toIso8601String(),
          };
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "This ticket has just been closed. Please raise a new ticket if you still need help.",
          ),
        ),
      );
      unawaited(_loadTickets());
      return null;
    }

    if (result.statusCode == 401) {
      return "Session expired. Please log in again.";
    }
    return result.message.isNotEmpty
        ? result.message
        : "Could not send your message. Please try again.";
  }

  void _replaceTicket(Map<String, dynamic> updated) {
    final index = tickets.indexWhere((t) => t["_id"] == updated["_id"]);
    if (index == -1) {
      tickets.insert(0, updated);
    } else {
      tickets[index] = updated;
    }
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        _statusLabel(status),
        style: AppType.body(size: 11, weight: FontWeight.w900)
            .copyWith(color: color),
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
    // Only block with the full spinner when there's nothing cached to show
    // yet — a refresh with tickets already on screen relies on the pull
    // gesture / refresh icon itself for feedback instead of a duplicate
    // loading state, and shouldn't trip the global loader either.
    final showLoader = tickets.isEmpty;
    setState(() {
      loadingTickets = showLoader;
      ticketLoadError = "";
    });

    // Always silent: this screen already renders its own loading state
    // above (the block right below), so the app-wide overlay would just be
    // a second, redundant spinner stacked on top of it.
    final result = await _ticketService.fetchTickets(silent: true);

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

    if (!mounted) return;
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
      if ((ticket["ref"]?.toString().trim() ?? "").isNotEmpty)
        "ref": ticket["ref"].toString().trim(),
      if (ticket["messages"] is List) "messages": ticket["messages"],
      if ((ticket["closedAt"]?.toString().trim() ?? "").isNotEmpty)
        "closedAt": ticket["closedAt"].toString().trim(),
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

  List<Map<String, dynamic>> _mergeTickets(
    List<Map<String, dynamic>> serverTickets,
    List<Map<String, dynamic>> cachedTickets,
  ) {
    final merged = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    final seenContent = <String>{};

    // Server tickets go in first and are always authoritative.
    for (final ticket in serverTickets) {
      seenIds.add(_ticketIdentity(ticket));
      seenContent.add(_ticketContentKey(ticket));
      merged.add(ticket);
    }

    for (final ticket in cachedTickets) {
      final id = _ticketIdentity(ticket);
      if (seenIds.contains(id)) continue;
      // A ticket just created locally (see _submitTicket/_ticketFromResponse)
      // falls back to a synthetic timestamp-based `_id` whenever the
      // create-ticket response doesn't echo a real server id. Once the
      // server list catches up with the real ticket, id-only dedup can't
      // recognize it as the same ticket (different ids), so a content match
      // is used as a second signal — otherwise the same ticket would appear
      // twice: once under its synthetic local id, once under the server's.
      if (seenContent.contains(_ticketContentKey(ticket))) continue;
      seenIds.add(id);
      seenContent.add(_ticketContentKey(ticket));
      merged.add(ticket);
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

  String _ticketContentKey(Map<String, dynamic> ticket) {
    return [
      ticket["title"]?.toString().trim().toLowerCase() ?? "",
      ticket["description"]?.toString().trim().toLowerCase() ?? "",
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
      hintStyle: AppType.body(size: 14)
          .copyWith(color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.surface,
      counterText: "",
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border, width: 1.2),
      boxShadow: AppShadows.subtle,
    );
  }
}