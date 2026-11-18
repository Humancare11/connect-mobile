import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_design_system.dart';

/// One message of a support-ticket conversation, as returned by the backend
/// (`messages[]` on a ticket): `sender` is `user` (the person who raised the
/// ticket) or `admin` (support).
class TicketMessage {
  const TicketMessage({
    required this.sender,
    required this.text,
    this.createdAt,
  });

  final String sender;
  final String text;
  final DateTime? createdAt;

  bool get isMine => sender != 'admin';

  /// Reads `messages` from a ticket map. A ticket without any (an older
  /// cached copy) falls back to a single message built from its description,
  /// like the backend does for tickets created before threads existed.
  static List<TicketMessage> listFrom(
    dynamic raw, {
    String fallbackText = '',
    dynamic fallbackAt,
  }) {
    final out = <TicketMessage>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final text = item['text']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        out.add(
          TicketMessage(
            sender: item['sender']?.toString() == 'admin' ? 'admin' : 'user',
            text: text,
            createdAt: _parse(item['createdAt']),
          ),
        );
      }
    }
    if (out.isEmpty && fallbackText.trim().isNotEmpty) {
      out.add(
        TicketMessage(
          sender: 'user',
          text: fallbackText.trim(),
          createdAt: _parse(fallbackAt),
        ),
      );
    }
    return out;
  }

  static DateTime? _parse(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

/// The conversation on one ticket plus (while it is open) a box to reply.
///
/// Mirrors the web's `MySupportTickets` thread: the user's messages and
/// support's replies in order, a reply box while the ticket is open, and — once
/// support has closed it — a notice instead of the box. Users can never close
/// a ticket themselves.
class TicketThreadView extends StatefulWidget {
  const TicketThreadView({
    super.key,
    required this.messages,
    required this.closed,
    required this.onSend,
    this.closedAt,
  });

  static const int maxLength = 2000;

  final List<TicketMessage> messages;
  final bool closed;
  final DateTime? closedAt;

  /// Sends [text]. Returns `null` on success, or a message to show if it
  /// failed (the typed text is kept so nothing is lost).
  final Future<String?> Function(String text) onSend;

  @override
  State<TicketThreadView> createState() => _TicketThreadViewState();
}

class _TicketThreadViewState extends State<TicketThreadView> {
  final _controller = TextEditingController();
  bool _sending = false;
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _error = '';
    });

    String? failure;
    try {
      failure = await widget.onSend(text);
    } catch (_) {
      failure = 'Could not send your message. Please try again.';
    }
    if (!mounted) return;

    setState(() {
      _sending = false;
      _error = failure ?? '';
      if (failure == null) _controller.clear();
    });
  }

  static String _stamp(DateTime? value) =>
      value == null ? '' : DateFormat('d MMM yyyy, hh:mm a').format(value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in widget.messages) _bubble(message),
        const SizedBox(height: 4),
        if (widget.closed) _closedNotice() else _replyBox(),
      ],
    );
  }

  Widget _bubble(TicketMessage message) {
    final mine = message.isMine;
    final stamp = _stamp(message.createdAt);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: mine ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                mine ? 'You' : 'Humancare Support',
                if (stamp.isNotEmpty) stamp,
              ].join(' · '),
              style: AppType.body(size: 11, weight: FontWeight.w800)
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: AppType.body(size: 13.5, height: 1.4)
                  .copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closedNotice() {
    final when = _stamp(widget.closedAt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        'This ticket was closed by support${when.isEmpty ? '' : ' on $when'}. '
        'Raise a new ticket if you still need help.',
        style: AppType.body(size: 13, height: 1.4)
            .copyWith(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _replyBox() {
    final canSend = !_sending && _controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          enabled: !_sending,
          minLines: 2,
          maxLines: 5,
          maxLength: TicketThreadView.maxLength,
          onChanged: (_) => setState(() {}),
          style: AppType.body(size: 14).copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Write a message to support…',
            hintStyle: AppType.body(size: 14)
                .copyWith(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _error,
            style: AppType.body(size: 12.5, weight: FontWeight.w700)
                .copyWith(color: const Color(0xFFC0392B)),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: canSend ? _send : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Send'),
          ),
        ),
      ],
    );
  }
}
