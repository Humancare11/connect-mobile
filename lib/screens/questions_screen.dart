import 'package:flutter/material.dart';
import '../services/api_client.dart';

class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen({super.key});

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final ApiClient _api = ApiClient();
  List<dynamic> _questions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final res = await _api.get('/qna/user-questions');
    if (res.success && res.data != null) {
      // API may return list directly or { data: [...] }
      setState(() => _questions = res.raw is List ? res.raw : (res.data!['data'] ?? []));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Questions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? const Center(child: Text('No questions yet'))
              : ListView.builder(
                  itemCount: _questions.length,
                  itemBuilder: (_, i) {
                    final q = _questions[i];
                    return ListTile(
                      title: Text(q['question'] ?? q['title'] ?? 'Question'),
                      subtitle: Text(q['answer'] ?? 'Pending'),
                    );
                  },
                ),
    );
  }
}
