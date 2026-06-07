import 'package:flutter/material.dart';
import '../services/api_client.dart';

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  final ApiClient _api = ApiClient();
  List<dynamic> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final res = await _api.get('/tickets/user/my');
    if (res.success && res.data != null) {
      setState(() => _tickets = res.raw is List ? res.raw : (res.data!['data'] ?? []));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support Tickets')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tickets.isEmpty
              ? const Center(child: Text('No tickets yet'))
              : ListView.builder(
                  itemCount: _tickets.length,
                  itemBuilder: (_, i) {
                    final t = _tickets[i];
                    return ListTile(
                      title: Text(t['title'] ?? 'Ticket'),
                      subtitle: Text(t['status'] ?? ''),
                    );
                  },
                ),
    );
  }
}
